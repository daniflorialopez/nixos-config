"""glass: the menu's two tiles for liquid glass.

Reverie does not do glass. A Hyprland plugin does, and the `glass` command
(pkgs/hyprglass) is the one thing that knows how to switch it: it keeps the
choice in ~/.local/state/theme/glass.json and makes the compositor, the bar
and the terminal follow. All this does is put that command on two tiles —
which is why they are only there when the package was built with it
(REVERIE_GLASS, see package.nix).

The command takes a moment (it reloads Hyprland's config), so the tile does
not wait for it: the new state is assumed and drawn at once, and the command
runs behind it. One at a time, in order — two of them writing the state
together would leave whichever finished last.
"""

import json
import os
import subprocess

BIN = os.environ.get("REVERIE_GLASS")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                     "theme", "glass.json")
LOOKS = ("liquid", "frosted", "clear")       # the command's own list, in its order


class Glass:
    def __init__(self):
        self.on = False
        self.look = LOOKS[0]
        self.child = None
        self.reload()

    def reload(self):
        """What the command last wrote; it may have been run by hand."""
        if self.child is not None and self.child.poll() is None:
            return                       # ours is still writing: what we assumed stands
        try:
            with open(STATE) as f:
                state = json.load(f)
        except (OSError, ValueError):
            return
        self.on = state.get("on") is True
        if state.get("look") in LOOKS:
            self.look = state["look"]

    def run(self, *words):
        if self.child is not None:
            try:
                self.child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        try:
            self.child = subprocess.Popen([BIN, *words], stdout=subprocess.DEVNULL,
                                          stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError:
            self.child = None

    def command(self, words):
        if not BIN:
            return "glass: not part of this build"
        what = words[0] if words else "status"
        if what in ("on", "off", "toggle"):
            self.on = not self.on if what == "toggle" else what == "on"
            self.run("on" if self.on else "off")
        elif what == "look":
            want = words[1] if len(words) > 1 else "next"
            if want == "next":
                want = LOOKS[(LOOKS.index(self.look) + 1) % len(LOOKS)]
            if want not in LOOKS:
                return f"glass: no look {want!r} (there are: {' '.join(LOOKS)})"
            self.look = want
            self.run("look", want)
        else:
            self.reload()
        return f"glass {'on' if self.on else 'off'} · look {self.look}"
