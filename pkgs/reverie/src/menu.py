"""menu: every switch at one glance, and it stays while you flip them.

The first menu was walker's dmenu: a list that scrolled, showed "on"/"off" as
a word at the end of a row, and closed the moment you picked anything — so
trying three settings meant opening it three times. A launcher is the wrong
tool for a control panel.

This is a deck along the bottom of the screen, ten tiles in two rows, nothing
to scroll. A tile that is on is lit, the way the bar lights the active
workspace. Flipping one does not close anything: the switch slides, and
because the deck sits low and leaves the middle of the screen alone, you
watch the thing itself change — the spotlight come on round the window, the
bar leave, a sample title card in the new style.

  1 … 0          flip that tile (0 is the tenth, as on the number row)
  arrows / hjkl  move      enter / space  flip      tab  next
  click          flip      esc, q, a click outside, or the menu key: close

The two tiles on the right do something and leave: reopen the window you last
closed (the tile says which), and the demo.
"""

import math
import os
import subprocess

import cairo

import common
from cards import STYLES
from common import (EFFECT, FONT, SPATIAL, Spring, focused_output, layer_window, rgba,
                    rounded, text)

from gi.repository import Gdk, Gtk, Gtk4LayerShell  # noqa: E402  (common pins versions)

ISLAND_RADIUS = float(os.environ.get("REVERIE_ISLAND_RADIUS", "12"))
COLS = 5
KEYS = "1234567890"
KNOB = (520.0, 36.0)         # a switch knob: quick, the faintest overshoot

# id, label, kind, the line under the label (toggles and actions). A tile has
# room for about 23 characters there.
TILES = [
    ("spotlight", "Spotlight", "toggle", "light follows focus"),
    ("zen", "Zen", "toggle", "no bar"),
    ("cards", "Title cards", "toggle", "name each workspace"),
    ("ripples", "Ripples", "toggle", "a ring on open, close"),
    ("sound", "Sound", "toggle", "a note per workspace"),
    ("fade", "Fade", "toggle", "idle windows dim"),
    ("font", "Font", "cycle", ""),
    ("style", "Card look", "cycle", ""),
    ("undo", "Reopen", "action", "nothing closed yet"),
    ("demo", "Demo", "action", "a 30 s tour"),
]
COMMANDS = {
    "spotlight": ["spotlight", "toggle"],
    "zen": ["zen", "toggle"],
    "cards": ["cards", "toggle"],
    "ripples": ["ripples", "toggle"],
    "sound": ["pulse", "sound", "toggle"],
    "fade": ["pulse", "fade", "toggle"],
    "font": ["font", "toggle"],
    "style": ["cards", "style", "next"],
    "undo": ["undo"],
}
MOVES = {"Left": (-1, 0), "h": (-1, 0), "Right": (1, 0), "l": (1, 0),
         "Up": (0, -1), "k": (0, -1), "Down": (0, 1), "j": (0, 1)}


class Menu:
    def __init__(self, app):
        self.app = app
        self.win = layer_window(app, "reverie-menu", keyboard=True)
        self.area = Gtk.DrawingArea()
        self.area.set_draw_func(self.draw)
        self.win.set_child(self.area)
        self.win.connect("map", lambda _w: self._apply_input())
        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self.on_key)
        self.win.add_controller(keys)
        click = Gtk.GestureClick()
        click.connect("released", self.on_click)
        self.area.add_controller(click)
        motion = Gtk.EventControllerMotion()
        motion.connect("motion", self.on_motion)
        self.area.add_controller(motion)

        self.shown = False
        self.cursor = 0
        self.alpha = Spring(0.0, EFFECT)
        self.rise = Spring(0.0, SPATIAL)
        self.knob = {t[0]: Spring(0.0, KNOB) for t in TILES if t[2] == "toggle"}
        self.hits = []               # (x, y, w, h, index)
        self.panel = (0, 0, 0, 0)
        self.pointer = None
        self.tick_id = 0
        self.last = None

    # -- show / hide ------------------------------------------------------
    def show(self):
        if self.shown:
            return
        self.shown = True
        mon, info = focused_output()
        if mon is not None and not self.win.get_visible():
            Gtk4LayerShell.set_monitor(self.win, mon)
        flags = self.app.flags()
        for tid, spring in self.knob.items():        # opens showing the truth, unanimated
            spring.x = spring.target = 1.0 if flags.get(tid) else 0.0
            spring.v = 0.0
        self.pointer = None
        self.alpha.target = 1.0
        self.rise.target = 1.0
        Gtk4LayerShell.set_keyboard_mode(self.win, Gtk4LayerShell.KeyboardMode.EXCLUSIVE)
        self.win.set_visible(True)
        self._apply_input()
        self._ensure_tick()
        # The spotlight has to leave the deck lit: it is where you are
        # looking while you switch the spotlight on.
        if mon is not None:
            geo = mon.get_geometry()
            u, x, y, pw, ph = self.geometry(geo.width, geo.height)[:5]
            self.app.fx.set_lit((info.get("x", 0) + x, info.get("y", 0) + y, pw, ph, 22 * u))

    def hide(self):
        if not self.shown:
            return
        self.shown = False
        self.alpha.target = 0.0
        self.rise.target = 0.0
        # Give the keyboard and the pointer back now, not when the fade ends.
        Gtk4LayerShell.set_keyboard_mode(self.win, Gtk4LayerShell.KeyboardMode.NONE)
        self._apply_input()
        self._ensure_tick()
        self.app.fx.set_lit(None)

    def _apply_input(self):
        surface = self.win.get_surface()
        if surface is None:
            return
        if self.shown:
            # The whole monitor: a click beside the deck has to reach us to close it.
            w, h = self.area.get_width(), self.area.get_height()
            surface.set_input_region(cairo.Region(cairo.RectangleInt(0, 0, max(w, 1), max(h, 1))))
        else:
            surface.set_input_region(cairo.Region())

    def command(self, words):
        what = words[0] if words else "toggle"
        if what == "show" or (what == "toggle" and not self.shown):
            self.show()
        elif what in ("hide", "toggle"):
            self.hide()
        elif what == "key" and len(words) > 1:
            # `reverie menu key <name>`: the key handler without a keyboard,
            # for tests (nothing on this machine can inject a key press).
            self.on_key(None, Gdk.keyval_from_name(words[1]), 0, 0)
        return f"menu {'open' if self.shown else 'closed'} · cursor {TILES[self.cursor][0]}"

    # -- input ------------------------------------------------------------
    def on_key(self, _ctl, keyval, _code, _state):
        if not self.shown:
            return False
        name = Gdk.keyval_name(keyval) or ""
        if name.startswith("KP_"):
            name = name[3:]
        if name in ("Escape", "q"):
            self.hide()
        elif len(name) == 1 and name in KEYS and KEYS.index(name) < len(TILES):
            self.activate(KEYS.index(name))
        elif name in MOVES:
            dx, dy = MOVES[name]
            rows = math.ceil(len(TILES) / COLS)
            col = (self.cursor % COLS + dx) % COLS
            row = (self.cursor // COLS + dy) % rows
            self.cursor = min(len(TILES) - 1, row * COLS + col)
        elif name in ("Tab", "ISO_Left_Tab"):
            self.cursor = (self.cursor + (1 if name == "Tab" else -1)) % len(TILES)
        elif name in ("Return", "Enter", "space"):
            self.activate(self.cursor)
        self._ensure_tick()
        return True

    def on_click(self, _gesture, _n, x, y):
        for hx, hy, hw, hh, i in self.hits:
            if hx <= x <= hx + hw and hy <= y <= hy + hh:
                self.activate(i)
                return
        px, py, pw, ph = self.panel
        if not (px <= x <= px + pw and py <= y <= py + ph):
            self.hide()

    def on_motion(self, _ctl, x, y):
        # The first event after mapping only says where the pointer already
        # was; moving the cursor there would fight the keyboard.
        moved = self.pointer is not None and (abs(x - self.pointer[0]) + abs(y - self.pointer[1])) > 2
        self.pointer = (x, y)
        if not moved:
            return
        for hx, hy, hw, hh, i in self.hits:
            if hx <= x <= hx + hw and hy <= y <= hy + hh and i != self.cursor:
                self.cursor = i
                self._ensure_tick()

    def activate(self, i):
        tid, _name, kind, _hint = TILES[i]
        self.cursor = i
        if tid == "demo":
            self.hide()
            try:
                subprocess.Popen([os.environ.get("REVERIE_BIN", "reverie"), "demo"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 start_new_session=True)
            except OSError:
                pass
            return
        self.app.command(COMMANDS[tid])
        if kind == "action":
            self.hide()
            return
        if tid == "cards" and self.app.cards.enabled:
            self.app.cards.preview()         # switched on: show what that means
        flags = self.app.flags()
        for key, spring in self.knob.items():        # zen also switches the cards on
            spring.target = 1.0 if flags.get(key) else 0.0
        self._ensure_tick()

    # -- animation --------------------------------------------------------
    def _ensure_tick(self):
        if not self.tick_id:
            self.last = None
            self.tick_id = self.area.add_tick_callback(self.tick)

    def tick(self, _area, clock):
        now = clock.get_frame_time() / 1e6
        dt = 0.016 if self.last is None else min(0.05, now - self.last)
        self.last = now
        self.alpha.step(dt)
        self.rise.step(dt)
        for spring in self.knob.values():
            spring.step(dt)
        self.area.queue_draw()
        if not self.shown and self.alpha.x < 0.01:
            self.win.set_visible(False)
            self.tick_id = 0
            return False
        if self.alpha.resting and self.rise.resting and \
                all(s.resting for s in self.knob.values()):
            self.tick_id = 0             # still: stop drawing frames
            return False
        return True

    # -- drawing ----------------------------------------------------------
    @staticmethod
    def geometry(w, h):
        """Everything in design units (px at 1440p), from the monitor's size."""
        u = h / 1440.0
        tw, th, gap, pad, head = 214 * u, 104 * u, 10 * u, 20 * u, 40 * u
        rows = math.ceil(len(TILES) / COLS)
        pw = 2 * pad + COLS * tw + (COLS - 1) * gap
        ph = pad + head + rows * th + (rows - 1) * gap + pad
        return u, (w - pw) / 2, h - 96 * u - ph, pw, ph, tw, th, gap, pad, head

    def draw(self, _area, cr, w, h):
        a = max(0.0, min(1.0, self.alpha.x))
        if a <= 0.0:
            return
        u, x, y, pw, ph, tw, th, gap, pad, head = self.geometry(w, h)
        self.panel = (x, y, pw, ph)
        y += (1.0 - self.rise.x) * 20 * u            # comes up into place

        # The bar's material, like every other island. Outside it the surface
        # is fully transparent, so the layer rule blurs under the deck only.
        rounded(cr, x, y, pw, ph, 22 * u)
        rgba(cr, "bg", 0.85 * a)
        cr.fill_preserve()
        cr.set_line_width(1.0 * u)
        rgba(cr, "fg", 0.10 * a)
        cr.stroke()

        text(cr, "Reverie", x + pad + 4 * u, y + pad - 1 * u, 17 * u, "fg", a,
             weight=FONT["regular"])
        text(cr, "1…0 flip   ·   arrows, enter   ·   esc closes", x + pw - pad - 4 * u,
             y + pad + 2 * u, 13 * u, "hint", a, align="right")

        flags = self.app.flags()
        self.hits = []
        for i, tile in enumerate(TILES):
            tx = x + pad + (i % COLS) * (tw + gap)
            ty = y + pad + head + (i // COLS) * (th + gap)
            self.hits.append((tx, ty, tw, th, i))
            self.draw_tile(cr, i, tile, flags, tx, ty, tw, th, u, a)

    def draw_tile(self, cr, i, tile, flags, x, y, w, h, u, a):
        tid, name, kind, hint = tile
        value = flags.get(tid)
        on = kind == "toggle" and bool(value)
        m = 16 * u

        rounded(cr, x, y, w, h, ISLAND_RADIUS * u)
        if on:
            rgba(cr, "accent", 0.16 * a)     # the bar's active-workspace wash
        else:
            rgba(cr, "fg", 0.04 * a)
        cr.fill_preserve()
        # Where the cursor is: a lighter line, never a different hue.
        focus = i == self.cursor
        cr.set_line_width((1.5 if focus else 1.0) * u)
        rgba(cr, "fg", (0.50 if focus else 0.08) * a)
        cr.stroke()

        text(cr, name, x + m, y + 13 * u, 17 * u,
             "fg" if on or kind != "toggle" else "subtle", a, weight=FONT["regular"])
        text(cr, KEYS[i], x + w - m, y + 15 * u, 13 * u, "hint", a, align="right")

        if kind == "cycle":
            sub, role = str(value), "fg"
        elif tid == "undo":
            sub, role = self.app.pulse.last_closed() or hint, "muted"
        else:
            sub, role = hint, "muted"
        cr.save()
        cr.rectangle(x + m, y, w - 2 * m, h)         # a long window class must not spill
        cr.clip()
        text(cr, sub, x + m, y + 42 * u, 13 * u, role, a, weight=FONT["regular"])
        cr.restore()

        bx, by = x + w - m, y + h - 15 * u           # bottom-right corner of the ornament
        if kind == "toggle":
            self.draw_switch(cr, bx - 34 * u, by - 18 * u, self.knob[tid].x, u, a)
        elif kind == "cycle":
            options = list(common.FONTS) if tid == "font" else list(STYLES)
            for k, option in enumerate(reversed(options)):
                cr.new_path()
                cx, cy = bx - 4 * u - k * 13 * u, by - 9 * u
                if option == value:
                    rgba(cr, "accent", a)
                    cr.arc(cx, cy, 4 * u, 0, math.tau)
                    cr.fill()
                else:
                    rgba(cr, "muted", 0.55 * a)
                    cr.set_line_width(1.2 * u)
                    cr.arc(cx, cy, 3 * u, 0, math.tau)
                    cr.stroke()
        else:
            cr.new_path()
            cr.set_line_width(1.6 * u)
            cr.set_line_cap(cairo.LINE_CAP_ROUND)
            cr.set_line_join(cairo.LINE_JOIN_ROUND)
            rgba(cr, "hint", a)
            cr.move_to(bx - 9 * u, by - 15 * u)
            cr.line_to(bx - 3 * u, by - 9 * u)
            cr.line_to(bx - 9 * u, by - 3 * u)
            cr.stroke()

    @staticmethod
    def draw_switch(cr, x, y, t, u, a):
        """34 x 18: the track fills with the accent as the knob crosses."""
        w, h = 34 * u, 18 * u
        lit = max(0.0, min(1.0, t))
        rounded(cr, x, y, w, h, h / 2)
        rgba(cr, "gutter", 0.9 * a)
        cr.fill_preserve()
        rgba(cr, "accent", 0.85 * a * lit)
        cr.fill()
        kx = x + h / 2 + (w - h) * max(-0.06, min(1.06, t))
        cr.new_path()
        cr.arc(kx, y + h / 2, 6.5 * u, 0, math.tau)
        rgba(cr, "muted", a)
        cr.fill_preserve()
        rgba(cr, "fg", a * lit)
        cr.fill()
