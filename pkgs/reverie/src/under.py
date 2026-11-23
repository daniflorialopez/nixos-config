"""under: liquid glass for a fullscreen window.

The plugin's glass behind a window is one of that window's decorations, and
Hyprland draws no decorations for a window in real fullscreen. So a terminal
with a see-through background, made fullscreen, had nothing behind it but the
wallpaper, sharp: no glass at all (Dani, 2026-11-23: "I would like the
full-screen apps to apply also the selected liquid glass style").

What Hyprland does still draw under a fullscreen window is the `background`
layer — that is where the wallpaper is. And the plugin will put its glass
behind any layer surface it is told about. So, while a see-through window is
fullscreen on a monitor, this maps one surface there: on `background`, above
the wallpaper, the size of the monitor, and as good as empty. The plugin
gives it the chosen look, of the wallpaper — which is all there is behind a
fullscreen window — and the window shows it, edge of the screen to edge of
the screen, as it would show its own glass edge to edge of itself.

Only while it is needed. Left there under ordinary windows it would be a
second pane behind each one's own; and under a game it would be work for
nothing, so it is not for every fullscreen window but for the ones that are
see-through — which, here, is what wm/glass.nix makes see-through.
"""

import cairo

import glass
from common import hypr, layer_window

from gi.repository import Gdk, GLib, Gtk, Gtk4LayerShell  # noqa: E402  (common pins versions)

# The windows that are see-through while glass is on (wm/glass.nix: the
# terminal's background opacity).
SEE_THROUGH = ("Alacritty",)
# The events after which the answer may have changed.
EVENTS = ("fullscreen", "workspace", "workspacev2", "focusedmon", "focusedmonv2", "openwindow",
          "closewindow", "movewindow", "movewindowv2", "activespecial", "monitoradded",
          "monitorremoved")


class Under:
    def __init__(self, app):
        self.app = app
        self.sheets = {}             # connector -> its window, made when first needed
        self.pending = 0

    def on_event(self, event, _data):
        if glass.BIN and event in EVENTS and not self.pending:
            # After Hyprland has finished with the event, and once for a burst.
            self.pending = GLib.timeout_add(30, self.check)

    def check(self):
        self.pending = 0
        wanted = set()
        if glass.BIN and self.app.glass.on:
            showing = {m["activeWorkspace"]["id"]: m["name"] for m in hypr("j/monitors") or []}
            for c in hypr("j/clients") or []:
                if c.get("fullscreen") == 2 and c.get("class") in SEE_THROUGH and \
                        c.get("workspace", {}).get("id") in showing:
                    wanted.add(showing[c["workspace"]["id"]])
        for name in wanted - {n for n, w in self.sheets.items() if w.get_visible()}:
            sheet = self.sheets.get(name) or self._sheet(name)
            if sheet is not None:
                sheet.set_visible(True)
        for name, sheet in self.sheets.items():
            if name not in wanted and sheet.get_visible():
                sheet.set_visible(False)
        return False

    def _sheet(self, name):
        monitors = Gdk.Display.get_default().get_monitors()
        mon = next((m for m in monitors if m.get_connector() == name), None)
        if mon is None:
            return None
        win = layer_window(self.app, "reverie-glass-under", layer=Gtk4LayerShell.Layer.BACKGROUND)
        Gtk4LayerShell.set_monitor(win, mon)
        area = Gtk.DrawingArea()
        area.set_draw_func(self.draw)
        win.set_child(area)
        win.connect("map", self._click_through)
        self.sheets[name] = win
        return win

    @staticmethod
    def _click_through(win):
        surface = win.get_surface()
        if surface is not None:
            surface.set_input_region(cairo.Region())

    @staticmethod
    def draw(_area, cr, _w, _h):
        # Not nothing: the plugin puts glass where a surface is not empty.
        # But as near to nothing as counts, so that what is seen is the glass.
        cr.set_source_rgba(0.0, 0.0, 0.0, 0.02)
        cr.paint()

    def close(self):
        for sheet in self.sheets.values():
            sheet.set_visible(False)
