"""rest: the HUD at rest, in glass. A PROTOTYPE, and only when liquid glass is on.

Glass shows through see-through shapes and at their edges, and the HUD is
neither: one dark surface the size of the monitor, carrying opaque pictures
and thin type. Three ways of giving that one surface to the plugin were tried
(2026-11-22) and none read as glass. What the plugin does is one glass per
layer surface, shaped by that surface's own box. So for the HUD to have glass
*pieces*, the pieces have to be surfaces of their own — with something to
look through to underneath them, and the panel's type and cards above.

That is three storeys, and the HUD is one. This adds the other two, but only
once the panel has ARRIVED: the entrance and the exit are the one-surface
panel exactly as it was — they are the part that was tuned frame by frame,
and two monitor-sized surfaces animating at once is what common.layer_window
warns about. When nothing is moving any more:

  1. `back`, a surface on the `top` layer, comes up underneath with the very
     picture the panel is showing as its backdrop. Nothing changes on screen.
  2. A moment later the panel stops painting that backdrop and goes
     see-through between its cards and its type. Still nothing changes: the
     same picture is now the one underneath.
  3. Between the two, also on `top`, the pieces fade in: a tray under the
     workspace cards, and a pill for each of the bar's chips. They are
     see-through, the plugin puts its glass behind them (the `glass` command
     lists their namespace), and the chips' own solid islands fade out as the
     pills come.

Leaving is the reverse, at once: the panel takes its backdrop back, then the
two extra storeys go, unseen behind it.

`top`, not `overlay` like the panel: Hyprland stacks surfaces of one layer in
the order they map, and these map after the panel but have to sit under it.
The price is that `top` is hidden by a fullscreen window, so over one of
those the panel simply stays as it was.
"""

import cairo

import glass
from common import EFFECT, Spring, layer_window, rgba, rounded

from gi.repository import GLib, Gtk4LayerShell, Gtk  # noqa: E402  (common pins versions)

TRAY = (0.16, 0.10)          # the tray: how solid, and its hairline
PILL = (0.30, 0.10)          # a chip's pill: the bar's island under glass (wm/glass.nix)
TRAY_RADIUS = 30             # design px, like everything in the panel


def _click_through(win):
    surface = win.get_surface()
    if surface is not None:
        surface.set_input_region(cairo.Region())


class Piece:
    """A small surface holding see-through shapes, placed on the monitor."""

    def __init__(self, app):
        self.win = layer_window(app, "reverie-hud-glass", layer=Gtk4LayerShell.Layer.TOP,
                                full=False)
        for edge in (Gtk4LayerShell.Edge.TOP, Gtk4LayerShell.Edge.LEFT):
            Gtk4LayerShell.set_anchor(self.win, edge, True)
        self.area = Gtk.DrawingArea()
        self.area.set_draw_func(self.draw)
        self.win.set_child(self.area)
        self.win.connect("map", _click_through)
        self.box = None              # x, y, w, h on the monitor, whole pixels
        self.shapes = []             # (x, y, w, h, radius, (fill, line)), monitor coordinates
        self.unit = 1.0
        self.light = None            # (picture, x, y, sx, sy, alpha): a glow inside the shapes

    def place(self, shapes, unit):
        """The shapes, and a surface exactly as big as what they cover."""
        self.unit = unit
        self.shapes = shapes
        if not shapes:
            return False
        x0 = int(min(s[0] for s in shapes)) - 1
        y0 = int(min(s[1] for s in shapes)) - 1
        x1 = int(max(s[0] + s[2] for s in shapes)) + 2
        y1 = int(max(s[1] + s[3] for s in shapes)) + 2
        box = (x0, y0, x1 - x0, y1 - y0)
        if box != self.box:
            self.box = box
            Gtk4LayerShell.set_margin(self.win, Gtk4LayerShell.Edge.LEFT, x0)
            Gtk4LayerShell.set_margin(self.win, Gtk4LayerShell.Edge.TOP, y0)
            self.area.set_content_width(box[2])
            self.area.set_content_height(box[3])
            self.win.set_default_size(box[2], box[3])
        self.area.queue_draw()
        return True

    def draw(self, _area, cr, _w, _h):
        if self.box is None:
            return
        cr.translate(-self.box[0], -self.box[1])
        for x, y, w, h, radius, (fill, line) in self.shapes:
            rounded(cr, x, y, w, h, radius)
            rgba(cr, "bg", fill)
            cr.fill_preserve()
            cr.set_line_width(1.0 * self.unit)
            rgba(cr, "fg", line)
            cr.stroke()
        if self.light and self.shapes:
            picture, x, y, sx, sy, alpha = self.light
            for sx0, sy0, sw, sh, radius, _look in self.shapes:
                rounded(cr, sx0, sy0, sw, sh, radius)
            cr.clip()
            cr.translate(x, y)
            cr.scale(sx, sy)
            cr.set_source_surface(picture, 0, 0)
            cr.get_source().set_filter(cairo.FILTER_BILINEAR)
            cr.paint_with_alpha(alpha)


class Rest:
    def __init__(self, hud, app):
        self.hud = hud
        self.app = app
        self.enabled = True          # `reverie hud glass off` keeps the panel as it was
        self.state = 0               # 0 not there · 1 the backdrop is coming up · 2 live
        self.token = 0
        self.glassy = Spring(0.0, EFFECT)    # 0 the chips' own islands · 1 the pills
        self.tray_rect = None        # as last laid out by Hud.draw_map / draw_bar
        self.chip_rects = []
        self.light = None            # the light behind the selected card, while live
        self.placed = None           # what the pieces were last given
        self.back = layer_window(app, "reverie-hud-back", layer=Gtk4LayerShell.Layer.TOP)
        self.back_area = Gtk.DrawingArea()
        self.back_area.set_draw_func(self.draw_back)
        self.back.set_child(self.back_area)
        self.back.connect("map", _click_through)
        self.tray = Piece(app)
        self.chips = Piece(app)

    @property
    def live(self):
        return self.state == 2

    def wanted(self):
        hud = self.hud
        if not (glass.BIN and self.enabled and self.app.glass.on):
            return False
        if not hud.shown or hud.backdrop is None or hud.zoom_ws is not None or hud.mon is None:
            return False
        # Over a fullscreen window the `top` layer is not drawn at all.
        return not any(c.get("fullscreen") == 2 and c.get("workspace", {}).get("id") == hud.here
                       for c in hud.snapshot["clients"])

    # -- coming and going ---------------------------------------------------
    def settled(self):
        """The panel has arrived (Hud.tick, every frame from then on): its
        backdrop is all there and it has stopped travelling. Time for the
        other two storeys."""
        if self.state == 0 and self.wanted():
            self.state = 1
            self.token += 1
            Gtk4LayerShell.set_monitor(self.back, self.hud.mon)
            self.back.set_visible(True)
            self.back_area.queue_draw()
            # Not until the backdrop is really on the glass underneath: a
            # panel gone see-through over nothing is the desktop, sharp.
            GLib.timeout_add(70, self._go_live, self.token)

    def _go_live(self, token):
        if token != self.token or self.state != 1:
            return False
        if not self.wanted():
            self.end()
            return False
        self.state = 2
        self.placed = None
        self.sync()
        for piece in (self.tray, self.chips):
            Gtk4LayerShell.set_monitor(piece.win, self.hud.mon)
            if piece.shapes:
                piece.win.set_visible(True)
        self.glassy.target = 1.0
        self.hud.area.queue_draw()
        self.hud._ensure_tick()
        return False

    def end(self):
        """The panel is leaving, or glass was switched off: one storey again."""
        if self.state == 0:
            return
        self.state = 0
        self.token += 1
        self.glassy.x = self.glassy.target = self.glassy.v = 0.0
        self.hud.area.queue_draw()           # with its backdrop, first ...
        GLib.timeout_add(45, self._drop, self.token)

    def _drop(self, token):
        if token == self.token and self.state == 0:      # ... then these, behind it
            for win in (self.tray.win, self.chips.win, self.back):
                win.set_visible(False)
        return False

    # -- keeping up -----------------------------------------------------------
    def sync(self):
        """Give the pieces what the panel last laid out (called as it draws)."""
        if self.state != 2:
            return
        if not self.wanted():
            self.end()
            return
        if self.light != self.tray.light:     # the light glides with the selection
            self.tray.light = self.light
            self.tray.area.queue_draw()
        now = (self.tray_rect, tuple(self.chip_rects))
        if now == self.placed:
            return
        self.placed = now
        u = self.hud.unit
        tray = [(*self.tray_rect, TRAY_RADIUS * u, TRAY)] if self.tray_rect else []
        self.tray.place(tray, u)
        self.chips.place([(*rect, self.hud.island_radius * u, PILL) for rect in self.chip_rects], u)

    def draw_back(self, _area, cr, w, h):
        backdrop = self.hud.backdrop
        if backdrop is None or self.state == 0:
            return
        bw, bh = backdrop.get_width(), backdrop.get_height()
        if (bw, bh) != (w, h):
            cr.scale(w / bw, h / bh)
        cr.set_source_surface(backdrop, 0, 0)
        cr.paint()
