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

The wallpaper is read the same way, once per picture and monitor, at card
size: the wallpaper daemon says which file is on which output.

A picture is kept until the window closes, so the next time the panel opens
it has something to show at once and the fresh one simply replaces it. It is
only shown while the window still has the size it was taken at: after a
resize the card falls back to the drawn window until the new picture lands.
"""

import ctypes
import os
import re
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


def _surface(pixbuf):
    """A (small) RGB pixbuf, repacked as the BGRX cairo wants."""
    width, height = pixbuf.get_width(), pixbuf.get_height()
    stride, pixels, step = pixbuf.get_rowstride(), pixbuf.get_pixels(), pixbuf.get_n_channels()
    buf = bytearray(width * height * 4)
    if stride == width * step:
        n = width * height * step
        buf[0::4], buf[1::4], buf[2::4] = pixels[2:n:step], pixels[1:n:step], pixels[0:n:step]
    else:                                    # rows padded to four bytes
        for y in range(height):
            row = pixels[y * stride:y * stride + width * step]
            at = y * width * 4
            buf[at:at + width * 4:4] = row[2::step]
            buf[at + 1:at + width * 4:4] = row[1::step]
            buf[at + 2:at + width * 4:4] = row[0::step]
    return cairo.ImageSurface.create_for_data(buf, cairo.FORMAT_RGB24, width, height, width * 4)


def wallpapers():
    """{output name: path of the picture on it}, as the wallpaper daemon
    reports it (awww, formerly swww). Empty if it is not there or shows a
    plain colour."""
    tool = shutil.which("awww") or shutil.which("swww")
    if tool is None:
        return {}
    try:
        text = subprocess.run([tool, "query"], capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    return {m.group(1): m.group(2).strip() for m in
            re.finditer(r"(\S+): \d+x\d+.*?displaying: image: (.+)$", text, re.MULTILINE)}


def _ppm(raw):
    """A binary PPM, which is what grim and ImageMagick are asked for, as a
    pixbuf; None if it is not one."""
    magic, size, depth, rgb = raw.split(b"\n", 3)
    w, h = (int(n) for n in size.split())
    if magic != b"P6" or depth != b"255" or len(rgb) < w * h * 3:
        return None
    return GdkPixbuf.Pixbuf.new_from_bytes(
        GLib.Bytes.new(rgb), GdkPixbuf.Colorspace.RGB, False, 8, w, h, w * 3)


def _converted(path, width, height):
    """A picture GdkPixbuf has no loader for, by way of ImageMagick: at least
    `width` x `height`, on black where it is see-through. Raises ValueError
    with the reason if that does not work either.

    The wallpaper daemon reads more formats than GdkPixbuf has loaders for
    here (SVG for one: awww carries a renderer for it), and a list of
    loaders kept to match it is one that falls behind without a word.
    ImageMagick reads those and whatever comes next, and is asked only when
    GdkPixbuf has said no, so the usual wallpaper costs nothing more.

      -size      a drawing (SVG) is drawn at that size, not drawn small and
                 then enlarged; a picture made of pixels ignores it
      [0]        the first frame of something animated
      -strip     or a comment in the file lands in the header of the PPM
    """
    tool = shutil.which("magick")
    if tool is None:
        raise ValueError("GdkPixbuf has no loader for it, and there is no `magick` to ask")
    size = f"{width}x{height}"
    done = subprocess.run(
        [tool, "-size", size, f"{path}[0]", "-strip",
         "-background", "black", "-alpha", "remove", "-alpha", "off",
         "-colorspace", "sRGB", "-resize", f"{size}^", "-depth", "8", "ppm:-"],
        capture_output=True, timeout=10)
    full = _ppm(done.stdout) if done.returncode == 0 and done.stdout else None
    if full is None:
        said = done.stderr.decode(errors="replace").strip().splitlines()
        raise ValueError(said[-1] if said else "ImageMagick made nothing of it")
    return full


def wallpaper(path, width, height):
    """The wallpaper as it sits on the monitor (scaled to fill, centred),
    `width` x `height`, or None."""
    try:
        try:
            full = GdkPixbuf.Pixbuf.new_from_file(path)
        except GLib.Error:
            full = _converted(path, width, height)
        scale = max(width / full.get_width(), height / full.get_height())
        w = max(width, round(full.get_width() * scale))
        h = max(height, round(full.get_height() * scale))
        small = full.scale_simple(w, h, GdkPixbuf.InterpType.BILINEAR)
        return _surface(small.new_subpixbuf((w - width) // 2, (h - height) // 2, width, height))
    except (GLib.Error, cairo.Error, MemoryError, ValueError, OSError,
            subprocess.SubprocessError) as exc:
        # Said out loud (the journal): whatever needed this picture goes on
        # without it, and "without it" looks like nothing having happened.
        print(f"reverie: cannot read the wallpaper {path}: {exc}", flush=True)
        return None


def picture(identifier, width, height):
    """One window as a cairo surface `width` x `height`, or None."""
    try:
        raw = subprocess.run(["grim", "-t", "ppm", "-T", identifier, "-"],
                             capture_output=True, timeout=2).stdout
        full = _ppm(raw)
        if full is None:
            return None
        w, h = full.get_width(), full.get_height()
        width, height = max(1, min(w, width)), max(1, min(h, height))
        small = full.scale_simple(width, height, GdkPixbuf.InterpType.BILINEAR)
        return _surface(small)
    except (OSError, ValueError, subprocess.SubprocessError, GLib.Error, cairo.Error,
            MemoryError):
        return None


class Thumbs:
    def __init__(self, landed):
        self.landed = landed                 # called with an address, on the main loop
        self.shots = {}                      # address -> (surface, the window's size then)
        self.walls = {}                      # output -> (path, mtime, size, surface)
        self.busy = False
        self.able = bool(shutil.which("grim"))
        self.took = 0.0                      # how long the last round was, for `status`

    def get(self, address, size):
        """The picture of this window, if there is one and it still fits."""
        shot = self.shots.get(address)
        return shot[0] if shot is not None and shot[1] == tuple(size) else None

    def wall(self, output):
        """The wallpaper on that output at card size, if it has been read."""
        held = self.walls.get(output)
        return held[3] if held is not None else None

    def refresh(self, wants, alive, cards=None):
        """`wants`: [(address, the window's size, the scale to keep it at)].

        `alive` is every window there is: the pictures of the rest are let go.
        `cards`: {output: (width, height)} — the size to keep each monitor's
        wallpaper at; given when the panel opens, so a changed wallpaper is
        picked up then."""
        for address in [a for a in self.shots if a not in alive]:
            del self.shots[address]
        if self.busy or not self.able or not (wants or cards):
            return
        self.busy = True
        threading.Thread(target=self._work, args=(list(wants), dict(cards or {})),
                         daemon=True).start()

    def _walls(self, cards):
        for output, path in wallpapers().items():
            if output not in cards:
                continue
            try:
                key = (path, os.stat(path).st_mtime, cards[output])
            except OSError:
                continue
            held = self.walls.get(output)
            if held is not None and held[:3] == key:
                continue                     # the same picture as last time
            surface = wallpaper(path, *cards[output])
            if surface is not None:
                GLib.idle_add(self._wall_landed, output, key + (surface,))

    def _wall_landed(self, output, held):
        self.walls[output] = held
        self.landed(None)
        return False

    def _work(self, wants, cards):
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
            if cards:
                self._walls(cards)           # after the windows: it can wait, they cannot
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
