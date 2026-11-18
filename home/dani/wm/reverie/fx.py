"""fx: light that follows attention.

One click-through overlay above the windows, used for two things.

spotlight  The desktop dims and the focused window sits in a pool of light.
           When focus moves, the pool does not jump: it *travels* there on a
           spring and reshapes itself on the way, so your eye is carried to
           the new window instead of having to find it. Focus as motion
           rather than as a border colour.

ripples    A window opening sends a ring outward from where it appeared; a
           window closing draws one inward to where it was. Half a second,
           then nothing. It answers "where did that just happen" for free,
           which matters most on a second monitor or a busy workspace.
"""

import math
import time

import cairo
from gi.repository import GLib, Gtk, Gtk4LayerShell

from common import EFFECT, Spring, focused_gdk_monitor, hypr, layer_window, rgba, rounded

GLIDE = (120.0, 19.0)        # travels with a little overshoot, settles fast
RIPPLE_S = 0.6


class Fx:
    def __init__(self, app, pulse):
        self.pulse = pulse
        self.win = layer_window(app, "reverie-fx")
        self.area = Gtk.DrawingArea()
        self.area.set_draw_func(self.draw)
        self.win.set_child(self.area)
        self.win.connect("map", self.on_map)
        self.spot = False
        self.ripples_on = False
        self.alpha = Spring(0.0, EFFECT)
        self.box = [Spring(0.0, GLIDE) for _ in range(4)]     # x, y, w, h
        self.have_box = False
        self.ripples = []            # (cx, cy, radius, t0, opening)
        self.origin = (0, 0)
        self.mon_id = None
        self.mon_name = None
        self.tick_id = 0
        self.poll_id = 0
        self.last = None
        self.drawn_at = 0.0

    def on_map(self, win):
        surface = win.get_surface()
        if surface is not None:
            surface.set_input_region(cairo.Region())

    # -- lifecycle --------------------------------------------------------
    def wake(self):
        mon = focused_gdk_monitor()
        # Re-anchoring a mapped layer surface remaps it, so only do it when the
        # focused monitor really changed.
        if mon is not None and mon.get_connector() != self.mon_name:
            self.mon_name = mon.get_connector()
            Gtk4LayerShell.set_monitor(self.win, mon)
        for m in hypr("j/monitors") or []:
            if m.get("focused"):
                self.origin = (m["x"], m["y"])
                self.mon_id = m["id"]
        self.win.set_visible(True)
        if not self.tick_id:
            self.last = None
            self.tick_id = self.area.add_tick_callback(self.tick)

    def tick(self, _widget, clock):
        now = clock.get_frame_time() / 1e6
        dt = 0.016 if self.last is None else min(0.05, now - self.last)
        self.last = now
        self.alpha.step(dt)
        for s in self.box:
            s.step(dt)
        t = time.monotonic()
        self.ripples = [r for r in self.ripples if t - r[3] < RIPPLE_S]
        moving = not (self.alpha.resting and all(s.resting for s in self.box))
        # Full-screen software draws: cap them at 60 a second on a 165 Hz
        # panel, and always draw the frame everything comes to rest on.
        if now - self.drawn_at >= 1 / 61 or not (self.ripples or moving):
            self.drawn_at = now
            self.area.queue_draw()
        if self.ripples or moving:
            return True
        self.tick_id = 0
        if not self.spot:
            self.win.set_visible(False)
        return False

    # -- events -----------------------------------------------------------
    def on_event(self, event, data):
        if self.spot and event in ("activewindowv2", "workspacev2", "fullscreen",
                                   "movewindowv2", "changefloatingmode"):
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
        self.wake()
        cx = at[0] - self.origin[0] + size[0] / 2
        cy = at[1] - self.origin[1] + size[1] / 2
        self.ripples.append((cx, cy, math.hypot(size[0], size[1]) / 2, time.monotonic(), opening))

    # -- spotlight --------------------------------------------------------
    def retarget(self):
        if not self.spot:
            return False
        win = hypr("j/activewindow") or {}
        if not win.get("address"):
            self.alpha.target = 0.0          # nothing focused: lights up
        else:
            if win.get("monitor") != self.mon_id:
                # Focus crossed to another monitor: follow it, and appear there
                # rather than fly across the gap between two panels.
                self.wake()
                self.have_box = False
            geo = (win["at"][0] - self.origin[0], win["at"][1] - self.origin[1],
                   win["size"][0], win["size"][1])
            moved = not self.have_box or any(
                abs(s.target - v) > 0.5 for s, v in zip(self.box, geo))
            if not moved and self.alpha.target == 1.0:
                return False                 # nothing changed: draw nothing
            for s, v in zip(self.box, geo):
                s.target = v
                if not self.have_box:
                    s.x = v
            self.have_box = True
            self.alpha.target = 1.0
        if not self.tick_id:
            self.last = None
            self.tick_id = self.area.add_tick_callback(self.tick)
        return False

    def poll(self):
        """Resizes and tiling reshuffles do not all raise an event."""
        if not self.spot:
            self.poll_id = 0
            return False
        self.retarget()
        return True

    # -- drawing ----------------------------------------------------------
    def draw(self, _area, cr, w, h):
        a = max(0.0, min(1.0, self.alpha.x))
        if a > 0.004 and self.have_box:
            x, y, bw, bh = (s.x for s in self.box)
            # The dimness is one even-odd fill with the pool left out of it,
            # and the penumbra is a few rings of the same colour laid inward
            # from the pool's edge. No offscreen group and no full-screen
            # erasures: only the scrim itself touches every pixel.
            feather, rings = 54.0, 9
            cr.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
            cr.new_path()
            cr.rectangle(0, 0, w, h)
            rounded(cr, x - feather, y - feather, bw + 2 * feather, bh + 2 * feather,
                    16 + feather)
            rgba(cr, "bgDeep", 0.58 * a)
            cr.fill()
            cr.set_fill_rule(cairo.FILL_RULE_WINDING)
            step = feather / rings
            cr.set_line_width(step + 0.5)
            for i in range(rings):
                grow = feather - step * (i + 0.5)
                rgba(cr, "bgDeep", 0.58 * a * (1 - (i + 1) / (rings + 1)))
                cr.new_path()
                rounded(cr, x - grow, y - grow, bw + 2 * grow, bh + 2 * grow, 16 + grow)
                cr.stroke()

        now = time.monotonic()
        for cx, cy, radius, t0, opening in self.ripples:
            t = (now - t0) / RIPPLE_S
            ease = 1 - (1 - t) ** 3
            r = radius * (0.25 + 0.85 * ease) if opening else radius * (1.1 - 0.85 * ease)
            cr.new_path()
            cr.set_line_width(2 + 5 * (1 - t))
            rgba(cr, "accent" if opening else "hint", 0.55 * (1 - t) ** 1.5)
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
                    self.wake()
                    self.retarget()
                    if not self.poll_id:
                        self.poll_id = GLib.timeout_add(250, self.poll)
                else:
                    self.alpha.target = 0.0
                    if not self.tick_id and self.win.get_visible():
                        self.last = None
                        self.tick_id = self.area.add_tick_callback(self.tick)
            return f"spotlight {'on' if self.spot else 'off'}"
        if words:
            self.ripples_on = state
        return f"ripples {'on' if self.ripples_on else 'off'}"
