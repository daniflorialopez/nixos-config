{ config, lib, pkgs, theme, metrics, ... }:

# REVERIE — a second shell drawn by hand. EXPERIMENTAL, branch rice/reverie.
#
# rice/overdrive asked "how loud can the compositor get". This asks the
# opposite question from docs/rice/concepts.md: what would the desktop look
# like if it were built for time, motion and attention instead of for a still
# screenshot — and it answers with surfaces the compositor cannot draw.
#
# One small Python daemon (./reverie, GTK4 + gtk4-layer-shell + cairo) owns
# all of it. Everything is off or invisible until asked for:
#
#   HUD        $mod+G and the monitor becomes an instrument panel: clock, a
#              day arc carrying today's focus history, gauges, everything the
#              bar shows, and every workspace as a scale map of its windows,
#              on the desktop itself thrown out of focus. Pinned like this
#              the map takes clicks and the number keys jump; $mod SHIFT+G
#              is the same panel only while held. This is "kill the bar" —
#   zen        — and zen (in the menu) actually does it: waybar stops, cards
#              announce workspace changes instead, the HUD is a key-hold away.
#   menu       $mod+R: a deck of tiles along the bottom, one per switch, lit
#              when on. It stays open while you flip them (reverie/menu.py).
#   cards      a film title card on every workspace switch: the number,
#              large, arriving from the direction you moved. Three looks
#              (bare, island, banner), switchable live.
#   spotlight  (menu) the desktop dims and the focused window sits in a
#              pool of light that TRAVELS to wherever focus goes next.
#   ripples    a ring outward where a window opens, inward where one closes.
#   pulse      sound: the workspaces are a pentatonic scale, so moving through
#              them plays a phrase. fade: windows dim the longer they are
#              ignored and come straight back on focus.
#   undo       $mod+U reopens the window you just closed, on its workspace
#              and (if it floated) in its place.
#
#   reverie hud show|hide|pin|hold|release     reverie zen on|off|toggle
#   reverie cards on|off|style <look>|next     reverie spotlight on|off|toggle
#   reverie ripples on|off                     reverie menu [show|hide]
#   reverie pulse [sound|fade] on|off          reverie undo · status · quit
#   reverie demo     the whole thing in under a minute, then back to normal
#   reverie try      no rebuild needed: starts the daemon and registers the
#                    binds for this session only (`reverie untry` removes them)
#
# No new downloads: python3 + pygobject + pycairo + gtk4 + gtk4-layer-shell
# were all already in this machine's store (walker pulls in the GTK side), and
# every sound is synthesised from sines at first use. Springs, not beziers,
# drive all motion (reverie/common.py), so an interrupted animation turns
# around instead of snapping.
#
# Colours: only from theme/palette.nix, handed to Python as the same JSON the
# contrast gate checks. Blue is the accent; the single warm thing on the HUD
# is the sun, and a gauge only turns warm when it needs you.
let
  python = pkgs.python3.withPackages (p: [ p.pygobject3 p.pycairo ]);

  # pygobject finds GTK through typelibs, and nothing in a plain Python
  # environment puts them on a search path. Listed by hand rather than via
  # wrapGAppsHook so the closure stays exactly "what was already here".
  typelibs = lib.makeSearchPath "lib/girepository-1.0" [
    pkgs.gtk4
    pkgs.pango.out
    pkgs.gdk-pixbuf
    pkgs.graphene
    pkgs.harfbuzz
    pkgs.gobject-introspection
    pkgs.glib.out
    pkgs.gtk4-layer-shell
  ];

  palette = pkgs.writeText "reverie-palette.json" theme.json;

  src = ./reverie;

  # Keys. One list, two consumers: the declared Hyprland config below, and
  # `reverie try`, which registers the same binds at runtime so the branch can
  # be lived in before anything is rebuilt.
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
  ];

  toBind = b: "${b.mods}, ${b.key}, ${b.desc}, event, reverie ${b.cmd}";

  # The runtime spelling: hyprctl does not expand the config's $mod.
  live = b: b // { mods = builtins.replaceStrings [ "$mod" ] [ "SUPER" ] b.mods; };
  tryLines = lib.concatStringsSep "\n" (
    map (b: ''hyprctl keyword bindd "${toBind (live b)}" >/dev/null'') binds
    ++ map (b: ''hyprctl keyword bindde "${toBind (live b)}" >/dev/null'') holds
    ++ map (b: ''hyprctl keyword binddr "${toBind (live b)}" >/dev/null'') releases
    ++ map (r: ''hyprctl keyword layerrule "${r}" >/dev/null'') layerRules
  );
  untryLines = lib.concatMapStringsSep "\n" (
    b: ''hyprctl keyword unbind "${(live b).mods}, ${b.key}" >/dev/null''
  ) (binds ++ holds);

  reverie = pkgs.writeShellApplication {
    name = "reverie";
    # hyprctl, pw-play, playerctl, nvidia-smi, nmcli and systemctl come
    # from the session PATH on purpose: each is optional at runtime (the
    # daemon checks) and naming them here would pin builds this host may not
    # use. grim is named because the HUD's backdrop is built on it.
    runtimeInputs = [ python pkgs.socat pkgs.coreutils pkgs.grim pkgs.jq pkgs.util-linux ];
    text = ''
      export GI_TYPELIB_PATH="${typelibs}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
      export REVERIE_PALETTE="${palette}"
      # The HUD's chips are islands in the sense theme/metrics.nix defines
      # (0.85 bg, a 10% fg hairline, a floating rounded box), so they take the
      # island radius from there rather than restating 12.
      export REVERIE_ISLAND_RADIUS="${toString metrics.islandRadius}"
      sock="''${XDG_RUNTIME_DIR:-/tmp}/reverie.sock"
      self="$(readlink -f "$0")"

      send() {
        if [ ! -S "$sock" ]; then
          echo "reverie: daemon is not running — 'systemctl --user start reverie', or 'reverie try'" >&2
          return 1
        fi
        printf '%s\n' "$*" | socat - "UNIX-CONNECT:$sock"
      }

      case "''${1:-status}" in
        daemon)
          # gtk4-layer-shell has to be loaded before libwayland-client, or GTK
          # creates ordinary xdg toplevels and every overlay becomes a window.
          export LD_PRELOAD="${pkgs.gtk4-layer-shell}/lib/libgtk4-layer-shell.so''${LD_PRELOAD:+:$LD_PRELOAD}"
          # GTK's software renderer, on purpose. Every surface here is drawn
          # with cairo anyway, so the GPU renderer only added a texture upload
          # per frame and a GL/Vulkan context to a process that is idle 99% of
          # the day. Measured on legionix (NVIDIA): resident memory 323 MB ->
          # ~100 MB idle, and every animated mode got cheaper, not dearer.
          export GSK_RENDERER="''${GSK_RENDERER:-cairo}"
          # So the menu's Demo tile can start `reverie demo` without a PATH.
          export REVERIE_BIN="$self"
          exec python3 ${src}/main.py
          ;;

        try)
          # Live in the branch without rebuilding: this session only. A
          # Hyprland reload or a logout forgets the binds; `untry` removes
          # them and stops the daemon.
          if [ ! -S "$sock" ]; then
            setsid -f "$self" daemon >/dev/null 2>&1
            for _ in $(seq 50); do
              if [ -S "$sock" ]; then break; fi
              sleep 0.1
            done
          fi
          # Unbind first: hyprctl adds a bind every time it is told to, and
          # two copies of a toggle cancel each other out. This makes `try`
          # safe to run again (after a Hyprland reload dropped the binds, or
          # just to be sure).
          ${untryLines}
          ${tryLines}
          echo "reverie is live for this session:"
          echo "  SUPER+G           the HUD, pinned (then 1…0 / click a window)"
          echo "  hold SUPER+SHIFT+G  glance: the HUD only while held"
          echo "  SUPER+U           undo close: reopen the last closed window"
          echo "  SUPER+R           the menu: every switch, and it stays open"
          echo "  $self untry       put it all back"
          ;;

        untry)
          ${untryLines}
          send quit || true
          ;;

        demo)
          before="$(send status)"
          was() { grep -q "$1 on" <<<"$before"; }
          restore() {
            trap - EXIT INT TERM
            send hud hide >/dev/null || true
            send spotlight off >/dev/null || true
            if ! was sound; then send pulse sound off >/dev/null || true; fi
            if ! was cards; then send cards off >/dev/null || true; fi
            if ! was ripples; then send ripples off >/dev/null || true; fi
          }
          trap restore EXIT INT TERM

          echo "1/3  the HUD — clock, focus arc, gauges, the bar's modules, workspace map"
          send hud show >/dev/null
          sleep 5
          send hud hide >/dev/null
          sleep 1

          echo "2/3  title cards and sound — three workspaces, three notes"
          send cards on >/dev/null
          send pulse sound on >/dev/null
          cur="$(hyprctl activeworkspace -j | jq -r .id)"
          sleep 1.2
          for ws in $((cur + 1)) $((cur + 2)) "$cur"; do
            hyprctl dispatch workspace "$ws" >/dev/null
            sleep 1.3
          done

          echo "3/3  spotlight — the light follows focus"
          send spotlight on >/dev/null
          sleep 4
          send spotlight off >/dev/null
          sleep 1
          restore
          echo "done — everything is back as it was"
          ;;

        *)
          send "$@"
          ;;
      esac
    '';
  };

  target = config.wayland.systemd.target;
in
{
  home.packages = [ reverie ];

  systemd.user = {
    services.reverie = {
      Unit = {
        Description = "reverie: HUD, title cards, spotlight, pulse";
        PartOf = [ target ];
        After = [ target ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };
      Service = {
        ExecStart = "${lib.getExe reverie} daemon";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ target ];
    };
  };

  # Presence. hypridle already runs (wm/hyprlock.nix) with no listeners; this
  # adds one that only TELLS the daemon you have gone and come back. It locks
  # nothing and dims nothing: the focus ledger stops counting while you are
  # away, so an empty chair is not booked as an hour in the terminal.
  services.hypridle.settings.listener = [
    {
      timeout = 180;
      on-timeout = "reverie away";
      on-resume = "reverie back";
    }
  ];

  wayland.windowManager.hyprland.settings = {
    bindd = map toBind binds;
    bindde = map toBind holds;
    binddr = map toBind releases;
    layerrule = layerRules;
  };
}
