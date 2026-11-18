"""ledger: where the day went.

Every time focus changes, the block that just ended is written down: which
application, from when, until when. That is the whole dataset — a class name
and two timestamps — and it never leaves ~/.local/state/reverie.

The HUD draws it on the day arc, so the arc that shows what time it is also
shows what the time was spent on. Nobody measures a rice; this measures the
one thing a desktop is for.

Presence: hypridle tells the daemon when you go idle (`reverie away` /
`reverie back`, see reverie.nix), and the open block is closed while you are
gone. Without that listener the ledger cannot tell reading from an empty
chair and will overcount the focused window.
"""

import datetime
import glob
import json
import os
import time

KEEP_DAYS = 14
MERGE_GAP = 3.0          # seconds: a flicker of focus elsewhere is not a context switch


class Ledger:
    def __init__(self):
        base = os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state"))
        self.dir = os.path.join(base, "reverie")
        self.day = datetime.date.today()
        self.blocks = []             # [start, end, class], wall-clock seconds
        self.open = None             # (start, class)
        self.last_class = ""
        self.away = False
        self.saved_at = 0.0
        self.load()

    def path(self, day):
        return os.path.join(self.dir, f"ledger-{day.isoformat()}.json")

    def load(self):
        try:
            with open(self.path(self.day)) as f:
                self.blocks = [b for b in json.load(f) if len(b) == 3]
        except (OSError, ValueError):
            self.blocks = []
        cutoff = (self.day - datetime.timedelta(days=KEEP_DAYS)).isoformat()
        for old in glob.glob(os.path.join(self.dir, "ledger-*.json")):
            if os.path.basename(old)[7:17] < cutoff:
                try:
                    os.unlink(old)
                except OSError:
                    pass

    def save(self, force=False):
        now = time.time()
        if not force and now - self.saved_at < 60:
            return
        self.saved_at = now
        try:
            os.makedirs(self.dir, exist_ok=True)
            tmp = self.path(self.day) + ".tmp"
            with open(tmp, "w") as f:
                json.dump(self.snapshot(), f)
            os.replace(tmp, self.path(self.day))
        except OSError:
            pass

    # -- recording --------------------------------------------------------
    def _close(self, now):
        if self.open is None:
            return
        start, cls = self.open
        self.open = None
        if now - start < 0.5:
            return
        last = self.blocks[-1] if self.blocks else None
        if last and last[2] == cls and start - last[1] < MERGE_GAP:
            last[1] = now
        else:
            self.blocks.append([start, now, cls])

    def _roll(self, now):
        today = datetime.date.fromtimestamp(now)
        if today != self.day:
            self._close(now)
            self.save(force=True)
            self.day = today
            self.blocks = []

    def focus(self, cls):
        now = time.time()
        self._roll(now)
        self._close(now)
        self.last_class = cls
        if cls and not self.away:
            self.open = (now, cls)
        self.save()

    def set_away(self, away):
        now = time.time()
        self.away = away
        self._close(now)
        if not away and self.last_class:
            self.open = (now, self.last_class)
        self.save(force=True)

    # -- reading ----------------------------------------------------------
    def snapshot(self):
        """Today's blocks including the one still running."""
        out = [list(b) for b in self.blocks]
        if self.open is not None:
            out.append([self.open[0], time.time(), self.open[1]])
        return out

    def totals(self):
        """[(class, seconds)] for today, longest first."""
        acc = {}
        for start, end, cls in self.snapshot():
            acc[cls] = acc.get(cls, 0.0) + (end - start)
        return sorted(acc.items(), key=lambda kv: -kv[1])

    def on_event(self, event, data):
        # The v1 event is the one that carries the class name.
        if event == "activewindow":
            self.focus(data.split(",")[0].lower())


def human(seconds):
    m = int(seconds // 60)
    return f"{m // 60}h {m % 60:02d}m" if m >= 60 else f"{m}m"
