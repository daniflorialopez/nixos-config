"""fx: light that follows attention.

Click-through overlays above the windows — one per monitor — used for two
things.

spotlight  The desktop dims and the focused window sits in a pool of light.
           When focus moves, the light is HANDED OVER rather than moved:

             1. it arrives first. The sides of the pool that have to grow
                reach the new window in about 70 ms, so for a moment both
                windows are lit and nothing you are about to look at is dark;
             2. the darkness follows. The sides that have to shrink come
                after it on a slower, soft-landing curve, so the old window
                is not switched off — it is covered, from the far side;
             3. it lands. The pool breathes out a few pixels and settles,
                and a glint leaves the point where the light came in and
                runs round the window's border both ways, to meet on the far
                side. The border is slate and the glint is light, not colour:
                focus stays a matter of value, never of hue.

           Switching the spotlight on closes the light in from the edges of
           the monitor; switching it off opens it back out.

ripples    A window opening sends a ring outward from where it appeared; a
           window closing draws one inward to where it was. Half a second,
           then nothing. It answers "where did that just happen" for free.

Why the handoff is lopsided on purpose: a pool that is ever SMALLER than the
focused window puts a dark band on the one thing you are looking at, and that
reads as lag however short it is. Growing early and shrinking late means the
pool can only ever err by being too big. The first version moved the whole
pool on one spring ("too slow, unresponsive"), the second on one exponential
("moves better", but plain); this keeps the second's speed where it matters
and spends the time where it shows.

When the SAME window moves or resizes, none of that applies: the pool simply
follows with the time constant of the compositor's own `windows` animation
(easeOutQuint over T is, within a few percent, an exponential with
tau = T / 6), so its edge and the window's travel together.

What makes the pool read as designed rather than as a dark rectangle with a
hole in it:

  - it is the window's own shape: same rectangle, same corner radius (read
    from the running config, not assumed);
  - its soft edge is exactly as wide as the gap around a window, so the light
    ends where the layout's own spacing ends;
  - that edge is drawn with real gradients (four strips and four corners),
    not stacked rings, so there are no visible steps in it;
  - the dimness is one flat layer and each pool is CUT out of it, so pools
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
"""

import math
import os
import time

import cairo

from common import EFFECT, Spring, hypr, layer_window, rgba, rounded

from gi.repository import Gdk, GLib, Gtk, Gtk4LayerShell  # noqa: E402  (common pins versions)

RIPPLE_S = 0.6
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
ARRIVAL_S = 0.10             # s — how long the light's arrival gets every frame
IRIS_OMEGA = 15.0            # rad/s — closing in when the spotlight is switched on
OPEN_TAU = 0.11              # s — opening back out when it is switched off
SWELL_PX = 6.0               # how far the pool breathes out as it lands
SWELL_OMEGA = 20.0           # rad/s — out by 50 ms, back by ~300
GLINT_S = 0.50               # s — one run of the glint round the border
GLINT_DELAY = 0.05           # s — it leaves when the light has arrived, not before
GLINT_PEAK = 0.85            # the head's opacity when it sets off


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


class View:
    """One monitor's overlay: a full-size canvas for the dimness and the pool,
    and four thin strips laid along the focused window's border for the glint.

    Why strips: a frame of the canvas is a whole-monitor buffer for the
    compositor to upload, and the glint outlasts the pool's own motion.
    Drawn on the canvas at the panel's 165 Hz, one focus change cost 265 ms
    of CPU here and 340 ms in Hyprland (measured). GTK only reports as damage
    the widgets that asked to be redrawn, so the glint lives in widgets a few
    pixels thick and the compositor's share fell to ~200 ms.

    Why the frame cap: the 265 ms did not move. Profiled, all the Python in a
    focus change — ticks, canvas, strips — is 30 ms; the rest is GTK's
    software renderer, which carries the whole window's buffer forward every
    frame however little of it changed (about 2.2 ms a frame at 1440p). The
    only lever left on that is the number of frames, so everything runs at
    every other frame once the light has arrived.
    """

    def __init__(self, fx, monitor):
        self.connector = monitor.get_connector()
        self.origin = (0, 0)
        self.fx = fx
        self.win = layer_window(fx.app, "reverie-fx")
        Gtk4LayerShell.set_monitor(self.win, monitor)
        self.area = Gtk.DrawingArea()
        self.area.set_draw_func(lambda _a, cr, w, h: fx.draw(self, cr, w, h))
        stack = Gtk.Overlay()
        stack.set_child(self.area)
        self.strips = []
        self.places = [(0, 0)] * 4       # each strip's top-left, in this view's coordinates
        for i in range(4):
            strip = Gtk.DrawingArea()
            strip.set_halign(Gtk.Align.START)
            strip.set_valign(Gtk.Align.START)
            strip.set_can_target(False)
            strip.set_visible(False)
            strip.set_draw_func(lambda _a, cr, _w, _h, i=i: fx.draw_strip(self, i, cr))
            stack.add_overlay(strip)
            self.strips.append(strip)
        self.win.set_child(stack)
        self.win.connect("map", self.on_map)
        self.tick_id = 0
        self.skipped = False
        self.was_busy = False
        self.laid_for = None             # the glint the strips are currently laid out for

    def run(self):
        if not self.tick_id:
            self.tick_id = self.area.add_tick_callback(self.tick)

    def lay_strips(self):
        """Put the four strips round the window the glint is running on."""
        fx = self.fx
        self.laid_for = fx.glint
        if fx.glint is None or not fx.have_box:
            for strip in self.strips:
                strip.set_visible(False)
            return
        ox, oy = self.origin
        left, top, right, bottom = (e.target for e in fx.edges)
        x, y, w, h = left - ox, top - oy, right - left, bottom - top
        pad, thick = fx.border + 6, fx.rounding + fx.border + 8
        rects = ((x - pad, y - pad, w + 2 * pad, thick),                        # top
                 (x - pad, y + h + pad - thick, w + 2 * pad, thick),            # bottom
                 (x - pad, y - pad, thick, h + 2 * pad),                        # left
                 (x + w + pad - thick, y - pad, thick, h + 2 * pad))            # right
        vw, vh = self.area.get_width(), self.area.get_height()
        for i, (strip, (rx, ry, rw, rh)) in enumerate(zip(self.strips, rects)):
            x0, y0 = max(0, int(rx)), max(0, int(ry))
            x1, y1 = min(vw, int(rx + rw) + 1), min(vh, int(ry + rh) + 1)
            if x1 - x0 < 1 or y1 - y0 < 1:
                strip.set_visible(False)         # that side is on another monitor
                continue
            self.places[i] = (x0, y0)
            strip.set_margin_start(x0)
            strip.set_margin_top(y0)
            strip.set_content_width(x1 - x0)
            strip.set_content_height(y1 - y0)
            strip.set_visible(True)

    def tick(self, _area, _clock):
        fx = self.fx
        fx.advance()                     # the first view to tick steps for all of them
        if fx.glint is not self.laid_for:
            self.lay_strips()
        # Every frame while the light is arriving; every other one (83 a
        # second on this panel) for the darkness that follows and the glint.
        self.skipped = not self.skipped and time.monotonic() - fx.kicked_at > ARRIVAL_S
        busy = not fx.still or bool(fx.ripples)
        if not self.skipped:
            fx.frames += 1
            if fx.glint is not None:
                for strip in self.strips:
                    strip.queue_draw()
            if busy:
                self.area.queue_draw()
        if self.was_busy and not busy:
            self.area.queue_draw()       # the resting frame, whatever was skipped
        self.was_busy = busy
        if fx.moving:
            return True
        # At rest: stop drawing. A lit spotlight costs nothing while focus
        # stays where it is. And with nothing dimmed there is nothing to show
        # at all, so unmap (see "Housekeeping" above).
        self.tick_id = 0
        if fx.alpha.x < 0.01:
            self.win.set_visible(False)
        return False

    @staticmethod
    def on_map(win):
        # An empty input region: every click falls through to the desktop.
        surface = win.get_surface()
        if surface is not None:
            surface.set_input_region(cairo.Region())


class Fx:
    def __init__(self, app, pulse):
        self.app = app
        self.pulse = pulse
        self.views = {}              # connector -> View
        self.spot = False
        self.ripples_on = False
        self.alpha = Spring(0.0, EFFECT)
        self.edges = [Edge() for _ in range(4)]     # left, top, right, bottom — global
        self.have_box = False
        self.addr = None             # the window the pool belongs to
        self.swell = Edge()          # px the pool is breathed out by, right now
        self.glint = None            # (start time, dx, dy towards where the light came from)
        self.lit = None              # (x, y, w, h, radius), global: also kept bright
        self.ripples = []            # (cx, cy, radius, t0, opening), global
        self.rounding = 16.0
        self.feather = 12.0
        self.border = 2.0
        self.tau = 0.05              # seconds; see read_layout
        self.moving = False
        self.still = True            # the pool and the dimness are where they should be
        self.kicked_at = 0.0         # when the pool was last sent somewhere
        self.frames = 0              # frames drawn since everything was last at rest
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
        if chosen is None:
            self.tau = 0.05
        elif not chosen.get("enabled") or opt.get("int") == 0:
            self.tau = 0.0
        else:
            self.tau = max(0.02, min(0.09, float(chosen.get("speed", 3.0)) * 0.1 / 6.0))

    def wake(self):
        """Map every overlay and run the frame clocks until things settle."""
        if not self.moving:
            self.sync_views()
            self.last = time.monotonic()     # so the first frame steps by real elapsed time
            self.began, self.frames = self.last, 0
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
        dt = min(0.05, dt)
        self.alpha.step(dt)
        for edge in self.edges:
            edge.step(dt)
        self.swell.step(dt)
        if self.glint is not None and now > self.glint[0] + GLINT_S:
            self.glint = None
        self.ripples = [r for r in self.ripples if now - r[3] < RIPPLE_S]
        self.still = self.alpha.resting and self.swell.resting and \
            all(e.resting for e in self.edges)
        self.moving = bool(self.ripples) or self.glint is not None or not self.still
        if not self.moving and os.environ.get("REVERIE_DEBUG"):
            print(f"fx: {self.frames} frames over {(now - self.began) * 1000:.0f} ms", flush=True)

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
        if self.spot or self.alpha.x > 0.01:
            self.wake()                  # one frame with the new shape

    # -- events -----------------------------------------------------------
    def on_event(self, event, data):
        if self.spot and event in FOCUS_EVENTS:
            # Now — the event is the news — and once more shortly after, for
            # geometry the layout had not finished deciding (a new window).
            self.retarget()
            GLib.timeout_add(40, self.retarget)
            self.busy_until = time.monotonic() + BUSY_S
        if not self.ripples_on:
            return
        if event == "openwindow":
            addr = "0x" + data.split(",")[0]
            GLib.timeout_add(140, self.ripple_for, addr, True)
        elif event == "closewindow":
            known = self.pulse.windows.get("0x" + data) if self.pulse else None
            if known:
                self.add_ripple(known["at"], known["size"], False)

    def ripple_for(self, addr, opening):
        for c in hypr("j/clients") or []:
            if c["address"] == addr:
                self.add_ripple(c["at"], c["size"], opening)
        return False

    def add_ripple(self, at, size, opening):
        self.ripples.append((at[0] + size[0] / 2, at[1] + size[1] / 2,
                             math.hypot(size[0], size[1]) / 2, time.monotonic(), opening))
        self.wake()

    # -- spotlight --------------------------------------------------------
    def retarget(self):
        """Aim the pool at the focused window (also a timeout callback, so
        it always returns False)."""
        if not self.spot:
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
        if not self.have_box or self.alpha.x < 0.05:
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
        if not self.spot:
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
    def cut(cr, x, y, w, h, r, f):
        """Remove the dimness inside a rounded rectangle, and fade it back in
        over `f` pixels outside. Only the source's alpha matters to DEST_OUT,
        so the colour set here is never seen."""
        cr.save()
        cr.set_operator(cairo.OPERATOR_DEST_OUT)
        cr.set_source_rgba(0, 0, 0, 1)
        cr.new_path()
        rounded(cr, x, y, w, h, r)
        cr.fill()

        # The soft edge: a smoothstep, sampled into gradient stops — nothing
        # left at the window's edge, everything left one gap further out.
        def stops(grad):
            for i in range(7):
                t = i / 6
                grad.add_color_stop_rgba(t, 0, 0, 0, 1 - t * t * (3 - 2 * t))
            return grad

        # Each strip reaches one pixel into the pool, where the gradient pads
        # with "remove everything": no seam while the pool is between pixels.
        strips = (
            (x + r, y - f, w - 2 * r, f + 1, (0, y, 0, y - f)),                 # top
            (x + r, y + h - 1, w - 2 * r, f + 1, (0, y + h, 0, y + h + f)),     # bottom
            (x - f, y + r, f + 1, h - 2 * r, (x, 0, x - f, 0)),                 # left
            (x + w - 1, y + r, f + 1, h - 2 * r, (x + w, 0, x + w + f, 0)),     # right
        )
        for sx, sy, sw, sh, line in strips:
            if sw <= 0 or sh <= 0:
                continue
            cr.set_source(stops(cairo.LinearGradient(*line)))
            cr.rectangle(sx, sy, sw, sh)
            cr.fill()
        # Corners: a radial falloff from the corner's own arc. Inside the arc
        # the gradient pads with "remove everything", beyond the outer radius
        # with "remove nothing", which is what each part of the square needs.
        corners = (
            (x - f, y - f, x + r, y + r),
            (x + w - r, y - f, x + w - r, y + r),
            (x - f, y + h - r, x + r, y + h - r),
            (x + w - r, y + h - r, x + w - r, y + h - r),
        )
        for qx, qy, ccx, ccy in corners:
            cr.set_source(stops(cairo.RadialGradient(ccx, ccy, r, ccx, ccy, r + f)))
            cr.rectangle(qx, qy, r + f, r + f)
            cr.fill()
        cr.restore()

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

    def draw_strip(self, view, i, cr):
        """One of a view's four border strips: the glint, shifted so that the
        strip is a window onto the same picture."""
        a = max(0.0, min(1.0, self.alpha.x))
        if self.glint is None or not self.have_box or a <= 0.004:
            return
        px, py = view.places[i]
        self.draw_glint(cr, view.origin[0] + px, view.origin[1] + py, a)

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

    def draw(self, view, cr, w, h):
        ox, oy = view.origin
        a = max(0.0, min(1.0, self.alpha.x))
        if a > 0.004:
            rgba(cr, "bgDeep", DIM * a)       # everything dim ...
            cr.paint()
            pools = []
            if self.have_box:
                s = max(0.0, self.swell.x)
                left, top, right, bottom = (e.x for e in self.edges)
                pools.append((left - s - ox, top - s - oy, right - left + 2 * s,
                              bottom - top + 2 * s, self.rounding + s, True))
            if self.lit is not None:
                lx, ly, lw, lh, lr = self.lit
                pools.append((lx - ox, ly - oy, lw, lh, lr, False))
            for x, y, bw, bh, r, window in pools:   # ... except where it is not
                if bw < 2 or bh < 2 or x >= w or y >= h or x + bw <= 0 or y + bh <= 0:
                    continue                  # that pool is on another monitor
                self.cut(cr, x, y, bw, bh, r, self.feather)
                if window:
                    # A hairline of light on the pool's rim: the edge catches
                    # it. Not across the deck, though, if the two overlap.
                    cr.save()
                    if self.lit is not None:
                        lx, ly, lw, lh, lr = self.lit
                        cr.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
                        cr.rectangle(0, 0, w, h)
                        rounded(cr, lx - ox, ly - oy, lw, lh, lr)
                        cr.clip()
                    cr.new_path()
                    rounded(cr, x - 0.5, y - 0.5, bw + 1, bh + 1, r + 0.5)
                    cr.set_line_width(1.0)
                    rgba(cr, "fg", 0.14 * a)
                    cr.stroke()
                    cr.restore()

        now = time.monotonic()
        for gx, gy, radius, t0, opening in self.ripples:
            cx, cy = gx - ox, gy - oy
            if not (-radius < cx < w + radius and -radius < cy < h + radius):
                continue
            t = (now - t0) / RIPPLE_S
            ease = 1 - (1 - t) ** 3
            r = radius * (0.25 + 0.85 * ease) if opening else radius * (1.1 - 0.85 * ease)
            cr.new_path()
            cr.set_line_width(1.5 + 4 * (1 - t))
            rgba(cr, "accent" if opening else "hint", 0.50 * (1 - t) ** 1.5)
            cr.arc(cx, cy, max(1.0, r), 0, math.tau)
            cr.stroke()

    # -- commands ---------------------------------------------------------
    def command(self, what, words):
        state = bool(words) and words[0] == "on"
        if what == "spotlight":
            if words and words[0] == "toggle":
                state = not self.spot
            if words:
                self.spot = state
                if state:
                    self.have_box = False
                    self.addr = None
                    self.read_layout()
                    self.retarget()
                    if not self.poll_id:
                        self.poll_id = GLib.timeout_add(POLL_MS, self.poll)
                else:
                    # Lights up: the pool opens back out to the monitor's
                    # edges while the dimness goes.
                    self.alpha.target = 0.0
                    self.glint = None
                    if self.have_box and self.tau > 0.0:
                        bounds = self.bounds_of((self.edges[0].x + self.edges[2].x) / 2,
                                                (self.edges[1].x + self.edges[3].x) / 2)
                        for edge, v, sign in zip(self.edges, bounds or (), (-1, -1, 1, 1)):
                            edge.aim(v + sign * (self.feather + 2), tau=OPEN_TAU)
                    self.addr = None
                    if self.views:
                        self.wake()
            return f"spotlight {'on' if self.spot else 'off'}"
        if words:
            self.ripples_on = (not self.ripples_on) if words[0] == "toggle" else state
        return f"ripples {'on' if self.ripples_on else 'off'}"
