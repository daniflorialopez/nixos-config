"""cards: a title card when the scene changes.

Switching workspace is a cut, and films mark cuts. For under a second a card
arrives in the middle of the screen with the workspace's number, what lives
there, and where it sits among the others; then it leaves. It is click-through
and takes no focus, so it is never in the way of what you switched there to
do — and it is the reason a workspace strip does not have to be on screen
permanently.

The card is made of the same thing as the rest of the chrome: the bar's
island material (bg at 0.85, a 10% fg hairline, blurred by the compositor
through a layer rule), the desktop font, and at its foot the bar's own
workspace pills — same colours for active, occupied and empty, read from the
same `persistent-workspaces` list.

The card travels in the direction you moved (up the numbers: from the right;
down: from the left), which is the "motion that means something" rule: the
animation carries information the still frame does not.
"""

import cairo

from common import (EFFECT, FONT, SPATIAL, Spring, focused_gdk_monitor, hypr, label,
                    layer_window, measure, rgba, rounded, text)

from gi.repository import GLib, Gtk, Gtk4LayerShell  # noqa: E402  (common pins versions)

HOLD_MS = 650                # how long the card stays before it leaves


class Cards:
    def __init__(self, app):
        self.enabled = False
        self.bar = None              # set by main: the bar reader (persistent workspaces)
        self.win = layer_window(app, "reverie-card")
        self.area = Gtk.DrawingArea()
        self.area.set_draw_func(self.draw)
        self.win.set_child(self.area)
        self.win.connect("map", self.on_map)
        self.alpha = Spring(0.0, EFFECT)
        self.slide = Spring(0.0, SPATIAL)
        self.label = ""
        self.names = ""
        self.strip = []              # [(id, "active" | "occupied" | "empty")]
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
        self.compose(wid, name)
        self.present(direction)

    def compose(self, wid, name):
        """Gather what the card says about workspace `wid`."""
        classes, occupied = [], set()
        for c in hypr("j/clients") or []:
            ws = c.get("workspace", {}).get("id")
            if ws is not None and ws > 0:
                occupied.add(ws)
            if ws == wid:
                cls = (c.get("class") or "").lower()
                if cls and cls not in classes:
                    classes.append(cls)
        self.label = name if wid < 0 else str(wid)
        self.names = "   ·   ".join(classes[:5]) if classes else "empty"
        always = self.bar.persistent_workspaces() if self.bar is not None else []
        ids = sorted(set(always) | occupied | ({wid} if wid > 0 else set()))
        self.strip = [(i, "active" if i == wid else "occupied" if i in occupied else "empty")
                      for i in ids]

    def present(self, direction):
        mon = focused_gdk_monitor()
        if mon is not None:
            Gtk4LayerShell.set_monitor(self.win, mon)
        self.slide.x = 70.0 * direction
        self.slide.v = 0.0
        self.slide.target = 0.0
        self.alpha.target = 1.0
        self.win.set_visible(True)
        if not self.tick_id:
            self.last = None
            self.tick_id = self.area.add_tick_callback(self.tick)
        if self.hide_id:
            GLib.source_remove(self.hide_id)
        self.hide_id = GLib.timeout_add(HOLD_MS, self.leave)

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
        num_size, name_size, pill_size = 150 * u, 16 * u, 15 * u
        pill_w, pill_h, pill_gap = 34 * u, 28 * u, 6 * u

        nw, nh = measure(cr, self.label, num_size, weight=FONT["numeral_weight"])
        names = label(self.names)
        tw, th = measure(cr, names, name_size, weight=FONT["regular"],
                         spacing=FONT["track"] * u)
        strip_w = len(self.strip) * pill_w + max(0, len(self.strip) - 1) * pill_gap
        pad = 44 * u
        cw = max(380 * u, nw + 2 * pad, tw + 2 * pad, strip_w + 2 * pad)
        ch = 30 * u + nh + 6 * u + th + 28 * u + pill_h + 30 * u
        x = (w - cw) / 2 + self.slide.x * u
        y = (h - ch) / 2

        # The island. Everything outside it stays fully transparent, so the
        # compositor's blur (layer rule, ignore_alpha 0) applies to the card
        # only.
        rounded(cr, x, y, cw, ch, 20 * u)
        rgba(cr, "bg", 0.85 * a)
        cr.fill_preserve()
        cr.set_line_width(1.0 * u)
        rgba(cr, "fg", 0.10 * a)
        cr.stroke()

        cx = x + cw / 2
        ty = y + 30 * u
        text(cr, self.label, cx, ty, num_size, "fg", a, weight=FONT["numeral_weight"],
             align="center")
        ty += nh + 6 * u
        text(cr, names, cx, ty, name_size, "muted", a, weight=FONT["regular"], align="center",
             spacing=FONT["track"] * u)
        ty += th + 28 * u

        # The bar's workspace pills: active on an accent wash, occupied in
        # `subtle`, empty in `muted` (wm/waybar.nix, #workspaces button).
        px = cx - strip_w / 2
        for wid, state in self.strip:
            if state == "active":
                rounded(cr, px, ty, pill_w, pill_h, 8 * u)
                rgba(cr, "accent", 0.16 * a)
                cr.fill()
            role = {"active": "fg", "occupied": "subtle", "empty": "muted"}[state]
            _, dh = measure(cr, str(wid), pill_size)
            text(cr, str(wid), px + pill_w / 2, ty + (pill_h - dh) / 2, pill_size, role,
                 a * (0.55 if state == "empty" else 1.0), align="center")
            px += pill_w + pill_gap

    def command(self, words):
        if words and words[0] in ("on", "off", "toggle"):
            self.enabled = (not self.enabled) if words[0] == "toggle" else words[0] == "on"
        return f"cards {'on' if self.enabled else 'off'}"
