"""The heads-up display: nothing on screen until you hold a key.

The bar is a 1995 taskbar: always on, full of numbers nobody is reading. This
is the opposite trade. While the key is held the whole monitor becomes an
instrument panel — clock, a day arc, gauges, and a live map of every workspace
with its windows drawn to scale — and on release it is gone.

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
from gi.repository import GLib, Gtk, Gtk4LayerShell

from common import (EFFECT, SPATIAL, Spring, focused_gdk_monitor, hypr, layer_window, rgba,
                    rounded, text)

UI = "Inter Variable"
TAU = math.tau


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
            link = os.path.basename(os.path.realpath("/nix/var/nix/profiles/system"))
            cur = os.readlink("/nix/var/nix/profiles/system") if os.path.islink(
                "/nix/var/nix/profiles/system") else link
            self.info["gen"] = cur.replace("system-", "").replace("-link", "")
            if shutil.which("nmcli"):
                out = self._run("nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active")
                names = [l.split(":")[0] for l in out.splitlines()
                         if l and not l.endswith(("loopback", "tun", "bridge"))]
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
        self.win.connect("map", self._passthrough)
        self.stats = Stats()
        self.alpha = Spring(0.0, EFFECT)
        self.rise = Spring(0.0, SPATIAL)     # 0 -> 1 entrance travel
        self.gauge = {k: Spring(0.0, SPATIAL) for k, _ in GAUGES}
        self.shown = False
        self.last = None
        self.tick_id = 0
        self.timer_id = 0
        self.snapshot = {"monitors": [], "clients": [], "active": None}
        self.pulse = None                    # set by main: gives focus ages
        self.hold_id = 0

    @staticmethod
    def _passthrough(win):
        surface = win.get_surface()
        if surface is not None:
            surface.set_input_region(cairo.Region())

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
            return
        self.shown = True
        mon = focused_gdk_monitor()
        if mon is not None:
            Gtk4LayerShell.set_monitor(self.win, mon)
        self.refresh()
        self.alpha.target = 1.0
        self.rise.target = 1.0
        self.win.set_visible(True)
        if not self.tick_id:
            self.last = None
            self.tick_id = self.area.add_tick_callback(self.tick)
        if not self.timer_id:
            self.timer_id = GLib.timeout_add(700, self.on_timer)

    def _expire(self):
        self.hold_id = 0
        self.hide()
        return False

    def hide(self):
        if not self.shown:
            return
        self.shown = False
        self.alpha.target = 0.0
        self.rise.target = 0.0
        for s in self.gauge.values():
            s.target = 0.0

    def toggle(self):
        self.hide() if self.shown else self.show(sticky=True)

    def on_timer(self):
        if not self.shown:
            self.timer_id = 0
            return False
        self.refresh()
        return True

    def refresh(self):
        self.stats.sample()
        for key, _ in GAUGES:
            v = self.stats.values[key]
            if v is None:
                v = 0.0
            elif key == "temp":
                v = min(1.0, max(0.0, (v - 30) / 70))   # 30..100 °C
            self.gauge[key].target = v
        try:
            self.snapshot = {
                "monitors": hypr("j/monitors") or [],
                "clients": hypr("j/clients") or [],
                "active": (hypr("j/activewindow") or {}).get("address"),
            }
        except OSError:
            pass

    def tick(self, _widget, clock):
        now = clock.get_frame_time() / 1e6
        dt = 0.016 if self.last is None else min(0.05, now - self.last)
        self.last = now
        self.alpha.step(dt)
        self.rise.step(dt)
        for s in self.gauge.values():
            s.step(dt)
        self.area.queue_draw()
        if not self.shown and self.alpha.x < 0.01:
            self.win.set_visible(False)
            self.tick_id = 0
            return False
        return True

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
        self.draw_gauges(cr, w / 2, 610 * u + lift * 1.6, u, a)
        self.draw_map(cr, w, h, u, a, lift * 2.4)
        self.draw_corners(cr, w, h, u, a)

    def draw_clock(self, cr, cx, cy, u, a):
        now = time.localtime()
        frac = (now.tm_hour * 3600 + now.tm_min * 60 + now.tm_sec) / 86400

        # The day as an arc: midnight at both feet, noon at the crown. The sun
        # is the one warm thing on the panel.
        r = 330 * u
        cr.set_line_width(2 * u)
        rgba(cr, "gutter", 0.9 * a)
        cr.new_path()
        cr.arc(cx, cy + 120 * u, r, math.pi, TAU)
        cr.stroke()
        rgba(cr, "slate", a)
        cr.new_path()
        cr.arc(cx, cy + 120 * u, r, math.pi, math.pi + math.pi * frac)
        cr.stroke()
        for hour in range(0, 25, 3):
            ang = math.pi + math.pi * hour / 24
            x0, y0 = cx + math.cos(ang) * (r + 8 * u), cy + 120 * u + math.sin(ang) * (r + 8 * u)
            x1, y1 = cx + math.cos(ang) * (r + 18 * u), cy + 120 * u + math.sin(ang) * (r + 18 * u)
            rgba(cr, "hint", 0.8 * a)
            cr.set_line_width(1.5 * u)
            cr.move_to(x0, y0)
            cr.line_to(x1, y1)
            cr.stroke()
        ang = math.pi + math.pi * frac
        sx, sy = cx + math.cos(ang) * r, cy + 120 * u + math.sin(ang) * r
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

    def draw_gauges(self, cr, cx, cy, u, a):
        present = [(k, label) for k, label in GAUGES if self.stats.values[k] is not None]
        gap = 190 * u
        x = cx - gap * (len(present) - 1) / 2
        r = 58 * u
        for key, label in present:
            raw = self.stats.values[key]
            v = max(0.0, min(1.08, self.gauge[key].x))
            # Loudness rule: a gauge is quiet blue until it actually needs you.
            hot = (key in ("cpu", "mem", "vram", "gpu") and raw > 0.9) or \
                  (key == "temp" and raw > 88) or \
                  (key == "bat" and raw < 0.15 and not self.stats.charging)
            cr.set_line_cap(1)  # round
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
            if key == "temp":
                val = f"{raw:.0f}°"
            else:
                val = f"{raw * 100:.0f}"
            text(cr, val, x, cy - 21 * u, 34 * u, "fg", a, family=UI, weight=300, align="center")
            text(cr, label, x, cy + r + 16 * u, 14 * u, "muted", a, family=UI, weight=600,
                 align="center", spacing=3 * u)
            x += gap

    def draw_map(self, cr, w, h, u, a, lift):
        """Every workspace that has windows, with those windows to scale."""
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
            rounded(cr, x, y, card_w, card_h, 14 * u)
            rgba(cr, "surface", (0.55 if live else 0.30) * a)
            cr.fill_preserve()
            cr.set_line_width(1.5 * u)
            rgba(cr, "hint" if live else "gutter", a)
            cr.stroke()
            s = card_w / mw
            for c in clients:
                cx0 = x + (c["at"][0] - mon["x"]) * s
                cy0 = y + (c["at"][1] - mon["y"]) * s
                cw, ch = c["size"][0] * s, c["size"][1] * s
                focused = c["address"] == self.snapshot["active"]
                rounded(cr, cx0 + 1, cy0 + 1, cw - 2, ch - 2, 5 * u)
                if focused:
                    rgba(cr, "accent", 0.30 * a)
                else:
                    # Attention heat: a window you were in a moment ago is
                    # lighter than one you have not touched for ten minutes.
                    age = 600.0
                    if self.pulse is not None and c["address"] in self.pulse.seen:
                        age = time.monotonic() - self.pulse.seen[c["address"]]
                    warmth = max(0.0, 1.0 - age / 600.0)
                    rgba(cr, "overlay", (0.45 + 0.50 * warmth) * a)
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
