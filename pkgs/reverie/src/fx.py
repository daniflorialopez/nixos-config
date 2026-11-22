"""fx: light that follows attention.

ripples    A window opening sends a ring outward from where it appeared; a
           window closing draws one inward to where it was. Half a second,
           then nothing. It answers "where did that just happen" for free.
           Drawn here, on a click-through overlay per monitor that is only
           mapped while a ring is on screen.

spotlight  The desktop dims and the focused window sits in a pool of light.
           That is spot.py, a program of its own, because it is the one
           effect that needs the graphics card (its header says why and what
           was measured). This module starts it when the spotlight is
           switched on, passes on what only the daemon knows — the menu deck
           wants to stay lit — and lets it go when it is switched off: it
           opens the light back out and exits by itself.

Coordinates are global (Hyprland's layout space) everywhere; each view
subtracts its own monitor's origin when it draws.
"""

import math
import os
import select
import subprocess
import sys
import time

import cairo

from common import hypr, layer_window, rgba

from gi.repository import Gdk, GLib, Gtk, Gtk4LayerShell  # noqa: E402  (common pins versions)

RIPPLE_S = 0.6
SPOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "spot.py")


class View:
    """One monitor's overlay, for the rings."""

    def __init__(self, fx, monitor):
        self.connector = monitor.get_connector()
        self.origin = (0, 0)
        self.fx = fx
        self.win = layer_window(fx.app, "reverie-fx")
        Gtk4LayerShell.set_monitor(self.win, monitor)
        self.area = Gtk.DrawingArea()
        self.area.set_draw_func(lambda _a, cr, w, h: fx.draw(self, cr, w, h))
        self.win.set_child(self.area)
        self.win.connect("map", self.on_map)
        self.tick_id = 0
        self.skipped = False

    def run(self):
        if not self.tick_id:
            self.tick_id = self.area.add_tick_callback(self.tick)

    def tick(self, _area, _clock):
        fx = self.fx
        now = time.monotonic()
        fx.ripples = [r for r in fx.ripples if now - r[3] < RIPPLE_S]
        # Every other frame (83 a second on this panel): a frame of this
        # canvas is a whole-monitor buffer, painted in software.
        self.skipped = not self.skipped
        if not self.skipped or not fx.ripples:
            self.area.queue_draw()
        if fx.ripples:
            return True
        self.tick_id = 0
        self.win.set_visible(False)      # nothing to show: do not sit above the windows
        return False

    @staticmethod
    def on_map(win):
        # An empty input region: every click falls through to the desktop.
        surface = win.get_surface()
        if surface is not None:
            surface.set_input_region(cairo.Region())


class Fx:
    def __init__(self, app, pulse):
        self.app = app
        self.pulse = pulse
        self.views = {}              # connector -> View
        self.spot = False
        self.proc = None             # spot.py, while the spotlight is on
        self.leaving = []            # ... and the ones that were told to go, until they have
        self.lit = None              # (x, y, w, h, radius), global: also kept bright
        self.ripples_on = False
        self.ripples = []            # (cx, cy, radius, t0, opening), global

    # -- views ------------------------------------------------------------
    def sync_views(self):
        """One overlay per connected monitor; follow hot-plugging."""
        layout = {m["name"]: (m["x"], m["y"]) for m in hypr("j/monitors") or []}
        monitors = Gdk.Display.get_default().get_monitors()
        present = set()
        for i in range(monitors.get_n_items()):
            mon = monitors.get_item(i)
            name = mon.get_connector()
            present.add(name)
            if name not in self.views:
                self.views[name] = View(self, mon)
            self.views[name].origin = layout.get(name, (0, 0))
        for name in list(self.views):
            if name not in present:
                self.views.pop(name).win.destroy()

    # -- ripples ----------------------------------------------------------
    def on_event(self, event, data):
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
        if not self.ripples:
            self.sync_views()
        self.ripples.append((at[0] + size[0] / 2, at[1] + size[1] / 2,
                             math.hypot(size[0], size[1]) / 2, time.monotonic(), opening))
        for view in self.views.values():
            view.win.set_visible(True)
            view.run()

    def draw(self, view, cr, w, h):
        ox, oy = view.origin
        now = time.monotonic()
        for gx, gy, radius, t0, opening in self.ripples:
            cx, cy = gx - ox, gy - oy
            if not (-radius < cx < w + radius and -radius < cy < h + radius):
                continue
            t = min(1.0, (now - t0) / RIPPLE_S)
            ease = 1 - (1 - t) ** 3
            r = radius * (0.25 + 0.85 * ease) if opening else radius * (1.1 - 0.85 * ease)
            cr.new_path()
            cr.set_line_width(1.5 + 4 * (1 - t))
            rgba(cr, "accent" if opening else "hint", 0.50 * (1 - t) ** 1.5)
            cr.arc(cx, cy, max(1.0, r), 0, math.tau)
            cr.stroke()

    # -- spotlight: another program ---------------------------------------
    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def say(self, line):
        try:
            self.proc.stdin.write((line + "\n").encode())
            self.proc.stdin.flush()
            return True
        except (AttributeError, OSError, ValueError):
            return False

    def say_lit(self):
        self.say("lit none" if self.lit is None else
                 "lit " + " ".join(f"{v:.1f}" for v in self.lit))

    def spotlight(self, want):
        self.spot = want
        if self.proc is not None:
            # Off: it opens the light back out, then exits. On again: a new
            # one, always — whether the old one would still hear "on" before
            # it leaves is a race, and two overlays crossing is not a fault.
            self.say("off")
            self.leaving.append(self.proc)
            self.proc = None
            GLib.timeout_add(1500, self.reap)
        if not want:
            return
        # The renderer is the point of the separate program: GTK's GL one,
        # where the daemon itself runs the software one.
        env = dict(os.environ, GSK_RENDERER="gl")
        try:
            self.proc = subprocess.Popen([sys.executable, SPOT], stdin=subprocess.PIPE,
                                         stdout=subprocess.PIPE, env=env)
        except OSError as exc:
            print(f"fx: spotlight: {exc!r}", flush=True)
            self.proc, self.spot = None, False
            return
        if self.lit is not None:
            self.say_lit()

    def reap(self):
        """Collect the ones that have left (a timeout callback)."""
        self.leaving = [p for p in self.leaving if p.poll() is None]
        return bool(self.leaving)        # still fading: look again

    def set_lit(self, rect):
        """A second pool: something that is not the focused window but must
        not be dimmed (the menu deck). None removes it."""
        self.lit = rect
        if self.alive():
            self.say_lit()

    def where(self):
        """For tests: where the pool is aimed and what is on screen."""
        if not (self.alive() and self.say("where")):
            return "spotlight is not running"
        ready, _, _ = select.select([self.proc.stdout], [], [], 1.0)
        return self.proc.stdout.readline().decode().strip() if ready else "no answer"

    def close(self):
        """The daemon is leaving: so does the spotlight, at once."""
        for proc in self.leaving + [self.proc]:
            if proc is not None:
                try:
                    proc.stdin.close()
                except OSError:
                    pass

    # -- commands ---------------------------------------------------------
    def command(self, what, words):
        state = bool(words) and words[0] == "on"
        if what == "spotlight":
            if self.spot and not self.alive():
                self.spot = False        # it died: say so rather than claim a light
            if words and words[0] == "where":
                return self.where()
            if words and words[0] == "toggle":
                state = not self.spot
            if words and state != self.spot:
                self.spotlight(state)
            return f"spotlight {'on' if self.spot else 'off'}"
        if words:
            self.ripples_on = (not self.ripples_on) if words[0] == "toggle" else state
        return f"ripples {'on' if self.ripples_on else 'off'}"
