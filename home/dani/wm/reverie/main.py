"""reverie daemon: one process owns every surface and listens for commands.

A daemon rather than a program per keypress because the HUD is hold-to-show:
GTK takes a few hundred ms to start, and a panel that arrives after you have
already let go of the key is not a panel. Commands are one line each on a unix
socket in $XDG_RUNTIME_DIR; `reverie <words>` is the client (see reverie.nix).

Idle it costs nothing: no surface is mapped, no frame callback is registered,
and the only wake-ups are Hyprland's own window events.
"""

import json
import os
import signal
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import common  # noqa: E402  (first: it pins the GI versions)
from gi.repository import Gio, GLib, GLibUnix, Gtk  # noqa: E402

from cards import Cards  # noqa: E402
from dream import Dream  # noqa: E402
from fx import Fx  # noqa: E402
from hud import Hud  # noqa: E402
from ledger import Ledger  # noqa: E402
from pulse import Pulse  # noqa: E402

# Tier 2 under ADR-005: runtime choices live in ~/.local/state/theme/, never in
# the Nix config. This file is only "which of the opt-in behaviours are on".
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                     "theme", "reverie.json")

USAGE = ("hud show|hide|pin|glass on|off · cards|ripples on|off · spotlight on|off|toggle · "
         "pulse [sound|fade] on|off · zen on|off|toggle · dream [auto on|off] · undo · "
         "status · quit")


def onoff(flag):
    return "on" if flag else "off"


class Reverie(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="dev.dani.reverie",
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.ready = False
        self.zen = False
        self.zen_cards = False       # what `cards` was before zen switched it on
        self.dream_auto = False
        self.dream_by_idle = False

    def do_activate(self):
        if self.ready:
            return
        self.ready = True
        self.hold()
        common.install_css()
        self.ledger = Ledger()
        self.pulse = Pulse(self)
        self.hud = Hud(self)
        self.dream = Dream(self)
        self.cards = Cards(self)
        self.fx = Fx(self, self.pulse)
        self.hud.pulse = self.pulse
        self.hud.ledger = self.ledger
        self.pulse.listeners += [self.ledger.on_event, self.cards.on_event, self.fx.on_event]
        self.restore()
        self.listen()
        for sig in (signal.SIGTERM, signal.SIGINT):
            GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, sig, self.shutdown)

    # -- state ------------------------------------------------------------
    def restore(self):
        try:
            with open(STATE) as f:
                state = json.load(f)
        except (OSError, ValueError):
            return
        for key in ("sound", "fade"):
            if state.get(key):
                self.pulse.command([key, "on"])
        if state.get("cards"):
            self.cards.command(["on"])
        if state.get("ripples"):
            self.fx.command("ripples", ["on"])
        self.hud.glass = state.get("glass", True)
        self.dream_auto = bool(state.get("dream_auto"))
        # Zen survives a daemon restart: the bar is still stopped, so the
        # daemon has to remember that it is the one who stopped it.
        self.zen = bool(state.get("zen"))
        self.zen_cards = bool(state.get("zen_cards"))

    def save(self):
        state = {
            "sound": self.pulse.sound,
            "fade": self.pulse.fade,
            "cards": self.cards.enabled,
            "ripples": self.fx.ripples_on,
            "glass": self.hud.glass,
            "dream_auto": self.dream_auto,
            "zen": self.zen,
            "zen_cards": self.zen_cards,
            # spotlight is a mode you enter, not a preference: never restored.
        }
        try:
            os.makedirs(os.path.dirname(STATE), exist_ok=True)
            with open(STATE, "w") as f:
                json.dump(state, f)
        except OSError:
            pass

    def shutdown(self, *_):
        """Leave the desktop as it was found: nothing dimmed, the bar back."""
        self.pulse.restore()
        self.ledger.set_away(True)       # closes and saves the open block
        if self.zen:
            self.set_zen(False)
        try:
            os.unlink(common.SOCK)
        except OSError:
            pass
        self.quit()
        return False

    # -- zen: kill the bar --------------------------------------------------
    def set_zen(self, want):
        """No bar at all. The HUD is one key-hold away and title cards announce
        every workspace change, which is everything the bar was for."""
        if want == self.zen:
            return
        self.zen = want
        if want:
            self.zen_cards = self.cards.enabled
            self.cards.enabled = True
        else:
            self.cards.enabled = self.zen_cards
        try:
            subprocess.Popen(["systemctl", "--user", "stop" if want else "start",
                              "waybar.service"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass

    # -- socket -----------------------------------------------------------
    def listen(self):
        try:
            os.unlink(common.SOCK)
        except FileNotFoundError:
            pass
        self.service = Gio.SocketService.new()
        self.service.add_address(Gio.UnixSocketAddress.new(common.SOCK),
                                 Gio.SocketType.STREAM, Gio.SocketProtocol.DEFAULT, None)
        self.service.connect("incoming", self.on_incoming)
        self.service.start()

    def on_incoming(self, _service, conn, _source):
        # The read is synchronous on the main loop, so a client that connects
        # and says nothing must not be able to freeze every surface.
        conn.get_socket().set_timeout(2)
        try:
            stream = Gio.DataInputStream.new(conn.get_input_stream())
            line, _ = stream.read_line_utf8(None)
            try:
                reply = self.command((line or "").split())
            except Exception as exc:     # a bad command must not take the daemon down
                reply = f"error: {exc!r}"
            conn.get_output_stream().write_all((reply + "\n").encode(), None)
            conn.close(None)
        except GLib.Error:
            pass
        return True

    def command(self, words):
        if not words:
            return USAGE
        head, rest = words[0], words[1:]
        if head == "hud":
            reply = self.hud.command(rest)
        elif head == "pulse":
            reply = self.pulse.command(rest)
        elif head == "cards":
            reply = self.cards.command(rest)
        elif head in ("spotlight", "ripples"):
            reply = self.fx.command(head, rest)
        elif head == "undo":
            return self.pulse.undo()
        elif head == "zen":
            want = not self.zen if (not rest or rest[0] == "toggle") else rest[0] == "on"
            self.set_zen(want)
            reply = f"zen {onoff(self.zen)}"
        elif head == "dream":
            if rest and rest[0] == "auto":
                if len(rest) > 1:
                    self.dream_auto = (not self.dream_auto) if rest[1] == "toggle" \
                        else rest[1] == "on"
                reply = f"dream auto {onoff(self.dream_auto)}"
            else:
                self.dream.toggle()
                return "ok"
        elif head == "away":
            # From hypridle. The ledger stops counting; the dream may start.
            self.ledger.set_away(True)
            # Never on battery: the dream is an animation, and an empty chair
            # is the worst possible moment to spend the charge on one.
            if self.dream_auto and not self.dream.shown and common.on_mains():
                self.dream.show()
                self.dream_by_idle = True
            return "ok"
        elif head == "back":
            self.ledger.set_away(False)
            if self.dream_by_idle:
                self.dream.hide()
            self.dream_by_idle = False
            return "ok"
        elif head == "status":
            return " · ".join([
                self.pulse.command(["status"]), self.cards.command([]),
                self.fx.command("ripples", []), self.fx.command("spotlight", []),
                f"zen {onoff(self.zen)}", f"dream auto {onoff(self.dream_auto)}",
                self.hud.command(["glass"]),
            ])
        elif head == "quit":
            GLib.idle_add(self.shutdown)
            return "bye"
        else:
            return f"unknown: {' '.join(words)}\n{USAGE}"
        self.save()
        return reply


if __name__ == "__main__":
    Reverie().run([])
