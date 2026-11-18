"""The heads-up display: nothing on screen until you hold a key.

The bar is a 1995 taskbar: always on, full of numbers nobody is reading. This
is the opposite trade. While the key is held the whole monitor becomes an
instrument panel — clock, a day arc that carries today's focus history,
gauges, and a live map of every workspace with its windows drawn to scale —
and on release it is gone.

Glass. Just before the panel maps, the output is captured once (in memory,
never on disk) and that picture becomes the panel's own backdrop. Each gauge
is then a lens: it paints the desktop that is really behind it, magnified, and
bent harder toward its rim, with a rim light on top. It is clear glass with
edge refraction — the material the compositor cannot give a layer surface —
done in cairo, and it costs one screenshot per show.

Pinned ($mod SHIFT+`), the same panel is a switcher: the map takes clicks and
number keys.

Everything moves on springs (common.Spring), so letting go halfway through the
entrance turns the motion around instead of snapping.
"""

import glob
import math
import os
import shutil
import subprocess
import threading
import time

import cairo

from common import (EFFECT, PAL, SPATIAL, Spring, focused_gdk_monitor, hypr, layer_window,
                    measure, rgba, rounded, text)
from ledger import human

from gi.repository import Gdk, GLib, Gtk, Gtk4LayerShell  # noqa: E402  (common pins versions)

UI = "Inter Variable"
TAU = math.tau
STAGGER = 0.045              # seconds between one gauge starting and the next
RANKS = ("accent", "fg", "hint", "slate")     # focus-history colours, most-used first


def _read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


class Stats:
    """Cheap system readings. Nothing here may block the frame clock."""

    def __init__(self):
        self._cpu_prev = self._cpu_times()
        self.values = {"cpu": 0.0, "mem": 0.0, "gpu": None, "vram": None,
                       "bat": None, "temp": None}
        self.info = {"playing": "", "gen": "", "net": ""}
        self.charging = False
        self._busy = False

    @staticmethod
    def _cpu_times():
        parts = _read("/proc/stat").splitlines()[0].split()[1:]
        nums = [int(p) for p in parts]
        return sum(nums), nums[3] + nums[4]

    def sample(self):
        total, idle = self._cpu_times()
        pt, pi = self._cpu_prev
        if total > pt:
            self.values["cpu"] = 1.0 - (idle - pi) / (total - pt)
        self._cpu_prev = (total, idle)

        mem = {}
        for line in _read("/proc/meminfo").splitlines():
            k, _, v = line.partition(":")
            mem[k] = int(v.split()[0])
        if mem.get("MemTotal"):
            self.values["mem"] = 1.0 - mem.get("MemAvailable", 0) / mem["MemTotal"]

        bats = glob.glob("/sys/class/power_supply/BAT*")
        if bats:
            cap = _read(bats[0] + "/capacity")
            self.values["bat"] = int(cap) / 100 if cap.isdigit() else None
            self.charging = _read(bats[0] + "/status") in ("Charging", "Full", "Not charging")

        temps = []
        for zone in glob.glob("/sys/class/hwmon/hwmon*"):
            if _read(zone + "/name") in ("coretemp", "k10temp", "zenpower"):
                for f in glob.glob(zone + "/temp*_input"):
                    v = _read(f)
                    if v.isdigit():
                        temps.append(int(v) / 1000)
        self.values["temp"] = max(temps) if temps else None

        if not self._busy:
            self._busy = True
            threading.Thread(target=self._slow, daemon=True).start()

    def _run(self, *cmd):
        try:
            return subprocess.run(cmd, capture_output=True, text=True, timeout=2).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            return ""

    def _slow(self):
        """Things that fork. Off the main thread; results land when they land."""
        try:
            if shutil.which("nvidia-smi"):
                out = self._run("nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total",
                                "--format=csv,noheader,nounits")
                try:
                    util, used, tot = (float(p) for p in out.splitlines()[0].split(","))
                    self.values["gpu"] = util / 100
                    self.values["vram"] = used / tot
                except (ValueError, IndexError):
                    pass
            if shutil.which("playerctl"):
                self.info["playing"] = self._run(
                    "playerctl", "metadata", "--format", "{{artist}} — {{title}}").strip(" —")
            try:
                link = os.readlink("/nix/var/nix/profiles/system")
                self.info["gen"] = link.replace("system-", "").replace("-link", "")
            except OSError:
                pass
            if shutil.which("nmcli"):
                out = self._run("nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active")
                names = [ln.split(":")[0] for ln in out.splitlines()
                         if ln and not ln.endswith(("loopback", "tun", "bridge"))]
                self.info["net"] = names[0] if names else "offline"
        finally:
            self._busy = False


GAUGES = [("cpu", "CPU"), ("mem", "MEM"), ("gpu", "GPU"), ("vram", "VRAM"),
          ("temp", "TEMP"), ("bat", "BAT")]


class Hud:
    def __init__(self, app):
        self.win = layer_window(app, "reverie-hud")
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

        self.stats = Stats()
        self.alpha = Spring(0.0, EFFECT)
        self.rise = Spring(0.0, SPATIAL)     # 0 -> 1 entrance travel
        self.gauge = {k: Spring(0.0, SPATIAL) for k, _ in GAUGES}
        self.goal = {k: 0.0 for k, _ in GAUGES}
        self.shown = False
        self.entered = False                 # the entrance animation has finished
        self.sticky = False
        self.glass = True
        self.backdrop = None
        self.token = 0
        self.shown_at = 0.0
        self.asked_at = 0.0
        self.drawn_at = 0.0
        self.last = None
        self.tick_id = 0
        self.timer_id = 0
        self.hold_id = 0
        self.hits = []                       # (x, y, w, h, kind, value), back to front
        self.snapshot = {"monitors": [], "clients": [], "active": None}
        self.pulse = None                    # set by main: focus ages
        self.ledger = None                   # set by main: today's focus blocks
        GLib.idle_add(self._warm)

    def _warm(self):
        """Pay the one-time costs at start-up instead of on the first keypress.

        The first map of a GTK window sets up the renderer (~120 ms measured)
        and the first use of a font loads it. So: draw once into a throwaway
        surface, and map the real one for a moment while it is still fully
        transparent and click-through. Nothing is visible; the first hold is
        then as quick as every later one.
        """
        scratch = cairo.ImageSurface(cairo.FORMAT_ARGB32, 320, 180)
        self.refresh()
        self.draw(None, cairo.Context(scratch), 320, 180)
        if not self.shown:
            self.win.set_visible(True)
            GLib.timeout_add(250, self._warm_done)
        return False

    def _warm_done(self):
        if not self.shown and self.alpha.x < 0.01:
            self.win.set_visible(False)
        return False

    # -- show / hide ------------------------------------------------------
    def show(self, sticky=False):
        if self.hold_id:
            GLib.source_remove(self.hold_id)
            self.hold_id = 0
        if not sticky:
            # Hold-to-show relies on the key RELEASE reaching Hyprland with the
            # modifier still down. Let go of the modifier first and that bind
            # never fires, so a held panel also lets itself out.
            self.hold_id = GLib.timeout_add_seconds(10, self._expire)
        if self.shown:
            if sticky != self.sticky:
                self.sticky = sticky
                self._apply_input()
                self.area.queue_draw()
            return
        self.shown = True
        self.sticky = sticky
        self.token += 1
        self.asked_at = time.monotonic()
        fading = self.win.get_visible()      # still on its way out: backdrop is still right
        mon = None
        if not fading:
            mon = focused_gdk_monitor()
            if mon is not None:
                Gtk4LayerShell.set_monitor(self.win, mon)
        if self.glass and mon is not None and shutil.which("grim"):
            self._capture(mon.get_connector(), self.token)
        else:
            self._present(self.token, self.backdrop if fading else None)

    def _capture(self, output, token):
        """One frame of the output over a pipe, decoded off the main loop.

        PPM rather than PNG: grim writes it in ~60 ms at 1440p and the pixels
        need no decoding, only repacking from RGB to cairo's BGRX — three
        extended-slice assignments, which run at C speed (~8 ms measured).
        PNG, even at compression level 0, cost about twice as much end to end.
        """
        def work():
            surf = None
            try:
                raw = subprocess.run(["grim", "-t", "ppm", "-o", output, "-"],
                                     capture_output=True, timeout=3).stdout
                magic, size, depth, rgb = raw.split(b"\n", 3)
                w, h = (int(n) for n in size.split())
                n = w * h * 3
                if magic == b"P6" and depth == b"255" and len(rgb) >= n:
                    buf = bytearray(w * h * 4)
                    buf[0::4] = rgb[2:n:3]
                    buf[1::4] = rgb[1:n:3]
                    buf[2::4] = rgb[0:n:3]
                    surf = cairo.ImageSurface.create_for_data(
                        buf, cairo.FORMAT_RGB24, w, h, w * 4)
            except (OSError, ValueError, subprocess.SubprocessError, cairo.Error, MemoryError):
                surf = None
            GLib.idle_add(self._present, token, surf)
        threading.Thread(target=work, daemon=True).start()

    def _present(self, token, backdrop):
        if token != self.token or not self.shown:
            return False                     # let go before the capture came back
        self.backdrop = backdrop
        self.entered = False
        self.refresh()
        self.shown_at = time.monotonic()
        self.alpha.target = 1.0
        self.rise.target = 1.0
        Gtk4LayerShell.set_keyboard_mode(
            self.win, Gtk4LayerShell.KeyboardMode.EXCLUSIVE if self.sticky
            else Gtk4LayerShell.KeyboardMode.NONE)
        self.win.set_visible(True)
        self._apply_input()
        self._ensure_tick()
        if os.environ.get("REVERIE_DEBUG"):
            print(f"hud: {(time.monotonic() - self.asked_at) * 1000:.0f} ms from command to map"
                  f" (glass {'on' if backdrop is not None else 'off'})", flush=True)
        if not self.timer_id:
            self.timer_id = GLib.timeout_add(2000, self.on_timer)
        return False

    def _apply_input(self):
        """Held: every click falls through. Pinned: the panel takes them."""
        surface = self.win.get_surface()
        if surface is None:
            return
        if self.sticky:
            w, h = self.area.get_width(), self.area.get_height()
            surface.set_input_region(cairo.Region(cairo.RectangleInt(0, 0, max(w, 1), max(h, 1))))
        else:
            surface.set_input_region(cairo.Region())

    def _expire(self):
        self.hold_id = 0
        self.hide()
        return False

    def hide(self):
        if self.hold_id:
            GLib.source_remove(self.hold_id)
            self.hold_id = 0
        if not self.shown:
            return
        self.shown = False
        self.alpha.target = 0.0
        self.rise.target = 0.0
        self._ensure_tick()

    def toggle(self):
        self.hide() if self.shown else self.show(sticky=True)

    def command(self, words):
        what = words[0] if words else "toggle"
        if what == "show":
            self.show()
        elif what == "hide":
            self.hide()
        elif what in ("toggle", "pin"):
            self.toggle()
        elif what == "glass":
            if len(words) > 1:
                self.glass = (not self.glass) if words[1] == "toggle" else words[1] == "on"
            return f"glass {'on' if self.glass else 'off'}"
        else:
            return f"unknown: hud {what}"
        return "ok"

    # -- input (pinned only) ----------------------------------------------
    def on_key(self, _ctl, keyval, _code, _state):
        if Gdk.KEY_0 <= keyval <= Gdk.KEY_9:
            n = keyval - Gdk.KEY_0
            hypr(f"dispatch workspace {10 if n == 0 else n}")
        self.hide()
        return True

    def on_click(self, _gesture, _n, x, y):
        for hx, hy, hw, hh, kind, value in reversed(self.hits):
            if hx <= x <= hx + hw and hy <= y <= hy + hh:
                if kind == "window":
                    hypr(f"dispatch focuswindow address:{value}")
                else:
                    hypr(f"dispatch workspace {value}")
                break
        self.hide()

    # -- data -------------------------------------------------------------
    def on_timer(self):
        if not self.shown:
            self.timer_id = 0
            return False
        self.refresh()
        self._ensure_tick()                  # the clock, and any gauge that moved
        return True

    def refresh(self):
        self.stats.sample()
        for key, _ in GAUGES:
            v = self.stats.values[key]
            if v is None:
                v = 0.0
            elif key == "temp":
                v = min(1.0, max(0.0, (v - 30) / 70))   # 30..100 °C
            # A dead band: CPU load jitters by a percent every sample, and
            # re-animating six gauges for that would redraw the whole panel
            # continuously for nothing anyone can see.
            if abs(v - self.goal[key]) >= 0.02 or v in (0.0, 1.0):
                self.goal[key] = v
        try:
            self.snapshot = {
                "monitors": hypr("j/monitors") or [],
                "clients": hypr("j/clients") or [],
                "active": (hypr("j/activewindow") or {}).get("address"),
            }
        except OSError:
            pass

    # -- animation --------------------------------------------------------
    def _ensure_tick(self):
        if not self.tick_id:
            self.last = None
            self.tick_id = self.area.add_tick_callback(self.tick)

    def tick(self, _widget, clock):
        now = clock.get_frame_time() / 1e6
        dt = 0.016 if self.last is None else min(0.05, now - self.last)
        self.last = now
        self.alpha.step(dt)
        self.rise.step(dt)
        since = time.monotonic() - self.shown_at
        waiting = False
        for i, (key, _) in enumerate(GAUGES):
            spring = self.gauge[key]
            if not self.shown:
                spring.target = 0.0
            elif since < i * STAGGER:
                waiting = True               # the gauges come up one after another
            elif self.entered:
                # After the entrance a gauge is an instrument, not an
                # animation: a new reading is one frame, not half a second of
                # full-screen redraws. (Measured: a pinned panel went from a
                # third of a core to about nothing.)
                spring.x = spring.target = self.goal[key]
                spring.v = 0.0
            else:
                spring.target = self.goal[key]
            spring.step(dt)
        # The panel may refresh at 165 Hz, and every frame here is a
        # full-screen software draw. Sixty is plenty for a spring.
        if now - self.drawn_at >= 1 / 61:
            self.drawn_at = now
            self.area.queue_draw()
        if not self.shown and self.alpha.x < 0.01:
            self.win.set_visible(False)
            self.backdrop = None             # ~14 MB; do not keep it while hidden
            self.tick_id = 0
            return False
        settled = self.alpha.resting and self.rise.resting and \
            all(s.resting for s in self.gauge.values())
        if self.shown and settled and not waiting:
            self.entered = True
            self.area.queue_draw()           # the resting frame, whatever the cap skipped
            self.tick_id = 0                 # nothing is moving: stop drawing frames
            return False
        return True

    # -- glass ------------------------------------------------------------
    def _paint_backdrop(self, cr, cx, cy, zoom, width, alpha):
        """Paint the captured desktop magnified by `zoom` about (cx, cy)."""
        s = width / self.backdrop.get_width()
        cr.save()
        cr.translate(cx, cy)
        cr.scale(zoom * s, zoom * s)
        cr.translate(-cx / s, -cy / s)
        cr.set_source_surface(self.backdrop, 0, 0)
        cr.get_source().set_filter(cairo.FILTER_BILINEAR)
        cr.paint_with_alpha(alpha)
        cr.restore()

    def _rim(self, cr, x0, y0, x1, y1, a):
        """Light catching the top-left edge, a fainter return at bottom-right."""
        fg = PAL["fg"]
        rim = cairo.LinearGradient(x0, y0, x1, y1)
        rim.add_color_stop_rgba(0.0, *fg, 0.60 * a)
        rim.add_color_stop_rgba(0.45, *fg, 0.07 * a)
        rim.add_color_stop_rgba(1.0, *fg, 0.26 * a)
        cr.set_source(rim)

    def lens(self, cr, cx, cy, radius, width, u, a):
        """A disc of clear glass: more magnification, and more bend, at the rim."""
        if self.backdrop is not None:
            for frac, zoom in ((1.0, 1.60), (0.96, 1.36), (0.90, 1.22), (0.80, 1.13)):
                cr.save()
                cr.new_path()
                cr.arc(cx, cy, radius * frac, 0, TAU)
                cr.clip()
                self._paint_backdrop(cr, cx, cy, zoom, width, a)
                cr.restore()
        # Smoked toward the centre, clear toward the rim: the number stays
        # readable over whatever is behind it, and the bend is left visible
        # where it is strongest.
        r, g, b = PAL["bgDeep"]
        smoke = cairo.RadialGradient(cx, cy, 0, cx, cy, radius)
        if self.backdrop is not None:
            smoke.add_color_stop_rgba(0.0, r, g, b, 0.82 * a)
            smoke.add_color_stop_rgba(0.60, r, g, b, 0.70 * a)
            smoke.add_color_stop_rgba(1.0, r, g, b, 0.30 * a)
        else:
            smoke.add_color_stop_rgba(0.0, r, g, b, 0.30 * a)
            smoke.add_color_stop_rgba(1.0, r, g, b, 0.30 * a)
        cr.new_path()
        cr.arc(cx, cy, radius, 0, TAU)
        cr.set_source(smoke)
        cr.fill()
        cr.new_path()
        cr.arc(cx, cy, radius - 0.75 * u, 0, TAU)
        cr.set_line_width(1.5 * u)
        self._rim(cr, cx - radius, cy - radius, cx + radius, cy + radius, a)
        cr.stroke()

    def pane(self, cr, x, y, w, h, r, width, u, a, live):
        """A glass card: the same idea as `lens`, for a rounded rectangle."""
        cx, cy = x + w / 2, y + h / 2
        if self.backdrop is not None:
            inset = 7 * u
            for grow, zoom in ((0.0, 1.30), (inset, 1.07)):
                cr.save()
                rounded(cr, x + grow, y + grow, w - 2 * grow, h - 2 * grow, max(1.0, r - grow))
                cr.clip()
                self._paint_backdrop(cr, cx, cy, zoom, width, a)
                cr.restore()
        rounded(cr, x, y, w, h, r)
        rgba(cr, "bgDeep", (0.52 if live else 0.66) * a)
        cr.fill()
        rounded(cr, x + 0.75 * u, y + 0.75 * u, w - 1.5 * u, h - 1.5 * u, r)
        cr.set_line_width(1.5 * u)
        self._rim(cr, x, y, x + w, y + h, a * (1.0 if live else 0.55))
        cr.stroke()

    # -- drawing ----------------------------------------------------------
    def draw(self, _area, cr, w, h):
        a = max(0.0, min(1.0, self.alpha.x))
        rise = self.rise.x
        u = h / 1440.0                      # design unit: px at 1440p

        # Scrim: the desktop stays recognisable underneath.
        rgba(cr, "bgDeep", 0.66 * a)
        cr.paint()

        lift = (1.0 - rise) * 46 * u       # everything travels up into place
        self.draw_clock(cr, w / 2, 250 * u + lift, u, a)
        self.draw_gauges(cr, w, w / 2, 630 * u + lift * 1.6, u, a)
        self.draw_map(cr, w, h, u, a, lift * 2.4)
        self.draw_corners(cr, w, h, u, a)
        if self.sticky:
            text(cr, "1–9  JUMP      CLICK  A WINDOW      ANY KEY  CLOSE", w / 2, h - 58 * u,
                 13 * u, "hint", a, family=UI, weight=600, align="center", spacing=3 * u)

    def draw_clock(self, cr, cx, cy, u, a):
        now = time.localtime()
        frac = (now.tm_hour * 3600 + now.tm_min * 60 + now.tm_sec) / 86400
        oy = cy + 120 * u                   # centre of the day arc

        # The day as an arc: midnight at both feet, noon at the crown. The sun
        # is the one warm thing on the panel.
        r = 330 * u
        cr.set_line_cap(cairo.LINE_CAP_BUTT)
        cr.set_line_width(2 * u)
        rgba(cr, "gutter", 0.9 * a)
        cr.new_path()
        cr.arc(cx, oy, r, math.pi, TAU)
        cr.stroke()
        rgba(cr, "slate", a)
        cr.new_path()
        cr.arc(cx, oy, r, math.pi, math.pi + math.pi * frac)
        cr.stroke()
        for hour in range(0, 25, 3):
            ang = math.pi + math.pi * hour / 24
            rgba(cr, "hint", 0.8 * a)
            cr.set_line_width(1.5 * u)
            cr.new_path()
            cr.move_to(cx + math.cos(ang) * (r + 8 * u), oy + math.sin(ang) * (r + 8 * u))
            cr.line_to(cx + math.cos(ang) * (r + 18 * u), oy + math.sin(ang) * (r + 18 * u))
            cr.stroke()

        # Today's focus, drawn where it happened: a second band inside the
        # arc, one stroke per block, coloured by how much of the day that
        # application has had.
        totals = self.ledger.totals() if self.ledger is not None else []
        rank = {cls: i for i, (cls, _) in enumerate(totals)}
        if self.ledger is not None:
            midnight = time.mktime(now[:3] + (0, 0, 0) + now[6:])
            cr.set_line_width(6 * u)
            for start, end, cls in self.ledger.snapshot():
                a0 = math.pi + math.pi * max(0.0, (start - midnight) / 86400)
                a1 = math.pi + math.pi * min(1.0, (end - midnight) / 86400)
                if a1 - a0 < 0.0006:         # under ~a quarter pixel: skip
                    continue
                i = rank.get(cls, 99)
                rgba(cr, RANKS[i] if i < len(RANKS) else "gutter", a)
                cr.new_path()
                cr.arc(cx, oy, r - 13 * u, a0, a1)
                cr.stroke()

        ang = math.pi + math.pi * frac
        sx, sy = cx + math.cos(ang) * r, oy + math.sin(ang) * r
        day = 0.25 < frac < 0.83
        for rad, al in ((26, 0.10), (16, 0.22), (8, 1.0)):
            rgba(cr, "attention" if day else "fg", al * a)
            cr.new_path()
            cr.arc(sx, sy, rad * u, 0, TAU)
            cr.fill()

        text(cr, time.strftime("%H:%M", now), cx, cy - 150 * u, 210 * u, "fg", a,
             family=UI, weight=200, align="center", spacing=-4 * u)
        text(cr, time.strftime("%A %-d %B", now).upper(), cx, cy + 96 * u, 22 * u, "muted", a,
             family=UI, weight=500, align="center", spacing=5 * u)

        # Legend for the focus band: the four applications that had the most
        # of today, each with the colour its strokes are drawn in.
        items = [(RANKS[i], f"{cls or 'desktop'}  {human(sec)}")
                 for i, (cls, sec) in enumerate(totals[:len(RANKS)]) if sec >= 60]
        if items:
            size, dot, gap, sep = 15 * u, 5 * u, 10 * u, 34 * u
            widths = [measure(cr, label, size, family=UI, weight=500)[0] for _, label in items]
            total = sum(widths) + len(items) * (2 * dot + gap) + (len(items) - 1) * sep
            x = cx - total / 2
            y = cy + 150 * u
            for (role, label), tw in zip(items, widths):
                rgba(cr, role, a)
                cr.new_path()
                cr.arc(x + dot, y + size * 0.62, dot, 0, TAU)
                cr.fill()
                text(cr, label, x + 2 * dot + gap, y, size, "subtle", a, family=UI, weight=500)
                x += 2 * dot + gap + tw + sep

    def draw_gauges(self, cr, width, cx, cy, u, a):
        present = [(k, label) for k, label in GAUGES if self.stats.values[k] is not None]
        gap = 200 * u
        x = cx - gap * (len(present) - 1) / 2
        r = 56 * u
        for key, label in present:
            raw = self.stats.values[key]
            v = max(0.0, min(1.08, self.gauge[key].x))
            self.lens(cr, x, cy, r + 24 * u, width, u, a)
            # Loudness rule: a gauge is quiet blue until it actually needs you.
            hot = (key in ("cpu", "mem", "vram", "gpu") and raw > 0.9) or \
                  (key == "temp" and raw > 88) or \
                  (key == "bat" and raw < 0.15 and not self.stats.charging)
            cr.set_line_cap(cairo.LINE_CAP_ROUND)
            cr.set_line_width(7 * u)
            rgba(cr, "gutter", 0.9 * a)
            cr.new_path()
            cr.arc(x, cy, r, 0.75 * math.pi, 2.25 * math.pi)
            cr.stroke()
            if v > 0.005:
                rgba(cr, "attention" if hot else "accent", a)
                cr.new_path()
                cr.arc(x, cy, r, 0.75 * math.pi, 0.75 * math.pi + 1.5 * math.pi * min(v, 1.0))
                cr.stroke()
            val = f"{raw:.0f}°" if key == "temp" else f"{raw * 100:.0f}"
            text(cr, val, x, cy - 22 * u, 34 * u, "fg", a, family=UI, weight=400, align="center")
            text(cr, label, x, cy + r + 38 * u, 14 * u, "muted", a, family=UI, weight=600,
                 align="center", spacing=3 * u)
            x += gap

    def draw_map(self, cr, w, h, u, a, lift):
        """Every workspace that has windows, with those windows to scale."""
        self.hits = []
        mons = {m["id"]: m for m in self.snapshot["monitors"]}
        by_ws = {}
        for c in self.snapshot["clients"]:
            ws = c.get("workspace", {})
            if not c.get("mapped", True) or ws.get("id", -1) < 0:
                continue
            by_ws.setdefault(ws["id"], []).append(c)
        active_ws = {m["activeWorkspace"]["id"] for m in mons.values()}
        ids = sorted(set(by_ws) | active_ws)
        if not ids:
            return
        card_w = min(330 * u, (w - 200 * u) / len(ids) - 26 * u)
        gap = 26 * u
        total = len(ids) * card_w + (len(ids) - 1) * gap
        x = (w - total) / 2
        y = h - 400 * u + lift
        for wid in ids:
            clients = by_ws.get(wid, [])
            mon = mons.get(clients[0]["monitor"]) if clients else next(
                (m for m in mons.values() if m["activeWorkspace"]["id"] == wid), None)
            if mon is None:
                continue
            mw, mh = mon["width"] / mon["scale"], mon["height"] / mon["scale"]
            card_h = card_w * mh / mw
            live = wid in active_ws
            self.pane(cr, x, y, card_w, card_h, 14 * u, w, u, a, live)
            self.hits.append((x, y, card_w, card_h, "workspace", wid))
            s = card_w / mw
            for c in clients:
                cx0 = x + (c["at"][0] - mon["x"]) * s
                cy0 = y + (c["at"][1] - mon["y"]) * s
                cw, ch = c["size"][0] * s, c["size"][1] * s
                focused = c["address"] == self.snapshot["active"]
                self.hits.append((cx0, cy0, cw, ch, "window", c["address"]))
                rounded(cr, cx0 + 1, cy0 + 1, cw - 2, ch - 2, 5 * u)
                rgba(cr, "bg", 0.62 * a)     # a floor, so the glass under it
                cr.fill_preserve()           # cannot make the label unreadable
                if focused:
                    rgba(cr, "accent", 0.30 * a)
                else:
                    # Attention heat: a window you were in a moment ago is
                    # lighter than one you have not touched for ten minutes.
                    age = 600.0
                    if self.pulse is not None and c["address"] in self.pulse.seen:
                        age = time.monotonic() - self.pulse.seen[c["address"]]
                    warmth = max(0.0, 1.0 - age / 600.0)
                    rgba(cr, "overlay", (0.30 + 0.50 * warmth) * a)
                cr.fill_preserve()
                cr.set_line_width(1 * u)
                rgba(cr, "accent" if focused else "slate", a)
                cr.stroke()
                if cw > 60 * u and ch > 26 * u:
                    cr.save()
                    cr.rectangle(cx0 + 4, cy0 + 2, cw - 8, ch - 4)
                    cr.clip()
                    # XWayland windows carry a mark: they are the ones paying
                    # the extra latency, and nothing else on screen says so.
                    name = (c.get("class") or "?").lower() + ("  ·x11" if c.get("xwayland") else "")
                    text(cr, name, cx0 + 8 * u, cy0 + 6 * u, 12 * u,
                         "fg" if focused else "subtle", a, family=UI, weight=500)
                    cr.restore()
            text(cr, str(wid), x + card_w / 2, y + card_h + 12 * u, 20 * u,
                 "fg" if live else "muted", a, family=UI, weight=300, align="center")
            x += card_w + gap

    def draw_corners(self, cr, w, h, u, a):
        m = 60 * u
        host = os.uname().nodename
        up = float(_read("/proc/uptime", "0").split()[0])
        upt = f"{int(up // 3600)}h {int(up % 3600 // 60):02d}m"
        text(cr, host.upper(), m, m, 15 * u, "fg", a, family=UI, weight=600, spacing=4 * u)
        gen = self.stats.info["gen"]
        line = f"generation {gen}   ·   up {upt}   ·   {os.uname().release}" if gen else f"up {upt}"
        text(cr, line, m, m + 26 * u, 15 * u, "muted", a, family=UI, weight=400)

        net = self.stats.info["net"]
        if net:
            text(cr, net, w - m, m, 15 * u, "fg", a, family=UI, weight=600, align="right")
        playing = self.stats.info["playing"]
        if playing:
            text(cr, playing[:70], w - m, m + 26 * u, 15 * u, "muted", a, family=UI,
                 weight=400, align="right")
