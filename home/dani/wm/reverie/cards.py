"""cards: a title card when the scene changes.

Switching workspace is a cut, and films mark cuts. For about a second the
workspace's number arrives large in the middle of the screen with the names of
what lives there, then leaves. It is click-through and takes no focus, so it
is never in the way of what you switched there to do — and it replaces the
reason to keep a workspace strip permanently on screen.

The numeral travels in the direction you moved (up the scale: from the right;
down: from the left), which is the "motion that means something" rule: the
animation carries information the static frame does not.
"""

import cairo
from gi.repository import GLib, Gtk, Gtk4LayerShell

from common import EFFECT, PAL, SPATIAL, Spring, focused_gdk_monitor, hypr, layer_window, text

UI = "Inter Variable"


class Cards:
    def __init__(self, app):
        self.enabled = False
        self.win = layer_window(app, "reverie-card")
        self.area = Gtk.DrawingArea()
        self.area.set_draw_func(self.draw)
        self.win.set_child(self.area)
        self.win.connect("map", self.on_map)
        self.alpha = Spring(0.0, EFFECT)
        self.slide = Spring(0.0, SPATIAL)
        self.label = ""
        self.names = ""
        self.prev = None
        self.tick_id = 0
        self.last = None
        self.hide_id = 0

    def on_map(self, win):
        # An empty input region: every click falls through to the desktop.
        surface = win.get_surface()
        if surface is not None:
            surface.set_input_region(cairo.Region())

    def on_event(self, event, data):
        if not self.enabled or event != "workspacev2":
            return
        wid, _, name = data.partition(",")
        if not wid.lstrip("-").isdigit():
            return
        wid = int(wid)
        direction = 0 if self.prev is None else (1 if wid > self.prev else -1)
        self.prev = wid
        classes = []
        for c in hypr("j/clients") or []:
            if c.get("workspace", {}).get("id") == wid:
                cls = (c.get("class") or "").lower()
                if cls and cls not in classes:
                    classes.append(cls)
        self.label = name if wid < 0 else str(wid)
        self.names = "   ·   ".join(classes[:6]) if classes else "empty"
        self.present(direction)

    def present(self, direction):
        mon = focused_gdk_monitor()
        if mon is not None:
            Gtk4LayerShell.set_monitor(self.win, mon)
        self.slide.x = 90.0 * direction
        self.slide.v = 0.0
        self.slide.target = 0.0
        self.alpha.target = 1.0
        self.win.set_visible(True)
        if not self.tick_id:
            self.last = None
            self.tick_id = self.area.add_tick_callback(self.tick)
        if self.hide_id:
            GLib.source_remove(self.hide_id)
        self.hide_id = GLib.timeout_add(650, self.leave)

    def leave(self):
        self.hide_id = 0
        self.alpha.target = 0.0
        return False

    def tick(self, _widget, clock):
        now = clock.get_frame_time() / 1e6
        dt = 0.016 if self.last is None else min(0.05, now - self.last)
        self.last = now
        self.alpha.step(dt)
        self.slide.step(dt)
        self.area.queue_draw()
        if self.alpha.target == 0.0 and self.alpha.x < 0.01:
            self.win.set_visible(False)
            self.tick_id = 0
            return False
        return True

    def draw(self, _area, cr, w, h):
        a = max(0.0, min(1.0, self.alpha.x))
        u = h / 1440.0
        cx, cy = w / 2 + self.slide.x * u, h / 2
        # A soft dark pool so the numeral reads over any window content.
        pool = cairo.RadialGradient(cx, cy, 0, cx, cy, 520 * u)
        r, g, b = PAL["bgDeep"]
        pool.add_color_stop_rgba(0.0, r, g, b, 0.80 * a)
        pool.add_color_stop_rgba(0.6, r, g, b, 0.45 * a)
        pool.add_color_stop_rgba(1.0, r, g, b, 0.0)
        cr.set_source(pool)
        cr.paint()
        text(cr, self.label, cx, cy - 260 * u, 340 * u, "fg", a, family=UI, weight=200,
             align="center")
        text(cr, self.names.upper(), w / 2, cy + 170 * u, 20 * u, "muted", a, family=UI,
             weight=500, align="center", spacing=5 * u)

    def command(self, words):
        if words and words[0] in ("on", "off"):
            self.enabled = words[0] == "on"
        return f"cards {'on' if self.enabled else 'off'}"
