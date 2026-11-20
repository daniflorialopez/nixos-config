"""capture: pictures of an output or of single windows, asked of the compositor
directly.

`grim` does this too, and thumbs.py uses it: a process per picture, the pixels
written out as a PPM, read back through a pipe and repacked — 55 to 130 ms
for the screen, 30 to 40 for a window (measured). That is fine for a card
that fades in. It is far too slow for the stage (stage.py), whose first frame
has to BE the desktop as it stands, so that what follows reads as the desktop
itself moving: every millisecond before that frame is a key that seems not to
have been pressed.

So this speaks the protocols itself, over its own connection to the
compositor, and hands back the pixels as they arrive in shared memory:

  wlr-screencopy          one output, without the pointer
  hyprland-toplevel-export one window's own buffer, by its address — nothing
                          drawn over it, and whether or not its workspace is
                          showing

There is no Wayland client library in this Python environment and none is
worth a download for a dozen requests. The wire format is small: a header of
(object id, size << 16 | opcode), then 32-bit little-endian arguments, strings
padded to four bytes, and file descriptors passed beside the bytes
(SCM_RIGHTS) rather than in them.

Nothing here touches GTK, so it can run on a worker thread. Nothing is
written anywhere but an anonymous memory file, and the picture is handed back
as that memory itself (a GLib.Bytes mapped on it, not a copy): it is gone
when the last thing holding the picture lets go.

Asking takes as long as the compositor takes — about 10 ms for the screen —
and not much more: what was learned about the compositor the first time
(which global is which, which output has which name) is remembered, so every
later request goes out in one write, with no questions first.
"""

import array
import os
import socket
import struct
import time

from gi.repository import GLib

# wl_shm formats -> how the bytes lie in memory (little-endian words).
ARGB8888, XRGB8888 = 0, 1
ABGR8888, XBGR8888 = 0x34324241, 0x34324258
LAYOUT = {ARGB8888: "BGRA", XRGB8888: "BGRX", ABGR8888: "RGBA", XBGR8888: "RGBX"}


class Shot:
    """One picture: `data` (a GLib.Bytes) is `height` rows of `stride`
    bytes, four bytes a pixel in the order `layout` says ("BGRX", "BGRA",
    "RGBX", "RGBA"; an A is premultiplied alpha). `flipped`: the first row is
    the bottom one."""

    __slots__ = ("width", "height", "stride", "layout", "data", "flipped", "took")

    def __init__(self, width, height, stride, layout, data, flipped, took):
        self.width, self.height, self.stride = width, height, stride
        self.layout, self.data, self.flipped, self.took = layout, data, flipped, took


class Wire:
    """Just enough of a Wayland client."""

    def __init__(self, timeout=1.0):
        name = os.environ.get("WAYLAND_DISPLAY", "wayland-1")
        path = name if name.startswith("/") else os.path.join(
            os.environ.get("XDG_RUNTIME_DIR", "/tmp"), name)
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(timeout)
        self.sock.connect(path)
        self.buf = b""
        self.next_id = 2
        self.handlers = {}               # object id -> callable(opcode, payload)

    def new_id(self):
        self.next_id += 1
        return self.next_id - 1

    def send(self, obj, opcode, payload=b"", fd=None):
        message = struct.pack("<IHH", obj, opcode, 8 + len(payload)) + payload
        if fd is None:
            self.sock.sendall(message)
        else:
            self.sock.sendmsg([message], [(socket.SOL_SOCKET, socket.SCM_RIGHTS,
                                           array.array("i", [fd]))])

    @staticmethod
    def string(s):
        raw = s.encode() + b"\0"
        return struct.pack("<I", len(raw)) + raw + b"\0" * (-len(raw) % 4)

    @staticmethod
    def read_string(payload, at):
        n, = struct.unpack_from("<I", payload, at)
        return payload[at + 4:at + 4 + n - 1].decode(errors="replace"), at + 4 + n + (-n % 4)

    def pump(self, done):
        """Read and route events until `done()` says so."""
        while not done():
            while len(self.buf) >= 8:
                obj, opcode, size = struct.unpack_from("<IHH", self.buf)
                if size < 8:
                    raise OSError("bad message")
                if len(self.buf) < size:
                    break
                payload, self.buf = self.buf[8:size], self.buf[size:]
                if obj == 1 and opcode == 0:                 # wl_display.error
                    raise OSError("protocol error: " + self.read_string(payload, 8)[0])
                handler = self.handlers.get(obj)
                if handler is not None:
                    handler(opcode, payload)
                if done():
                    return
            if done():
                return
            data = self.sock.recv(65536)
            if not data:
                raise OSError("compositor hung up")
            self.buf += data

    def roundtrip(self):
        """wl_display.sync: everything sent so far has been acted on."""
        flag = []
        callback = self.new_id()
        self.handlers[callback] = lambda _op, _p: flag.append(1)
        self.send(1, 0, struct.pack("<I", callback))
        self.pump(lambda: bool(flag))
        del self.handlers[callback]

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


class _Frame:
    """One capture in flight, for either protocol: they differ only in the
    numbers of their events and in one argument of `copy`."""

    def __init__(self, wire, shm, frame, export):
        self.wire, self.shm, self.frame, self.export = wire, shm, frame, export
        self.spec = None                 # (format, width, height, stride)
        self.fd = -1
        self.flipped = False
        self.state = "waiting"           # -> "copying" -> "ready" | "failed"
        self.began = time.monotonic()
        self.took = 0.0
        wire.handlers[frame] = self.on_event

    def on_event(self, opcode, payload):
        # screencopy:  buffer 0, flags 1, ready 2, failed 3, damage 4, dmabuf 5, done 6
        # export:      buffer 0, damage 1, flags 2, ready 3, failed 4, dmabuf 5, done 6
        flags, ready, failed = (2, 3, 4) if self.export else (1, 2, 3)
        if opcode == 0:
            spec = struct.unpack("<IIII", payload[:16])
            if self.spec is None or spec[0] in (XRGB8888, ARGB8888):
                self.spec = spec         # several may be offered: take the plain one
        elif opcode == 6 and self.state == "waiting":
            self.copy()
        elif opcode == flags:
            self.flipped = bool(struct.unpack("<I", payload[:4])[0] & 1)
        elif opcode == ready:
            self.state, self.took = "ready", time.monotonic() - self.began
        elif opcode == failed:
            self.state = "failed"

    def copy(self):
        if self.spec is None or self.spec[0] not in LAYOUT:
            self.state = "failed"
            return
        fmt, width, height, stride = self.spec
        size = stride * height
        self.fd = os.memfd_create("reverie-capture", os.MFD_CLOEXEC)
        os.ftruncate(self.fd, size)
        pool, buffer = self.wire.new_id(), self.wire.new_id()
        self.wire.send(self.shm, 0, struct.pack("<Ii", pool, size), fd=self.fd)     # create_pool
        self.wire.send(pool, 0, struct.pack("<IiiiiI", buffer, 0, width, height, stride, fmt))
        if self.export:
            self.wire.send(self.frame, 0, struct.pack("<Ii", buffer, 1))     # copy, ignore damage
        else:
            self.wire.send(self.frame, 0, struct.pack("<I", buffer))        # copy
        self.state = "copying"

    @property
    def over(self):
        return self.state in ("ready", "failed")

    def shot(self):
        try:
            if self.state != "ready":
                return None
            fmt, width, height, stride = self.spec
            # The shared memory itself, not a copy of it: the mapping keeps
            # the anonymous file alive for as long as the bytes are held.
            data = GLib.MappedFile.new_from_fd(self.fd, False).get_bytes()
            return Shot(width, height, stride, LAYOUT[fmt], data, self.flipped, self.took)
        finally:
            if self.fd >= 0:
                os.close(self.fd)
                self.fd = -1


_known = {}                  # what the compositor told us last time (see _grab)


def grab(output=None, windows=(), timeout=1.0):
    """One round: the output called `output` (if given) and each window whose
    address (as hyprctl prints it, "0x…") is in `windows`.

    Returns (Shot or None, {address: Shot}). Everything is asked for at once
    and comes back as the compositor gets to it; a picture that fails or is
    not back in `timeout` seconds is simply missing.
    """
    if _known:
        try:
            return _grab(output, windows, timeout, _known)
        except (OSError, struct.error, KeyError):
            _known.clear()               # a monitor came or went: ask again
    try:
        return _grab(output, windows, timeout, None)
    except (OSError, struct.error):
        return None, {}


def _grab(output, windows, timeout, known):
    """`known`: {"globals": {interface: (name, version)}, "outputs": {output
    name: its global's name}} from an earlier round, or None to find out.

    Finding out is two round trips to the compositor before the first
    request can be made; with it known, the registry, the binds and the
    requests all go out together.
    """
    wire = Wire(timeout)
    frames = []
    try:
        registry = wire.new_id()
        wire.send(1, 1, struct.pack("<I", registry))             # wl_display.get_registry

        def bind(interface, name, version):
            new = wire.new_id()
            wire.send(registry, 0, struct.pack("<I", name) + wire.string(interface)
                      + struct.pack("<II", version, new))
            return new

        if known is None:
            found, output_globals, names = {}, [], {}

            def on_global(opcode, payload):
                if opcode == 0:
                    name, = struct.unpack_from("<I", payload)
                    interface, at = wire.read_string(payload, 4)
                    version, = struct.unpack_from("<I", payload, at)
                    if interface == "wl_output":
                        output_globals.append((name, version))
                    else:
                        found[interface] = (name, version)
            wire.handlers[registry] = on_global
            wire.roundtrip()
            for name, version in output_globals:
                if version >= 4:         # (older ones do not say what they are called)
                    oid = bind("wl_output", name, 4)
                    wire.handlers[oid] = lambda op, p, name=name: names.__setitem__(
                        wire.read_string(p, 0)[0], name) if op == 4 else None
            wire.roundtrip()
            known = {"globals": found, "outputs": names}
            _known.update(known)
        found = known["globals"]
        if "wl_shm" not in found:
            return None, {}
        shm = bind("wl_shm", found["wl_shm"][0], 1)

        shot_frame = None
        if output is not None and "zwlr_screencopy_manager_v1" in found \
                and output in known["outputs"]:
            target = bind("wl_output", known["outputs"][output], 4)
            manager = bind("zwlr_screencopy_manager_v1", found["zwlr_screencopy_manager_v1"][0], 3)
            frame = wire.new_id()
            # capture_output(frame, overlay_cursor = 0, output)
            wire.send(manager, 0, struct.pack("<IiI", frame, 0, target))
            shot_frame = _Frame(wire, shm, frame, export=False)
            frames.append(shot_frame)

        by_window = {}
        if windows and "hyprland_toplevel_export_manager_v1" in found:
            manager = bind("hyprland_toplevel_export_manager_v1",
                           found["hyprland_toplevel_export_manager_v1"][0], 1)
            for address in windows:
                frame = wire.new_id()
                # capture_toplevel(frame, overlay_cursor = 0, handle): the
                # handle is the low 32 bits of the window's address.
                wire.send(manager, 0, struct.pack("<IiI", frame, 0, int(address, 16) & 0xFFFFFFFF))
                by_window[address] = _Frame(wire, shm, frame, export=True)
                frames.append(by_window[address])

        if frames:
            try:
                wire.pump(lambda: all(f.over for f in frames))
            except socket.timeout:
                pass                     # whatever is ready is still ours
        shots = {address: f.shot() for address, f in by_window.items()}
        return (shot_frame.shot() if shot_frame is not None else None,
                {address: s for address, s in shots.items() if s is not None})
    finally:
        for f in frames:
            if f.fd >= 0:
                os.close(f.fd)
        wire.close()
