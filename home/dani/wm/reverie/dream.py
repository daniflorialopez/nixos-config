"""dream: what the desktop does when you are not looking at it.

A slow field of drifting light over the dimmed desktop — about a thousand
streamlines following a vector field that itself changes over minutes. Mostly
slate and blue; one particle in fourteen is a warm one, so the sunset shows up
as sparse threads rather than a wash. Any key or click wakes it.

Cost is the design constraint, because this runs while nobody is watching:

  - it is drawn at half resolution into a persistent surface that is faded a
    little each frame, so the trails are the only state;
  - the vector field is sampled onto a coarse grid a couple of times a second
    instead of being evaluated per particle per frame — the field changes over
    minutes, so nothing is lost;
  - particles are stroked one colour at a time, a handful of cairo calls
    instead of a thousand;
  - 20 frames a second, whatever the panel can do, and a nearest-neighbour
    upscale (crisper than bilinear, and a fifth cheaper).

Nothing here touches the compositor: it is one overlay surface.
"""

import math
import random
import time

import cairo

from common import (EFFECT, FONT, PAL, Spring, focused_gdk_monitor, label, layer_window, rgba,
                    text)

from gi.repository import Gtk, Gtk4LayerShell  # noqa: E402  (common pins versions)

SCALE = 2            # render at 1/SCALE resolution
COUNT = 1100
FPS = 20
FILTER = cairo.FILTER_NEAREST     # measured: 28% of a core against 35% for bilinear
CELL = 16            # field grid pitch, in render pixels (a power of two)
SHIFT = 4            # log2(CELL)
STEP = 2.3           # render pixels a particle travels per frame
REFIELD = 0.6        # seconds between field rebuilds
COOL = ("slate", "hint", "accent", "accentText", "muted")
WARM = ("attention", "warning", "critical")


def angle(x, y, t):
    """A smooth pseudo-noise field from a few incommensurate sines."""
    a = math.sin(x * 0.0031 + t * 0.07) + math.cos(y * 0.0043 - t * 0.05)
    b = math.sin((x + y) * 0.0017 + t * 0.03) * 1.3
    c = math.cos(x * 0.0009 - y * 0.0013 + t * 0.02) * 1.7
    return (a + b + c) * 1.25


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
        self.groups = []             # (rgb, alpha, [[x, y, life], ...]) per colour
        self.field = []
        self.field_at = 0.0
        self.t0 = time.monotonic()
        self.last = None
        self.drawn_at = 0.0

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
        if now - self.drawn_at >= 1 / FPS:
            self.drawn_at = now
            self.area.queue_draw()
        if not self.shown and self.alpha.x < 0.01:
            self.win.set_visible(False)
            self.surface = None
            self.groups = []
            self.tick_id = 0
            return False
        return True

    def seed(self, sw, sh):
        """Deal the particles into one list per colour."""
        roles = [(r, 0.55) for r in COOL] + [(r, 0.9) for r in WARM]
        groups = [(PAL[role], alpha, []) for role, alpha in roles]
        for _ in range(COUNT):
            warm = random.random() < 1 / 14
            pool = groups[len(COOL):] if warm else groups[:len(COOL)]
            random.choice(pool)[2].append(
                [random.uniform(0, sw), random.uniform(0, sh), random.randint(40, 260)])
        return groups

    def build_field(self, sw, sh, t):
        """Unit steps on a coarse grid; particles just look their cell up."""
        cols, rows = (sw >> SHIFT) + 2, (sh >> SHIFT) + 2
        field = []
        for j in range(rows):
            y = j * CELL * SCALE
            row = []
            for i in range(cols):
                a = angle(i * CELL * SCALE, y, t)
                row.append((math.cos(a) * STEP, math.sin(a) * STEP))
            field.append(row)
        return field

    def draw(self, _area, cr, w, h):
        sw, sh = max(1, w // SCALE), max(1, h // SCALE)
        now = time.monotonic()
        if self.surface is None or self.surface.get_width() != sw:
            self.surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, sw, sh)
            self.groups = self.seed(sw, sh)
            self.field_at = 0.0
        if now - self.field_at > REFIELD:
            self.field = self.build_field(sw, sh, now - self.t0)
            self.field_at = now
        field = self.field
        rnd = random.random

        sc = cairo.Context(self.surface)
        # Fade what is there toward transparent: trails are the only memory.
        sc.set_operator(cairo.OPERATOR_DEST_OUT)
        sc.set_source_rgba(0, 0, 0, 0.045)
        sc.paint()
        sc.set_operator(cairo.OPERATOR_OVER)
        sc.set_line_width(1.0)
        sc.set_line_cap(cairo.LINE_CAP_ROUND)
        for (r, g, b), alpha, parts in self.groups:
            sc.set_source_rgba(r, g, b, alpha)
            for p in parts:
                x, y = p[0], p[1]
                dx, dy = field[int(y) >> SHIFT][int(x) >> SHIFT]
                nx, ny = x + dx, y + dy
                sc.move_to(x, y)
                sc.line_to(nx, ny)
                p[2] -= 1
                if p[2] <= 0 or not (0 <= nx < sw and 0 <= ny < sh):
                    p[0], p[1], p[2] = rnd() * sw, rnd() * sh, 40 + int(rnd() * 220)
                else:
                    p[0], p[1] = nx, ny
            sc.stroke()

        a = max(0.0, min(1.0, self.alpha.x))
        # SOURCE, not OVER: the target starts out clear, so the scrim can be
        # written rather than blended — a fill instead of 3.7 M blends.
        cr.set_operator(cairo.OPERATOR_SOURCE)
        rgba(cr, "bgDeep", 0.90 * a)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)
        cr.save()
        cr.scale(SCALE, SCALE)
        cr.set_source_surface(self.surface, 0, 0)
        cr.get_source().set_filter(FILTER)
        cr.paint_with_alpha(a)
        cr.restore()

        u = h / 1440.0
        text(cr, time.strftime("%H:%M"), w - 70 * u, h - 150 * u, 84 * u, "fg", 0.85 * a,
             weight=FONT["clock_weight"], align="right")
        text(cr, label("any key wakes it"), w - 72 * u, h - 52 * u, 14 * u, "hint", a,
             weight=FONT["strong"], align="right", spacing=FONT["track"] * u)
