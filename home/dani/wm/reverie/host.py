"""host: the daemon's end of the stage.

stage.py is the HUD as its own program, because it draws on the graphics card
and the daemon does not (stage.py's header says why). This starts it when the
daemon starts, so that it is warm by the time a key is pressed, and from then
on passes `hud …` commands down a pipe to it.

The daemon's own panel (hud.py) is still there and is what answers whenever
this is not usable: switched off (`reverie hud stage off`), not started yet,
gone, or no longer answering. That last case matters more than it sounds. A
pinned panel is a surface over the whole screen that holds the keyboard; if
the program behind it hung, nothing short of another terminal would get rid
of it. So while its panel is up it is pinged every second, and one that has
not answered for four is killed — its surface goes with it — and the plain
panel takes over. (While it is away it is only asked twice a minute whether
it is still there.) One that had been running for a while is started again,
once; one that dies young is left dead, and `reverie hud stage on` is how to
try again.
"""

import json
import os
import select
import subprocess
import sys
import time

from gi.repository import GLib

import common

STAGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stage.py")
SILENCE = 4.0                # s without an answer before it is taken for hung
GRACE = 10.0                 # s it is given to start: GTK, GL, the wallpaper
SETTLED = 30.0               # s of life after which a death is worth one restart
IDLE_PING = 30               # s between pings while its panel is away


class StageHost:
    def __init__(self, app):
        self.app = app
        self.wanted = False              # the choice (`hud stage on|off`), kept across restarts
        self.proc = None
        self.ready = False               # it has answered at least once
        self.started_at = 0.0
        self.pong_at = 0.0
        self.pushed_at = 0.0             # when it was last sent the day's focus blocks
        self.pending = b""
        self.reply = None
        self.up = False                  # its panel is on screen (it says so)
        self.asked_at = 0.0              # when it was last pinged
        self.watch_id = 0
        self.ping_id = 0

    # -- its life -----------------------------------------------------------
    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def usable(self):
        return self.wanted and self.ready and self.alive()

    def start(self):
        if self.alive():
            return
        self.forget()
        # The renderer is the point of the separate program: GTK's GL one,
        # where the daemon itself runs the software one. And it is told to
        # remember for longer: by default it drops any picture it has not
        # drawn for fifteen seconds, which is every picture the panel is
        # made of by the time the panel is next wanted — the first frame
        # then waited 140 ms for them to be handed over again (measured).
        # Ten minutes, and the stage shows it its pictures every four
        # (stage.Stage._keep); what the stage itself has let go of is still
        # freed.
        env = dict(os.environ, GSK_RENDERER="gl", GSK_CACHE_TIMEOUT="600")
        args = [sys.executable, STAGE, "--font", common.FONT["name"]]
        if self.app.hud.beats:
            args.append("--beats")           # what was learned about held keys (hud.Hud.hold)
        try:
            self.proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                         env=env)
        except OSError as exc:
            print(f"host: stage: {exc!r}", flush=True)
            self.proc = None
            return
        fd = self.proc.stdout.fileno()
        os.set_blocking(fd, False)
        self.watch_id = GLib.io_add_watch(fd, GLib.PRIORITY_DEFAULT,
                                          GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, self.on_output)
        self.started_at = self.pong_at = self.asked_at = time.monotonic()
        self.up = True                   # until it has answered once: watch it closely
        if not self.ping_id:
            self.ping_id = GLib.timeout_add(1000, self.ping)
        self.say("ping")
        return False                     # (also a timeout callback: see `lost`)

    def forget(self):
        if self.watch_id:
            GLib.source_remove(self.watch_id)
            self.watch_id = 0
        self.proc, self.ready, self.pending, self.up = None, False, b"", False

    def stop(self):
        """Tell it to go (it leaves when its input ends) and stop listening."""
        proc = self.proc
        self.forget()
        if proc is not None:
            try:
                proc.stdin.close()
            except OSError:
                pass
            GLib.timeout_add(1500, self.reap, proc)

    @staticmethod
    def reap(proc):
        if proc.poll() is None:
            proc.kill()                      # it was asked; now it is told
            return True
        return False

    def ping(self):
        if self.proc is None:
            self.ping_id = 0
            return False
        now = time.monotonic()
        if not self.alive():
            self.lost("the stage is gone")
        elif now - self.asked_at < (1.0 if self.up else IDLE_PING) - 0.05:
            pass                             # away, and asked not long ago
        elif self.asked_at > self.pong_at and \
                now - self.pong_at > (SILENCE if self.ready else GRACE):
            self.proc.kill()
            self.lost("the stage stopped answering: killed")
        else:
            self.asked_at = now
            self.say("ping")
        return True

    def lost(self, why):
        lived = time.monotonic() - self.started_at
        again = self.wanted and lived > SETTLED
        print(f"host: {why} after {lived:.0f} s; the plain panel takes over"
              + (", and it is started again" if again else ""), flush=True)
        self.forget()
        if again:
            GLib.timeout_add_seconds(2, self.start)

    # -- the pipe -------------------------------------------------------------
    def say(self, line):
        try:
            self.proc.stdin.write((line + "\n").encode())
            self.proc.stdin.flush()
            return True
        except (AttributeError, OSError, ValueError):
            return False

    def on_output(self, fd, _condition):
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            return True
        except OSError:
            data = b""
        if not data:
            self.watch_id = 0
            return False                     # it has gone; `ping` will notice and say so
        self.feed(data)
        return True

    def feed(self, data):
        self.pending += data
        while b"\n" in self.pending:
            line, self.pending = self.pending.split(b"\n", 1)
            self.heard(line.decode(errors="replace").strip())

    def heard(self, line):
        if line in ("up", "down"):
            self.up = line == "up"           # watched every second while it is up
        elif line == "pong":
            self.pong_at = time.monotonic()
            if not self.ready:
                self.ready = True
                if os.environ.get("REVERIE_DEBUG"):
                    print(f"host: stage ready {(self.pong_at - self.started_at) * 1000:.0f} ms "
                          "after it was started", flush=True)
        elif line.startswith("status "):
            self.reply = line[7:]
        elif line.startswith("beats "):
            self.app.hud.beats = line.endswith("1")      # kept in the state file from there
            self.app.save()
        elif line == "want ledger":
            self.push_ledger(force=True)

    def push_ledger(self, force=False):
        """The focus history lives here; the stage draws it on its day arc."""
        now = time.monotonic()
        if force or now - self.pushed_at > 1.0:
            self.pushed_at = now
            self.say("ledger " + json.dumps(self.app.ledger.snapshot()))

    # -- what the daemon asks of it -------------------------------------------
    def command(self, words):
        if words and words[0] == "status":
            return self.status()
        self.push_ledger()
        self.say("hud " + " ".join(words))
        # It answers with whether its panel is up. Until it has, assume so
        # and ask at once: if it has hung, this is when that has to be seen.
        if not self.up:
            self.up = True
            self.asked_at = time.monotonic()
            self.say("ping")
        return "hud: " + (" ".join(words) or "toggle")

    def status(self):
        """Asked and waited for, briefly: only tests and the command line ask."""
        self.reply = None
        if not self.say("status"):
            return "hud: no stage"
        fd, end = self.proc.stdout.fileno(), time.monotonic() + 0.4
        while self.reply is None and time.monotonic() < end:
            ready, _, _ = select.select([fd], [], [], max(0.0, end - time.monotonic()))
            if not ready:
                break
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                continue
            except OSError:
                break
            if not data:
                break
            self.feed(data)
        return self.reply or "hud: no answer"

    def hide(self):
        if self.usable():
            self.say("hud hide")

    def font(self, name):
        if self.alive():
            self.say("font " + name)
