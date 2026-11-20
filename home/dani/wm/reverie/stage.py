"""stage: the HUD, on the graphics card. A program of its own.

What it shows is hud.py's panel — the same clock under the arc of the day,
the same gauges, the same chips for everything the bar carries, painted by
the same code. What is different is everything that moves.

  The desktop steps back.  The first frame is a capture of the screen as it
      stands, so nothing changes — and then that picture recedes into space
      and becomes the card of the workspace you are on. Behind it is the
      wallpaper, going out of focus as the picture leaves it.
  The other workspaces are there.  They stand to either side on a carousel,
      in true perspective, each one built from pictures of its own windows.
      Left and right turn the carousel; the one in front stands forward, in
      a pool of light.
  Going somewhere is travelling there.  The chosen card comes forward until
      it is the whole screen, and the panel lets go over the real thing.
      Leaving without choosing is the same journey back: the desktop returns
      to where it was.
  It answers the hand.  While it is pinned the carousel leans a degree or
      two towards the pointer.

Why a program of its own: all of that is a whole-monitor picture changing
every frame, with images scaled and turned in it. The daemon runs GTK's
software renderer — a third of the memory, and right for everything else in
it — where a frame of the plain panel is already 8 to 21 ms. GTK chooses its
renderer once per process, so, like the spotlight (spot.py), this is a second
process that chooses the GL one. Here a frame is a list of render nodes for
the graphics card to compose, and half a millisecond of Python.

And why its own captures: the first frame has to BE the desktop, or the rest
does not read as the desktop moving. grim needs 55 to 130 ms for the screen;
asked directly (capture.py) the compositor hands it over in about 15.

What it costs, measured on legionix (1440p, 165 Hz):

  - from the key to the first frame, about 30 ms: 15 for the capture, 15 to
    hand it to the graphics card. That frame is the screen, pixel for pixel
    (compared: no difference), so what is felt is when it starts to move;
  - after the machine has been idle for five seconds or more, about 85 ms,
    and the next tenth of a second at 30 to 60 frames a second instead of
    165. The graphics card idles at a tenth of its clock (210 MHz of 2100)
    and takes about a fifth of a second of work to leave it; nothing here
    can hurry that, only ask less of it, which most of the comments below
    are about. After that, and whenever the card is awake: every frame;
  - closing: gone in 0.26 s, every frame;
  - kept running, it holds about 190 MB of memory and 180 MB of the
    graphics card's. The plain panel needs neither (`reverie hud stage off`).

What that took, each learned by measuring a version that did not do it:

  - nothing is captured while anything moves (`_photograph`);
  - a picture is given to the graphics card between frames, never by the
    frame that first shows it (`hand_over`);
  - the surface is never unmapped, only moved under the windows (`stand`);
  - a card is laid out at the size it is seen at (`place_cards`);
  - as few passes over the screen as possible while the desktop is stepping
    back (`draw_backdrop`), and nothing painted with cairo per frame.

The daemon starts this at its own start, keeps it warm, and passes on the
`hud …` commands down a pipe (host.py); the panel's logic — hold, pin,
release, the keys — is hud.Hud's, inherited. If this program is not there or
stops answering, the daemon's own panel does the job as before.

On stdin, one per line:  hud <words>  ·  status  ·  ledger <json>  ·
font <name>  ·  ping.   On stdout:  pong  ·  status <text>  ·  beats 0|1  ·
want ledger  ·  up  ·  down  (the panel is on screen / has gone).
"""

import ctypes
import datetime
import json
import math
import os
import queue
import sys
import threading
import time
import weakref

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import common  # noqa: E402  (first: it pins the GI versions)
from common import (EFFECT, FONT, ICON_FAMILY, PAL, SPATIAL, Spring, focused_output,  # noqa: E402
                    hypr, hypr_events_path, ink, label, measure, rgba, text)

import cairo  # noqa: E402
import gi  # noqa: E402

gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Graphene", "1.0")
gi.require_version("Gsk", "4.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Graphene, Gsk, Gtk, Gtk4LayerShell  # noqa: E402

import capture  # noqa: E402
from hud import GAUGES, HERO, STALE, SWEEP, VIGNETTE, Hud  # noqa: E402
from thumbs import _surface, wallpapers  # noqa: E402

# The stage, in design px (px at 1440p) and degrees.
BASE = 560.0                 # a card's width where it stands
PERSPECTIVE = 1900.0         # from the eye to the plane the selected card's slot is in
RADIUS = 1500.0              # of the carousel
STEP = 26.0                  # between one card and the next
POP = PERSPECTIVE * (1.0 - 1.0 / HERO)     # how far the selected card stands forward: HERO x
FADE = (40.0, 75.0)          # a card turned this far starts to go; this far, it is gone
DEPTH_IN = 520.0             # how far back the neighbours start their entrance
CENTRE_Y = 716.0             # where the carousel's middle is, as in hud.py
TILT = (2.4, 1.6)            # degrees the carousel leans to the pointer, across and up
TINT = 0.52                  # bgDeep over the wallpaper when it is fully out of focus
GLOW = 0.16                  # the light behind the selected card, at its brightest
LABELS = 1.3                 # the cards' lettering is drawn this much larger than shown
FLY = (200.0, 23.0)          # the desktop stepping back: half-way in 0.1 s, in place by 0.3
RETURN = (900.0, 60.0)       # a card coming forward to be the screen: no overshoot, 90% in 130 ms
LET_GO = (0.93, 0.030)       # how far it has come when the panel starts to go, and how fast (s)
TURN = (190.0, 21.0)         # the carousel turning
LEAN = (70.0, 15.0)          # ... and leaning
FRESH = 5.0                  # s — for this long the capture is still the desktop as it is
LANDED = 0.38                # s after opening: the desktop is in its card and nothing moves
LAYERS = ("corners", "clock", "gauges", "title", "index", "bar", "hint")

try:
    _trim = ctypes.CDLL(None).malloc_trim
except (OSError, AttributeError):            # not glibc
    _trim = None


# ------------------------------------------------------------------ small things
def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def colour(role, alpha=1.0):
    c = Gdk.RGBA()
    c.red, c.green, c.blue = PAL[role]
    c.alpha = alpha
    return c


def rect(x, y, w, h):
    return Graphene.Rect().init(x, y, w, h)


def rrect(x, y, w, h, r):
    out = Gsk.RoundedRect()
    out.init_from_rect(Graphene.Rect().init(x, y, w, h), max(0.0, min(r, w / 2, h / 2)))
    return out


def stop(offset, role, alpha):
    s = Gsk.ColorStop()
    s.offset, s.color = offset, colour(role, alpha)
    return s


# Matrices: 4 x 4, row-major, acting on column vectors. Kept here rather than
# left to the snapshot's own perspective()/rotate_3d() so that a click can be
# traced back through exactly the transform the card was drawn with.
def mul(a, b):
    return tuple(sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4))
                 for r in range(4) for c in range(4))


def chain(*ms):
    out = ms[0]
    for m in ms[1:]:
        out = mul(out, m)
    return out


def move(x, y, z=0.0):
    return (1.0, 0.0, 0.0, x, 0.0, 1.0, 0.0, y, 0.0, 0.0, 1.0, z, 0.0, 0.0, 0.0, 1.0)


def grow(s):
    return (s, 0.0, 0.0, 0.0, 0.0, s, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)


def turn_y(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return (c, 0.0, s, 0.0, 0.0, 1.0, 0.0, 0.0, -s, 0.0, c, 0.0, 0.0, 0.0, 0.0, 1.0)


def turn_x(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return (1.0, 0.0, 0.0, 0.0, 0.0, c, -s, 0.0, 0.0, s, c, 0.0, 0.0, 0.0, 0.0, 1.0)


def lens(depth):
    """Perspective: a point `z` towards the eye is drawn 1 / (1 - z/depth) as
    large; the z = 0 plane is untouched."""
    return (1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, -1.0 / depth, 1.0)


def project(m, x, y):
    """Where the point (x, y, 0) of a card lands on the screen."""
    w = m[12] * x + m[13] * y + m[15]
    return (m[0] * x + m[1] * y + m[3]) / w, (m[4] * x + m[5] * y + m[7]) / w


def unproject(m, sx, sy):
    """The point of the card's plane that is drawn at (sx, sy), or None."""
    a, b, c = m[0], m[1], m[3]
    d, e, f = m[4], m[5], m[7]
    g, h, i = m[12], m[13], m[15]
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    if abs(det) < 1e-12:
        return None
    x = ((e * i - f * h) * sx + (c * h - b * i) * sy + (b * f - c * e)) / det
    y = ((f * g - d * i) * sx + (a * i - c * g) * sy + (c * d - a * f)) / det
    w = ((d * h - e * g) * sx + (b * g - a * h) * sy + (a * e - b * d)) / det
    return (x / w, y / w) if abs(w) > 1e-12 else None


def graphene(m):
    """Graphene keeps the transpose: row vectors, translation in the last row."""
    out = Graphene.Matrix()
    out.init_from_float([m[c * 4 + r] for r in range(4) for c in range(4)])
    return out


def bump(d):
    """How much a card `d` places from the front is the selected one."""
    return math.cos(math.pi * d / 2) ** 2 if abs(d) < 1.0 else 0.0


# ------------------------------------------------------------------ pictures
def texture_of_surface(surface):
    surface.flush()
    fmt = Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED \
        if surface.get_format() == cairo.FORMAT_ARGB32 else Gdk.MemoryFormat.B8G8R8X8
    return Gdk.MemoryTexture.new(surface.get_width(), surface.get_height(), fmt,
                                 GLib.Bytes.new(bytes(surface.get_data())), surface.get_stride())


def _opaque(layout):
    # Captures are opaque whatever their fourth byte says (it is 255 here,
    # but nothing promises that), so they are read as X, never as A.
    return Gdk.MemoryFormat.B8G8R8X8 if layout[0] == "B" else Gdk.MemoryFormat.R8G8B8X8


def texture_of_shot(shot):
    return Gdk.MemoryTexture.new(shot.width, shot.height, _opaque(shot.layout), shot.data,
                                 shot.stride)


def reduced_texture_of_shot(shot):
    """The same picture at half its size, scaled in C (GdkPixbuf does not
    care which byte is red, so the capture's own byte order goes straight
    through). Half is what a window's picture is kept at: four times what a
    card needs, so that it holds up while its card comes forward to be the
    screen, and a quarter of what the whole would weigh."""
    width, height = max(1, shot.width // 2), max(1, shot.height // 2)
    full = GdkPixbuf.Pixbuf.new_from_bytes(shot.data, GdkPixbuf.Colorspace.RGB, True, 8,
                                           shot.width, shot.height, shot.stride)
    small = full.scale_simple(width, height, GdkPixbuf.InterpType.BILINEAR)
    return Gdk.MemoryTexture.new(width, height, _opaque(shot.layout), small.read_pixel_bytes(),
                                 small.get_rowstride())


def texture_of_pixbuf(pixbuf):
    fmt = Gdk.MemoryFormat.R8G8B8A8 if pixbuf.get_has_alpha() else Gdk.MemoryFormat.R8G8B8
    return Gdk.MemoryTexture.new(pixbuf.get_width(), pixbuf.get_height(), fmt,
                                 pixbuf.read_pixel_bytes(), pixbuf.get_rowstride())


def wallpaper_levels(path, width, height):
    """The wallpaper as it sits on the monitor (scaled to fill, centred), at
    half size, and four copies of it further and further out of focus.

    Out of focus the way hud.frost does it: halved, then doubled back up,
    each doubling a linear interpolation — a wide even blur made almost
    entirely on images too small to cost anything. A copy is kept no larger
    than 640 px wide: what is left in it is so smooth that the graphics card
    can stretch it the rest of the way.

    The panel fades from each to the next as it opens, so the wallpaper goes
    out of focus rather than being swapped for a blurred one; and each is
    also darker than the one before, towards its corners most.
    """
    full = GdkPixbuf.Pixbuf.new_from_file(path)
    w, h = max(2, width // 2), max(2, height // 2)
    scale = max(w / full.get_width(), h / full.get_height())
    sw, sh = max(w, round(full.get_width() * scale)), max(h, round(full.get_height() * scale))
    sharp = full.scale_simple(sw, sh, GdkPixbuf.InterpType.BILINEAR) \
        .new_subpixbuf((sw - w) // 2, (sh - h) // 2, w, h).copy()

    def doubled(src):
        # With cairo, not GdkPixbuf: its enlargement leaves each source pixel
        # a soft-edged square, and four of those on top of each other were a
        # lattice across the whole backdrop. And not one interpolation but
        # the mean of four, half a pixel apart: a plain one is smooth but
        # creased along every line of the coarsest picture, and on a slow
        # gradient the creases show as faint stripes.
        out = cairo.ImageSurface(cairo.FORMAT_RGB24, src.get_width() * 2, src.get_height() * 2)
        ctx = cairo.Context(out)
        ctx.scale(2, 2)
        ctx.set_operator(cairo.OPERATOR_ADD)
        for ox, oy in ((-0.5, -0.5), (0.5, -0.5), (-0.5, 0.5), (0.5, 0.5)):
            ctx.set_source_surface(src, ox, oy)
            ctx.get_source().set_filter(cairo.FILTER_BILINEAR)
            ctx.get_source().set_extend(cairo.EXTEND_PAD)     # no dark fringe at the edges
            ctx.paint_with_alpha(0.25)
        return out

    levels, down = [texture_of_pixbuf(sharp)], sharp
    for step in range(1, 5):
        down = down.scale_simple(max(1, down.get_width() // 2), max(1, down.get_height() // 2),
                                 GdkPixbuf.InterpType.BILINEAR)       # halving: an average
        up = _surface(down)
        while up.get_width() * 2 <= max(640, w // 2):
            up = doubled(up)
        # ... and each a step further into shadow, darker towards its
        # corners: painted into the copy here, once, so that a frame does
        # not have to lay a tint and a gradient over the whole screen.
        share = step / 4
        uw, uh = up.get_width(), up.get_height()
        ctx = cairo.Context(up)
        ctx.set_source_rgba(*PAL["bgDeep"], TINT * share)
        ctx.paint()
        edge = cairo.RadialGradient(uw / 2, uh / 2, 0.42 * min(uw, uh),
                                    uw / 2, uh / 2, 0.5 * math.hypot(uw, uh))
        edge.add_color_stop_rgba(0.0, *PAL["bgDeep"], 0.0)
        edge.add_color_stop_rgba(1.0, *PAL["bgDeep"], VIGNETTE * share)
        ctx.set_source(edge)
        ctx.paint()
        levels.append(texture_of_surface(up))
    return levels


class Layer:
    """Something painted with cairo once and shown as a picture after that."""

    __slots__ = ("texture", "x", "y", "w", "h")

    def __init__(self, texture, x, y, w, h):
        self.texture, self.x, self.y, self.w, self.h = texture, x, y, w, h


def layer_of(painter, pad=2):
    """Paint with `painter(cr)` in the panel's own coordinates; what comes
    back is exactly as large as what was painted, and knows where it goes."""
    record = cairo.RecordingSurface(cairo.CONTENT_COLOR_ALPHA, None)
    painter(cairo.Context(record))
    x, y, w, h = record.ink_extents()
    if w < 1 or h < 1:
        return None
    x0, y0 = math.floor(x) - pad, math.floor(y) - pad
    width, height = math.ceil(x + w) - x0 + pad, math.ceil(y + h) - y0 + pad
    image = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    cr = cairo.Context(image)
    cr.set_source_surface(record, -x0, -y0)
    cr.paint()
    return Layer(texture_of_surface(image), x0, y0, width, height)


class Pic:
    """A window's picture, and the size the window had when it was taken."""

    __slots__ = ("size", "texture")

    def __init__(self, size, texture):
        self.size, self.texture = size, texture


class Canvas(Gtk.Widget):
    """The whole monitor, as render nodes rather than as a picture."""

    def __init__(self, stage):
        super().__init__()
        self.stage = stage

    def do_snapshot(self, snap):
        self.stage.compose(snap, self.get_width(), self.get_height())


# ------------------------------------------------------------------ the stage
class Stage(Hud):
    NAMESPACE = "reverie-stage"

    def __init__(self, app):
        super().__init__(app)
        # hud.Hud built a cairo drawing area; this draws with render nodes.
        self.canvas = Canvas(self)
        self.win.set_child(self.canvas)
        self.area = self.canvas              # what Hud asks for ticks, redraws and its size
        click = Gtk.GestureClick()
        click.connect("released", self.on_click)
        self.canvas.add_controller(click)
        pointer = Gtk.EventControllerMotion()
        pointer.connect("motion", self.on_motion)
        self.canvas.add_controller(pointer)
        if os.environ.get("REVERIE_DEBUG"):
            self.win.connect("realize", lambda w: (
                w.get_frame_clock().connect("before-paint", self._timed, "before"),
                w.get_frame_clock().connect("after-paint", self._timed, "after")))

        self.phase = "hidden"                # -> "arming" -> "open" -> "closing" -> "hidden"
        self.warming = False
        self.size = (2560, 1440)             # of the canvas, as last drawn (or as the monitor)
        self.opened_at = self.closed_at = 0.0
        self.exact = False                   # this opening began from a capture
        self.shot = None                     # the capture, as a texture
        self.shot_ws = None                  # ... and the workspace it is a picture of
        self.exit_ws = None                  # while closing: the card that becomes the screen
        self.going = False                   # ... and the panel has started to dissolve over it
        self.frames, self.worst, self.began = 0, 0.0, 0.0     # for the debug line
        self.paints, self.gaps, self.paint_at = [], [], 0.0
        self.switched = False                # ... and whether that is somewhere else
        self.openness = Spring(0.0, EFFECT)  # 0 -> 1: the wallpaper out of focus and dimmed
        self.ui = Spring(0.0, EFFECT)        # the instruments' opacity
        self.mix = Spring(0.0, EFFECT)       # this workspace's card: capture -> live pictures
        self.turn = Spring(0.0, TURN)        # which card is in front, as a place in self.ids
        self.lean = (Spring(0.0, LEAN), Spring(0.0, LEAN))     # towards the pointer, -1..1
        self.flights = {}                    # workspace -> Spring: 0 in its slot, 1 the screen
        self.cards = {}                      # workspace -> {"mon", "clients", "sig"}
        self.layers = {}                     # name -> Layer, painted with hud.py's own code
        self.dirty = set()                   # the ones to paint again
        self.card_layers = {}                # workspace -> (sig, texture): the lettering on it
        self.numerals = {}                   # text -> Layer
        self.signs = {}                      # name -> what its picture was painted from
        self.given = weakref.WeakSet()       # the pictures the graphics card has had (hand_over)
        self.pics = {}                       # address -> Pic
        self.fresh = set()                   # windows photographed since they were last on screen
        self.showing = set()                 # the workspaces that are on a monitor
        self.live = False                    # this opening: the windows in front have been retaken
        self.landed = False                  # ... and the desktop has reached its card
        self.after_id = self.tidy_id = 0
        self.pause = threading.Event()       # never set: a wait on it is a sleep
        self.walls = None                    # [sharp, …, furthest out of focus]
        self.wall_key = None
        self.quads = []                      # (workspace, matrix, q) as last drawn, back to front
        self.rounding, self.border = 16.0, 2.0
        self.asked_ledger = 0.0
        self.jobs = queue.Queue()
        threading.Thread(target=self._work, daemon=True).start()
        GLib.timeout_add_seconds(240, self._keep)

    def _mark(self, what):
        # (stdout is the line to the daemon here: say it on stderr.)
        if os.environ.get("REVERIE_DEBUG"):
            print(f"stage: {what} at {(time.monotonic() - self.asked_at) * 1000:.0f} ms",
                  file=sys.stderr, flush=True)

    # -- the worker: everything that waits on the compositor or on a file ---
    def _work(self):
        while True:
            job = self.jobs.get()
            try:
                job()
            except Exception as exc:         # a failed picture must not end the pictures
                print(f"stage: {exc!r}", file=sys.stderr, flush=True)
            # Captures pass through here as ten or fifteen megabytes each,
            # and glibc keeps what a thread's arena has freed (thumbs.py
            # measured 150 MB of it). Hand it back — but only while the panel
            # is away: trimming holds the allocator, and a frame that needs
            # memory in that moment waits for it.
            if _trim is not None and self.jobs.empty() and self.phase == "hidden":
                _trim(0)

    def _warm(self):
        """Pay the one-time costs before the first key: the wallpaper read
        and put out of focus, the bar's modules, the GL surface set up and
        the shaders compiled — by drawing one frame of everything a real
        frame uses, at an opacity nobody can see."""
        delay = (hypr("j/getoption input:repeat_delay") or {}).get("int")
        rate = (hypr("j/getoption input:repeat_rate") or {}).get("int")
        if delay and rate:
            self.repeat = (delay / 1000, 1 / rate)
        else:
            self.beats = False
        for name, key in (("rounding", "decoration:rounding"), ("border", "general:border_size")):
            value = (hypr(f"j/getoption {key}") or {}).get("int")
            if isinstance(value, int):
                setattr(self, name, float(value))
        self.bar.refresh()
        self.refresh()
        mon, info = focused_output()
        if mon is not None:
            Gtk4LayerShell.set_monitor(self.win, mon)
            self.output = mon.get_connector()
            geo = mon.get_geometry()
            self.size = (geo.width, geo.height)
        self.relayout()
        self.jobs.put(self._job_wall)
        self._photograph(showing=True, spaced=True)      # so the first opening has them all
        # Mapped now and for good — but under the windows (see `stand`).
        self.stand(False)
        self.warming = True
        self.win.set_visible(True)
        GLib.timeout_add(400, self._warm_done)
        return False

    def _warm_done(self):
        self.warming = False
        self.area.queue_draw()               # ... and empty again
        return False

    def stand(self, up):
        """Where the surface is: on the `overlay` layer while the panel is
        up, on the `bottom` one — under every window, with nothing drawn on
        it — the rest of the time.

        It is never unmapped. A window mapped afresh for each opening is a
        new GL surface with a new renderer: its first frame took 44 ms
        (measured) setting that up and handing every picture to the graphics
        card again, and the map itself is a round trip to the compositor
        before any frame at all. Kept, the surface, its renderer and what
        the graphics card holds are simply there, and moving it between
        layers is one request.

        Under the windows rather than over them, because an overlay surface
        that is mapped — even an empty one — keeps the compositor from
        handing a fullscreen game straight to the display (it looks at the
        `top` and `overlay` layers for that, not below).
        """
        Gtk4LayerShell.set_layer(self.win, Gtk4LayerShell.Layer.OVERLAY if up
                                 else Gtk4LayerShell.Layer.BOTTOM)

    # -- what there is to show ----------------------------------------------
    def read(self):
        """The desktop as it is: three questions, a fifth of a millisecond."""
        try:
            self.snapshot = {
                "monitors": hypr("j/monitors") or [],
                "clients": hypr("j/clients") or [],
                "active": (hypr("j/activewindow") or {}).get("address"),
            }
        except OSError:
            pass

    def refresh(self):
        """hud.Hud.refresh, without the 20 ms: reading the machine is one
        file per core for the temperatures, each of which wakes that core.
        That goes to the worker; the gauges show the reading before until it
        is back."""
        self.read()
        self.jobs.put(self._job_stats)

    def _job_stats(self, graphics=True):
        """`graphics`: also ask the graphics card how busy it is. That is
        nvidia-smi, which stops the card's own work for a moment while it
        looks — the well-known stutter — so it is only asked while nothing
        on the panel is moving (the two-second readings), never as it opens."""
        self.stats.sample(slow=graphics)
        GLib.idle_add(self._sampled)

    def _sampled(self):
        self._aim_gauges()
        self.dirty |= {"gauges", "corners"}
        if self.shown:
            self._ensure_tick()
        return False

    def metrics(self):
        w, h = self.size
        u = h / 1440.0
        cw = BASE * u
        return w, h, u, cw, cw * h / w

    def relayout(self):
        """The workspaces and their windows, from the last reading."""
        mons = {m["id"]: m for m in self.snapshot["monitors"]}
        by_ws = {}
        for c in self.snapshot["clients"]:
            ws = c.get("workspace", {}).get("id", -1)
            if c.get("mapped", True) and ws >= 0 and min(c["size"]) >= 1:
                by_ws.setdefault(ws, []).append(c)
        showing = {m["activeWorkspace"]["id"] for m in mons.values()}
        self.here = next((m["activeWorkspace"]["id"] for m in mons.values() if m.get("focused")),
                         None)
        cards = {}
        for wid in sorted(set(by_ws) | showing):
            clients = by_ws.get(wid, [])
            mon = mons.get(clients[0]["monitor"]) if clients else next(
                (m for m in mons.values() if m["activeWorkspace"]["id"] == wid), None)
            if mon is None:
                continue
            # Back to front, as the compositor stacks them.
            clients = sorted(clients, key=lambda c: (bool(c.get("fullscreen")),
                                                     bool(c.get("floating")),
                                                     -c.get("focusHistoryID", 0)))
            sig = tuple((c["address"], tuple(c["at"]), tuple(c["size"]), c.get("class"),
                         c.get("title"), c["address"] == self.snapshot["active"],
                         bool(c.get("xwayland"))) for c in clients)
            cards[wid] = {"mon": mon, "clients": clients, "sig": sig}
        self.cards = cards
        self.ids = list(cards)
        self.showing = showing
        if self.cursor not in cards:
            self.cursor = self.here if self.here in cards else (self.ids[0] if self.ids else None)
        for wid in [w for w in self.card_layers if w not in cards]:
            del self.card_layers[wid]
        alive = {c["address"] for c in self.snapshot["clients"]}
        for address in [a for a in self.pics if a not in alive]:
            del self.pics[address]
        for address in [a for a in self.reveal if a not in alive]:
            del self.reveal[address]
        # A window that is on screen is drawing: no picture of it stays true.
        self.fresh = {a for a in self.fresh if a in alive} - {
            c["address"] for wid in showing if wid in cards for c in cards[wid]["clients"]}

    def place(self, wid):
        return self.ids.index(wid) if wid in self.ids else 0

    def pic(self, client):
        """The picture of this window, if there is one that still fits it."""
        held = self.pics.get(client["address"])
        if held is None or held.size != tuple(client["size"]):
            return None
        return held.texture

    def composed(self, wid):
        """Every window of that workspace has its picture."""
        card = self.cards.get(wid)
        return card is not None and all(self.pic(c) is not None for c in card["clients"])

    # -- pictures -----------------------------------------------------------
    def _photograph(self, showing, spaced=False):
        """Ask for windows' pictures (capture.py): of every window that has
        none that fits or has been on screen since its last one, and — with
        `showing` — of the ones that are on screen now.

        WHEN this is called is the whole design. Taking a window's picture
        stops the compositor for a few milliseconds while it reads the
        pixels back, and every frame of ours waits behind that. The first
        version asked for all of them as the panel opened: the desktop's
        step back began with frames 50, 30 and 24 ms long (measured), which
        is a stutter exactly where the eye is. So:

          - a window on a workspace that is not showing is not drawing, so
            its picture stays true: it is taken once, shortly after its
            workspace is left (`elsewhere`), one window at a time
            (`spaced`), while the panel is nowhere to be seen;
          - nothing is taken while the panel opens. Its cards have those
            pictures already, and the card of the workspace in front is the
            capture of the screen itself;
          - the windows in front are taken when the desktop has landed in
            its card and nothing is moving, and again with each reading of
            the gauges.

        Returns whether anything was asked for.
        """
        wants = []
        for wid, card in self.cards.items():
            on_screen = wid in self.showing
            for c in card["clients"]:
                if on_screen and not showing:
                    continue
                if not on_screen:
                    if c["address"] in self.fresh and self.pic(c) is not None:
                        continue
                    self.fresh.add(c["address"])
                wants.append((c["address"], tuple(c["size"])))
        if wants:
            token = self.token if showing else None
            self.jobs.put(lambda: self._job_pics(wants, spaced, token))
        return bool(wants)

    def _job_pics(self, wants, spaced, token):
        try:
            for group in ([[w] for w in wants] if spaced else [wants]):
                _none, shots = capture.grab(None, [w[0] for w in group])
                for address, size in group:
                    shot = shots.get(address)
                    if shot is not None:
                        GLib.idle_add(self._pic_landed, address, size, reduced_texture_of_shot(shot))
                if spaced:
                    self.pause.wait(0.08)    # one at a time: nobody notices one
        finally:
            GLib.idle_add(self._pics_done, token)

    def _pic_landed(self, address, size, texture):
        self.pics[address] = Pic(size, texture)
        if self.phase == "hidden":
            self.hand_over([(texture, True)])        # now, while nobody is waiting for a frame
        if address not in self.reveal:
            self.reveal[address] = Spring(0.0, EFFECT)       # a first picture fades in
        self.reveal[address].target = 1.0
        if self.phase != "hidden":
            self._ensure_tick()
        return False

    def _pics_done(self, token):
        if token is not None and token == self.token and self.phase == "open":
            self.live = True                 # the windows in front are as they are now
            self._ensure_tick()
        return False

    def elsewhere(self):
        """Something changed on the desktop (a workspace left, a window
        opened or moved). Once it has settled, and if the panel is not up:
        the pictures that have gone stale."""
        if self.after_id:
            GLib.source_remove(self.after_id)
        self.after_id = GLib.timeout_add(700, self._elsewhere)

    def _elsewhere(self):
        self.after_id = 0
        if self.phase == "hidden":
            self.read()
            self.relayout()
            self._photograph(showing=False, spaced=True)
        return False

    def hand_over(self, textures, again=False):
        """Give pictures to the graphics card now, between frames.

        A picture is uploaded the first time a frame shows it, and the frame
        waits: 16 ms for one the size of the screen, a few for a window's.
        The wait is not the problem — a late frame is. GTK paces frames by
        what the last ones took, and after one long frame it ran the next
        dozen at every second refresh (measured: 12 ms apart with 2 ms of
        work in each), which is the desktop's step back at half its
        smoothness. So whatever a coming frame will need is drawn once here,
        a few pixels large into a picture nobody keeps, with the surface's
        own renderer: after that it is there, and no frame waits.
        """
        renderer = self.win.get_renderer()
        # Only what it has not been given already (unless `again`: _keep).
        # Even for pictures it has, the asking is work for the graphics
        # card, and as the panel opens that is the very moment the
        # compositor needs the card for the capture (measured, after an
        # idle spell: 17 ms of asking, and a capture 10 ms slower for it).
        textures = [t for t in textures if t[0] is not None
                    and (again or t[0] not in self.given)]
        if renderer is None or not textures:
            return
        for texture, _reduced in textures:
            self.given.add(texture)
        snap = Gtk.Snapshot()
        for i, (texture, reduced) in enumerate(textures):
            # As the frames will ask for it: a picture that they filter
            # through its reductions needs those made too, and one that
            # they do not must not be given them for nothing.
            snap.append_scaled_texture(texture, Gsk.ScalingFilter.TRILINEAR if reduced
                                       else Gsk.ScalingFilter.LINEAR, rect(i * 4, 0, 4, 4))
        node = snap.to_node()
        if node is not None:
            try:
                renderer.render_texture(node, rect(0, 0, 4 * len(textures), 4))
            except GLib.Error:
                pass                         # then the frame that shows it does the work

    def at_hand(self):
        """Every picture the panel is made of, as it stands, and whether it
        is shown smaller than it is."""
        out = [(t, False) for t in self.walls or []]
        out += [(t, True) for t in (self.walls or [])[:1]]       # ... and, sharp, on every card
        out += [(held.texture, False) for held in self.layers.values() if held is not None]
        out += [(held[1], True) for held in self.card_layers.values()]
        out += [(held.texture, True) for held in self.numerals.values()]
        out += [(held.texture, True) for held in self.pics.values()]
        return out

    def _job_capture(self, token, output):
        began = time.monotonic()
        shot, _none = capture.grab(output)
        texture = texture_of_shot(shot) if shot is not None else None
        if os.environ.get("REVERIE_DEBUG"):
            print(f"stage: the capture was begun {(began - self.asked_at) * 1000:.0f} ms in and took "
                  f"{(time.monotonic() - began) * 1000:.0f} ms"
                  + (f" ({shot.took * 1000:.0f} of them the compositor's)" if shot else ""),
                  file=sys.stderr, flush=True)
        GLib.idle_add(self._captured, token, texture)

    def _job_wall(self):
        output = self.output
        path = wallpapers().get(output) if output else None
        if not path:
            return
        try:
            key = (path, os.stat(path).st_mtime, self.size)
        except OSError:
            return
        if key == self.wall_key:
            return                           # the picture that is already here
        levels = wallpaper_levels(path, *self.size)
        GLib.idle_add(self._wall_landed, key, levels)

    def _wall_landed(self, key, levels):
        self.wall_key, self.walls = key, levels
        if self.phase != "hidden":
            self._ensure_tick()
        else:
            self.hand_over(self.at_hand())
        return False

    def _keep(self):
        """Every few minutes while the panel is away: show the renderer its
        pictures again. It forgets what it has not drawn for a while (ten
        minutes as host.py starts this, fifteen seconds by default), and
        whatever it has forgotten the next opening has to wait for."""
        if self.phase == "hidden":
            self.hand_over(self.at_hand(), again=True)
        return True

    # -- show / hide ----------------------------------------------------------
    def show(self, sticky=False):
        if self.hold_id:
            GLib.source_remove(self.hold_id)
            self.hold_id = 0
        if not sticky:
            # A held panel must not be able to outstay the hand that holds it.
            self.hold_id = GLib.timeout_add_seconds(10, self._expire)
        if self.phase == "closing":
            if self.switched or self.exit_ws is None:
                self._finish()               # on its way somewhere else: start afresh
            else:
                # On its way back to the desktop: turn it round where it is.
                self.shown, self.sticky, self.phase = True, sticky, "open"
                flight = self.flights.get(self.exit_ws)
                if flight is not None:
                    flight.k, flight.c = FLY
                    flight.target = 0.0
                self.openness.target = self.alpha.target = 1.0
                self.alpha.v = 0.0
                self.exit_ws, self.going = None, False
                self._keyboard()
                self._ensure_tick()
                return
        if self.shown:
            if sticky != self.sticky:
                self.sticky = sticky
                self.dirty.add("hint")
                self._keyboard()
                self.area.queue_draw()
            return
        self.shown, self.sticky = True, sticky
        self.cursor = None                   # start on the workspace you are on
        self.token += 1
        self.asked_at = time.monotonic()
        mon, _info = focused_output()
        if mon is not None:
            Gtk4LayerShell.set_monitor(self.win, mon)
            self.output = mon.get_connector()
            geo = mon.get_geometry()
            self.size = (geo.width, geo.height)
        # Raised, with nothing drawn on it, and the capture asked for — both
        # before anything that takes time: everything below happens while
        # the compositor is taking the picture, through the empty surface.
        # The first frame that has anything in it is that picture.
        self.stand(True)
        self.jobs.put(lambda token=self.token, output=self.output:
                      self._job_capture(token, output))
        self.read()
        self.relayout()
        self._aim_gauges()                   # at the last reading, until there is a new one
        self._mark("data read")
        self.phase = "arming"
        self.entered = self.live = self.landed = False
        self.shot, self.shot_ws, self.exit_ws = None, self.here, None
        self.flights, self.arrive, self.going = {}, {}, False
        for spring in (self.alpha, self.openness, self.ui, self.mix, self.rise, *self.lean):
            spring.x = spring.v = spring.target = 0.0
        # Everything cairo paints, now, while the capture is on its way —
        # not on the frame that first shows it, mid-flight. (Nearly always
        # there is nothing to do: a picture is kept until what it was painted
        # from changes.)
        self.dirty |= set(LAYERS)
        for name in LAYERS:
            self.layer(name)
        for wid in self.ids:
            self.lettering(wid)
            self.numeral(wid)
        self._mark("painted")
        self.hand_over(self.at_hand())       # (while the capture is being taken)
        self._mark("at hand")
        self._keyboard()
        GLib.timeout_add(90, self._unarmed, self.token)
        self.bar_age = 0
        if not self.timer_id:
            self.timer_id = GLib.timeout_add(2000, self.on_timer)

    def _keyboard(self):
        Gtk4LayerShell.set_keyboard_mode(
            self.win, Gtk4LayerShell.KeyboardMode.EXCLUSIVE if self.sticky and self.shown
            else Gtk4LayerShell.KeyboardMode.NONE)
        self._apply_input()

    def _captured(self, token, texture):
        if token == self.token and self.phase == "arming":
            self.shot = texture
            self._mark("captured" if texture is not None else "no capture")
            self.hand_over([(texture, False)])
            self._mark("handed over")
            self._open()
        return False

    def _unarmed(self, token):
        """The capture did not come: open without it rather than not at all."""
        if token == self.token and self.phase == "arming":
            self._mark("capture late")
            self._open()
        return False

    def _open(self):
        self.phase = "open"
        self.opened_at = time.monotonic()
        self.shown_at = self.opened_at
        self.exact = self.shot is not None and self.here in self.cards
        self.turn.x = self.turn.target = float(self.place(self.cursor))
        self.turn.v = 0.0
        if self.exact:
            # Frame one is the screen. From there the desktop steps back.
            self.alpha.x = self.alpha.target = 1.0
            flight = Spring(1.0, FLY)
            flight.target = 0.0
            self.flights[self.here] = flight
        else:
            self.alpha.target = 1.0          # nothing to step back from: fade in
        self.arrive = {wid: Spring(0.0, SPATIAL) for wid in self.ids if wid not in self.flights}
        self.openness.target = 1.0
        self.rise.target = 1.0
        self.first_frame = True
        self._ensure_tick()

    def hide(self):
        if self.hold_id:
            GLib.source_remove(self.hold_id)
            self.hold_id = 0
        if not self.shown:
            return
        self._close(self.here if self.here in self.cards else None, switched=False)

    def leave(self, wid):
        """Gone to a workspace: its card comes forward until it is the whole
        screen, and only then does the panel let go — over the real thing.
        The switch itself has already been asked for and waits for none of
        this; the keyboard and the pointer go back at once."""
        if not self.shown:
            return
        card = self.cards.get(wid)
        there = self.phase == "open" and card is not None and \
            card["mon"].get("name") == self.output
        self._close(wid if there else None, switched=wid != self.here)

    def _close(self, exit_ws, switched):
        if self.hold_id:
            GLib.source_remove(self.hold_id)
            self.hold_id = 0
        self.shown = False
        self._keyboard()                     # the keyboard and the pointer, back at once
        if self.phase == "arming":
            self._finish()
            return
        self.phase = "closing"
        self.closed_at = time.monotonic()
        self.exit_ws, self.switched = exit_ws, switched
        self.ui.target = 0.0
        self.going = exit_ws is None         # nothing to travel on: simply fade
        if exit_ws is not None:
            flight = self.flights.get(exit_ws) or Spring(0.0, RETURN)
            flight.k, flight.c = RETURN
            flight.target = 1.0
            self.flights[exit_ws] = flight
            if not switched:
                self.openness.target = 0.0   # the wallpaper comes back into focus under it
                if self.shot is not None and exit_ws == self.shot_ws and \
                        time.monotonic() - self.opened_at < FRESH:
                    self.mix.target = 0.0    # the capture is still the truth: end on it
        self._ensure_tick()

    def _finish(self):
        """Gone from the screen. Let go of everything that is only worth
        keeping while it is up."""
        self.phase = "hidden"
        print("down", flush=True)
        self.stand(False)
        self.area.queue_draw()               # one last frame, with nothing in it
        self.shown = False
        self.shot = None                     # ~15 MB, here and on the graphics card
        self.flights, self.exit_ws, self.going = {}, None, False
        self.tick_id = 0
        self._paced("gone")
        self.jobs.put(lambda: None)          # wakes the worker, which tidies up after the show
        if self.tidy_id:
            GLib.source_remove(self.tidy_id)
        self.tidy_id = GLib.timeout_add(1500, self._tidy)

    def _tidy(self):
        """A moment after the panel has gone: whatever it learned while it
        was up (the bar's modules, the machine's readings) is painted and
        given to the graphics card now, so that the next opening finds
        everything as it left it and has nothing to do but open."""
        self.tidy_id = 0
        if self.phase == "hidden":
            for name in LAYERS:
                self.layer(name)
            for wid in self.ids:
                self.lettering(wid)
                self.numeral(wid)
            self.hand_over(self.at_hand())
        return False

    # -- input ----------------------------------------------------------------
    def on_motion(self, _controller, x, y):
        w, h = self.size
        self.lean[0].target = clamp(x / max(1, w) * 2 - 1, -1.0, 1.0)
        self.lean[1].target = clamp(y / max(1, h) * 2 - 1, -1.0, 1.0)
        if self.phase == "open":
            self._ensure_tick()

    def on_click(self, _gesture, _n, x, y):
        _w, _h, _u, cw, ch = self.metrics()
        for wid, matrix, q in reversed(self.quads):          # the one in front first
            at = unproject(matrix, x, y)
            if at is None:
                continue
            at = (at[0] / q, at[1] / q)      # laid out q times its size: see draw_carousel
            if not (0 <= at[0] <= cw and 0 <= at[1] <= ch):
                continue
            card = self.cards.get(wid)
            if card is None:
                break
            mon = card["mon"]
            gx = mon["x"] + at[0] / cw * mon["width"] / mon["scale"]
            gy = mon["y"] + at[1] / ch * mon["height"] / mon["scale"]
            for c in reversed(card["clients"]):
                if c["at"][0] <= gx <= c["at"][0] + c["size"][0] and \
                        c["at"][1] <= gy <= c["at"][1] + c["size"][1]:
                    hypr(f"dispatch focuswindow address:{c['address']}")
                    break
            else:
                hypr(f"dispatch workspace {wid}")
            self.leave(wid)
            return
        self.hide()

    # -- data -------------------------------------------------------------------
    def on_timer(self):
        if not self.shown:
            self.timer_id = 0
            return False
        self.refresh()                       # (the machine's readings follow, from the worker)
        self.relayout()
        if self.phase == "open" and self.landed:
            self._photograph(showing=True)
        self.dirty |= {"corners", "clock", "gauges"}
        self.bar_age += 1
        if self.bar_age >= 5:                # pinned: the bar's modules every ~10 s
            self.bar_age = 0
            self.bar.refresh()
        if time.monotonic() - self.asked_ledger > 10:
            self.asked_ledger = time.monotonic()
            print("want ledger", flush=True)
        self._ensure_tick()
        return True

    def _bar_landed(self):
        self.dirty |= {"bar", "title"}
        if self.shown:
            self._ensure_tick()

    def _stats_landed(self):
        self.dirty |= {"gauges", "corners"}
        return super()._stats_landed()

    def restyle(self):
        """The voice changed (`reverie font …`): every picture of text is stale."""
        self.layers, self.card_layers, self.numerals = {}, {}, {}
        if self.shown:
            self._ensure_tick()

    # -- animation --------------------------------------------------------------
    def tick(self, _widget, clock):
        now = clock.get_frame_time() / 1e6
        if self.last is None:
            dt, self.frames, self.worst, self.began = 0.006, 0, 0.0, now
            if self.phase == "open" and not self.entered:
                self.paints, self.gaps = [], []
        else:
            dt = now - self.last
            self.frames += 1
            self.worst = max(self.worst, dt)
            if len(self.gaps) < 14:
                self.gaps.append(dt * 1000)
            dt = min(0.05, dt)
        self.last = now
        if self.phase == "hidden":
            self.tick_id = 0
            return False
        since = time.monotonic() - self.opened_at
        opening = self.phase == "open"
        waiting = False

        if opening:
            self.ui.target = 1.0 if since > 0.07 else 0.0
            if self.turn.target != float(self.place(self.cursor)):
                self.turn.target = float(self.place(self.cursor))
                self.dirty.add("index")
            if not self.landed and since > LANDED:
                # In its card, nothing moving: now the windows in front can
                # be photographed (see _photograph for why not before) — and
                # everything else that costs something can be looked up: the
                # bar's modules (a dozen scripts), the wallpaper (has it
                # changed?). Until they are back the panel shows what it knew.
                self.landed = True
                if not self._photograph(showing=True):
                    self.live = True         # nothing in front to take
                self.bar.refresh()
                self.jobs.put(self._job_wall)
                self.jobs.put(lambda: self._job_stats(graphics=False))
            # The card of this workspace shows the capture until its windows'
            # own pictures, as they are now, are all there.
            if self.exact and self.live and self.composed(self.shot_ws):
                self.mix.target = 1.0
        for spring in (self.alpha, self.openness, self.ui, self.mix, self.rise, self.turn,
                       *self.lean):
            spring.step(dt)
        for spring in self.reveal.values():
            spring.step(dt)
        for wid, flight in list(self.flights.items()):
            flight.step(dt)
            if opening and flight.target == 0.0 and flight.resting:
                del self.flights[wid]        # landed: a card like the others
        at = self.place(self.here)
        for wid, spring in self.arrive.items():
            if opening and since < 0.03 + abs(self.place(wid) - at) * SWEEP:
                waiting = True               # the neighbours set off one after another
            else:
                spring.target = 1.0
            spring.step(dt)
        # (The gauges are simply at their readings. hud.py sweeps them up
        # one after another, which here would be cairo painting and a new
        # picture every frame of the entrance — on a processor that is as
        # freshly woken as the graphics card.)
        for key, _name in GAUGES:
            spring = self.gauge[key]
            if spring.x != self.goal[key]:
                spring.x = spring.target = self.goal[key]
                spring.v = 0.0
                self.dirty.add("gauges")

        if self.phase == "closing":
            # A spring's last few percent take as long as its first ninety,
            # and waiting them out was most of a 0.75 s exit (simulated). The
            # card is all but the screen well before that, and what it shows
            # is what is under it: the panel starts to dissolve then, and is
            # gone a tenth of a second later.
            flight = self.flights.get(self.exit_ws)
            if flight is None or flight.x > LET_GO[0]:
                self.going = True
            if self.going:
                self.alpha.x *= math.exp(-dt / LET_GO[1])
                self.alpha.target, self.alpha.v = self.alpha.x, 0.0     # the spring has no say now
            # Whatever else: a panel that has been told to go is gone within
            # the second. (Simulated before it ever ran: the spring above was
            # still pulling towards 1, and the panel settled at 4% — a whole-
            # screen surface nobody could see, mapped for good.)
            if self.alpha.x < 0.02 or time.monotonic() - self.closed_at > 0.8:
                self._finish()
                return False
        self.area.queue_draw()
        if opening:
            settled = not waiting and not self.flights and all(
                s.resting for s in (self.alpha, self.openness, self.ui, self.mix, self.rise,
                                    self.turn, *self.lean, *self.reveal.values(),
                                    *self.arrive.values()))
            if settled and self.landed:
                self.entered = True
                self.tick_id = 0             # nothing is moving: stop drawing frames
                self._paced("at rest")
                return False
        return True

    def _timed(self, clock, phase):
        """Debug only: how long the first frames of an opening spend being
        painted, as against waiting for the compositor."""
        if phase == "before":
            self.paint_at = time.monotonic()
        elif len(self.paints) < 14 and self.paint_at:
            self.paints.append((time.monotonic() - self.paint_at) * 1000)

    def _paced(self, what):
        if os.environ.get("REVERIE_DEBUG") and self.last is not None and self.frames:
            print(f"stage: {what}: {self.frames} frames over {(self.last - self.began) * 1000:.0f} "
                  f"ms, longest wait for one {self.worst * 1000:.0f} ms"
                  + (" · first frames, paint ms: " + " ".join(f"{p:.0f}" for p in self.paints)
                     + " · tick gaps ms: " + " ".join(f"{g:.0f}" for g in self.gaps)
                     if what == "at rest" else ""), file=sys.stderr, flush=True)

    # -- drawing: what cairo paints once ------------------------------------------
    def sign(self, name):
        """What a layer's picture depends on: it is painted again only when
        this changes."""
        minute = datetime.datetime.now().strftime("%j %H:%M")
        voice = FONT["name"]
        if name == "clock":
            # The arc, the sun and the focus band move a pixel every two
            # minutes; the digits every one.
            totals = self.ledger.totals()[:4] if self.ledger is not None else []
            return minute, tuple((cls, int(sec // 60)) for cls, sec in totals), voice
        if name == "corners":
            return minute, self.stats.info["gen"], voice
        if name == "gauges":
            return (tuple(round(self.gauge[k].x, 3) for k, _n in GAUGES),
                    tuple(self.stats.values[k] if self.stats.values[k] is None
                          else round(self.stats.values[k], 2) for k, _n in GAUGES),
                    self.stats.charging, voice)
        if name == "bar":
            return tuple((it["text"], it["detail"], it["role"]) for it in self.bar.items), voice
        if name == "title":
            return self.bar.title, voice
        if name == "index":
            return tuple(self.ids), self.cursor, self.here, voice
        return self.sticky, voice            # hint

    def layer(self, name):
        if name in self.dirty or name not in self.layers:
            self.dirty.discard(name)
            sign = self.sign(name)
            if name in self.layers and sign == self.signs.get(name):
                return self.layers[name]     # asked to look again; nothing has changed
            self.signs[name] = sign
            w, h, u, _cw, ch = self.metrics()
            painters = {
                "corners": lambda cr: self.draw_corners(cr, u, 1.0),
                "clock": lambda cr: self.draw_clock(cr, w / 2, 92 * u, u, 1.0),
                "gauges": lambda cr: self.draw_gauges(cr, w - 64 * u, 100 * u, u, 1.0),
                "bar": lambda cr: self.draw_bar(cr, w, 1104 * u, u, 1.0),
                # hyprland/window: what the bar prints next to the workspaces.
                "title": lambda cr: self.bar.title and text(
                    cr, self.bar.title, w / 2, CENTRE_Y * u - ch * HERO / 2 - 58 * u, 15 * u,
                    "muted", 1.0, family=ICON_FAMILY, weight=400, align="center"),
                "index": lambda cr: self.draw_index(cr, w / 2, 1056 * u, u),
                # 1…0 is how the keybinds palette writes the number row: 0 is ten.
                "hint": lambda cr: self.sticky and text(
                    cr, label("1…0 workspaces 1-10   ·   ← → enter   ·   click a window   ·   esc"),
                    w / 2, h - 58 * u, 13 * u, "hint", 1.0, weight=FONT["strong"],
                    align="center", spacing=FONT["track"] * u),
            }
            self.layers[name] = layer_of(painters[name])
        return self.layers[name]

    def draw_index(self, cr, cx, y, u):
        """Every workspace by its number, in one line: the carousel shows the
        one in front and two to either side, and with more than five there
        are some it does not. The one in front is `fg`; where you are has the
        accent dot under it."""
        if len(self.ids) <= 5:
            return
        size, gap = 15 * u, 26 * u
        widths = [measure(cr, str(wid), size, weight=FONT["regular"])[0] for wid in self.ids]
        x = cx - (sum(widths) + gap * (len(widths) - 1)) / 2
        for wid, tw in zip(self.ids, widths):
            text(cr, str(wid), x, y, size, "fg" if wid == self.cursor else "hint", 1.0,
                 weight=FONT["regular"])
            if wid == self.here:
                rgba(cr, "accent", 1.0)
                cr.new_path()
                cr.arc(x + tw / 2, y + size * 1.55, 2.2 * u, 0, math.tau)
                cr.fill()
            x += tw + gap

    def lettering(self, wid):
        """What is written on a card: each window's name and title on a shade
        at its top edge, as on hud.py's cards. One picture per card, painted
        again only when its windows change."""
        card = self.cards[wid]
        held = self.card_layers.get(wid)
        if held is not None and held[0] == card["sig"]:
            return held[1]
        _w, _h, u, cw, ch = self.metrics()
        image = cairo.ImageSurface(cairo.FORMAT_ARGB32, math.ceil(cw * LABELS),
                                   math.ceil(ch * LABELS))
        cr = cairo.Context(image)
        cr.scale(LABELS, LABELS)
        mon, clients = card["mon"], card["clients"]
        sx, sy = cw / (mon["width"] / mon["scale"]), ch / (mon["height"] / mon["scale"])
        ts = 12.5 * u
        if not clients:
            _tw, th = measure(cr, label("empty"), 12 * u)
            text(cr, label("empty"), cw / 2, (ch - th) / 2, 12 * u, "hint", 1.0, align="center",
                 spacing=FONT["track"] * u)
        for c in clients:
            px, py = (c["at"][0] - mon["x"]) * sx, (c["at"][1] - mon["y"]) * sy
            pw, ph = c["size"][0] * sx, c["size"][1] * sy
            room = pw - 18 * u
            if room <= 40 * u or ph <= ts * 1.5 + 12 * u:
                continue
            focused = c["address"] == self.snapshot["active"]
            title = (c.get("title") or "").strip()
            titled = bool(title) and ph > ts * 3.0 + 12 * u
            depth = min(ph, ts * (4.6 if titled else 3.0))
            shade = cairo.LinearGradient(0, py, 0, py + depth)
            shade.add_color_stop_rgba(0.0, *PAL["bgDeep"], 0.86)
            shade.add_color_stop_rgba(0.55, *PAL["bgDeep"], 0.60)
            shade.add_color_stop_rgba(1.0, *PAL["bgDeep"], 0.0)
            cr.rectangle(px, py, pw, depth)
            cr.set_source(shade)
            cr.fill()
            # XWayland windows carry a mark: they are the ones paying the
            # extra latency, and nothing else on screen says so.
            name = (c.get("class") or "?").lower() + ("  ·x11" if c.get("xwayland") else "")
            text(cr, name, px + 9 * u, py + 7 * u, ts, "fg" if focused else "subtle", 1.0,
                 weight=FONT["regular"], width=room)
            if titled:
                text(cr, title, px + 9 * u, py + 7 * u + ts * 1.5, ts - 1.0 * u, "muted", 1.0,
                     family=ICON_FAMILY, weight=400, width=room)
        texture = texture_of_surface(image)
        self.card_layers[wid] = (card["sig"], texture)
        return texture

    def numeral(self, wid):
        """A workspace's number, set like the title card's: thin, placed by
        the digit's own box."""
        key = (str(wid), FONT["name"])
        if key not in self.numerals:
            u = self.metrics()[2]
            size = 50 * u * LABELS
            scratch = cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1))
            ix, iy, iw, ih = ink(scratch, str(wid), size, weight=FONT["numeral_weight"])
            image = cairo.ImageSurface(cairo.FORMAT_ARGB32, math.ceil(iw) + 4, math.ceil(ih) + 4)
            text(cairo.Context(image), str(wid), 2 - ix, 2 - iy, size, "fg", 1.0,
                 weight=FONT["numeral_weight"])
            self.numerals[key] = Layer(texture_of_surface(image), 0, 0,
                                       image.get_width() / LABELS, image.get_height() / LABELS)
        return self.numerals[key]

    # -- drawing: what the graphics card composes ---------------------------------
    def compose(self, snap, w, h):
        if self.warming:
            self.compose_warm(snap, w, h)
            return
        if self.phase in ("hidden", "arming") or w < 2 or h < 2:
            return
        if (w, h) != self.size:
            self.size = (w, h)
            self.layers, self.card_layers, self.numerals = {}, {}, {}
        if self.first_frame:
            self.first_frame = False
            self._mark("first frame")
        a = clamp(self.alpha.x)
        if a <= 0.003:
            return
        snap.push_clip(rect(0, 0, w, h))
        if a < 0.999:
            snap.push_opacity(a)
        cards = self.place_cards()
        self.draw_backdrop(snap, self.covered(cards))
        self.draw_instruments(snap)
        self.draw_carousel(snap, cards)
        if a < 0.999:
            snap.pop()
        snap.pop()

    def compose_warm(self, snap, w, h):
        """One of each kind of node, where nobody can see it."""
        snap.push_opacity(0.004)
        dot = cairo.ImageSurface(cairo.FORMAT_ARGB32, 4, 4)
        texture = texture_of_surface(dot)
        shape = rrect(0, 0, 64, 36, 6)
        snap.save()
        snap.transform_matrix(graphene(chain(move(w / 2, h / 2), lens(PERSPECTIVE), turn_y(20.0),
                                             move(-32, -18))))
        snap.append_outset_shadow(shape, colour("bgDeep", 0.5), 0, 4, 1, 12)
        snap.push_rounded_clip(shape)
        snap.push_cross_fade(0.5)
        snap.append_scaled_texture(texture, Gsk.ScalingFilter.TRILINEAR, rect(0, 0, 64, 36))
        snap.pop()
        snap.append_texture(texture, rect(0, 0, 64, 36))
        snap.pop()
        snap.append_color(colour("bgDeep", 0.5), rect(0, 0, 64, 36))
        snap.pop()
        snap.append_border(shape, [1.0] * 4, [colour("fg", 0.3)] * 4)
        snap.restore()
        snap.append_radial_gradient(rect(0, 0, 64, 64), Graphene.Point().init(32, 32), 32, 32,
                                    0.0, 1.0, [stop(0.0, "fg", 0.2), stop(1.0, "fg", 0.0)])
        snap.pop()

    def draw_backdrop(self, snap, hidden=None):
        """The wallpaper, going out of focus and into shadow as the panel
        opens, darker towards the corners.

        As cheaply as it can be done. When the panel opens after the
        machine has been idle the graphics card is at its lowest clock —
        210 MHz of 2100 here — and needs about a fifth of a second of work
        before it leaves it (measured), which is exactly while the desktop
        is stepping back. At that clock a pass over the whole screen is some
        3 ms, and a frame has 6. So:

          - one picture and the next one over it at the strength of the
            blend, not a cross-fade (which draws both to the side first);
          - the tint and the vignette are in the pictures (wallpaper_levels);
          - and nothing at all behind `hidden`, the rectangle the desktop's
            own picture is covering: at the start that is the whole screen.
        """
        w, h, u, _cw, _ch = self.metrics()
        o = clamp(self.openness.x)
        if hidden is None:
            parts = [rect(0, 0, w, h)]
        else:
            hx, hy, hw, hh = hidden
            parts = [rect(0, 0, w, hy), rect(0, hy + hh, w, h - hy - hh),
                     rect(0, hy, hx, hh), rect(hx + hw, hy, w - hx - hw, hh)]
        full = rect(0, 0, w, h)
        lx, ly = self.lean[0].x, self.lean[1].x
        for part in parts:
            if part.get_width() < 1 or part.get_height() < 1:
                continue
            snap.push_clip(part)
            if self.walls:
                depth = o * (len(self.walls) - 1)
                i = min(int(depth), len(self.walls) - 2)
                t = depth - i
                # A little larger than the screen, so it can shift against
                # the carousel as that leans without showing an edge.
                snap.save()
                snap.translate(Graphene.Point().init(w / 2 + lx * 9 * u, h / 2 + ly * 6 * u))
                snap.scale(1.02, 1.02)
                snap.translate(Graphene.Point().init(-w / 2, -h / 2))
                snap.append_texture(self.walls[i], full)
                if t > 0.004:
                    snap.push_opacity(t)
                    snap.append_texture(self.walls[i + 1], full)
                    snap.pop()
                snap.restore()
            else:
                snap.append_color(colour("bgDeep"), full)
            snap.pop()

    def draw_instruments(self, snap):
        """The clock, the gauges, the machine, the bar's chips: hud.py's own
        drawing, each painted once and shown as a picture."""
        a = clamp(self.ui.x)
        if a <= 0.003:
            return
        u = self.metrics()[2]
        lift = (1.0 - self.rise.x) * 46 * u      # everything travels up into place
        shares = {"clock": 0.6, "gauges": 0.6, "title": 1.6, "bar": 2.2}
        for name in LAYERS:
            held = self.layer(name)
            if held is None:
                continue
            # Faded one by one. As a group they would first be drawn to the
            # side — a picture the size of the screen, since they sit in all
            # four corners of it — and that is a pass more over everything.
            if a < 0.999:
                snap.push_opacity(a)
            snap.append_texture(held.texture, rect(held.x, held.y + round(lift * shares.get(name, 0.0)),
                                                   held.w, held.h))
            if a < 0.999:
                snap.pop()

    def place_cards(self):
        """Where every card is this frame, back to front:
        [(workspace, matrix, q, selectedness, flight, opacity, shade)]."""
        w, h, u, cw, ch = self.metrics()
        if not self.ids:
            return []
        vx, vy = w / 2, CENTRE_Y * u
        leaving = self.flights.get(self.exit_ws) if self.phase == "closing" else None
        # While a card is on its way to being the screen, the rest get out
        # of its way.
        rest = 1.0 if leaving is None else clamp(1.0 - 2.5 * clamp(leaving.x))
        turn = self.turn.x
        lean_x, lean_y = self.lean[0].x * TILT[0], -self.lean[1].x * TILT[1]
        drawn = []
        for i, wid in enumerate(self.ids):
            d = i - turn
            arrive = self.arrive.get(wid)
            ar = 1.0 if arrive is None else arrive.x
            flight = self.flights.get(wid)
            f = 0.0 if flight is None else min(1.0, flight.x)
            # In its slot: on the carousel, turned as the carousel is there.
            # Arriving, the neighbours come up out of the depth and fan out.
            phi = d * STEP * (0.55 + 0.45 * min(1.0, ar))
            seen = clamp((FADE[1] - abs(phi)) / (FADE[1] - FADE[0])) * clamp(ar * 1.4)
            if flight is None:
                seen *= rest
            if seen <= 0.003 and f <= 0.001:
                continue
            g = bump(d)
            rad = math.radians(phi)
            sx = RADIUS * u * math.sin(rad)
            sz = -RADIUS * u * (1.0 - math.cos(rad)) + POP * u * g \
                - (1.0 - min(1.0, ar)) * DEPTH_IN * u
            # ... and, as far as it is in flight, on the way to being the
            # screen: flat, square on, at z = 0 where a pixel is a pixel.
            cx = vx + sx + (w / 2 - vx - sx) * f
            cy = vy + (h / 2 - vy) * f
            cz = sz * (1.0 - f)
            size = math.exp(math.log(w / cw) * f)
            still = 1.0 - clamp(f)
            # The card is laid out `q` times its nominal size and the matrix
            # takes that back out, with `q` about the size it is seen at.
            # The matrix alone would do — but the renderer picks which
            # reduction of a picture to sample from the size it is LAID OUT
            # at, and cannot see a magnification that is inside a projective
            # matrix: frame one, the capture at the size of the screen, came
            # out of the copy meant for a card and was a blur (measured: 23%
            # of its pixels wrong). Laid out at the size it is seen at, frame
            # one is the capture, pixel for pixel.
            q = size / max(0.2, 1.0 - cz / (PERSPECTIVE * u))
            if flight is None:
                # ... to the nearest quarter, for a card in its slot. A card
                # that is fading in is drawn to the side first, into a
                # picture the size it is laid out at; a size that changes by
                # a hair every frame is a new picture to allocate every
                # frame, and the old ones are kept.
                q = max(0.5, round(q * 4) / 4)
            matrix = chain(move(vx, vy), lens(PERSPECTIVE * u),
                           turn_y(lean_x * still), turn_x(lean_y * still),
                           move(cx - vx, cy - vy, cz), turn_y(phi * (1.0 - f)), grow(size / q),
                           move(-cw * q / 2, -ch * q / 2))
            shade = clamp(-sz / (RADIUS * u)) * 0.55 * still     # further back, further in shadow
            drawn.append((flight is not None, wid == self.exit_ws, -abs(d),
                          wid, matrix, q, g, clamp(f), max(seen, clamp(f * 8)), shade))
        return [item[3:] for item in sorted(drawn)]

    def covered(self, cards):
        """The rectangle of the screen that a card in flight is hiding
        completely, if one is: (x, y, w, h), or None.

        Only for the card that is the capture, opaque and large — the
        desktop stepping back, or coming back. Its corners are rounded, so
        the rectangle stops short of them."""
        w, h, u, cw, ch = self.metrics()
        for wid, matrix, q, _g, f, seen, _shade in reversed(cards):
            if f < 0.25 or seen < 0.999:
                continue
            if not (wid == self.shot_ws and self.shot is not None) and not self.walls:
                continue                         # (a card without a picture is not opaque)
            corners = [project(matrix, x, y) for x, y in
                       ((0, 0), (cw * q, 0), (cw * q, ch * q), (0, ch * q))]
            inset = 14 * u * (1.0 - f) * q * 0.4 + 2          # past the rounding of its corners
            left = max(corners[0][0], corners[3][0]) + inset
            right = min(corners[1][0], corners[2][0]) - inset
            top = max(corners[0][1], corners[1][1]) + inset
            bottom = min(corners[2][1], corners[3][1]) - inset
            left, top = max(0.0, math.ceil(left)), max(0.0, math.ceil(top))
            right, bottom = min(float(w), math.floor(right)), min(float(h), math.floor(bottom))
            if right - left > w * 0.3 and bottom - top > h * 0.3:
                return left, top, right - left, bottom - top
            return None
        return None

    def draw_carousel(self, snap, cards):
        w, h, u, cw, ch = self.metrics()
        self.quads = []
        if not cards:
            return
        vx, vy = w / 2, CENTRE_Y * u
        o = clamp(self.openness.x)
        leaving = self.flights.get(self.exit_ws) if self.phase == "closing" else None
        rest = 1.0 if leaving is None else clamp(1.0 - 2.5 * clamp(leaving.x))
        # The selected card sits in a pool of light — the spotlight's idea,
        # on the panel.
        light = GLOW * o * rest
        if light > 0.003:
            rx, ry = cw * HERO * 1.05, ch * HERO * 1.3
            snap.append_radial_gradient(
                rect(vx - rx, vy - ry, 2 * rx, 2 * ry), Graphene.Point().init(vx, vy), rx, ry,
                0.0, 1.0, [stop(0.0, "fg", light), stop(0.35, "fg", light * 0.62),
                           stop(0.7, "fg", light * 0.18), stop(1.0, "fg", 0.0)])
        for wid, matrix, q, g, f, seen, shade in cards:
            self.draw_card(snap, wid, matrix, q, g, f, seen, shade)
            self.quads.append((wid, matrix, q))

    def draw_card(self, snap, wid, matrix, q, g, f, seen, shade):
        """One workspace's card. Everything in here is in the card's own
        units times `q` (see draw_carousel)."""
        _w, _h, u, cw, ch = self.metrics()
        cw, ch, u = cw * q, ch * q, u * q
        card = self.cards[wid]
        still = 1.0 - f                          # how much of a card it still is
        # What is written on and under it belongs to the card, not to the
        # desktop it is or is about to be: only once it is nearly in place.
        written = clamp(1.0 - f * 2.5)
        shape = rrect(0, 0, cw, ch, 14 * u * still)
        full = rect(0, 0, cw, ch)
        snap.save()
        snap.transform_matrix(graphene(matrix))
        if seen < 0.999:
            snap.push_opacity(seen)
        # Its shadow, once it is small enough to have one: under a card
        # that still fills most of the screen it would fall outside it, and
        # be one more pass over all of it.
        shadow = clamp((0.62 - f) / 0.3)
        if shadow > 0.01:
            snap.append_outset_shadow(shape, colour("bgDeep", (0.34 + 0.30 * g) * shadow),
                                      0, (10 + 12 * g) * u, 2 * u, (28 + 30 * g) * u)
        snap.push_rounded_clip(shape)
        mix = clamp(self.mix.x) if wid == self.shot_ws and self.shot is not None else 1.0
        if mix > 0.001:
            self.draw_windows(snap, card, cw, ch, u, g, f)
        if mix < 0.999:
            # The capture of the screen, over the windows' own pictures at
            # whatever is left of it. Not a cross-fade of the two: that
            # draws each to the side first, and a card in flight is a new
            # size every frame — a new pair of pictures to allocate every
            # frame, up to the size of the screen.
            #
            # Plainly filtered, where every other picture here is given its
            # reductions and filtered through them: making those for a
            # picture the size of the screen is 50 to 70 ms on a graphics
            # card that has just been woken (measured after three idle
            # seconds: 90 ms to hand it over with them, 35 without), and that
            # is time during which a key has been pressed and nothing has
            # happened. Without them it is a little crisp while it is small
            # and in flight; at rest its place is taken by the windows' own
            # pictures, which have theirs.
            if mix > 0.001:
                snap.push_opacity(1.0 - mix)
            snap.append_scaled_texture(self.shot, Gsk.ScalingFilter.LINEAR, full)
            if mix > 0.001:
                snap.pop()
        if written > 0.01:
            snap.push_opacity(written)
            snap.append_scaled_texture(self.lettering(wid), Gsk.ScalingFilter.TRILINEAR, full)
            snap.pop()
        if shade > 0.003:
            snap.append_color(colour("bgDeep", shade), full)
        snap.pop()
        if still > 0.02:
            snap.append_border(shape, [(1.0 + 0.5 * g) * u] * 4,
                               [colour("fg", (0.10 + 0.26 * g) * still)] * 4)
        if written > 0.01:
            # Its number under it, in the card's own plane. Where you are is
            # full strength, with the accent dot.
            held = self.numeral(wid)
            here = wid == self.here
            top = ch + 24 * u
            nw, nh = held.w * q, held.h * q
            snap.push_opacity((1.0 if here else 0.42 + 0.30 * g) * written)
            snap.append_scaled_texture(held.texture, Gsk.ScalingFilter.TRILINEAR,
                                       rect(cw / 2 - nw / 2, top, nw, nh))
            snap.pop()
            if here:
                r = 3.5 * u
                dot = rrect(cw / 2 - r, top + nh + 16 * u, 2 * r, 2 * r, r)
                snap.push_rounded_clip(dot)
                snap.append_color(colour("accent", written), dot.bounds)
                snap.pop()
        if seen < 0.999:
            snap.pop()
        snap.restore()

    def draw_windows(self, snap, card, cw, ch, u, g, f):
        """A workspace, put together: the wallpaper, and on it each window's
        own picture at its place, to scale. (`cw`, `ch`, `u`: the card's
        size and unit as laid out — see draw_card.)"""
        still = 1.0 - f
        full = rect(0, 0, cw, ch)
        if self.walls:
            snap.append_scaled_texture(self.walls[0], Gsk.ScalingFilter.TRILINEAR, full)
        else:
            snap.append_color(colour("bg"), full)
        held_back = (0.44 - 0.34 * g) * still    # the unselected ones stand back a little
        if held_back > 0.003:
            snap.append_color(colour("bgDeep", held_back), full)
        mon = card["mon"]
        sx, sy = cw / (mon["width"] / mon["scale"]), ch / (mon["height"] / mon["scale"])
        now = time.monotonic()
        for c in card["clients"]:
            px, py = (c["at"][0] - mon["x"]) * sx, (c["at"][1] - mon["y"]) * sy
            pw, ph = c["size"][0] * sx, c["size"][1] * sy
            if pw < 1 or ph < 1:
                continue
            focused = c["address"] == self.snapshot["active"]
            # Attention heat: a window you were in a moment ago is lighter
            # than one you have not touched for ten minutes.
            age = 600.0
            if self.pulse is not None and c["address"] in self.pulse.seen:
                age = now - self.pulse.seen[c["address"]]
            heat = 1.0 if focused else max(0.0, 1.0 - age / 600.0)
            pane = rrect(px, py, pw, ph, max(self.rounding * sx, 5 * u * still))
            picture = self.pic(c)
            shown = 0.0
            if picture is not None and c["address"] in self.reveal:
                shown = clamp(self.reveal[c["address"]].x)
            snap.push_rounded_clip(pane)
            if shown < 0.999:
                # No picture (yet): the window as a drawn pane.
                snap.append_color(colour("accent", 0.26) if focused
                                  else colour("overlay", 0.30 + 0.50 * heat), pane.bounds)
            if shown > 0.001:
                if shown < 0.999:
                    snap.push_opacity(shown)
                snap.append_scaled_texture(picture, Gsk.ScalingFilter.TRILINEAR, pane.bounds)
                if shown < 0.999:
                    snap.pop()
                stale = STALE * (1.0 - heat) * still * shown
                if stale > 0.003:
                    snap.append_color(colour("bgDeep", stale), pane.bounds)
            snap.pop()
            # As thin as a card's line where it is a card; as wide as the
            # window's real border where it is about to be the window.
            line = 1.1 * u * still + self.border * sx * f
            snap.append_border(pane, [line] * 4,
                               [colour("accent" if focused else "slate")] * 4)


# ------------------------------------------------------------------ the program
class Feed:
    """Today's focus blocks, as the daemon last sent them (ledger.Ledger's
    reading side)."""

    def __init__(self):
        self.blocks = []

    def snapshot(self):
        return self.blocks

    def totals(self):
        acc = {}
        for start, end, cls in self.blocks:
            acc[cls] = acc.get(cls, 0.0) + (end - start)
        return sorted(acc.items(), key=lambda kv: -kv[1])


class Ages:
    """When each window last had focus (pulse.Pulse's `seen`), kept here from
    the compositor's own events."""

    def __init__(self):
        self.seen = {}


class App(Gtk.Application):
    def __init__(self, beats, font):
        super().__init__(application_id="dev.dani.reverie.stage",
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.stage = None
        self.pending = b""
        self.start = (beats, font)
        self.told = None

    def do_activate(self):
        if self.stage is not None:
            return
        self.hold()
        common.install_css()
        common.set_font(self.start[1])
        self.stage = Stage(self)
        self.stage.beats = self.start[0]
        self.stage.pulse = Ages()
        self.stage.ledger = Feed()
        GLib.io_add_watch(0, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR,
                          self.on_input)
        self.listen()

    def listen(self):
        try:
            conn = Gio.SocketClient().connect(
                Gio.UnixSocketAddress.new(hypr_events_path()), None)
        except GLib.Error:
            return
        self.conn = conn
        self.stream = Gio.DataInputStream.new(conn.get_input_stream())
        self.stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_line)

    def on_line(self, stream, result):
        try:
            line, _ = stream.read_line_finish_utf8(result)
        except GLib.Error:
            line = None
        if line is None:
            self.quit()                      # the compositor has gone
            return
        event, _, data = line.partition(">>")
        if event == "activewindowv2" and data:
            self.stage.pulse.seen["0x" + data] = time.monotonic()
        elif event in ("workspacev2", "focusedmonv2", "openwindow", "closewindow",
                       "movewindowv2", "changefloatingmode", "fullscreen"):
            self.stage.elsewhere()           # pictures of what is no longer on screen
        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_line)

    def on_input(self, _fd, condition):
        data = b""
        if condition & GLib.IO_IN:
            try:
                data = os.read(0, 65536)
            except OSError:
                data = b""
        if not data:
            self.quit()                      # the daemon has gone: nothing left on screen
            return False
        self.pending += data
        while b"\n" in self.pending:
            line, self.pending = self.pending.split(b"\n", 1)
            try:
                self.command(line.decode(errors="replace"))
            except Exception as exc:         # a bad line must not take the panel down
                print(f"stage: {line[:80]!r}: {exc!r}", file=sys.stderr, flush=True)
        return True

    def command(self, line):
        head, _, rest = line.strip().partition(" ")
        stage = self.stage
        if head == "hud":
            stage.command(rest.split())
            print("down" if stage.phase == "hidden" else "up", flush=True)
        elif head == "status":
            print("status " + stage.command(["status"]), flush=True)
        elif head == "ledger":
            stage.ledger.blocks = [b for b in json.loads(rest) if len(b) == 3]
            stage.dirty.add("clock")
        elif head == "font":
            common.set_font(rest.strip())
            stage.restyle()
        elif head == "ping":
            print("pong", flush=True)
        if stage.beats != self.told:         # what was learned about held keys: the daemon keeps it
            self.told = stage.beats
            print(f"beats {int(stage.beats)}", flush=True)


if __name__ == "__main__":
    # The worker and the bar's readers are Python too, and a thread that
    # holds the interpreter keeps it for 5 ms by default: most of a frame.
    sys.setswitchinterval(0.0005)
    args = sys.argv[1:]
    App(beats="--beats" in args,
        font=args[args.index("--font") + 1] if "--font" in args else "caskaydia").run([])
