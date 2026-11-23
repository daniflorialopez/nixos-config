# What reverie asks of Hyprland: its keys, and the rules for its surfaces.
#
# One list, two consumers. The Home Manager module (home/dani/wm/reverie.nix)
# declares them in the Hyprland config; `reverie try` (package.nix) registers
# the same ones at runtime, so the program can be lived in before anything is
# rebuilt. Plain data in a file of its own, so that neither has to reach into
# the other and the two cannot drift apart.
{
  # Keys.
  #
  # The first attempt at these collided with the existing scheme without
  # duplicating a single chord, which is why "is the exact chord free?" was
  # the wrong check. In wm/hyprland.nix a key is a FAMILY: $mod, $mod SHIFT
  # and $mod CTRL of one key are siblings (three Firefox profiles on B,
  # dismiss / dismiss-all / restore on the ' key). $mod CTRL+S, +D and +Z
  # therefore squatted in the Scratchpads/Capture, colour-picker and
  # keyboard-layout families; ` sat between Lock ($mod+Escape) and workspace
  # 1; and zen — a lasting change — was one modifier-slip from the
  # $mod CTRL+H/J/K/L resize keys.
  #
  # The rules now, checked against the live table (`hyprctl binds -j`,
  # 2026-11-18):
  #   1. only keys whose WHOLE family is unused — G, U and R have no $mod,
  #      $mod SHIFT, $mod CTRL or $mod ALT bind anywhere;
  #   2. letters, not punctuation: they need no keycode workaround for the
  #      us/es layouts and sit on the Corne's base layer;
  #   3. a chord only for what needs one. The HUD and reopening a window are
  #      reflexes. Modes (zen, spotlight, the toggles) are chosen, not hit,
  #      so they live in one menu.
  #
  #   $mod+G         the HUD, pinned as a switcher. The plain chord, because
  #                  pinning turned out to be the common case (second review).
  #   $mod SHIFT+G   glance: the same panel only while held
  #   $mod+U         Undo close: the window that was just closed comes back.
  #                  It was $mod SHIFT+T, the browser's chord for the same
  #                  thing, which Dani found "not the most mnemonic-friendly".
  #                  $mod SHIFT+W would be the textbook inverse of $mod+W, but
  #                  that is WhatsApp; U had no bind in any family.
  #   $mod+R         the Reverie menu: every mode and toggle, with its state
  #
  # None of these exec anything. `event` makes Hyprland say the words on its
  # event socket, where the daemon is already listening (reverie/main.py):
  # no fork per keypress, and presses and releases cannot overtake each other.
  binds = [
    { mods = "$mod"; key = "G"; desc = "Glance - pin the HUD as a switcher"; cmd = "hud pin"; }
    { mods = "$mod"; key = "U"; desc = "Undo close - reopen the last closed window"; cmd = "undo"; }
    { mods = "$mod"; key = "R"; desc = "Reverie menu"; cmd = "menu"; }
  ];
  # Hold-to-glance. The press repeats (binde) so the daemon can tell the chord
  # is still down; why it needs to is in reverie/hud.py, `hold`.
  holds = [
    { mods = "$mod SHIFT"; key = "G"; desc = "Glance - the HUD only while held"; cmd = "hud hold"; }
  ];
  # ... and its release, which only ever fires when G is the first of the
  # three keys to come up: once any other key of the chord is released,
  # Hyprland shadows the binds on the keys still held (pressed for real and
  # watched, every order — see reverie/hud.py, `hold`). The other orders are
  # the heartbeat's job. `hud release` ends a HELD panel only. The keybinds
  # palette skips release binds.
  releases = [
    { mods = "$mod SHIFT"; key = "G"; desc = "Glance (release)"; cmd = "hud release"; }
  ];

  layerRules = [
    # The HUD paints its own backdrop (a blurred capture); the compositor's
    # blur under it only matters for the fraction of a second it is fading
    # in. Every surface animates itself on springs, so the compositor's layer
    # animation would only fight them.
    "blur true, match:namespace reverie-hud"
    "ignore_alpha 0, match:namespace reverie-hud"
    "no_anim true, match:namespace reverie-hud"
    # The title card is an island too: blurred like the bar, and only where
    # it is drawn (everything around it is fully transparent).
    "blur true, match:namespace reverie-card"
    "ignore_alpha 0, match:namespace reverie-card"
    "no_anim true, match:namespace reverie-card"
    # The bare title card: no blur on purpose (see reverie/cards.py).
    "no_anim true, match:namespace reverie-title"
    # The menu deck: an island again.
    "blur true, match:namespace reverie-menu"
    "ignore_alpha 0, match:namespace reverie-menu"
    "no_anim true, match:namespace reverie-menu"
    "no_anim true, match:namespace reverie-fx"
    # The sheet of glass under a fullscreen window (src/under.py). It covers
    # the monitor, so the layers' usual pop-in would be the whole wallpaper
    # growing; it fades, and the plugin's glass fades with it.
    "animation fade, match:namespace reverie-glass-under"
  ];

  # How a bind is spelt in the Hyprland config.
  toBind = b: "${b.mods}, ${b.key}, ${b.desc}, event, reverie ${b.cmd}";
}
