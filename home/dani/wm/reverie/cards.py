"""cards: a title card when the scene changes.

Switching workspace is a cut, and films mark cuts. For about a second a card
arrives in the middle of the screen with the workspace's number, what lives
there, and where it sits among the others; then it leaves. It is click-through
and takes no focus, so it is never in the way of what you switched there to
do — and it is the reason a workspace strip does not have to be on screen
permanently.

The card travels in the direction you moved (up the numbers: from the right;
down: from the left), which is the "motion that means something" rule: the
animation carries information the still frame does not.

Three looks. Which one is right is a question for the eye, not for an
argument, so they are switchable live (`reverie cards style <name>|next`, or
the menu, which shows a sample each time you change it):

  bare     the number alone, very large, on a soft pool of shade. No box.
           This is the first version's idea, set in the desktop's own font.
  island   a card made of the bar's material (bg at 0.85, a 10% fg hairline,
           the compositor's blur under it): number, names, the bar's pills.
  banner   the same material laid out the way the bar is: one wide pill,
           number on the left, names and pills on the right.

All three say the same three things. Where the others sit is drawn the way
the bar draws it — active on an accent wash, occupied in `subtle`, empty in
`muted`, from the same `persistent-workspaces` list — as pills on the two
boxed looks and as dots on the bare one.
"""

import math

import cairo

from common import (EFFECT, FONT, PAL, SPATIAL, Spring, focused_gdk_monitor, hypr, ink, label,
                    layer_window, measure, rgba, rounded, text)

from gi.repository import GLib, Gtk, Gtk4LayerShell  # noqa: E402  (common pins versions)

HOLD_MS = 1000               # how long the card stays before it leaves
STYLES = ("bare", "island", "banner")
PILL_ROLE = {"active": "fg", "occupied": "subtle", "empty": "muted"}


class Cards:
    def __init__(self, app):
        self.enabled = False
        self.style = STYLES[0]
        self.bar = None              # set by main: the bar reader (persistent workspaces)
        # Two surfaces. The boxed looks want the compositor's blur under the
        # card (a layer rule on reverie-card). The bare one must not have it:
        # a blur that stops where a soft shade fades to nothing shows up as a
        # ring, so it lives in a namespace with no blur rule.
        self.boxed = self._surface(app, "reverie-card")
        self.plain = self._surface(app, "reverie-title")
        self.active = None           # whichever of the two is on screen
        self.alpha = Spring(0.0, EFFECT)
        self.slide = Spring(0.0, SPATIAL)
        self.label = ""
        self.names = ""
        self.strip = []              # [(id, "active" | "occupied" | "empty")]
        self.prev = None
        self.tick_id = 0
        self.last = None
        self.hide_id = 0

    def _surface(self, app, namespace):
        win = layer_window(app, namespace)
        area = Gtk.DrawingArea()
        area.set_draw_func(self.draw)
        win.set_child(area)
        win.connect("map", self.on_map)
        return win, area

    @staticmethod
    def on_map(win):
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

    def preview(self):
        """The card for where you already are: for comparing the looks."""
        ws = hypr("j/activeworkspace") or {}
        if ws.get("id") is None:
            return
        self.prev = ws["id"]
        self.compose(ws["id"], ws.get("name", str(ws["id"])))
        self.present(0)

    def present(self, direction):
        target = self.plain if self.style == "bare" else self.boxed
        if self.active is not None and self.active is not target:
            win, area = self.active
            if self.tick_id:
                area.remove_tick_callback(self.tick_id)
                self.tick_id = 0
            win.set_visible(False)
            self.alpha.x = self.alpha.v = 0.0
        self.active = target
        win, area = target
        mon = focused_gdk_monitor()
        if mon is not None:
            Gtk4LayerShell.set_monitor(win, mon)
        self.slide.x = 70.0 * direction
        self.slide.v = 0.0
        self.slide.target = 0.0
        self.alpha.target = 1.0
        win.set_visible(True)
        self._ensure_tick()
        if self.hide_id:
            GLib.source_remove(self.hide_id)
        self.hide_id = GLib.timeout_add(HOLD_MS, self.leave)

    def leave(self):
        self.hide_id = 0
        self.alpha.target = 0.0
        self._ensure_tick()
        return False

    def _ensure_tick(self):
        if not self.tick_id and self.active is not None:
            self.last = None
            self.tick_id = self.active[1].add_tick_callback(self.tick)

    def tick(self, area, clock):
        now = clock.get_frame_time() / 1e6
        dt = 0.016 if self.last is None else min(0.05, now - self.last)
        self.last = now
        self.alpha.step(dt)
        self.slide.step(dt)
        area.queue_draw()
        if self.alpha.target == 0.0 and self.alpha.x < 0.01:
            area.get_root().set_visible(False)
            self.tick_id = 0
            return False
        if self.alpha.resting and self.slide.resting:
            # Arrived and holding still: nothing to draw until it leaves.
            self.tick_id = 0
            return False
        return True

    # -- drawing ----------------------------------------------------------
    def draw(self, _area, cr, w, h):
        a = max(0.0, min(1.0, self.alpha.x))
        if a <= 0.0:
            return
        getattr(self, "draw_" + self.style)(cr, w, h, h / 1440.0, a)

    @staticmethod
    def _island(cr, x, y, w, h, r, u, a):
        """The bar's material. Everything outside it stays fully transparent,
        so the compositor's blur (ignore_alpha 0) applies to the card only."""
        rounded(cr, x, y, w, h, r)
        rgba(cr, "bg", 0.85 * a)
        cr.fill_preserve()
        cr.set_line_width(1.0 * u)
        rgba(cr, "fg", 0.10 * a)
        cr.stroke()

    def _names(self, cr, size, u):
        s = label(self.names)
        spacing = FONT["track"] * u
        return s, spacing, measure(cr, s, size, weight=FONT["regular"], spacing=spacing)

    def _pills(self, cr, x, y, u, a, pw, ph, gap, size):
        """The bar's workspace pills (wm/waybar.nix, #workspaces button)."""
        for wid, state in self.strip:
            if state == "active":
                rounded(cr, x, y, pw, ph, 8 * u)
                rgba(cr, "accent", 0.16 * a)
                cr.fill()
            _, dh = measure(cr, str(wid), size)
            text(cr, str(wid), x + pw / 2, y + (ph - dh) / 2, size, PILL_ROLE[state],
                 a * (0.55 if state == "empty" else 1.0), align="center")
            x += pw + gap

    def _strip_width(self, pw, gap):
        return len(self.strip) * pw + max(0, len(self.strip) - 1) * gap

    def draw_bare(self, cr, w, h, u, a):
        cx, cy = w / 2 + self.slide.x * u, h / 2
        weight, size = FONT["numeral_weight"], 300 * u
        ix, iy, iw, ih = ink(cr, self.label, size, weight=weight)
        names, spacing, (_, th) = self._names(cr, 18 * u, u)
        rule, dots = 34 * u, 24 * u
        top = cy - (ih + rule + 20 * u + th + dots + 8 * u) / 2

        # A pool of shade, wider than tall, so the number reads over a white
        # page as well as over a terminal: level under the type, then a
        # smoothstep down to nothing, so it has no edge to notice.
        r, g, b = PAL["bgDeep"]
        cr.save()
        cr.translate(cx, cy)
        cr.scale(620 * u, 420 * u)
        pool = cairo.RadialGradient(0, 0, 0, 0, 0, 1)
        for i in range(13):
            t = i / 12
            f = max(0.0, (t - 0.28) / 0.72)
            pool.add_color_stop_rgba(t, r, g, b, 0.86 * a * (1 - f * f * (3 - 2 * f)))
        cr.set_source(pool)
        cr.new_path()
        cr.arc(0, 0, 1, 0, math.tau)
        cr.fill()
        cr.restore()

        # Placed by the glyphs' own box, not the line box: the space above
        # and below a numeral this size is otherwise visibly uneven.
        text(cr, self.label, cx - iw / 2 - ix, top - iy, size, "fg", a, weight=weight)
        y = top + ih + rule
        rgba(cr, "fg", 0.26 * a)
        cr.rectangle(cx - 40 * u, y, 80 * u, max(1.0, u))
        cr.fill()
        y += 20 * u
        text(cr, names, cx, y, 18 * u, "subtle", a, weight=FONT["regular"], align="center",
             spacing=spacing)
        y += th + dots
        gap = 20 * u
        x = cx - gap * (len(self.strip) - 1) / 2
        for _wid, state in self.strip:
            cr.new_path()
            if state == "active":
                rgba(cr, "accent", a)
                cr.arc(x, y, 4.5 * u, 0, math.tau)
                cr.fill()
            elif state == "occupied":
                rgba(cr, "subtle", 0.9 * a)
                cr.arc(x, y, 3 * u, 0, math.tau)
                cr.fill()
            else:
                rgba(cr, "muted", 0.55 * a)
                cr.set_line_width(1.2 * u)
                cr.arc(x, y, 3 * u, 0, math.tau)
                cr.stroke()
            x += gap

    def draw_island(self, cr, w, h, u, a):
        weight, size = FONT["numeral_weight"], 150 * u
        ix, iy, iw, ih = ink(cr, self.label, size, weight=weight)
        names, spacing, (tw, th) = self._names(cr, 16 * u, u)
        pw, ph, gap = 34 * u, 28 * u, 6 * u
        sw = self._strip_width(pw, gap)
        pad = 44 * u
        cw = max(380 * u, iw + 2 * pad, tw + 2 * pad, sw + 2 * pad)
        ch = 42 * u + ih + 28 * u + th + 26 * u + ph + 32 * u
        x = (w - cw) / 2 + self.slide.x * u
        y = (h - ch) / 2
        self._island(cr, x, y, cw, ch, 20 * u, u, a)
        cx = x + cw / 2
        ty = y + 42 * u
        text(cr, self.label, cx - iw / 2 - ix, ty - iy, size, "fg", a, weight=weight)
        ty += ih + 28 * u
        text(cr, names, cx, ty, 16 * u, "muted", a, weight=FONT["regular"], align="center",
             spacing=spacing)
        ty += th + 26 * u
        self._pills(cr, cx - sw / 2, ty, u, a, pw, ph, gap, 15 * u)

    def draw_banner(self, cr, w, h, u, a):
        weight, size = FONT["numeral_weight"], 96 * u
        ix, iy, iw, ih = ink(cr, self.label, size, weight=weight)
        names, spacing, (tw, th) = self._names(cr, 17 * u, u)
        pw, ph, gap = 30 * u, 24 * u, 5 * u
        sw = self._strip_width(pw, gap)
        pad, mid, ch = 42 * u, 30 * u, 128 * u
        cw = pad + iw + 2 * mid + max(tw, sw) + pad
        x = (w - cw) / 2 + self.slide.x * u
        y = (h - ch) / 2
        self._island(cr, x, y, cw, ch, 32 * u, u, a)
        text(cr, self.label, x + pad - ix, y + (ch - ih) / 2 - iy, size, "fg", a, weight=weight)
        dx = x + pad + iw + mid
        rgba(cr, "fg", 0.10 * a)
        cr.rectangle(dx, y + 30 * u, max(1.0, u), ch - 60 * u)
        cr.fill()
        rx = dx + mid
        by = y + (ch - (th + 12 * u + ph)) / 2
        text(cr, names, rx, by, 17 * u, "subtle", a, weight=FONT["regular"], spacing=spacing)
        self._pills(cr, rx, by + th + 12 * u, u, a, pw, ph, gap, 13 * u)

    # -- commands ---------------------------------------------------------
    def command(self, words):
        what = words[0] if words else ""
        if what in ("on", "off", "toggle"):
            self.enabled = (not self.enabled) if what == "toggle" else what == "on"
        elif what == "style":
            want = words[1] if len(words) > 1 else ""
            if want == "next":
                want = STYLES[(STYLES.index(self.style) + 1) % len(STYLES)]
            if want in STYLES:
                self.style = want
                self.preview()
        elif what == "show":
            self.preview()
        return f"cards {'on' if self.enabled else 'off'} · card style {self.style}"
