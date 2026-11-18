"""reverie daemon: one process owns every surface and listens for commands.

A daemon rather than a program per keypress because the HUD is hold-to-show:
GTK takes a few hundred ms to start, and a panel that arrives after you have
already let go of the key is not a panel. Commands are one line each on a unix
socket; `reverie <words>` is the client (see the Nix wrapper).
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import common  # noqa: E402  (first: it pins the GI versions)
from gi.repository import Gio, GLib, Gtk  # noqa: E402
from hud import Hud  # noqa: E402


# Tier 2 under ADR-005: runtime choices live in ~/.local/state/theme/, never in
# the Nix config. This file is only "which of the opt-in behaviours are on".
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                     "theme", "reverie.json")


class Reverie(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="dev.dani.reverie",
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.hud = None
        self.dream = None
        self.pulse = None
        self.cards = None
        self.service = None

    def do_activate(self):
        if self.hud is not None:
            return
        self.hold()
        common.install_css()
        self.hud = Hud(self)
        try:
            from dream import Dream
            self.dream = Dream(self)
        except ImportError:
            pass
        try:
            from pulse import Pulse
            self.pulse = Pulse(self)
        except ImportError:
            pass
        try:
            from cards import Cards
            self.cards = Cards(self)
            if self.pulse:
                self.pulse.listeners.append(self.cards.on_event)
        except ImportError:
            self.cards = None
        self.hud.pulse = self.pulse
        self.restore()
        self.listen()

    def restore(self):
        try:
            with open(STATE) as f:
                state = json.load(f)
        except (OSError, ValueError):
            return
        if self.pulse:
            for key in ("sound", "fade"):
                if state.get(key):
                    self.pulse.command([key, "on"])
        if self.cards and state.get("cards"):
            self.cards.command(["on"])

    def save(self):
        state = {
            "sound": bool(self.pulse and self.pulse.sound),
            "fade": bool(self.pulse and self.pulse.fade),
            "cards": bool(self.cards and self.cards.enabled),
        }
        try:
            os.makedirs(os.path.dirname(STATE), exist_ok=True)
            with open(STATE, "w") as f:
                json.dump(state, f)
        except OSError:
            pass

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
        stream = Gio.DataInputStream.new(conn.get_input_stream())
        line, _ = stream.read_line_utf8(None)
        reply = self.command((line or "").split())
        conn.get_output_stream().write_all((reply + "\n").encode(), None)
        conn.close(None)
        return True

    def command(self, words):
        if not words:
            return "usage: hud show|hide|toggle · dream · pulse [sound|fade] on|off · cards on|off · undo · quit"
        head, rest = words[0], words[1:]
        if head == "hud":
            getattr(self.hud, rest[0] if rest and rest[0] in ("show", "hide", "toggle")
                    else "toggle")()
            return "ok"
        if head == "dream" and self.dream:
            self.dream.toggle()
            return "ok"
        if head == "pulse" and self.pulse:
            reply = self.pulse.command(rest)
            self.save()
            return reply
        if head == "status":
            return (self.pulse.command(["status"]) if self.pulse else "") + " · " + \
                (self.cards.command([]) if self.cards else "")
        if head == "cards" and self.cards:
            reply = self.cards.command(rest)
            self.save()
            return reply
        if head == "undo" and self.pulse:
            return self.pulse.undo()
        if head == "quit":
            if self.pulse:
                self.pulse.restore()          # never leave windows dimmed behind
            GLib.idle_add(self.quit)
            return "bye"
        return f"unknown: {' '.join(words)}"


if __name__ == "__main__":
    Reverie().run([])
