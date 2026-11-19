"""Pictures of the windows themselves, for the HUD's workspace cards.

Not screenshots of workspaces. A screenshot can only be taken of what is on
the output right now, so a card for another workspace would need a picture
saved the last time you were there: stale by however long ago that was, with
the spotlight's darkness and any title card baked into it, and a rule for
when to stop trusting it. Hyprland can instead hand out the picture of ONE
window — its own buffer, nothing drawn over it — whether or not its workspace
is showing (ext-image-copy-capture with a foreign-toplevel source; `grim -T`
speaks it). So when the panel opens, every window is photographed there and
then (30-40 ms each, measured, a few at a time and off the main loop), and
the card is put together from those the same way the drawn one was: each
window at its place, to scale. Nothing is ever written to disk.

Two things are needed that neither `hyprctl` nor grim provide:

  * grim wants the window's foreign-toplevel identifier, Hyprland's IPC only
    knows window addresses, and the two are unrelated numbers. The
    ext-foreign-toplevel-list protocol lists the identifiers and
    hyprland-toplevel-mapping turns each handle into an address. There is no
    Wayland client library in this Python environment and none is worth a
    download for three requests, so `toplevels` speaks the wire format
    itself: a header of (object, size << 16 | opcode), 32-bit little-endian
    arguments, strings padded to four bytes.
  * the picture comes back full size. It is scaled down by GdkPixbuf, in C
    and with the interpreter lock released, straight from the PPM's packed
    RGB; only the small result is repacked for cairo.

A picture is kept until the window closes, so the next time the panel opens
it has something to show at once and the fresh one simply replaces it. It is
only shown while the window still has the size it was taken at: after a
resize the card falls back to the drawn window until the new picture lands.
"""

import ctypes
import os
import shutil
import socket
import struct
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import cairo

import gi

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, GLib  # noqa: E402

WORKERS = 4                  # grims at a time: each is a core for ~35 ms

try:
    _trim = ctypes.CDLL(None).malloc_trim
except (OSError, AttributeError):            # not glibc
    _trim = None


class _Wire:
    """Just enough of a Wayland client to ask three questions."""

    def __init__(self):
        name = os.environ.get("WAYLAND_DISPLAY", "wayland-1")
        path = name if name.startswith("/") else os.path.join(
            os.environ.get("XDG_RUNTIME_DIR", "/tmp"), name)
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(1.0)
        self.sock.connect(path)
        self.buf = b""
        self.next_id = 2

    def new_id(self):
        self.next_id += 1
        return self.next_id - 1

    def send(self, obj, opcode, payload=b""):
        self.sock.sendall(struct.pack("<IHH", obj, opcode, 8 + len(payload)) + payload)

    @staticmethod
    def string(s):
        raw = s.encode() + b"\0"
        return struct.pack("<I", len(raw)) + raw + b"\0" * (-len(raw) % 4)

    @staticmethod
    def read_string(payload, at):
        n, = struct.unpack_from("<I", payload, at)
        return payload[at + 4:at + 4 + n - 1].decode(errors="replace"), at + 4 + n + (-n % 4)

    def roundtrip(self, on_event):
        """wl_display.sync, and every event that arrives before its answer."""
        done = self.new_id()
        self.send(1, 0, struct.pack("<I", done))
        while True:
            while len(self.buf) >= 8:
                obj, opcode, size = struct.unpack_from("<IHH", self.buf)
                if size < 8:
                    raise OSError("bad message")
                if len(self.buf) < size:
                    break
                payload, self.buf = self.buf[8:size], self.buf[size:]
                if obj == done:
                    return
                if obj == 1 and opcode == 0:         # wl_display.error
                    raise OSError("protocol error")
                on_event(obj, opcode, payload)
            data = self.sock.recv(65536)
            if not data:
                raise OSError("compositor hung up")
            self.buf += data

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def toplevels():
    """{window address as hyprctl prints it: foreign-toplevel identifier}."""
    wire = _Wire()
    try:
        registry = wire.new_id()
        wire.send(1, 1, struct.pack("<I", registry))             # wl_display.get_registry
        found = {}

        def on_global(obj, opcode, payload):
            if obj == registry and opcode == 0:
                name, = struct.unpack_from("<I", payload)
                interface, _ = wire.read_string(payload, 4)
                found[interface] = name
        wire.roundtrip(on_global)
        if "ext_foreign_toplevel_list_v1" not in found or \
                "hyprland_toplevel_mapping_manager_v1" not in found:
            return {}

        def bind(interface):
            new = wire.new_id()
            wire.send(registry, 0, struct.pack("<I", found[interface]) + wire.string(interface)
                      + struct.pack("<II", 1, new))
            return new
        listing = bind("ext_foreign_toplevel_list_v1")
        mapping = bind("hyprland_toplevel_mapping_manager_v1")
        identifiers = {}                                          # handle -> identifier

        def on_toplevel(obj, opcode, payload):
            if obj == listing and opcode == 0:                    # .toplevel(new handle)
                identifiers[struct.unpack("<I", payload)[0]] = None
            elif obj in identifiers and opcode == 4:              # handle.identifier(string)
                identifiers[obj] = wire.read_string(payload, 0)[0]
        wire.roundtrip(on_toplevel)

        asked, out = {}, {}
        for handle, identifier in identifiers.items():
            if identifier:
                query = wire.new_id()
                asked[query] = identifier
                # .get_window_for_toplevel(new mapping handle, toplevel)
                wire.send(mapping, 0, struct.pack("<II", query, handle))

        def on_address(obj, opcode, payload):
            if obj in asked and opcode == 0:                      # .window_address(hi, lo)
                hi, lo = struct.unpack("<II", payload)
                out[f"0x{(hi << 32) | lo:x}"] = asked[obj]
        wire.roundtrip(on_address)
        return out
    finally:
        wire.close()


def picture(identifier, width, height):
    """One window as a cairo surface `width` x `height`, or None."""
    try:
        raw = subprocess.run(["grim", "-t", "ppm", "-T", identifier, "-"],
                             capture_output=True, timeout=2).stdout
        magic, size, depth, rgb = raw.split(b"\n", 3)
        w, h = (int(n) for n in size.split())
        if magic != b"P6" or depth != b"255" or len(rgb) < w * h * 3:
            return None
        full = GdkPixbuf.Pixbuf.new_from_bytes(
            GLib.Bytes.new(rgb), GdkPixbuf.Colorspace.RGB, False, 8, w, h, w * 3)
        width, height = max(1, min(w, width)), max(1, min(h, height))
        small = full.scale_simple(width, height, GdkPixbuf.InterpType.BILINEAR)
        stride, pixels = small.get_rowstride(), small.get_pixels()
        buf = bytearray(width * height * 4)
        if stride == width * 3:
            n = width * height * 3
            buf[0::4], buf[1::4], buf[2::4] = pixels[2:n:3], pixels[1:n:3], pixels[0:n:3]
        else:                                # rows padded to four bytes
            for y in range(height):
                row = pixels[y * stride:y * stride + width * 3]
                at = y * width * 4
                buf[at:at + width * 4:4] = row[2::3]
                buf[at + 1:at + width * 4:4] = row[1::3]
                buf[at + 2:at + width * 4:4] = row[0::3]
        return cairo.ImageSurface.create_for_data(buf, cairo.FORMAT_RGB24, width, height,
                                                  width * 4)
    except (OSError, ValueError, subprocess.SubprocessError, GLib.Error, cairo.Error,
            MemoryError):
        return None


class Thumbs:
    def __init__(self, landed):
        self.landed = landed                 # called with an address, on the main loop
        self.shots = {}                      # address -> (surface, the window's size then)
        self.busy = False
        self.able = bool(shutil.which("grim"))
        self.took = 0.0                      # how long the last round was, for `status`

    def get(self, address, size):
        """The picture of this window, if there is one and it still fits."""
        shot = self.shots.get(address)
        return shot[0] if shot is not None and shot[1] == tuple(size) else None

    def refresh(self, wants, alive):
        """`wants`: [(address, the window's size, the scale to keep it at)].

        `alive` is every window there is: the pictures of the rest are let go."""
        for address in [a for a in self.shots if a not in alive]:
            del self.shots[address]
        if self.busy or not self.able or not wants:
            return
        self.busy = True
        threading.Thread(target=self._work, args=(list(wants),), daemon=True).start()

    def _work(self, wants):
        start = time.monotonic()
        try:
            identifiers = toplevels()

            def one(want):
                address, size, scale = want
                identifier = identifiers.get(address)
                if identifier is None:
                    return
                surface = picture(identifier, round(size[0] * scale), round(size[1] * scale))
                if surface is not None:
                    GLib.idle_add(self._land, address, surface, tuple(size))
            with ThreadPoolExecutor(max_workers=WORKERS) as pool:
                list(pool.map(one, wants))
        except (OSError, struct.error):
            pass                             # no pictures: the cards stay drawn
        finally:
            self.took = time.monotonic() - start
            # Every full-size picture passed through here as ten megabytes
            # or so, on a worker thread, and glibc keeps what a thread's
            # arena has freed: measured, the daemon sat 150 MB above where it
            # started after a few rounds. Hand it back.
            if _trim is not None:
                _trim(0)
            GLib.idle_add(self._done)

    def _land(self, address, surface, size):
        self.shots[address] = (surface, size)
        self.landed(address)
        return False

    def _done(self):
        self.busy = False
        return False
