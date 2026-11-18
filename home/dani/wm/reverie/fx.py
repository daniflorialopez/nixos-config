"""fx: light that follows attention.

Click-through overlays above the windows — one per monitor — used for two
things.

spotlight  The desktop dims and the focused window sits in a pool of light.
           When focus moves, the pool does not jump: it *travels* there on a
           spring and reshapes itself on the way, so your eye is carried to
           the new window instead of having to find it. Focus as motion
           rather than as a border colour.

ripples    A window opening sends a ring outward from where it appeared; a
           window closing draws one inward to where it was. Half a second,
           then nothing. It answers "where did that just happen" for free.

What makes the spotlight read as designed rather than as a dark rectangle
with a hole in it:

  - the pool is the window's own shape: same rectangle, same corner radius
    (read from the running config, not assumed);
  - its soft edge is exactly as wide as the gap around a window, so the light
    ends where the layout's own spacing ends. A wider feather bleeds a
    gradient across the bar and the neighbouring windows, which is what the
    first version did;
  - that edge is drawn with real gradients (four strips and four corners),
    not stacked rings, so there are no visible steps in it;
  - every monitor dims, not only the one with focus.

Coordinates are global (Hyprland's layout space) everywhere; each view
subtracts its own monitor's origin when it draws.
"""

import math
import time

import cairo

from common import EFFECT, PAL, Spring, hypr, layer_window, rgba, rounded

from gi.repository import Gdk, GLib, Gtk, Gtk4LayerShell  # noqa: E402  (common pins versions)

GLIDE = (120.0, 19.0)        # travels with the faintest overshoot, settles fast
RIPPLE_S = 0.6
DIM = 0.50                   # how dark "everything else" gets
FRAME_MS = 16


class View:
    """One monitor's overlay."""

    def __init__(self, fx, monitor):
        self.connector = monitor.get_connector()
        self.origin = (0, 0)
        self.win = layer_window(fx.app, "reverie-fx")
        Gtk4LayerShell.set_monitor(self.win, monitor)
        self.area = Gtk.DrawingArea()
        self.area.set_draw_func(lambda _a, cr, w, h: fx.draw(self, cr, w, h))
        self.win.set_child(self.area)
        self.win.connect("map", self.on_map)

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
        self.box = [Spring(0.0, GLIDE) for _ in range(4)]     # global x, y, w, h
        self.have_box = False
        self.ripples = []            # (cx, cy, radius, t0, opening), global
        self.rounding = 16.0
        self.feather = 12.0
        self.timer_id = 0
        self.poll_id = 0
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

    def wake(self):
        self.sync_views()
        for view in self.views.values():
            view.win.set_visible(True)
        if not self.timer_id:
            self.last = None
            self.timer_id = GLib.timeout_add(FRAME_MS, self.tick)

    def tick(self):
        now = time.monotonic()
        dt = 0.016 if self.last is None else min(0.05, now - self.last)
        self.last = now
        self.alpha.step(dt)
        for s in self.box:
            s.step(dt)
        self.ripples = [r for r in self.ripples if now - r[3] < RIPPLE_S]
        for view in self.views.values():
            view.area.queue_draw()
        moving = not (self.alpha.resting and all(s.resting for s in self.box))
        if self.ripples or moving:
            return True
        # At rest: stop drawing. A lit spotlight costs nothing while focus
        # stays where it is.
        self.timer_id = 0
        if not self.spot:
            for view in self.views.values():
                view.win.set_visible(False)
        return False

    # -- events -----------------------------------------------------------
    def on_event(self, event, data):
        if self.spot and event in ("activewindowv2", "workspacev2", "fullscreen", "movewindowv2",
                                   "changefloatingmode", "openwindow", "closewindow",
                                   "focusedmonv2"):
            GLib.timeout_add(30, self.retarget)
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
        if not self.spot:
            return False
        win = hypr("j/activewindow") or {}
        if not win.get("address"):
            if self.alpha.target == 0.0:
                return False
            self.alpha.target = 0.0          # nothing focused: lights up
        else:
            geo = (win["at"][0], win["at"][1], win["size"][0], win["size"][1])
            moved = not self.have_box or any(
                abs(s.target - v) > 0.5 for s, v in zip(self.box, geo))
            if not moved and self.alpha.target == 1.0:
                return False                 # nothing changed: draw nothing
            # Arriving from "no focus" (an empty workspace) the pool should
            # appear in place rather than fly in from wherever it last was.
            fresh = not self.have_box or self.alpha.x < 0.05
            for s, v in zip(self.box, geo):
                s.target = v
                if fresh:
                    s.x, s.v = v, 0.0
            self.have_box = True
            self.alpha.target = 1.0
        if not self.timer_id:
            self.last = None
            self.timer_id = GLib.timeout_add(FRAME_MS, self.tick)
        return False

    def poll(self):
        """Resizes and tiling reshuffles do not all raise an event."""
        if not self.spot:
            self.poll_id = 0
            return False
        self.retarget()
        return True

    # -- drawing ----------------------------------------------------------
    def draw_pool(self, cr, x, y, w, h, vw, vh, a):
        """Dimness everywhere except a soft-edged, window-shaped pool."""
        f, r = self.feather, self.rounding
        dim = DIM * a
        cr_, cg, cb = PAL["bgDeep"]

        # 1. Flat dimness outside the pool's outer bounding box.
        cr.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
        cr.new_path()
        cr.rectangle(0, 0, vw, vh)
        cr.rectangle(x - f, y - f, w + 2 * f, h + 2 * f)
        cr.set_source_rgba(cr_, cg, cb, dim)
        cr.fill()
        cr.set_fill_rule(cairo.FILL_RULE_WINDING)

        # 2. The soft edge. A smoothstep falloff, sampled into gradient stops:
        #    0 at the window's edge, full dimness one gap further out.
        def stops(grad):
            for i in range(7):
                t = i / 6
                grad.add_color_stop_rgba(t, cr_, cg, cb, dim * t * t * (3 - 2 * t))
            return grad

        strips = (
            (x + r, y - f, w - 2 * r, f, (0, y, 0, y - f)),                 # top
            (x + r, y + h, w - 2 * r, f, (0, y + h, 0, y + h + f)),         # bottom
            (x - f, y + r, f, h - 2 * r, (x, 0, x - f, 0)),                 # left
            (x + w, y + r, f, h - 2 * r, (x + w, 0, x + w + f, 0)),         # right
        )
        for sx, sy, sw, sh, line in strips:
            if sw <= 0 or sh <= 0:
                continue
            cr.set_source(stops(cairo.LinearGradient(*line)))
            cr.rectangle(sx, sy, sw, sh)
            cr.fill()
        # Corners: a radial falloff from the corner's own arc. Beyond the
        # outer radius the gradient pads with full dimness, which is exactly
        # what the square outside the arc needs.
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

        # 3. A hairline of light on the pool's rim: the edge catches it.
        rounded(cr, x - 0.5, y - 0.5, w + 1, h + 1, r + 0.5)
        cr.set_line_width(1.0)
        rgba(cr, "fg", 0.14 * a)
        cr.stroke()

    def draw(self, view, cr, w, h):
        ox, oy = view.origin
        a = max(0.0, min(1.0, self.alpha.x))
        if a > 0.004:
            x, y, bw, bh = (s.x for s in self.box)
            x, y = x - ox, y - oy
            on_this = self.have_box and x < w and y < h and x + bw > 0 and y + bh > 0
            if on_this:
                self.draw_pool(cr, x, y, bw, bh, w, h, a)
            else:
                rgba(cr, "bgDeep", DIM * a)   # another monitor: simply dimmed
                cr.paint()

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
                    self.read_layout()
                    self.wake()
                    self.retarget()
                    if not self.poll_id:
                        self.poll_id = GLib.timeout_add(250, self.poll)
                else:
                    self.alpha.target = 0.0
                    if not self.timer_id and self.views:
                        self.last = None
                        self.timer_id = GLib.timeout_add(FRAME_MS, self.tick)
            return f"spotlight {'on' if self.spot else 'off'}"
        if words:
            self.ripples_on = (not self.ripples_on) if words[0] == "toggle" else state
        return f"ripples {'on' if self.ripples_on else 'off'}"
