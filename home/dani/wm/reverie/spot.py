"""spot: the spotlight. Its own program, because it is the one thing here that
has to be drawn on the graphics card.

The desktop dims and the focused window sits in a pool of light. When focus
moves, the light is HANDED OVER rather than moved:

  1. it arrives first. The sides of the pool that have to grow reach the new
     window in about 70 ms, so for a moment both windows are lit and nothing
     you are about to look at is dark;
  2. the darkness follows. The sides that have to shrink come after it on a
     slower, soft-landing curve, so the old window is not switched off — it
     is covered, from the far side;
  3. it lands. The pool breathes out a few pixels and settles, and a glint
     leaves the point where the light came in and runs round the window's
     border both ways, to meet on the far side. The border is slate and the
     glint is light, not colour: focus stays a matter of value, never of hue.

Switching the spotlight on closes the light in from the edges of the monitor;
switching it off opens it back out.

Why the handoff is lopsided on purpose: a pool that is ever SMALLER than the
focused window puts a dark band on the one thing you are looking at, and that
reads as lag however short it is. Growing early and shrinking late means the
pool can only ever err by being too big.

When the SAME window moves or resizes, none of that applies: the pool simply
follows with the time constant of the compositor's own `windows` animation
(easeOutQuint over T is, within a few percent, an exponential with
tau = T / 6), so its edge and the window's travel together.

Why a program of its own. Until 2026-11-19 this lived in the daemon (fx.py)
and was painted with cairo, like everything else there: the daemon runs GTK's
software renderer, which is what keeps it at a third of the memory. A
spotlight is a whole-monitor picture that changes every frame, and in
software that is a 15 MB buffer painted, carried forward and uploaded each
time. Measured on real focus changes it drew 21-22 frames in half a second —
about 42 a second on a 165 Hz panel, with single waits of 17-28 ms — and that
was what "could be smoother" was. The renderer is chosen once per process
(GTK caches the answer), so the fix is a process that chooses the other one.
Here the picture is a handful of render nodes — a flat dimness, masked by
the pools — and the graphics card composes it: the same motion measured
164 frames a second, every one of them on time. It only exists while the
spotlight is on; the daemon starts it and talks to it down a pipe
(fx.Fx.spotlight).

What makes the pool read as designed rather than as a dark rectangle with a
hole in it:

  - it is the window's own shape: same rectangle, same corner radius (read
    from the running config, not assumed);
  - its soft edge is as wide as the gap around a window, so the light ends
    where the layout's own spacing ends;
  - the dimness is one flat layer and the pools are a MASK on it, so pools
    can overlap: the menu deck asks to stay lit while it is open, and its
    pool and the window's simply merge;
  - every monitor dims, not only the one with focus.

Housekeeping: frames come from the monitor's frame clock and only while
something is moving; a resize or a drag raises no event, so geometry is
polled (20 Hz while anything changes, 4 Hz otherwise); and whenever nothing
is dimmed — no focused window, or one that is truly fullscreen — the overlays
unmap, because even a transparent surface above a fullscreen game keeps the
compositor from scanning it straight out.

Coordinates are global (Hyprland's layout space) everywhere; each view
subtracts its own monitor's origin when it draws.

On stdin, one per line: `off` (opens out, then exits), `lit x y w h r` or
`lit none`, `where` (answered on stdout, for the tests). End of input — the
daemon has gone — and it leaves at once.
"""

import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import common  # noqa: E402,F401  (first: it pins the GI versions)
from common import EFFECT, PAL, Spring, hypr, hypr_events_path, layer_window, rgba  # noqa: E402

import cairo  # noqa: E402
import gi  # noqa: E402

gi.require_version("Graphene", "1.0")
gi.require_version("Gsk", "4.0")
from gi.repository import Gdk, Gio, GLib, Graphene, Gsk, Gtk, Gtk4LayerShell  # noqa: E402

DIM = 0.50                   # how dark "everything else" gets
POLL_MS = 50                 # geometry poll while something is changing
IDLE_EVERY = 5               # ... and every this-many polls when nothing is
BUSY_S = 1.5                 # how long after the last change "changing" lasts
FOCUS_EVENTS = ("activewindowv2", "workspacev2", "fullscreen", "movewindowv2",
                "changefloatingmode", "openwindow", "closewindow", "focusedmonv2")

# The handoff. Times are what the eye gets, not parameters to admire:
LEAD_TAU = 0.028             # s — growing sides: 83% there in 50 ms, all of it by ~100
TRAIL_OMEGA = 24.0           # rad/s — shrinking sides: half-way at 70 ms, 90% at 160
FINISH_TAU = 0.022           # s — and the last few pixels briskly, so it ends, not fades
CUT_S = 0.40                 # s — after a workspace switch, the pool jumps (see on_event)
IRIS_OMEGA = 15.0            # rad/s — closing in when the spotlight is switched on
OPEN_TAU = 0.11              # s — opening back out when it is switched off
SWELL_PX = 6.0               # how far the pool breathes out as it lands
SWELL_OMEGA = 20.0           # rad/s — out by 50 ms, back by ~300
GLINT_S = 0.50               # s — one run of the glint round the border
GLINT_DELAY = 0.05           # s — it leaves when the light has arrived, not before
GLINT_PEAK = 0.85            # the head's opacity when it sets off



def colour(role, alpha):
    c = Gdk.RGBA()
    c.red, c.green, c.blue = PAL[role]
    c.alpha = alpha
    return c


def rrect(x, y, w, h, r):
    out = Gsk.RoundedRect()
    out.init_from_rect(Graphene.Rect().init(x, y, w, h), max(0.0, min(r, w / 2, h / 2)))
    return out


OPAQUE = Gdk.RGBA()
OPAQUE.red = OPAQUE.green = OPAQUE.blue = OPAQUE.alpha = 1.0


class Edge:
    """One side of the pool (or any other single number that travels).

    It moves in one of two ways, chosen each time it is aimed:

      tau    an exponential follower — every instant it closes the same
             fraction of what is left. Fastest at the start, no overshoot.
      omega  a critically damped spring — starts from rest, speeds up, lands
             softly. Integrated exactly, so a late frame cannot blow it up,
             and a new target mid-flight keeps the speed it had. A spring's
             last pixels take as long as its first hundred, which on screen
             is an edge that creeps; within `finish` px of home it therefore
             switches to the follower and is simply done.

    With neither, it snaps (animations switched off in the compositor).
    """

    def __init__(self):
        self.x = self.v = self.target = 0.0
        self.tau = self.omega = self.finish = 0.0

    def aim(self, target, tau=0.0, omega=0.0, finish=0.0):
        self.target = float(target)
        self.tau, self.omega, self.finish = tau, omega, finish
        if not omega:
            self.v = 0.0

    def jump(self, value):
        self.x = self.target = float(value)
        self.v = 0.0

    def step(self, dt):
        d = self.x - self.target
        if self.omega > 0.0:
            e = math.exp(-self.omega * dt)
            c = self.v + self.omega * d
            self.x = self.target + (d + c * dt) * e
            self.v = (self.v - c * self.omega * dt) * e
            if abs(self.x - self.target) < self.finish:
                self.tau, self.omega, self.v = FINISH_TAU, 0.0, 0.0
            elif abs(self.x - self.target) < 0.3 and abs(self.v) < 8.0:
                self.x, self.v = self.target, 0.0     # land exactly: geometry is whole pixels
        elif self.tau > 0.0 and abs(d) >= 0.3:
            self.x = self.target + d * math.exp(-dt / self.tau)
        else:
            self.x, self.v = self.target, 0.0

    @property
    def resting(self):
        return self.x == self.target and self.v == 0.0


class Canvas(Gtk.Widget):
    """The whole monitor, as render nodes rather than as a picture."""

    def __init__(self, view):
        super().__init__()
        self.view = view

    def do_snapshot(self, snap):
        self.view.spot.snapshot(self.view, snap, self.get_width(), self.get_height())


class View:
    """One monitor's overlay."""

    def __init__(self, spot, monitor):
        self.connector = monitor.get_connector()
        self.origin = (0, 0)
        self.spot = spot
        self.win = layer_window(spot.app, "reverie-fx")
        Gtk4LayerShell.set_monitor(self.win, monitor)
        self.canvas = Canvas(self)
        self.win.set_child(self.canvas)
        self.win.connect("map", self.on_map)
        self.tick_id = 0
        self.drawn = None                # (opacity, pool, lit?) as last drawn; see Spot.snapshot

    def run(self):
        self.canvas.queue_draw()         # every change is owed a frame, moving or not
        if not self.tick_id:
            self.tick_id = self.canvas.add_tick_callback(self.tick)

    def tick(self, _widget, _clock):
        spot = self.spot
        spot.advance()                   # the first view to tick steps for all of them
        self.canvas.queue_draw()         # every frame: a frame here is a few nodes, not a buffer
        if spot.moving:
            return True
        # At rest: stop drawing. A lit spotlight costs nothing while focus
        # stays where it is. And with nothing dimmed there is nothing to show
        # at all, so unmap (see "Housekeeping" above).
        self.tick_id = 0
        if spot.alpha.x < 0.01:
            self.win.set_visible(False)
            if not spot.on:
                spot.app.quit()          # switched off, and the lights are up
        return False

    @staticmethod
    def on_map(win):
        # An empty input region: every click falls through to the desktop.
        surface = win.get_surface()
        if surface is not None:
            surface.set_input_region(cairo.Region())


class Spot:
    def __init__(self, app):
        self.app = app
        self.views = {}              # connector -> View
        self.on = False
        self.alpha = Spring(0.0, EFFECT)
        self.edges = [Edge() for _ in range(4)]     # left, top, right, bottom — global
        self.have_box = False
        self.addr = None             # the window the pool belongs to
        self.swell = Edge()          # px the pool is breathed out by, right now
        self.glint = None            # (start time, dx, dy towards where the light came from)
        self.cut_until = 0.0         # until then, a new target is jumped to, not travelled to
        self.cut_from = 0.0          # -1 / +1: the side the new workspace slid in from
        self.slide_s = 0.35          # how long the compositor's workspace slide takes
        self.workspace = None
        self.lit = None              # (x, y, w, h, radius), global: also kept bright
        self.rounding = 16.0
        self.feather = 12.0
        self.border = 2.0
        self.tau = 0.05              # seconds; see read_layout
        self.moving = False
        self.kicked_at = 0.0         # when the pool was last sent somewhere
        self.frames = 0              # frames stepped since everything was last at rest
        self.worst = 0.0
        self.began = 0.0
        self.poll_id = 0
        self.beat = 0
        self.busy_until = 0.0
        self.last = None

    # -- views ------------------------------------------------------------
    def sync_views(self):
        """One overlay per connected monitor; follow hot-plugging."""
        layout = {m["name"]: (m["x"], m["y"]) for m in hypr("j/monitors") or []}
        monitors = Gdk.Display.get_default().get_monitors()
        present = set()
        for i in range(monitors.get_n_items()):
            mon = monitors.get_item(i)
            name = mon.get_connector()
            present.add(name)
            if name not in self.views:
                self.views[name] = View(self, mon)
            self.views[name].origin = layout.get(name, (0, 0))
        for name in list(self.views):
            if name not in present:
                self.views.pop(name).win.destroy()

    def read_layout(self):
        """The window shape comes from the compositor, so the pool matches it."""
        opt = hypr("j/getoption decoration:rounding") or {}
        if isinstance(opt.get("int"), int):
            self.rounding = float(opt["int"])
        opt = hypr("j/getoption general:gaps_out") or {}
        parts = str(opt.get("custom", "")).split()
        if parts and parts[0].lstrip("-").isdigit():
            self.feather = float(max(6, int(parts[0])))
        opt = hypr("j/getoption general:border_size") or {}
        if isinstance(opt.get("int"), int):
            self.border = float(opt["int"])
        # How long the compositor takes to move a window. easeOutQuint over
        # T is, to within a few percent, an exponential with tau = T / 6
        # (it is 83% there at 0.3 T; so is 1 - e^-1.8). No animations: snap.
        tree = hypr("j/animations") or []
        anims = {a.get("name"): a for a in (tree[0] if tree else [])}
        chosen = next((anims[n] for n in ("windowsMove", "windows", "global")
                       if anims.get(n, {}).get("overridden")), None)
        opt = hypr("j/getoption animations:enabled") or {}
        slide = anims.get("workspaces", {})
        if slide.get("overridden"):
            self.slide_s = float(slide.get("speed", 3.5)) * 0.1 if slide.get("enabled") else 0.0
        if chosen is None:
            self.tau = 0.05
        elif not chosen.get("enabled") or opt.get("int") == 0:
            self.tau = 0.0
        else:
            self.tau = max(0.02, min(0.09, float(chosen.get("speed", 3.0)) * 0.1 / 6.0))

    def wake(self):
        """Something changed: map every overlay, give each a frame, and keep
        the frame clocks running until things settle."""
        if not self.moving:
            self.sync_views()
            self.last = time.monotonic()     # so the first frame steps by real elapsed time
            self.began, self.frames, self.worst = self.last, 0, 0.0
        self.moving = True
        for view in self.views.values():
            view.win.set_visible(True)
            view.run()

    def advance(self):
        now = time.monotonic()
        dt = now - self.last if self.last is not None else 0.0
        if self.last is not None and dt < 0.002:
            return                       # another monitor's clock already did this frame
        self.last = now
        self.frames += 1
        self.worst = max(self.worst, dt)     # the longest wait for a frame, for the debug line
        dt = min(0.05, dt)
        self.alpha.step(dt)
        for edge in self.edges:
            edge.step(dt)
        self.swell.step(dt)
        if self.alpha.target == 0.0 and self.alpha.x < 0.004:
            # Nothing is dimmed any more, so nothing still in motion can be
            # seen. Stop here instead of animating an invisible pool to rest.
            self.alpha.x = self.alpha.v = 0.0
            for edge in self.edges:
                edge.jump(edge.target)
            self.swell.jump(0.0)
            self.glint = None
        if self.glint is not None and now > self.glint[0] + GLINT_S:
            self.glint = None
        still = self.alpha.resting and self.swell.resting and all(e.resting for e in self.edges)
        self.moving = self.glint is not None or not still
        if not self.moving and os.environ.get("REVERIE_DEBUG"):
            print(f"spot: {self.frames} frames over {(now - self.began) * 1000:.0f} ms, "
                  f"longest wait for one {self.worst * 1000:.0f} ms", file=sys.stderr, flush=True)

    @staticmethod
    def bounds_of(cx, cy):
        """The monitor a point is on, as (left, top, right, bottom), or None."""
        for m in hypr("j/monitors") or []:
            w, h = m["width"] / m["scale"], m["height"] / m["scale"]
            if m["x"] <= cx < m["x"] + w and m["y"] <= cy < m["y"] + h:
                return m["x"], m["y"], m["x"] + w, m["y"] + h
        return None

    def set_lit(self, rect):
        """A second pool: something that is not the focused window but must
        not be dimmed (the menu deck). None removes it."""
        self.lit = rect
        if self.on or self.alpha.x > 0.01:
            self.wake()                  # one frame with the new shape

    # -- events -----------------------------------------------------------
    def on_event(self, event, data):
        if not self.on:
            return
        if event == "workspacev2":
            wid = data.split(",")[0]
            if wid.lstrip("-").isdigit():
                came = int(wid)
                if self.workspace is not None and came != self.workspace:
                    self.cut_from = 1.0 if came > self.workspace else -1.0
                self.workspace = came
            # A workspace switch is a cut, not a pan. The compositor is
            # sliding every window on the monitor; a pool sweeping across
            # that says nothing, right when the compositor has the least
            # time to spare. So the light is simply at its new place — the
            # window slides into it — and only the glint plays, once the
            # window has arrived.
            now = time.monotonic()
            self.cut_until = now + CUT_S
            # Hyprland may announce the newly focused window before the
            # workspace. Then a handoff has just begun: it is this cut's,
            # so its glint is kept and re-timed rather than dropped.
            begun = self.glint is not None and now - self.kicked_at < 0.15
            for edge in self.edges:
                edge.jump(edge.target)
            self.swell.jump(0.0)
            self.glint = (now + self.slide_s * 0.6, self.cut_from, 0.0) if begun else None
            if self.have_box:
                self.wake()
        if event in FOCUS_EVENTS:
            # Now — the event is the news — and once more shortly after, for
            # geometry the layout had not finished deciding (a new window).
            self.retarget()
            GLib.timeout_add(40, self.retarget)
            self.busy_until = time.monotonic() + BUSY_S

    # -- spotlight --------------------------------------------------------
    def retarget(self):
        """Aim the pool at the focused window (also a timeout callback, so
        it always returns False)."""
        if not self.on:
            return False
        win = hypr("j/activewindow") or {}
        addr = win.get("address")
        if not addr or win.get("fullscreen", 0) >= 2:
            # Nothing focused, or one window that owns the whole screen:
            # lights up, and the overlays unmap once they have faded.
            if self.alpha.target != 0.0:
                self.alpha.target = 0.0
                self.wake()
            return False
        left, top = win["at"]
        goal = (float(left), float(top),
                float(left + win["size"][0]), float(top + win["size"][1]))
        placed = self.have_box and all(abs(e.target - v) <= 0.5
                                       for e, v in zip(self.edges, goal))
        if placed and addr == self.addr and self.alpha.target == 1.0:
            return False                 # nothing changed: draw nothing
        cx, cy = (goal[0] + goal[2]) / 2, (goal[1] + goal[3]) / 2
        animated = self.tau > 0.0
        now = time.monotonic()
        if now < self.cut_until and (addr != self.addr or not self.have_box):
            for edge, v in zip(self.edges, goal):
                edge.jump(v)
            if animated:
                # From the side the workspace came in on, when it has landed.
                self.glint = (self.cut_until - CUT_S + self.slide_s * 0.6, self.cut_from, 0.0)
        elif not self.have_box or self.alpha.x < 0.05:
            # Lights down (switched on, or arriving from an empty workspace):
            # start with the whole monitor lit and close in on the window.
            start = self.bounds_of(cx, cy) if animated else None
            out = self.feather + 2
            for edge, v, s, sign in zip(self.edges, goal, start or goal, (-1, -1, 1, 1)):
                if start:
                    edge.jump(s + sign * out)
                    edge.aim(v, omega=IRIS_OMEGA, finish=self.feather)
                else:
                    edge.jump(v)
            if animated:
                self.glint = (time.monotonic() + 0.24, 0.0, -1.0)
        elif addr != self.addr:
            # The handoff: light arrives early, darkness follows late.
            ox = (self.edges[0].x + self.edges[2].x) / 2
            oy = (self.edges[1].x + self.edges[3].x) / 2
            for i, (edge, v) in enumerate(zip(self.edges, goal)):
                growing = v < edge.x if i < 2 else v > edge.x
                if not animated:
                    edge.aim(v)
                elif growing:
                    edge.aim(v, tau=LEAD_TAU)
                else:
                    edge.aim(v, omega=TRAIL_OMEGA, finish=self.feather)
            if animated:
                kick = SWELL_PX * SWELL_OMEGA * math.e       # peaks at exactly SWELL_PX
                self.swell.aim(0.0, omega=SWELL_OMEGA)
                self.swell.v = min(self.swell.v + kick, kick * 1.4)
                self.glint = (time.monotonic() + GLINT_DELAY, ox - cx, oy - cy)
        else:
            # The same window, somewhere else: move as it moves.
            for edge, v in zip(self.edges, goal):
                edge.aim(v, tau=self.tau)
        self.addr = addr
        self.have_box = True
        self.alpha.target = 1.0
        self.kicked_at = time.monotonic()
        self.wake()
        return False

    def poll(self):
        """A resize, a drag and most tiling reshuffles raise no event."""
        if not self.on:
            self.poll_id = 0
            return False
        self.beat += 1
        now = time.monotonic()
        if now < self.busy_until or self.beat % IDLE_EVERY == 0:
            before = (self.addr, [e.target for e in self.edges], self.alpha.target)
            self.retarget()
            if before != (self.addr, [e.target for e in self.edges], self.alpha.target):
                self.busy_until = now + BUSY_S
        return True

    # -- drawing ----------------------------------------------------------
    @staticmethod
    def entry(dx, dy, w, h, rad):
        """How far along rounded()'s path — which starts at the top-right
        corner's arc and runs clockwise — a ray from the box's centre towards
        (dx, dy) crosses the outline."""
        if abs(dx) < 1.0 and abs(dy) < 1.0:
            dx, dy = 0.0, -1.0           # no direction to speak of: top centre
        hw, hh = w / 2, h / 2
        k = min(hw / abs(dx) if dx else math.inf, hh / abs(dy) if dy else math.inf)
        px, py = dx * k, dy * k          # from the centre; on the square outline
        sw, sh, arc = w - 2 * rad, h - 2 * rad, math.pi * rad / 2
        right, bottom, left = arc, 2 * arc + sh, 3 * arc + sh + sw
        top = left + sh + arc

        def along(v, length):
            return max(0.0, min(length, v))

        if abs(px - hw) < 0.5:
            return right + along(py + hh - rad, sh)      # right side, going down
        if abs(py - hh) < 0.5:
            return bottom + along(hw - rad - px, sw)     # bottom, going left
        if abs(px + hw) < 0.5:
            return left + along(hh - rad - py, sh)       # left side, going up
        return top + along(px + hw - rad, sw)            # top, going right

    @staticmethod
    def trace(cr, x, y, w, h, rad, begin, length):
        """Append the stretch of rounded()'s outline that starts `begin`
        along it and runs `length` further (clockwise, from the top-right
        corner's arc — the same path, cut to size).

        The first version stroked the WHOLE outline with a dash pattern that
        left one dash visible. Cairo walks the entire path to place a dash,
        and four strips doing that eight times a frame cost more than the
        full-screen canvas they were meant to spare (measured: 288 ms of CPU
        per focus change). A comet is a few hundred pixels of line; this
        draws those and nothing else.
        """
        rad = max(rad, 0.01)
        sw, sh, arc = w - 2 * rad, h - 2 * rad, math.pi * rad / 2
        sizes = (arc, sh, arc, sw, arc, sh, arc, sw)
        total = 2 * (sw + sh) + 4 * arc
        s = begin % total
        k, start = 0, 0.0
        while k < 7 and s >= start + sizes[k]:
            start += sizes[k]
            k += 1
        left, first = min(length, total), True
        while left > 1e-6:
            a = s - start
            b = min(sizes[k], a + left)
            if b > a:
                if k % 2 == 0:               # a corner: arcs 0, 2, 4, 6 start at -90, 0, 90, 180 deg
                    cx = x + w - rad if k in (0, 2) else x + rad
                    cy = y + rad if k in (0, 6) else y + h - rad
                    turn = (k // 2 - 1) * math.pi / 2
                    if first:
                        cr.new_sub_path()
                    cr.arc(cx, cy, rad, turn + a / rad, turn + b / rad)
                else:                        # a side: right down, bottom left, left up, top right
                    if k == 1:
                        p0, p1 = (x + w, y + rad + a), (x + w, y + rad + b)
                    elif k == 3:
                        p0, p1 = (x + w - rad - a, y + h), (x + w - rad - b, y + h)
                    elif k == 5:
                        p0, p1 = (x, y + h - rad - a), (x, y + h - rad - b)
                    else:
                        p0, p1 = (x + rad + a, y), (x + rad + b, y)
                    if first:
                        cr.move_to(*p0)
                    cr.line_to(*p1)
                first = False
            left -= b - a
            start = 0.0 if k == 7 else start + sizes[k]
            k = (k + 1) % 8
            s = start

    def draw_glint(self, cr, ox, oy, a):
        """Two points of light leave the place where the light came in and
        run round the window's border in opposite directions, fading, to meet
        on the far side."""
        t0, dx, dy = self.glint
        t = (time.monotonic() - t0) / GLINT_S
        if not 0.0 <= t <= 1.0:
            return
        left, top, right, bottom = (e.target for e in self.edges)   # the window, not the pool
        o = self.border / 2              # Hyprland draws the border outside the window's box
        x, y, w, h = left - o - ox, top - o - oy, right - left + 2 * o, bottom - top + 2 * o
        rad = min(self.rounding + o, w / 2, h / 2)
        total = 2 * (w - 2 * rad) + 2 * (h - 2 * rad) + 2 * math.pi * rad
        if total < 40:
            return
        start = self.entry(dx, dy, w, h, rad)
        reach = total / 2 * (1 - (1 - t) ** 3)       # ease-out: they slow as they meet
        fade = (1 - t) ** 1.3 * GLINT_PEAK * a
        # As long as a comet looks at rest — and, while it is travelling
        # further than that between two frames, as long as the gap, so that
        # a fast one is a streak rather than a row of dashes.
        speed = total / 2 * 3 * (1 - t) ** 2 / GLINT_S
        seg = min(total / 3, max(60.0, min(240.0, total * 0.09), speed / 80))
        cr.save()
        cr.set_line_cap(cairo.LINE_CAP_ROUND)
        for head, sense in ((start + reach, 1), (start - reach, -1)):
            # A comet, tail behind it: a soft glow and a faint line the whole
            # length, then two shorter, brighter ones towards the head.
            for share, strokes in ((1.0, ((5.0, 0.08), (1.6, 0.24))), (0.55, ((1.6, 0.42),)),
                                   (0.22, ((1.8, 1.0),))):
                n = seg * share
                cr.new_path()
                self.trace(cr, x, y, w, h, rad, head - n if sense > 0 else head, n)
                for width, alpha in strokes:
                    cr.set_line_width(width)
                    rgba(cr, "fg", alpha * fade)
                    cr.stroke_preserve()
        cr.new_path()
        cr.restore()

    def snapshot(self, view, snap, w, h):
        ox, oy = view.origin
        a = max(0.0, min(1.0, self.alpha.x))
        # What this overlay now shows, for `where`: the state can be right
        # while the picture is stale, and only the picture is on screen.
        view.drawn = (round(a, 2), tuple(round(e.x) for e in self.edges)
                      if self.have_box and a > 0.004 else None, self.lit is not None)
        if a <= 0.004:
            return
        f = self.feather
        full = Graphene.Rect().init(0, 0, w, h)
        pools = []
        if self.have_box:
            s = max(0.0, self.swell.x)
            left, top, right, bottom = (e.x for e in self.edges)
            pools.append((left - s - ox, top - s - oy, right - left + 2 * s,
                          bottom - top + 2 * s, self.rounding + s, True))
        deck = None
        if self.lit is not None:
            lx, ly, lw, lh, lr = self.lit
            deck = rrect(lx - ox, ly - oy, lw, lh, lr)
            pools.append((lx - ox, ly - oy, lw, lh, lr, False))
        # (A pool that is on another monitor is not this overlay's.)
        pools = [p for p in pools if p[2] >= 2 and p[3] >= 2 and p[0] < w and p[1] < h
                 and p[0] + p[2] > 0 and p[1] + p[3] > 0]
        snap.push_clip(full)
        if pools:
            # Everything dim, except where it is not: the pools are drawn
            # as a mask, solid inside and fading out over one gap's width
            # (a shadow half a gap out, blurred by half a gap: nothing left
            # at the window's edge, everything one gap further out).
            snap.push_mask(Gsk.MaskMode.INVERTED_ALPHA)
            for x, y, bw, bh, r, _window in pools:
                shape = rrect(x, y, bw, bh, r)
                snap.push_rounded_clip(shape)
                snap.append_color(OPAQUE, shape.bounds)
                snap.pop()
                snap.append_outset_shadow(shape, OPAQUE, 0, 0, f / 2, f / 2)
            snap.pop()
        snap.append_color(colour("bgDeep", DIM * a), full)
        if pools:
            snap.pop()
        for x, y, bw, bh, r, window in pools:
            if window:
                # A hairline of light on the pool's rim: the edge catches
                # it. Not across the deck, though, if the two overlap.
                rim = colour("fg", 0.14 * a)
                if deck is not None:
                    snap.push_mask(Gsk.MaskMode.INVERTED_ALPHA)
                    snap.push_rounded_clip(deck)
                    snap.append_color(OPAQUE, deck.bounds)
                    snap.pop()
                    snap.pop()
                snap.append_border(rrect(x - 1, y - 1, bw + 2, bh + 2, r + 1), [1.0] * 4, [rim] * 4)
                if deck is not None:
                    snap.pop()
        if self.glint is not None and self.have_box and \
                0.0 <= time.monotonic() - self.glint[0] <= GLINT_S:
            # The glint is line work, which cairo does best. It is drawn into
            # four strips laid along the window's border — a few pixels thick,
            # so what is handed to the graphics card each frame is small.
            left, top, right, bottom = (e.target for e in self.edges)
            x, y, bw, bh = left - ox, top - oy, right - left, bottom - top
            pad, thick = self.border + 6, self.rounding + self.border + 8
            for rx, ry, rw, rh in ((x - pad, y - pad, bw + 2 * pad, thick),
                                   (x - pad, y + bh + pad - thick, bw + 2 * pad, thick),
                                   (x - pad, y - pad + thick, thick, bh + 2 * pad - 2 * thick),
                                   (x + bw + pad - thick, y - pad + thick, thick,
                                    bh + 2 * pad - 2 * thick)):
                x0, y0 = max(0.0, math.floor(rx)), max(0.0, math.floor(ry))
                x1, y1 = min(float(w), math.ceil(rx + rw)), min(float(h), math.ceil(ry + rh))
                if x1 - x0 >= 1 and y1 - y0 >= 1:
                    cr = snap.append_cairo(Graphene.Rect().init(x0, y0, x1 - x0, y1 - y0))
                    self.draw_glint(cr, ox, oy, a)
        snap.pop()

    # -- commands ---------------------------------------------------------
    def switch(self, state):
        self.on = state
        if state:
            self.have_box = False
            self.addr = None
            self.read_layout()
            self.retarget()
            if not self.poll_id:
                self.poll_id = GLib.timeout_add(POLL_MS, self.poll)
            return
        # Lights up: the pool opens back out to the monitor's edges while the
        # dimness goes. The last frame of that ends the program (View.tick).
        self.alpha.target = 0.0
        self.glint = None
        if self.have_box and self.tau > 0.0:
            bounds = self.bounds_of((self.edges[0].x + self.edges[2].x) / 2,
                                    (self.edges[1].x + self.edges[3].x) / 2)
            for edge, v, sign in zip(self.edges, bounds or (), (-1, -1, 1, 1)):
                edge.aim(v + sign * (self.feather + 2), tau=OPEN_TAU)
        self.addr = None
        if self.views and self.alpha.x >= 0.01:
            self.wake()
        else:
            self.app.quit()

    def where(self):
        aimed = tuple(round(e.target) for e in self.edges) if self.have_box else None
        drawn = {name: v.drawn if v.win.get_visible() else "unmapped"
                 for name, v in self.views.items()}
        return (f"aimed={aimed} dim={self.alpha.target:.0f} window={self.addr} "
                f"lit={self.lit} drawn={drawn}")


class App(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="dev.dani.reverie.spot",
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.spot = None
        self.pending = b""

    def do_activate(self):
        if self.spot is not None:
            return
        self.hold()
        common.install_css()
        self.spot = Spot(self)
        GLib.io_add_watch(0, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR,
                          self.on_input)
        self.listen()
        self.spot.switch(True)

    # Hyprland's events, read here rather than relayed: the daemon's copy
    # would arrive a pipe and a main-loop turn later.
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
            self.quit()                  # the compositor has gone
            return
        event, _, data = line.partition(">>")
        try:
            self.spot.on_event(event, data)
        except Exception as exc:         # one odd event must not end the light
            print(f"spot: {line!r}: {exc!r}", file=sys.stderr, flush=True)
        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_line)

    def on_input(self, _fd, condition):
        data = b""
        if condition & GLib.IO_IN:
            try:
                data = os.read(0, 4096)
            except OSError:
                data = b""
        if not data:
            self.quit()                  # the daemon has gone: no orphaned darkness
            return False
        self.pending += data
        while b"\n" in self.pending:
            line, self.pending = self.pending.split(b"\n", 1)
            words = line.decode(errors="replace").split()
            try:
                self.command(words)
            except Exception as exc:
                print(f"spot: {words!r}: {exc!r}", file=sys.stderr, flush=True)
        return True

    def command(self, words):
        if not words:
            return
        if words[0] == "off":
            self.spot.switch(False)
        elif words[0] == "lit":
            self.spot.set_lit(None if len(words) < 6 else tuple(float(v) for v in words[1:6]))
        elif words[0] == "where":
            print(self.spot.where(), flush=True)


if __name__ == "__main__":
    App().run([])
