"""dream: what the desktop does when you are not looking at it.

A slow field of drifting light over the dimmed desktop — a few thousand
streamlines following a vector field that itself changes over minutes. Mostly
slate and blue; one particle in fourteen is a warm one, so the sunset shows up
as sparse threads rather than a wash. Any key or click wakes it.

Drawn at half resolution into a persistent surface that is faded a little each
frame, so the trails are the only state and a frame costs a few hundred short
lines. Nothing here touches the compositor: it is one overlay surface.
"""

import math
import random
import time

import cairo
from gi.repository import Gtk, Gtk4LayerShell

from common import PAL, EFFECT, Spring, focused_gdk_monitor, layer_window, rgba, text

SCALE = 2          # render at 1/SCALE resolution
COUNT = 1400
COOL = ("slate", "hint", "accent", "accentText", "muted")
WARM = ("attention", "warning", "critical")


class Dream:
    def __init__(self, app):
        self.win = layer_window(app, "reverie-dream", keyboard=True)
        self.area = Gtk.DrawingArea()
        self.area.set_draw_func(self.draw)
        self.win.set_child(self.area)
        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", lambda *_: self.hide() or True)
        self.win.add_controller(keys)
        click = Gtk.GestureClick()
        click.connect("pressed", lambda *_: self.hide())
        self.area.add_controller(click)
        self.alpha = Spring(0.0, EFFECT)
        self.shown = False
        self.tick_id = 0
        self.surface = None
        self.parts = []
        self.t0 = time.monotonic()
        self.last = None

    def toggle(self):
        self.hide() if self.shown else self.show()

    def show(self):
        if self.shown:
            return
        self.shown = True
        mon = focused_gdk_monitor()
        if mon is not None:
            Gtk4LayerShell.set_monitor(self.win, mon)
        self.surface = None
        self.alpha.target = 1.0
        self.win.set_visible(True)
        if not self.tick_id:
            self.last = None
            self.tick_id = self.area.add_tick_callback(self.tick)

    def hide(self):
        self.shown = False
        self.alpha.target = 0.0

    def tick(self, _widget, clock):
        now = clock.get_frame_time() / 1e6
        dt = 0.016 if self.last is None else min(0.05, now - self.last)
        self.last = now
        self.alpha.step(dt)
        self.area.queue_draw()
        if not self.shown and self.alpha.x < 0.01:
            self.win.set_visible(False)
            self.surface = None
            self.tick_id = 0
            return False
        return True

    def spawn(self, w, h):
        warm = random.random() < 1 / 14
        role = random.choice(WARM if warm else COOL)
        return [random.uniform(0, w), random.uniform(0, h), PAL[role],
                random.uniform(0.25, 0.8) if not warm else 0.9,
                random.randint(60, 260)]

    def angle(self, x, y, t):
        """A smooth pseudo-noise field from a few incommensurate sines."""
        a = math.sin(x * 0.0031 + t * 0.07) + math.cos(y * 0.0043 - t * 0.05)
        b = math.sin((x + y) * 0.0017 + t * 0.03) * 1.3
        c = math.cos(x * 0.0009 - y * 0.0013 + t * 0.02) * 1.7
        return (a + b + c) * 1.25

    def draw(self, _area, cr, w, h):
        sw, sh = max(1, w // SCALE), max(1, h // SCALE)
        if self.surface is None or self.surface.get_width() != sw:
            self.surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, sw, sh)
            self.parts = [self.spawn(sw, sh) for _ in range(COUNT)]
        t = time.monotonic() - self.t0

        sc = cairo.Context(self.surface)
        # Fade what is there toward transparent: trails are the only memory.
        sc.set_operator(cairo.OPERATOR_DEST_OUT)
        sc.set_source_rgba(0, 0, 0, 0.035)
        sc.paint()
        sc.set_operator(cairo.OPERATOR_OVER)
        sc.set_line_width(1.0)
        sc.set_line_cap(cairo.LINE_CAP_ROUND)
        for p in self.parts:
            x, y = p[0], p[1]
            ang = self.angle(x * SCALE, y * SCALE, t)
            nx, ny = x + math.cos(ang) * 1.5, y + math.sin(ang) * 1.5
            r, g, b = p[2]
            sc.set_source_rgba(r, g, b, p[3])
            sc.move_to(x, y)
            sc.line_to(nx, ny)
            sc.stroke()
            p[0], p[1] = nx, ny
            p[4] -= 1
            if p[4] <= 0 or not (0 <= nx < sw and 0 <= ny < sh):
                p[:] = self.spawn(sw, sh)

        a = max(0.0, min(1.0, self.alpha.x))
        rgba(cr, "bgDeep", 0.90 * a)
        cr.paint()
        cr.save()
        cr.scale(SCALE, SCALE)
        cr.set_source_surface(self.surface, 0, 0)
        cr.get_source().set_filter(cairo.FILTER_BILINEAR)
        cr.paint_with_alpha(a)
        cr.restore()

        u = h / 1440.0
        text(cr, time.strftime("%H:%M"), w - 70 * u, h - 150 * u, 84 * u, "fg", 0.85 * a,
             family="Inter Variable", weight=200, align="right")
        text(cr, "any key wakes it", w - 72 * u, h - 52 * u, 14 * u, "hint", a,
             family="Inter Variable", weight=500, align="right", spacing=3 * u)


