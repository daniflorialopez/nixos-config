"""pulse: the desktop as something you can hear and that remembers attention.

Two behaviours hang off Hyprland's event socket. Both are off until asked for.

sound  The desktop is an instrument. Each workspace is a note of a D-major
       pentatonic scale, so moving 1 -> 2 -> 3 plays a rising phrase and no
       sequence of workspaces can sound wrong. A window opening is a soft
       rising grace note, closing a falling one, urgency two taps. All of it
       is synthesised here from sines — no samples, nothing to download.

fade   Windows fade when ignored. Each window remembers when it last had
       focus; after a grace period its opacity eases down, and comes straight
       back the moment you return. What is on screen then shows where your
       attention has actually been, which no static rule can.
"""

import math
import os
import shlex
import shutil
import struct
import subprocess
import time
import wave

from gi.repository import Gio, GLib

from common import hypr, hypr_events_path

RATE = 44100
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "reverie")

# D major pentatonic, two octaves: workspaces 1..10.
SCALE = [293.66, 329.63, 369.99, 440.00, 493.88, 587.33, 659.25, 739.99, 880.00, 987.77]


def _tone(freqs, length=0.9, decay=5.5, gain=0.5):
    """A soft mallet: fundamental plus two quiet partials, exponential decay.

    `freqs` is a list of (frequency, start_seconds). Returns 16-bit stereo
    frames; the right channel is a few ms late for a little width.
    """
    n = int(RATE * length)
    mono = [0.0] * n
    for freq, start in freqs:
        off = int(start * RATE)
        for i in range(n - off):
            t = i / RATE
            env = (1 - math.exp(-t * 900)) * math.exp(-t * decay)
            s = math.sin(math.tau * freq * t)
            s += 0.22 * math.sin(math.tau * freq * 2 * t) * math.exp(-t * 4)
            s += 0.06 * math.sin(math.tau * freq * 3.01 * t) * math.exp(-t * 9)
            mono[off + i] += s * env
    peak = max(1e-9, max(abs(v) for v in mono))
    delay = int(0.004 * RATE)
    out = bytearray()
    for i in range(n):
        left = mono[i] / peak * gain
        right = (mono[i - delay] if i >= delay else 0.0) / peak * gain
        out += struct.pack("<hh", int(left * 32767), int(right * 32767))
    return bytes(out)


def build_sounds():
    """Render the whole instrument once; ~1 s of CPU, then cached."""
    os.makedirs(CACHE, exist_ok=True)
    wanted = {f"ws{i + 1}": [(f, 0.0)] for i, f in enumerate(SCALE)}
    wanted["open"] = [(880.00, 0.0), (1174.66, 0.07)]
    wanted["close"] = [(880.00, 0.0), (587.33, 0.07)]
    wanted["urgent"] = [(739.99, 0.0), (739.99, 0.16)]
    paths = {}
    for name, freqs in wanted.items():
        path = os.path.join(CACHE, f"{name}.wav")
        paths[name] = path
        if os.path.exists(path):
            continue
        short = name in ("open", "close")
        frames = _tone(freqs, length=0.55 if short else 1.0, decay=9 if short else 5.5,
                       gain=0.28 if short else 0.5)
        with wave.open(path + ".tmp", "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(frames)
        os.replace(path + ".tmp", path)
    return paths


class Pulse:
    def __init__(self, _app):
        self.sound = False
        self.fade = False
        self.volume = 0.35
        self.grace = 60.0        # seconds a window keeps full opacity unfocused
        self.span = 240.0        # seconds over which it then eases down
        self.floor = 0.62        # opacity multiplier it settles at
        self.sounds = {}
        self.player = shutil.which("pw-play")
        self.last_played = 0.0
        self.seen = {}           # address -> last time it had focus
        self.applied = {}        # address -> multiplier we last set
        self.focused = None
        self.stream = None
        self.timer = 0
        self.listeners = []      # other modules that want the raw events
        self.windows = {}        # address -> what it would take to reopen it
        self.closed = []         # most recent last
        for c in hypr("j/clients") or []:
            self.remember(c)
        self.connect()

    # -- event socket -----------------------------------------------------
    def connect(self):
        try:
            client = Gio.SocketClient()
            conn = client.connect(Gio.UnixSocketAddress.new(hypr_events_path()), None)
        except GLib.Error:
            GLib.timeout_add_seconds(5, self._reconnect)
            return
        self.conn = conn
        self.stream = Gio.DataInputStream.new(conn.get_input_stream())
        self.stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_line)

    def _reconnect(self):
        self.connect()
        return False

    def on_line(self, stream, result):
        try:
            line, _ = stream.read_line_finish_utf8(result)
        except GLib.Error:
            line = None
        if line is None:
            GLib.timeout_add_seconds(5, self._reconnect)
            return
        event, _, data = line.partition(">>")
        try:
            self.on_event(event, data)
        except Exception as exc:  # an event handler must never kill the daemon
            print(f"pulse: {event}: {exc!r}", flush=True)
        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_line)

    # -- memory: undo for the desktop --------------------------------------
    def remember(self, c):
        """Record how to bring this window back: command line, place, shape."""
        try:
            with open(f"/proc/{c['pid']}/cmdline", "rb") as f:
                argv = [a.decode(errors="replace") for a in f.read().split(b"\0") if a]
        except OSError:
            argv = []
        old = self.windows.get(c["address"], {})
        self.windows[c["address"]] = {
            "argv": argv or old.get("argv", []),
            "class": c.get("class", ""),
            "workspace": c.get("workspace", {}).get("id", 1),
            "floating": c.get("floating", False),
            "at": c.get("at", [0, 0]),
            "size": c.get("size", [800, 600]),
        }

    def refresh_memory(self):
        for c in hypr("j/clients") or []:
            self.remember(c)

    def undo(self):
        """Reopen the most recently closed window where and how it was."""
        while self.closed:
            w = self.closed.pop()
            if not w["argv"]:
                continue
            rules = [f"workspace {w['workspace']} silent"]
            if w["floating"]:
                rules += ["float", f"move {w['at'][0]} {w['at'][1]}",
                          f"size {w['size'][0]} {w['size'][1]}"]
            cmd = " ".join(shlex.quote(a) for a in w["argv"])
            hypr(f"dispatch exec [{'; '.join(rules)}] {cmd}")
            return f"reopened {w['class'] or w['argv'][0]} on workspace {w['workspace']}"
        return "nothing to undo"

    def on_event(self, event, data):
        for listener in self.listeners:
            listener(event, data)
        if event in ("openwindow", "activewindowv2", "movewindowv2", "changefloatingmode"):
            self.refresh_memory()
        if event == "closewindow":
            gone = self.windows.pop("0x" + data, None)
            if gone:
                self.closed.append(gone)
                del self.closed[:-12]
        if event == "workspacev2":
            wid = data.split(",")[0]
            if wid.lstrip("-").isdigit() and 1 <= int(wid) <= len(SCALE):
                self.play(f"ws{int(wid)}")
        elif event == "openwindow":
            self.seen["0x" + data.split(",")[0]] = time.monotonic()
            self.play("open")
        elif event == "closewindow":
            addr = "0x" + data
            self.seen.pop(addr, None)
            self.applied.pop(addr, None)
            self.play("close")
        elif event == "urgent":
            self.play("urgent")
        elif event == "activewindowv2":
            addr = "0x" + data if data else None
            now = time.monotonic()
            if self.focused:
                self.seen[self.focused] = now
            self.focused = addr
            if addr:
                self.seen[addr] = now
                if self.fade:
                    self.set_opacity(addr, 1.0)

    # -- sound ------------------------------------------------------------
    def play(self, name):
        if not (self.sound and self.player):
            return
        now = time.monotonic()
        # Opening a window also fires workspace/focus events; let one sound win.
        if now - self.last_played < 0.09:
            return
        self.last_played = now
        path = self.sounds.get(name)
        if path:
            subprocess.Popen([self.player, "--volume", f"{self.volume:.2f}", path],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # -- fade -------------------------------------------------------------
    def set_opacity(self, addr, value):
        value = round(value * 50) / 50              # 0.02 steps: fewer IPC calls, 1.0 stays 1.0
        if abs(self.applied.get(addr, 1.0) - value) < 0.001:
            return
        # A window rule `opacity` is a MULTIPLIER on the configured
        # active/inactive opacity, so 1.0 means "as declared", not "opaque".
        try:
            reply = hypr(f"dispatch setprop address:{addr} opacity {value:.2f}")
        except OSError:
            return
        if reply.strip() == "ok":
            self.applied[addr] = value
        else:
            print(f"pulse: setprop {addr}: {reply.strip()}", flush=True)

    def sweep(self):
        if not self.fade:
            self.timer = 0
            return False
        now = time.monotonic()
        for c in hypr("j/clients") or []:
            addr = c["address"]
            if addr == self.focused:
                self.seen[addr] = now
                self.set_opacity(addr, 1.0)
                continue
            age = now - self.seen.setdefault(addr, now)
            t = max(0.0, min(1.0, (age - self.grace) / self.span))
            t = t * t * (3 - 2 * t)                 # ease in and out
            self.set_opacity(addr, 1.0 - (1.0 - self.floor) * t)
        return True

    def restore(self):
        for addr in list(self.applied):
            self.set_opacity(addr, 1.0)
        self.applied.clear()

    # -- commands ---------------------------------------------------------
    def command(self, words):
        what = words[0] if words else "status"
        if what in ("on", "off"):
            words = ["both", what]
            what = "both"
        if what == "status":
            dimmed = sum(1 for v in self.applied.values() if v < 0.999)
            return (f"sound {'on' if self.sound else 'off'} · fade {'on' if self.fade else 'off'}"
                    + (f" ({dimmed} dimmed)" if self.fade else ""))
        state = len(words) > 1 and words[1] == "on"
        if len(words) > 1 and words[1] == "toggle" and what in ("sound", "fade"):
            state = not (self.sound if what == "sound" else self.fade)
        if what in ("sound", "both"):
            if state and not self.sounds:
                self.sounds = build_sounds()
            self.sound = state
            if state:
                active = hypr("j/activeworkspace") or {}
                wid = active.get("id", 1)
                self.play(f"ws{wid}" if 1 <= wid <= len(SCALE) else "open")
        if what in ("fade", "both"):
            self.fade = state
            if state:
                # `pulse fade on 5 20` = grace 5 s, span 20 s: for showing it off.
                nums = [float(w) for w in words[2:4] if w.replace(".", "").isdigit()]
                if len(nums) == 2:
                    self.grace, self.span = nums
                self.focused = (hypr("j/activewindow") or {}).get("address")
                if not self.timer:
                    self.timer = GLib.timeout_add_seconds(2, self.sweep)
            else:
                self.restore()
        return self.command(["status"])
