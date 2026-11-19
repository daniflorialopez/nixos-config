"""The heads-up display: nothing on screen until you hold a key.

The bar is a 1995 taskbar: always on, full of numbers nobody is reading. This
is the opposite trade. While the key is held the whole monitor becomes an
instrument panel — clock, a day arc that carries today's focus history,
gauges, and a live map of every workspace with its windows shown to scale —
and on release it is gone.

The backdrop is the desktop itself, out of focus. As the panel maps, the
output is captured once (in memory, never on disk), blurred hard and
darkened, and that picture is what the panel sits on — the lock screen's
recipe (wm/hyprlock.nix: a screenshot, three blur passes, brightness 0.6), so
the two read as the same material. The compositor's own blur cannot do this
job: it is tuned for the bar's small islands (one pass, size 3) and under a
whole-screen panel it leaves every line of a terminal half-legible, competing
with the panel for the same pixels. The panel does not wait for the picture:
it comes up at once on a plain scrim of the same darkness and the desktop
goes out of focus under it about a twelfth of a second later, which reads as
a focus pull rather than as a delay.

On it, everything is either type and line drawn straight on the backdrop
(clock, arc, gauges) or an island in the bar's own material (the bar's
modules, the workspace cards). Nothing pretends to be glass: the first two
versions drew refracting lenses round the gauges and they read as an effect
from another desktop.

The layout has one hero. Pinned — which is how it is mostly used — this is a
switcher, so the workspaces take the middle of the screen: one card each with
its windows to scale — each one its own picture, taken as the panel opens
(thumbs.py), on a drawn pane until that lands — and named (application, then
title, because two browser windows are told apart by nothing else). The card the switcher is on
is drawn larger and lifted off the panel; left and right move it, enter goes
there, the number row jumps straight to a workspace, a click on a window
focuses that window. Everything else is arranged round that and kept quiet:
the time and the day's focus history above it, the machine's readings in a
corner, what the bar would be showing below.

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

from barinfo import BarInfo
from common import (EFFECT, FONT, ICON_FAMILY, PAL, SPATIAL, Spring, focused_gdk_monitor, hypr,
                    ink, label, layer_window, measure, rgba, rounded, text)
from ledger import human
from thumbs import Thumbs

from gi.repository import Gdk, GLib, Gtk, Gtk4LayerShell  # noqa: E402  (common pins versions)

TAU = math.tau
# The bar's island radius (theme/metrics.nix islandRadius), handed over by the
# wrapper so a chip here and a pill on the bar stay the same shape.
ISLAND_RADIUS = float(os.environ.get("REVERIE_ISLAND_RADIUS", "12"))
STAGGER = 0.045              # seconds between one gauge starting and the next
HERO = 1.24                  # how much larger the selected workspace's card is drawn
CARD = 540                   # the widest an unselected card gets, in design px
STALE = 0.25                 # how far a window's picture darkens when left alone ten minutes
MODIFIERS = ("Super_L", "Super_R", "Shift_L", "Shift_R", "Control_L", "Control_R", "Alt_L",
             "Alt_R", "Meta_L", "Meta_R", "ISO_Level3_Shift", "Caps_Lock", "Num_Lock")
HALVINGS = 5                 # the capture is halved this often before going back up
TINT = 0.56                  # how much bgDeep is laid over the blurred desktop
VEIL = 0.90                  # the scrim that has to do the job alone if there is no capture
RANKS = ("accent", "fg", "hint", "slate")     # focus-history colours, most-used first


def _read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


class Stats:
    """System readings. `sample` runs on the main loop and may only do what
    is free; anything that can block goes in `_slow`, on a thread.

    The battery belongs in the second group and was in the first. The kernel
    caches a battery reading for about a second and then asks the embedded
    controller again, which on this laptop takes ~70 ms — and since the panel
    is shown rarely, every show was that uncached read, taken before the
    window was even mapped. It was most of the HUD's start-up delay."""

    def __init__(self):
        self._cpu_prev = self._cpu_times()
        self.values = {"cpu": 0.0, "mem": 0.0, "gpu": None, "vram": None,
                       "bat": None, "temp": None}
        self.info = {"gen": ""}
        self.charging = False
        self.listener = None             # called on the main loop when _slow has landed
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
        """Things that fork or wait on hardware. Off the main thread; the
        listener is told when they have landed."""
        try:
            bats = glob.glob("/sys/class/power_supply/BAT*")
            if bats:
                cap = _read(bats[0] + "/capacity")
                self.values["bat"] = int(cap) / 100 if cap.isdigit() else None
                self.charging = _read(bats[0] + "/status") in ("Charging", "Full", "Not charging")
            if shutil.which("nvidia-smi"):
                out = self._run("nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total",
                                "--format=csv,noheader,nounits")
                try:
                    util, used, tot = (float(p) for p in out.splitlines()[0].split(","))
                    self.values["gpu"] = util / 100
                    self.values["vram"] = used / tot
                except (ValueError, IndexError):
                    pass
            try:
                link = os.readlink("/nix/var/nix/profiles/system")
                self.info["gen"] = link.replace("system-", "").replace("-link", "")
            except OSError:
                pass
        finally:
            self._busy = False
            if self.listener is not None:
                GLib.idle_add(self.listener)


GAUGES = [("cpu", "cpu"), ("mem", "mem"), ("gpu", "gpu"), ("vram", "vram"),
          ("temp", "temp"), ("bat", "bat")]


def frost(shot, width, height):
    """A capture of the output -> the same picture out of focus and darkened,
    at the size the panel draws at.

    Halved five times and doubled back up. Each halving averages four pixels
    and each doubling interpolates between them, so the chain is a wide, even
    blur — the dual-filter trick compositors use — and nearly all of it
    happens on images too small to cost anything (about 10 ms in all at
    1440p, measured). The tint is baked in here as well, off the main loop,
    so that a frame of the panel is a single blit.
    """
    def resample(src, w, h):
        out = cairo.ImageSurface(cairo.FORMAT_RGB24, max(1, w), max(1, h))
        ctx = cairo.Context(out)
        ctx.scale(out.get_width() / src.get_width(), out.get_height() / src.get_height())
        ctx.set_source_surface(src, 0, 0)
        ctx.get_source().set_filter(cairo.FILTER_BILINEAR)
        ctx.get_source().set_extend(cairo.EXTEND_PAD)     # no dark fringe at the edges
        ctx.paint()
        return out, ctx

    steps = [shot]
    for _ in range(HALVINGS):
        last = steps[-1]
        steps.append(resample(last, last.get_width() // 2, last.get_height() // 2)[0])
    out = steps.pop()
    for bigger in reversed(steps[1:]):
        out = resample(out, bigger.get_width(), bigger.get_height())[0]
    out, ctx = resample(out, width, height)
    ctx.identity_matrix()
    ctx.set_source_rgba(*PAL["bgDeep"], TINT)
    ctx.paint()
    return out


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
        self.stats.listener = self._stats_landed
        self.alpha = Spring(0.0, EFFECT)
        self.rise = Spring(0.0, SPATIAL)     # 0 -> 1 entrance travel
        self.gauge = {k: Spring(0.0, SPATIAL) for k, _ in GAUGES}
        self.goal = {k: 0.0 for k, _ in GAUGES}
        self.shown = False
        self.entered = False                 # the entrance animation has finished
        self.sticky = False
        self.backdrop = None                 # the blurred, darkened desktop
        self.frosted = Spring(0.0, EFFECT)   # 0 -> 1 as that picture fades in
        self.veil = Spring(TINT, EFFECT)     # scrim under it while it is not there
        self.token = 0
        self.shown_at = 0.0
        self.asked_at = 0.0
        self.drawn_at = 0.0
        self.last = None
        self.tick_id = 0
        self.timer_id = 0
        self.hold_id = 0
        self.first_frame = False
        self.beat_at = 0.0                   # when the held chord last made itself heard
        self.beats = False                   # ... and whether this machine repeats it at all
        self.repeated = False                # this hold has been heard from more than once
        self.gave_up_at = 0.0                # when a hold was ended for want of a repeat
        self.repeat = (0.6, 0.04)            # the keyboard's repeat delay and interval, s
        self.cursor = None                   # the workspace the switcher is on
        self.ids = []                        # the workspaces on the map, in order
        self.grow = {}                       # workspace -> Spring: 0 as the rest, 1 selected
        self.hits = []                       # (x, y, w, h, kind, value), back to front
        self.snapshot = {"monitors": [], "clients": [], "active": None}
        self.pulse = None                    # set by main: focus ages
        self.ledger = None                   # set by main: today's focus blocks
        self.bar = BarInfo()                 # everything waybar shows
        self.bar.listeners.append(self._bar_landed)
        self.bar_age = 0
        self.thumbs = Thumbs(self._thumb_landed)     # the windows' own pictures
        self.reveal = {}                     # address -> Spring: its picture fading in
        GLib.idle_add(self._warm)

    def _bar_landed(self):
        if self.shown:
            self._ensure_tick()              # one frame with the new readings

    def _warm(self):
        """Pay the one-time costs at start-up instead of on the first keypress.

        The first map of a GTK window sets up the renderer (~120 ms measured)
        and the first use of a font loads it. So: draw once into a throwaway
        surface, and map the real one for a moment while it is still fully
        transparent and click-through. Nothing is visible; the first hold is
        then as quick as every later one.
        """
        scratch = cairo.ImageSurface(cairo.FORMAT_ARGB32, 320, 180)
        delay = (hypr("j/getoption input:repeat_delay") or {}).get("int")
        rate = (hypr("j/getoption input:repeat_rate") or {}).get("int")
        if delay and rate:
            self.repeat = (delay / 1000, 1 / rate)
        else:
            self.beats = False               # key repeat is off: nothing to listen for
        self.bar.refresh()                   # so the first show already has it
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
            # A held panel must not be able to outstay the hand that holds it.
            # This is the last line of that; `hold` usually knows much sooner.
            self.hold_id = GLib.timeout_add_seconds(10, self._expire)
        if self.shown:
            if sticky != self.sticky:
                self.sticky = sticky
                Gtk4LayerShell.set_keyboard_mode(
                    self.win, Gtk4LayerShell.KeyboardMode.EXCLUSIVE if sticky
                    else Gtk4LayerShell.KeyboardMode.NONE)
                self._apply_input()
                self.area.queue_draw()
            return
        self.shown = True
        self.sticky = sticky
        self.cursor = None                   # start on the workspace you are on
        self.grow = {}
        self.token += 1
        self.asked_at = time.monotonic()
        fading = self.win.get_visible()      # still on its way out
        mon = focused_gdk_monitor()
        self._mark("monitor known")
        if mon is not None and not fading:
            Gtk4LayerShell.set_monitor(self.win, mon)
        if self.backdrop is None:
            # (Shown again while fading out, it keeps the picture it has.)
            self.frosted.x = self.frosted.v = self.frosted.target = 0.0
            self.veil.x = self.veil.target = TINT
            self.veil.v = 0.0
            if mon is not None and shutil.which("grim"):
                geo = mon.get_geometry()
                self._capture(mon.get_connector(), geo.width, geo.height, self.token)
            else:
                self.veil.target = VEIL
        self._present()

    def _capture(self, output, width, height, token):
        """One frame of the output over a pipe, blurred off the main loop.

        PPM at full size, not PNG and not grim's own -s: measured at 1440p,
        full-size PPM is 55 ms, and asking grim to scale it down first is 140
        (its scaler is the slow part). The pixels need no decoding, only
        repacking from RGB to cairo's BGRX — three extended-slice
        assignments, which run at C speed (~12 ms).

        The panel is usually already on screen when the capture is taken, a
        few percent opaque. After five halvings that is not something anyone
        can find in the result.
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
                    shot = cairo.ImageSurface.create_for_data(
                        buf, cairo.FORMAT_RGB24, w, h, w * 4)
                    surf = frost(shot, width, height)
            except (OSError, ValueError, subprocess.SubprocessError, cairo.Error, MemoryError):
                surf = None
            GLib.idle_add(self._frosted, token, surf)
        threading.Thread(target=work, daemon=True).start()

    def _frosted(self, token, backdrop):
        if token != self.token or not self.shown:
            return False                     # let go before the capture came back
        if backdrop is None:
            self.veil.target = VEIL          # no picture: the scrim does it alone
        else:
            self.backdrop = backdrop
            self.frosted.target = 1.0
        self._mark("backdrop ready" if backdrop is not None else "backdrop missing")
        self._ensure_tick()
        return False

    def _mark(self, what):
        if os.environ.get("REVERIE_DEBUG"):
            print(f"hud: {what} at {(time.monotonic() - self.asked_at) * 1000:.0f} ms", flush=True)

    def _present(self):
        self._mark("present")
        self.entered = False
        self.bar.refresh()                   # shows the cached readings meanwhile
        self.bar_age = 0
        self.refresh()
        self._mark("data read")
        self._photograph(everything=True)
        self.shown_at = time.monotonic()
        self.alpha.target = 1.0
        self.rise.target = 1.0
        Gtk4LayerShell.set_keyboard_mode(
            self.win, Gtk4LayerShell.KeyboardMode.EXCLUSIVE if self.sticky
            else Gtk4LayerShell.KeyboardMode.NONE)
        self.win.set_visible(True)
        self._apply_input()
        self._ensure_tick()
        self._mark("mapped")
        self.first_frame = True
        if not self.timer_id:
            self.timer_id = GLib.timeout_add(2000, self.on_timer)

    def _apply_input(self):
        """Held: every click falls through. Pinned: the panel takes them."""
        surface = self.win.get_surface()
        if surface is None:
            return
        if self.sticky and self.shown:
            w, h = self.area.get_width(), self.area.get_height()
            surface.set_input_region(cairo.Region(cairo.RectangleInt(0, 0, max(w, 1), max(h, 1))))
        else:
            surface.set_input_region(cairo.Region())

    def _expire(self):
        self.hold_id = 0
        if self.shown and not self.sticky and self.beats and not self.repeated:
            self.gave_up_at = time.monotonic()
        self.hide()
        return False

    def _expire_in(self, seconds):
        if self.hold_id:
            GLib.source_remove(self.hold_id)
        self.hold_id = GLib.timeout_add(int(seconds * 1000), self._expire)

    def hold(self):
        """One beat of the held chord ($mod SHIFT+G).

        Hold-to-glance ends on the key's release bind — but only if G is the
        first of the three keys to come up. Pressed for real (a virtual
        keyboard through /dev/uinput, every order of letting go): the moment
        any other key of the chord is released, Hyprland shadows the binds
        on the keys still held, and no release bind fires for them at all —
        not one on G with the remaining modifier, not one on the modifier
        keys themselves, not one that ignores modifiers. Two orders out of
        three would leave the panel up.

        So the bind also REPEATS (binde): this is called once for the press
        and then at the keyboard's repeat rate for as long as the chord is
        down, and "the beats stopped" is the other way to know it was let go.
        Measured with the same virtual keyboard: Super up first, panel gone
        203 ms later; held for two seconds, never cut short.

        That a held bind repeats is learned rather than assumed (and then
        remembered across restarts): until two beats have arrived a repeat
        interval apart — no hand does that — the panel keeps a ten-second
        limit. Once they have, a press with no repeat inside the keyboard's
        repeat delay means the key is already up, and after that every missed
        beat does. If that ever ends a panel while the key is in fact still
        down — the release then arrives for a panel that is already gone —
        the lesson is unlearned (see `command`).
        """
        now = time.monotonic()
        gap, self.beat_at = now - self.beat_at, now
        delay, interval = self.repeat
        if self.shown and not self.sticky:
            self.repeated = True
            if gap < interval * 3:
                self.beats = True
            if self.beats:
                self._expire_in(interval * 3 + 0.15)
        else:
            self.repeated = False
            self.gave_up_at = 0.0
            self.show()
            if self.beats:
                self._expire_in(delay + 0.25)

    def hide(self):
        if self.hold_id:
            GLib.source_remove(self.hold_id)
            self.hold_id = 0
        if not self.shown:
            return
        self.shown = False
        self.alpha.target = 0.0
        self.rise.target = 0.0
        # Give the keyboard and the pointer back now, not when the fade ends:
        # the surface stays mapped for another 0.4 s while it fades, and a
        # pinned panel would swallow whatever was typed in that time.
        Gtk4LayerShell.set_keyboard_mode(self.win, Gtk4LayerShell.KeyboardMode.NONE)
        self._apply_input()
        self._ensure_tick()

    def toggle(self):
        self.hide() if self.shown else self.show(sticky=True)

    def command(self, words):
        what = words[0] if words else "toggle"
        if what == "show":
            self.show()
        elif what == "hold":
            self.hold()
        elif what == "release":
            if self.shown and not self.sticky:   # ends a held panel, never a pinned one
                self.hide()
            elif self.gave_up_at and time.monotonic() - self.gave_up_at < 15:
                # The key was still down when the panel stopped waiting for a
                # repeat: binds do not repeat here (any more). Back to the
                # ten-second limit until they are seen to again.
                self.beats = False
            self.gave_up_at = 0.0
        elif what == "hide":
            self.hide()
        elif what in ("toggle", "pin"):
            self.toggle()
        elif what != "status":
            return f"unknown: hud {what}"
        return "hud " + ("hidden" if not self.shown else "pinned" if self.sticky else "held")

    # -- input (pinned only) ----------------------------------------------
    def on_key(self, _ctl, keyval, _code, _state):
        name = Gdk.keyval_name(keyval) or ""
        if name in MODIFIERS:
            # A modifier going down is the start of a chord, not a key: the
            # chord that pins this panel has to be able to unpin it, and it
            # cannot if its own Super has already closed the panel.
            return False
        if name.startswith("KP_"):
            name = name[3:]
        if len(name) == 1 and name.isdigit():
            hypr(f"dispatch workspace {10 if name == '0' else name}")
        elif name in ("Left", "h", "ISO_Left_Tab", "Right", "l", "Tab") and self.ids:
            step = -1 if name in ("Left", "h", "ISO_Left_Tab") else 1
            at = self.ids.index(self.cursor) if self.cursor in self.ids else 0
            self.cursor = self.ids[(at + step) % len(self.ids)]
            self._ensure_tick()              # the cards trade sizes
            return True
        elif name in ("Return", "Enter", "space") and self.cursor is not None:
            hypr(f"dispatch workspace {self.cursor}")
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
        self._photograph(everything=False)
        self.bar_age += 1
        if self.bar_age >= 5:                # pinned: the bar's modules every ~10 s
            self.bar_age = 0
            self.bar.refresh()
        self._ensure_tick()                  # the clock, and any gauge that moved
        return True

    def _stats_landed(self):
        """The slow readings (battery, GPU) are in: a glance is often over
        before the two-second timer would have picked them up."""
        if self.shown:
            self._aim_gauges()
            self._ensure_tick()
        return False

    def refresh(self):
        self.stats.sample()
        self._aim_gauges()
        try:
            self.snapshot = {
                "monitors": hypr("j/monitors") or [],
                "clients": hypr("j/clients") or [],
                "active": (hypr("j/activewindow") or {}).get("address"),
            }
        except OSError:
            pass

    def _photograph(self, everything):
        """Ask for the windows' pictures (see thumbs.py).

        All of them when the panel opens. After that only what can have
        changed: a window on a workspace that is not showing is not drawing
        frames, so its picture is still true; the ones in front of you are
        taken again with each reading of the gauges, and any window that has
        appeared or changed size since gets its first one.
        """
        mons = {m["id"]: m for m in self.snapshot["monitors"]}
        showing = {m["activeWorkspace"]["id"] for m in mons.values()}
        alive, wants = set(), []
        for c in self.snapshot["clients"]:
            ws, mon = c.get("workspace", {}).get("id", -1), mons.get(c.get("monitor"))
            if not c.get("mapped", True) or ws < 0 or mon is None or min(c["size"]) < 1:
                continue
            alive.add(c["address"])
            if everything or ws in showing or self.thumbs.get(c["address"], c["size"]) is None:
                # Kept at the size the selected card shows it, in device
                # pixels: sizes are in layout pixels, 1440 design px are the
                # monitor's height, and the picture is as wide as the buffer.
                scale = CARD * HERO * mon["height"] / mon["scale"] / 1440 / mon["width"]
                wants.append((c["address"], c["size"], min(1.0, scale * mon["scale"])))
        for address in [a for a in self.reveal if a not in alive]:
            del self.reveal[address]
        self.thumbs.refresh(wants, alive)

    def _thumb_landed(self, address):
        if address not in self.reveal:
            self.reveal[address] = Spring(0.0, EFFECT)   # a first picture fades in
        self.reveal[address].target = 1.0
        if self.shown:
            self._ensure_tick()

    def _aim_gauges(self):
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
        self.frosted.step(dt)
        self.veil.step(dt)
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
        for wid, spring in self.grow.items():
            spring.target = 1.0 if wid == self.cursor else 0.0
            spring.step(dt)
        for spring in self.reveal.values():
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
        settled = self.alpha.resting and self.rise.resting and self.frosted.resting and \
            self.veil.resting and all(s.resting for s in self.gauge.values()) and \
            all(s.resting for s in self.grow.values()) and \
            all(s.resting for s in self.reveal.values())
        if self.shown and settled and not waiting:
            self.entered = True
            self.area.queue_draw()           # the resting frame, whatever the cap skipped
            self.tick_id = 0                 # nothing is moving: stop drawing frames
            return False
        return True

    # -- drawing ----------------------------------------------------------
    def draw(self, _area, cr, w, h):
        if self.first_frame:
            self.first_frame = False
            self._mark("first frame drawn")
        a = max(0.0, min(1.0, self.alpha.x))
        rise = self.rise.x
        u = h / 1440.0                      # design unit: px at 1440p

        f = max(0.0, min(1.0, self.frosted.x))
        if f < 0.999:
            # Until the picture is there (and for good if it never comes): a
            # scrim over the live desktop, as dark as the picture will be.
            rgba(cr, "bgDeep", max(0.0, min(1.0, self.veil.x)) * a)
            cr.paint()
        if self.backdrop is not None and f > 0.001:
            # The desktop, out of focus and already darkened (see frost).
            bw, bh = self.backdrop.get_width(), self.backdrop.get_height()
            cr.save()
            if (bw, bh) != (w, h):
                cr.scale(w / bw, h / bh)
            cr.set_source_surface(self.backdrop, 0, 0)
            cr.paint_with_alpha(a * f)
            cr.restore()

        lift = (1.0 - rise) * 46 * u       # everything travels up into place
        self.draw_corners(cr, u, a)                                   # the machine, top left
        self.draw_clock(cr, w / 2, 92 * u + lift * 0.6, u, a)         # the time, top centre
        self.draw_gauges(cr, w - 64 * u, 100 * u + lift * 0.6, u, a)  # its readings, top right
        self.draw_map(cr, w, u, a, lift * 1.6)                        # the hero
        self.draw_bar(cr, w, 1104 * u + lift * 2.2, u, a)             # what the bar would show
        if self.sticky:
            # 1…0 is how the keybinds palette writes the number row: 0 is ten.
            text(cr, label("1…0 workspaces 1-10   ·   ← → enter   ·   click a window   ·   esc"),
                 w / 2, h - 58 * u, 13 * u, "hint", a, weight=FONT["strong"], align="center",
                 spacing=FONT["track"] * u)

    def draw_clock(self, cr, cx, top, u, a):
        """The time under the arc of the day; `top` is the arc's crown."""
        now = time.localtime()
        frac = (now.tm_hour * 3600 + now.tm_min * 60 + now.tm_sec) / 86400
        r = 215 * u
        oy = top + r                        # the arc's centre: where its feet stand

        # The day as an arc: midnight at both feet, noon at the crown. The sun
        # is the one warm thing on the panel.
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
            cr.move_to(cx + math.cos(ang) * (r + 6 * u), oy + math.sin(ang) * (r + 6 * u))
            cr.line_to(cx + math.cos(ang) * (r + 13 * u), oy + math.sin(ang) * (r + 13 * u))
            cr.stroke()

        # Today's focus, drawn where it happened: a second band inside the
        # arc, one stroke per block, coloured by how much of the day that
        # application has had.
        totals = self.ledger.totals() if self.ledger is not None else []
        rank = {cls: i for i, (cls, _) in enumerate(totals)}
        if self.ledger is not None:
            midnight = time.mktime(now[:3] + (0, 0, 0) + now[6:])
            cr.set_line_width(5 * u)
            for start, end, cls in self.ledger.snapshot():
                a0 = math.pi + math.pi * max(0.0, (start - midnight) / 86400)
                a1 = math.pi + math.pi * min(1.0, (end - midnight) / 86400)
                if a1 - a0 < 0.0009:         # under ~a quarter pixel: skip
                    continue
                i = rank.get(cls, 99)
                rgba(cr, RANKS[i] if i < len(RANKS) else "gutter", a)
                cr.new_path()
                cr.arc(cx, oy, r - 10 * u, a0, a1)
                cr.stroke()

        ang = math.pi + math.pi * frac
        sx, sy = cx + math.cos(ang) * r, oy + math.sin(ang) * r
        day = 0.25 < frac < 0.83
        for rad, al in ((19, 0.10), (12, 0.22), (6, 1.0)):
            rgba(cr, "attention" if day else "fg", al * a)
            cr.new_path()
            cr.arc(sx, sy, rad * u, 0, TAU)
            cr.fill()

        # Set like the lock screen (wm/hyprlock.nix): the time in `fg`, the
        # date under it in `subtle`. Placed by the digits' own box so that it
        # sits in the dome whatever the voice, and narrowed if the voice is
        # too wide for it.
        clock = time.strftime("%H:%M", now)
        size = FONT["clock_size"] * 0.70 * u
        room = 2 * math.sqrt(max(1.0, r * r - (118 * u) ** 2)) - 64 * u
        ix, iy, iw, ih = ink(cr, clock, size, weight=FONT["clock_weight"],
                             spacing=FONT["clock_track"] * u)
        if iw > room:
            size *= room / iw
            ix, iy, iw, ih = ink(cr, clock, size, weight=FONT["clock_weight"],
                                 spacing=FONT["clock_track"] * u)
        text(cr, clock, cx - iw / 2 - ix, oy - 84 * u - ih / 2 - iy, size, "fg", a,
             weight=FONT["clock_weight"], spacing=FONT["clock_track"] * u)
        text(cr, label(time.strftime("%A %-d %B", now)), cx, oy + 18 * u, 20 * u, "subtle", a,
             weight=FONT["regular"], align="center", spacing=FONT["track"] * 1.6 * u)

        # Legend for the focus band: the four applications that had the most
        # of today, each with the colour its strokes are drawn in.
        items = [(RANKS[i], f"{cls or 'desktop'}  {human(sec)}")
                 for i, (cls, sec) in enumerate(totals[:len(RANKS)]) if sec >= 60]
        if items:
            size, dot, gap, sep = 14 * u, 4.5 * u, 9 * u, 30 * u
            widths = [measure(cr, lbl, size, weight=FONT["regular"])[0] for _, lbl in items]
            total = sum(widths) + len(items) * (2 * dot + gap) + (len(items) - 1) * sep
            x = cx - total / 2
            y = oy + 60 * u
            for (role, lbl), tw in zip(items, widths):
                rgba(cr, role, a)
                cr.new_path()
                cr.arc(x + dot, y + size * 0.62, dot, 0, TAU)
                cr.fill()
                text(cr, lbl, x + 2 * dot + gap, y, size, "muted", a, weight=FONT["regular"])
                x += 2 * dot + gap + tw + sep

    def draw_gauges(self, cr, right, cy, u, a):
        """The machine's readings: small rings in the corner, right-aligned."""
        present = [(k, name) for k, name in GAUGES if self.stats.values[k] is not None]
        gap, r = 80 * u, 23 * u
        x = right - r - gap * (len(present) - 1)
        for key, name in present:
            raw = self.stats.values[key]
            v = max(0.0, min(1.08, self.gauge[key].x))
            # Loudness rule: a gauge is quiet blue until it actually needs you.
            hot = (key in ("cpu", "mem", "vram", "gpu") and raw > 0.9) or \
                  (key == "temp" and raw > 88) or \
                  (key == "bat" and raw < 0.15 and not self.stats.charging)
            cr.set_line_cap(cairo.LINE_CAP_ROUND)
            cr.set_line_width(4 * u)
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
            ix, iy, iw, ih = ink(cr, val, 15 * u, weight=FONT["regular"])
            text(cr, val, x - iw / 2 - ix, cy - ih / 2 - iy, 15 * u, "fg", a, weight=FONT["regular"])
            text(cr, label(name), x, cy + r + 12 * u, 12 * u, "muted", a,
                 weight=FONT["strong"], align="center", spacing=FONT["track"] * u)
            x += gap

    def draw_map(self, cr, w, u, a, lift):
        """The hero: every workspace that has windows, as a card with those
        windows to scale. The card the switcher is on is larger."""
        self.hits = []
        mons = {m["id"]: m for m in self.snapshot["monitors"]}
        by_ws = {}
        for c in self.snapshot["clients"]:
            ws = c.get("workspace", {})
            if not c.get("mapped", True) or ws.get("id", -1) < 0:
                continue
            by_ws.setdefault(ws["id"], []).append(c)
        active_ws = {m["activeWorkspace"]["id"] for m in mons.values()}
        here = next((m["activeWorkspace"]["id"] for m in mons.values() if m.get("focused")), None)
        self.ids = ids = sorted(set(by_ws) | active_ws)
        if not ids:
            return
        if self.cursor not in ids:
            self.cursor = here if here in ids else ids[0]
        for wid in ids:
            if wid not in self.grow:         # arrives at its size, does not grow into it
                self.grow[wid] = Spring(1.0 if wid == self.cursor else 0.0, SPATIAL)

        # One row, centred. Widths come from the springs, so when the
        # selection moves the cards trade sizes and their neighbours make room.
        n, gap = len(ids), 40 * u
        base = min(CARD * u, (w - 240 * u - gap * (n - 1)) / (n - 1 + HERO))
        grown = {wid: max(0.0, min(1.15, self.grow[wid].x)) for wid in ids}
        widths = {wid: base * (1.0 + (HERO - 1.0) * grown[wid]) for wid in ids}
        x = (w - sum(widths.values()) - gap * (n - 1)) / 2
        cy = 716 * u + lift
        placed, tallest = [], 0.0
        for wid in ids:
            clients = by_ws.get(wid, [])
            mon = mons.get(clients[0]["monitor"]) if clients else next(
                (m for m in mons.values() if m["activeWorkspace"]["id"] == wid), None)
            if mon is not None:
                mw, mh = mon["width"] / mon["scale"], mon["height"] / mon["scale"]
                ch = widths[wid] * mh / mw
                placed.append((wid, x, cy - ch / 2, widths[wid], ch, mon, clients))
                tallest = max(tallest, base * HERO * mh / mw)
            x += widths[wid] + gap

        # hyprland/window: what the bar prints next to the workspaces.
        if self.bar.title:
            text(cr, self.bar.title, w / 2, cy - tallest / 2 - 54 * u, 15 * u, "muted", a,
                 family=ICON_FAMILY, weight=400, align="center")
        for wid, x, y, cw, ch, mon, clients in placed:
            g = min(1.0, grown[wid])
            self.draw_workspace(cr, wid, x, y, cw, ch, mon, clients, g, u, a)
            # Its number, set like the title card's: thin, placed by the
            # digit's own box. Where you are is `fg` with the accent dot.
            size = (40 + 22 * g) * u
            ix, iy, iw, _ih = ink(cr, str(wid), size, weight=FONT["numeral_weight"])
            ny = cy + tallest / 2 + 28 * u
            role = "fg" if wid == here else "subtle" if g > 0.5 else "muted"
            text(cr, str(wid), x + cw / 2 - iw / 2 - ix, ny - iy, size, role, a,
                 weight=FONT["numeral_weight"])
            if wid == here:
                rgba(cr, "accent", a)
                cr.new_path()
                cr.arc(x + cw / 2, ny + 66 * u, 3.5 * u, 0, TAU)
                cr.fill()

    def draw_workspace(self, cr, wid, x, y, cw, ch, mon, clients, g, u, a):
        """One workspace: an island, its windows to scale on it, as pictures
        of themselves where there are any (thumbs.py). `g` is how
        far it is the selected one (0..1): larger already, and lifted — a
        darker, brighter-edged card with a shadow under it."""
        rad = 14 * u
        for spread, alpha in ((20, 0.06), (11, 0.09), (4, 0.13)):
            if g > 0.02:
                rounded(cr, x - spread * u, y - spread * u + 8 * u * g, cw + 2 * spread * u,
                        ch + 2 * spread * u, rad + spread * u)
                rgba(cr, "bgDeep", alpha * g * a)
                cr.fill()
        rounded(cr, x, y, cw, ch, rad)
        rgba(cr, "bg", (0.50 + 0.38 * g) * a)
        cr.fill_preserve()
        cr.set_line_width((1.0 + 0.5 * g) * u)
        rgba(cr, "fg", (0.10 + 0.24 * g) * a)
        cr.stroke()
        self.hits.append((x, y, cw, ch, "workspace", wid))

        s = cw / (mon["width"] / mon["scale"])
        ts = max(12.5 * u, min(15 * u, 60 * u * s))   # the names grow with the card
        if not clients:
            _, eh = measure(cr, label("empty"), 13 * u)
            text(cr, label("empty"), x + cw / 2, y + (ch - eh) / 2, 13 * u, "hint", a,
                 align="center", spacing=FONT["track"] * u)
            return
        cr.save()
        rounded(cr, x, y, cw, ch, rad)
        cr.clip()                           # a window hanging off the monitor stays on the card
        # Back to front, as the compositor stacks them: tiled, then floating
        # (the one used last on top), then whatever is fullscreen.
        for c in sorted(clients, key=lambda c: (bool(c.get("fullscreen")), bool(c.get("floating")),
                                                -c.get("focusHistoryID", 0))):
            px = x + (c["at"][0] - mon["x"]) * s
            py = y + (c["at"][1] - mon["y"]) * s
            pw, ph = c["size"][0] * s, c["size"][1] * s
            focused = c["address"] == self.snapshot["active"]
            self.hits.append((px, py, pw, ph, "window", c["address"]))
            # Attention heat: a window you were in a moment ago is lighter
            # than one you have not touched for ten minutes.
            age = 600.0
            if self.pulse is not None and c["address"] in self.pulse.seen:
                age = time.monotonic() - self.pulse.seen[c["address"]]
            heat = 1.0 if focused else max(0.0, 1.0 - age / 600.0)
            shot = self.thumbs.get(c["address"], c["size"])
            seen = 0.0                      # how far its picture has faded in
            if shot is not None and c["address"] in self.reveal:
                seen = max(0.0, min(1.0, self.reveal[c["address"]].x))
            if seen < 0.999:
                # No picture (yet): the window as a drawn pane.
                rounded(cr, px + 1, py + 1, pw - 2, ph - 2, 6 * u)
                if focused:
                    rgba(cr, "accent", 0.26 * a)
                else:
                    rgba(cr, "overlay", (0.30 + 0.50 * heat) * a)
                cr.fill()
            if seen > 0.001:
                # The window itself, as it looks right now.
                cr.save()
                rounded(cr, px + 1, py + 1, pw - 2, ph - 2, 6 * u)
                cr.clip()
                cr.translate(px + 1, py + 1)
                cr.scale((pw - 2) / shot.get_width(), (ph - 2) / shot.get_height())
                cr.set_source_surface(shot, 0, 0)
                cr.get_source().set_filter(cairo.FILTER_BILINEAR)
                cr.paint_with_alpha(a * seen)
                cr.restore()
                if heat < 1.0:
                    rounded(cr, px + 1, py + 1, pw - 2, ph - 2, 6 * u)
                    rgba(cr, "bgDeep", STALE * (1.0 - heat) * a * seen)
                    cr.fill()
            room = pw - 20 * u
            named = room > 44 * u and ph > ts * 1.5 + 12 * u
            title = (c.get("title") or "").strip()
            titled = named and bool(title) and ph > ts * 3.0 + 12 * u
            if named and seen > 0.001:
                # Its name is written on the picture, so the picture is
                # shaded behind it: dark at the top edge, gone below the text.
                depth = min(ph - 2, ts * (4.6 if titled else 3.0))
                shade = cairo.LinearGradient(0, py + 1, 0, py + 1 + depth)
                shade.add_color_stop_rgba(0.0, *PAL["bgDeep"], 0.86 * a * seen)
                shade.add_color_stop_rgba(0.55, *PAL["bgDeep"], 0.60 * a * seen)
                shade.add_color_stop_rgba(1.0, *PAL["bgDeep"], 0.0)
                cr.save()
                rounded(cr, px + 1, py + 1, pw - 2, ph - 2, 6 * u)
                cr.clip()
                cr.rectangle(px + 1, py + 1, pw - 2, depth)
                cr.set_source(shade)
                cr.fill()
                cr.restore()
            rounded(cr, px + 1, py + 1, pw - 2, ph - 2, 6 * u)
            cr.set_line_width((1.0 + 0.6 * seen * focused) * u)
            rgba(cr, "accent" if focused else "slate", a)
            cr.stroke()
            if named:
                # XWayland windows carry a mark: they are the ones paying
                # the extra latency, and nothing else on screen says so.
                name = (c.get("class") or "?").lower() + ("  ·x11" if c.get("xwayland") else "")
                text(cr, name, px + 10 * u, py + 8 * u, ts, "fg" if focused else "subtle", a,
                     weight=FONT["regular"], width=room)
                if titled:
                    text(cr, title, px + 10 * u, py + 8 * u + ts * 1.5, ts - 1.0 * u, "muted", a,
                         family=ICON_FAMILY, weight=400, width=room)
        cr.restore()

    def draw_corners(self, cr, u, a):
        m = 60 * u
        host = os.uname().nodename
        up = float(_read("/proc/uptime", "0").split()[0])
        upt = f"{int(up // 3600)}h {int(up % 3600 // 60):02d}m"
        text(cr, label(host), m, m, 15 * u, "fg", a, weight=FONT["strong"],
             spacing=FONT["track"] * 1.3 * u)
        gen = self.stats.info["gen"]
        line = f"generation {gen}   ·   up {upt}   ·   {os.uname().release}" if gen else f"up {upt}"
        text(cr, line, m, m + 26 * u, 15 * u, "muted", a, weight=FONT["regular"])

    # -- the bar, unfolded --------------------------------------------------
    def island(self, cr, x, y, w, h, u, a):
        """The bar's own material: 0.85 bg, a 10% fg hairline, the island radius."""
        rounded(cr, x, y, w, h, ISLAND_RADIUS * u)
        rgba(cr, "bg", 0.85 * a)
        cr.fill_preserve()
        cr.set_line_width(1.0 * u)
        rgba(cr, "fg", 0.10 * a)
        cr.stroke()

    def draw_bar(self, cr, w, y, u, a):
        """Every module the bar is showing, as a chip: its glyph in the bar's
        own colour for its state, and — because here there is room — the
        sentence the bar keeps in a tooltip."""
        items = self.bar.items
        if not items:
            return
        pad, gap, between = 16 * u, 12 * u, 11 * u
        size, dsize, ch = 17 * u, 15 * u, 44 * u
        chips = []
        for it in items:
            tw, th = measure(cr, it["text"], size, family=ICON_FAMILY)
            dw, dh = measure(cr, it["detail"], dsize) if it["detail"] else (0, 0)
            chips.append((it, tw, th, dw, dh, pad * 2 + tw + (between + dw if dw else 0)))
        # Flow into centred rows of about equal width: work out how many rows
        # the chips need, then fill each to its share. Greedy wrapping alone
        # leaves the last chip alone on a row of its own.
        total = sum(c[5] for c in chips) + gap * (len(chips) - 1)
        count = max(1, math.ceil(total / (w * 0.80)))
        share = total / count
        rows, acc = [[]], 0.0
        for chip in chips:
            if rows[-1] and len(rows) < count and acc + chip[5] / 2 > share:
                rows.append([])
                acc = 0.0
            rows[-1].append(chip)
            acc += chip[5] + gap
        for r, row in enumerate(rows):
            x = (w - sum(c[5] for c in row) - gap * (len(row) - 1)) / 2
            ry = y + r * (ch + gap)
            for it, tw, th, dw, dh, cw in row:
                self.island(cr, x, ry, cw, ch, u, a)
                role = it["role"] if it["role"] in PAL else "subtle"
                text(cr, it["text"], x + pad, ry + (ch - th) / 2, size, role, a,
                     family=ICON_FAMILY)
                if dw:
                    text(cr, it["detail"], x + pad + tw + between, ry + (ch - dh) / 2, dsize,
                         "muted", a, weight=FONT["regular"])
                x += cw + gap
