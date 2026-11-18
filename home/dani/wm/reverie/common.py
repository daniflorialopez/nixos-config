"""Shared plumbing for reverie: palette, Hyprland IPC, springs, text."""

import json
import math
import os
import socket

import gi

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, Gtk, Gtk4LayerShell, Pango, PangoCairo  # noqa: E402

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
SOCK = os.path.join(RUNTIME, "reverie.sock")

# ---------------------------------------------------------------- palette
# Every colour comes from theme/palette.nix, handed over as the same JSON the
# build-time contrast gate validates. No literal hex in this package.


def _load_palette():
    with open(os.environ["REVERIE_PALETTE"]) as f:
        roles = json.load(f)["roles"]
    out = {}
    for name, role in roles.items():
        h = role["hex"].lstrip("#")
        out[name] = tuple(int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return out


PAL = _load_palette()


def rgba(cr, role, alpha=1.0):
    r, g, b = PAL[role]
    cr.set_source_rgba(r, g, b, alpha)


def mix(a, b, t):
    """Blend two palette roles; returns an rgb tuple."""
    ca, cb = PAL[a], PAL[b]
    return tuple(ca[i] + (cb[i] - ca[i]) * t for i in range(3))


# ------------------------------------------------------------- typography
# One voice for every surface. The default is the desktop's own: the bar,
# walker, mako and the lock screen are all CaskaydiaMono, and wm/hyprlock.nix
# is the reference for how a large clock is set in it (regular colour `fg`,
# date in `subtle`, mixed case). `inter` is kept as the alternative that the
# first version shipped with, so the two can be compared live:
# `reverie font caskaydia|inter`.
#
# No semibold in Caskaydia: its flat-topped capitals read as cropped once the
# strokes get heavy, so emphasis there is colour, never weight.
FONTS = {
    "caskaydia": {
        "family": "CaskaydiaMono Nerd Font", "regular": 400, "strong": 400, "thin": 300,
        "clock_size": 150, "clock_weight": 300, "clock_track": 0.0,
        "upper": False, "track": 0.0, "numeral_weight": 200,
    },
    "inter": {
        "family": "Inter Variable", "regular": 400, "strong": 600, "thin": 300,
        "clock_size": 210, "clock_weight": 200, "clock_track": -4.0,
        "upper": True, "track": 3.0, "numeral_weight": 200,
    },
}
FONT = {"name": "caskaydia", **FONTS["caskaydia"]}
# Glyphs (the bar's Nerd Font icons) always come from here, whatever the voice.
ICON_FAMILY = "CaskaydiaMono Nerd Font"


def set_font(name):
    if name in FONTS:
        FONT.clear()
        FONT.update({"name": name, **FONTS[name]})
    return FONT["name"]


def label(s):
    """Small captions: upper-case and tracked in Inter, as typed in Caskaydia."""
    return s.upper() if FONT["upper"] else s


# ----------------------------------------------------------- Hyprland IPC


def _hypr_dir():
    return os.path.join(RUNTIME, "hypr", os.environ["HYPRLAND_INSTANCE_SIGNATURE"])


def hypr(cmd):
    """One request on the command socket. `j/` prefix returns parsed JSON."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.settimeout(1.0)
        s.connect(os.path.join(_hypr_dir(), ".socket.sock"))
        s.sendall(cmd.encode())
        chunks = []
        while True:
            data = s.recv(65536)
            if not data:
                break
            chunks.append(data)
    finally:
        s.close()
    text = b"".join(chunks).decode(errors="replace")
    if cmd.startswith("j/"):
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return None
    return text


def hypr_events_path():
    return os.path.join(_hypr_dir(), ".socket2.sock")


# ---------------------------------------------------------------- springs
# Motion tokens, after Material 3 Expressive: `spatial` may overshoot (things
# that move), `effect` never does (opacity, colour). A real spring can be
# retargeted mid-flight and simply turns around, which a bezier cannot.

SPATIAL = (210.0, 17.0)
EFFECT = (260.0, 32.5)  # ~critically damped


class Spring:
    def __init__(self, value=0.0, token=EFFECT):
        self.x = value
        self.v = 0.0
        self.target = value
        self.k, self.c = token

    def step(self, dt):
        # Semi-implicit Euler in small substeps so a dropped frame cannot
        # blow the integration up.
        n = max(1, int(dt / 0.004))
        h = dt / n
        for _ in range(n):
            a = self.k * (self.target - self.x) - self.c * self.v
            self.v += a * h
            self.x += self.v * h
        return self.x

    @property
    def resting(self):
        return abs(self.target - self.x) < 0.001 and abs(self.v) < 0.01


# ------------------------------------------------------------------- text


def _layout(cr, s, size, family, weight, spacing):
    layout = PangoCairo.create_layout(cr)
    desc = Pango.FontDescription()
    desc.set_family(family)
    desc.set_absolute_size(size * Pango.SCALE)
    desc.set_weight(weight)
    layout.set_font_description(desc)
    if spacing:
        attrs = Pango.AttrList()
        attrs.insert(Pango.attr_letter_spacing_new(int(spacing * Pango.SCALE)))
        layout.set_attributes(attrs)
    layout.set_text(s, -1)
    return layout


def measure(cr, s, size, family=None, weight=400, spacing=0):
    """Pixel size `text` would occupy, without drawing it."""
    return _layout(cr, s, size, family or FONT["family"], weight, spacing).get_pixel_size()


def text(cr, s, x, y, size, role="fg", alpha=1.0, family=None,
         weight=400, align="left", spacing=0):
    """Draw `s` with its top-left (or top-centre / top-right) at x, y."""
    layout = _layout(cr, s, size, family or FONT["family"], weight, spacing)
    w, h = layout.get_pixel_size()
    if align == "center":
        x -= w / 2
    elif align == "right":
        x -= w
    rgba(cr, role, alpha)
    cr.move_to(x, y)
    PangoCairo.show_layout(cr, layout)
    cr.new_path()            # leave no current point behind for the next arc
    return w, h


def ink(cr, s, size, family=None, weight=400, spacing=0):
    """The box the glyphs really cover, as (x, y, w, h) from the point `text`
    would be asked to draw at. A line box includes room for descenders and
    accents that a numeral never uses, so anything set large is placed by
    this instead."""
    rect, _ = _layout(cr, s, size, family or FONT["family"], weight, spacing).get_pixel_extents()
    return rect.x, rect.y, rect.width, rect.height


def rounded(cr, x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 1.5 * math.pi)
    cr.close_path()


# ----------------------------------------------------------- layer window


def layer_window(app, namespace, keyboard=False, layer=None):
    """A transparent full-monitor overlay surface."""
    win = Gtk.Window(application=app)
    Gtk4LayerShell.init_for_window(win)
    Gtk4LayerShell.set_namespace(win, namespace)
    Gtk4LayerShell.set_layer(win, layer or Gtk4LayerShell.Layer.OVERLAY)
    for edge in (Gtk4LayerShell.Edge.TOP, Gtk4LayerShell.Edge.BOTTOM,
                 Gtk4LayerShell.Edge.LEFT, Gtk4LayerShell.Edge.RIGHT):
        Gtk4LayerShell.set_anchor(win, edge, True)
    Gtk4LayerShell.set_exclusive_zone(win, -1)
    Gtk4LayerShell.set_keyboard_mode(
        win,
        Gtk4LayerShell.KeyboardMode.EXCLUSIVE if keyboard else Gtk4LayerShell.KeyboardMode.NONE,
    )
    win.add_css_class("reverie")
    return win


def focused_gdk_monitor():
    """The Gdk monitor Hyprland says has focus, or None."""
    mons = hypr("j/monitors") or []
    name = next((m["name"] for m in mons if m.get("focused")), None)
    display = Gdk.Display.get_default()
    monitors = display.get_monitors()
    for i in range(monitors.get_n_items()):
        mon = monitors.get_item(i)
        if mon.get_connector() == name:
            return mon
    return None


def install_css():
    css = Gtk.CssProvider()
    css.load_from_data(
        b"window.reverie, window.reverie.background { background: none; box-shadow: none; }")
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER
    )
