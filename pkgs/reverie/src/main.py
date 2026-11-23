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

from cards import STYLES, Cards  # noqa: E402
from fx import Fx  # noqa: E402
from glass import Glass  # noqa: E402
import hud  # noqa: E402
from hud import Hud  # noqa: E402
from ledger import Ledger  # noqa: E402
from menu import Menu  # noqa: E402
from pulse import Pulse  # noqa: E402
from under import Under  # noqa: E402

# Tier 2 under ADR-005: runtime choices live in ~/.local/state/theme/, never in
# the Nix config. This file is only "which of the opt-in behaviours are on".
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                     "theme", "reverie.json")

USAGE = ("hud show|hide|pin|hold|release|look glass|wallpaper|desktop|next · "
         "cards on|off|style bare|island|banner|next · "
         "ripples on|off · spotlight on|off|toggle · "
         "pulse [sound|fade] on|off · zen on|off|toggle · undo · "
         "font caskaydia|inter · glass on|off|toggle|look liquid|frosted|clear|next · "
         "menu [show|hide] · "
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
        self.saved = None            # the state as last written, to write only changes

    def do_activate(self):
        if self.ready:
            return
        self.ready = True
        self.hold()
        common.install_css()
        self.ledger = Ledger()
        self.pulse = Pulse(self)
        self.hud = Hud(self)
        self.cards = Cards(self)
        self.fx = Fx(self, self.pulse)
        self.glass = Glass()
        self.under = Under(self)         # glass for a fullscreen window (under.py)
        self.menu = Menu(self)
        self.hud.pulse = self.pulse
        self.hud.ledger = self.ledger
        self.cards.bar = self.hud.bar
        self.pulse.listeners += [self.ledger.on_event, self.cards.on_event, self.fx.on_event,
                                 self.under.on_event, self.on_key_event]
        GLib.idle_add(self.under.check)  # one may be fullscreen already
        self.watch_wallpaper()
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
        if state.get("card_style") in STYLES:
            self.cards.style = state["card_style"]
        if state.get("ripples"):
            self.fx.command("ripples", ["on"])
        common.set_font(state.get("font", "caskaydia"))
        self.hud.beats = bool(state.get("hold_repeats"))    # see Hud.hold
        if state.get("hud_look") in hud.LOOKS:
            self.hud.look = state["hud_look"]
        elif state.get("hud_glass") is False:            # how it was saved before there were three
            self.hud.look = "desktop"
        # Zen is a preference, so it survives a restart. Whether the bar is
        # really stopped is not something this file can know — a clean
        # shutdown brings it back, a crash leaves it down — so say it again.
        if state.get("zen"):
            self.zen = True
            self.zen_cards = bool(state.get("zen_cards"))
            self.cards.enabled = True
            self.bar_running(False)

    def save(self):
        state = {
            "sound": self.pulse.sound,
            "fade": self.pulse.fade,
            "cards": self.cards.enabled,
            "card_style": self.cards.style,
            "ripples": self.fx.ripples_on,
            "font": common.FONT["name"],
            "hold_repeats": self.hud.beats,
            "hud_look": self.hud.look,
            "zen": self.zen,
            "zen_cards": self.zen_cards,
            # spotlight is a mode you enter, not a preference: never restored.
        }
        if state == self.saved:
            return                       # every command ends here; most change nothing
        self.saved = state
        try:
            os.makedirs(os.path.dirname(STATE), exist_ok=True)
            with open(STATE, "w") as f:
                json.dump(state, f)
        except OSError:
            pass

    def shutdown(self, *_):
        """Leave the desktop as it was found: nothing dimmed, the bar back."""
        self.pulse.restore()
        self.fx.close()                  # the spotlight is a child: it goes too
        self.under.close()
        self.ledger.set_away(True)       # closes and saves the open block
        if self.zen:
            self.bar_running(True)       # the preference stays; the bar must not stay gone
        try:
            os.unlink(common.SOCK)
        except OSError:
            pass
        self.quit()
        return False

    def flags(self):
        """Every switch and choice, for the menu to draw."""
        return {
            "spotlight": self.fx.spot, "zen": self.zen, "cards": self.cards.enabled,
            "ripples": self.fx.ripples_on, "sound": self.pulse.sound, "fade": self.pulse.fade,
            "font": common.FONT["name"], "style": self.cards.style,
            "glass": self.glass.on, "glass_look": self.glass.look,
        }

    # -- the wallpaper ------------------------------------------------------
    def watch_wallpaper(self):
        """Two things here are pictures OF the wallpaper: the HUD's backdrop
        (hud.py) and the glass under a fullscreen window (under.py). Neither
        is told when it changes — the wallpaper daemon says nothing — so this
        watches the file the choice is written to (wm/wall-apply.nix; the
        path comes with the package, REVERIE_WALLPAPER_STATE). Without it
        both still catch up, later: the HUD on its next opening, the glass
        when the window leaves fullscreen."""
        path = os.environ.get("REVERIE_WALLPAPER_STATE")
        self.wall_timer = 0
        if not path:
            return
        try:
            self.wall = Gio.File.new_for_path(path).monitor_file(Gio.FileMonitorFlags.NONE, None)
        except GLib.Error:
            return
        self.wall.connect("changed", self.on_wallpaper)

    def on_wallpaper(self, *_):
        self.under.follow()              # through the crossfade, as it happens
        if self.wall_timer:
            GLib.source_remove(self.wall_timer)
        self.wall_timer = GLib.timeout_add(1500, self.wallpaper_changed)

    def wallpaper_changed(self):
        self.wall_timer = 0
        self.hud.prepare()               # once the daemon reports the new picture
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
        self.bar_running(not want)

    @staticmethod
    def bar_running(want):
        try:
            subprocess.Popen(["systemctl", "--user", "start" if want else "stop",
                              "waybar.service"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass

    # -- keys -------------------------------------------------------------
    def on_key_event(self, event, data):
        """The binds do not run `reverie <words>`. They have Hyprland say the
        words on its event socket (`event, reverie hud pin` arrives here as
        `custom>>reverie hud pin`), which this daemon is already reading.

        Two reasons. Nothing is forked, so a key reaches the panel in well
        under a millisecond instead of after a shell, a readlink and a socat.
        And the events arrive in the order the keys were pressed: with two
        processes racing, a quick tap could deliver "release" before "hold"
        and leave the panel up.
        """
        if event == "custom" and data.startswith("reverie "):
            try:
                self.command(data.split()[1:])
            except Exception as exc:         # a bad bind must not take the daemon down
                print(f"reverie: {data!r}: {exc!r}", flush=True)

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
            self.menu.hide()             # one panel with the keyboard at a time
            reply = self.hud.command(rest)
        elif head == "menu":
            if not self.menu.shown:
                self.hud.hide()
            return self.menu.command(rest)
        elif head == "pulse":
            reply = self.pulse.command(rest)
        elif head == "cards":
            reply = self.cards.command(rest)
        elif head in ("spotlight", "ripples"):
            reply = self.fx.command(head, rest)
        elif head == "undo":
            return self.pulse.undo()
        elif head == "font":
            # The voice of every surface; kept switchable so the two can be
            # compared on the real screen rather than argued about.
            if rest:
                names = list(common.FONTS)
                want = rest[0]
                if want == "toggle":
                    want = names[(names.index(common.FONT["name"]) + 1) % len(names)]
                common.set_font(want)
            reply = f"font {common.FONT['name']}"
        elif head == "glass":
            reply = self.glass.command(rest)     # its state is the command's, not ours
            self.hud.prepare()                   # the HUD's backdrop follows the look
            self.under.check()                   # and so does a fullscreen window's glass
            return reply
        elif head == "zen":
            want = not self.zen if (not rest or rest[0] == "toggle") else rest[0] == "on"
            self.set_zen(want)
            reply = f"zen {onoff(self.zen)}"
        elif head in ("away", "back"):
            # From hypridle: the ledger stops counting while nobody is here.
            self.ledger.set_away(head == "away")
            return "ok"
        elif head == "status":
            return " · ".join([
                self.pulse.command(["status"]), self.cards.command([]),
                self.fx.command("ripples", []), self.fx.command("spotlight", []),
                f"zen {onoff(self.zen)}",
                f"font {common.FONT['name']}",
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
