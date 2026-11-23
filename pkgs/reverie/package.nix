# REVERIE — a second shell drawn by hand. EXPERIMENTAL, branch rice/reverie.
#
# This file is the program: `nix build .#reverie`, `nix run .#reverie -- try`.
# What turns it on for a desktop — the service, the keys, the layer rules — is
# the Home Manager module, home/dani/wm/reverie.nix.
#
# rice/overdrive asked "how loud can the compositor get". This asks the
# opposite question from docs/rice/concepts.md: what would the desktop look
# like if it were built for time, motion and attention instead of for a still
# screenshot — and it answers with surfaces the compositor cannot draw.
#
# One small Python daemon (./src, GTK4 + gtk4-layer-shell + cairo) owns
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
#              when on. It stays open while you flip them (src/menu.py).
#              Built with `glass` (pkgs/hyprglass), three of the tiles are
#              liquid glass: on/off and its look, where reverie only passes
#              the word on (src/glass.py), and what the HUD stands on.
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
#   under      with `glass`: a see-through window made fullscreen keeps the
#              glass it had (src/under.py); nothing to switch.
#
#   reverie hud show|hide|pin|hold|release     reverie zen on|off|toggle
#   reverie cards on|off|style <look>|next     reverie spotlight on|off|toggle
#   reverie ripples on|off                     reverie menu [show|hide]
#   reverie pulse [sound|fade] on|off          reverie undo · status · quit
#   reverie glass on|off|toggle|look <name>    (only when built with `glass`)
#   reverie hud look glass|wallpaper|desktop|next
#                    what the HUD stands on while glass is on (the HUD look
#                    tile): the plugin's glass of the wallpaper alone, the
#                    wallpaper darkened by the HUD itself, or the desktop out
#                    of focus as without glass
#   reverie demo     the whole thing in under a minute, then back to normal
#   reverie try      no rebuild needed: starts the daemon and registers the
#                    binds for this session only (`reverie untry` removes them)
#
# No new downloads: python3 + pygobject + pycairo + gtk4 + gtk4-layer-shell
# were all already in this machine's store (walker pulls in the GTK side), and
# every sound is synthesised from sines at first use. Springs, not beziers,
# drive all motion (src/common.py), so an interrupted animation turns
# around instead of snapping.
#
# Colours: only from theme/palette.nix, handed to Python as the same JSON the
# contrast gate checks. Blue is the accent; the single warm thing on the HUD
# is the sun, and a gauge only turns warm when it needs you.
{
  lib,
  runCommand,
  writeShellApplication,
  writeText,
  python3,
  socat,
  coreutils,
  grim,
  jq,
  util-linux,
  gtk4,
  pango,
  gdk-pixbuf,
  graphene,
  harfbuzz,
  gobject-introspection,
  glib,
  gtk4-layer-shell,
  # Not from nixpkgs: this repo's own design tokens (theme/palette.nix and
  # theme/metrics.nix), handed in by whoever calls this.
  theme,
  metrics,
  # The `glass` command, where liquid glass is installed; null where it is not.
  glass ? null,
  # ... and the windows it makes see-through, a regex on their class
  # (src/under.py lays glass under those when they are fullscreen).
  glassWindows ? null,
  # The file the chosen wallpaper is written to (wm/wall-apply.nix), where
  # there is one: watched, so that what is drawn from the wallpaper — the
  # HUD's backdrop, the glass under a fullscreen window — changes with it.
  wallpaperState ? null,
}:
let
  python = python3.withPackages (p: [
    p.pygobject3
    p.pycairo
  ]);

  # pygobject finds GTK through typelibs, and nothing in a plain Python
  # environment puts them on a search path. Listed by hand rather than via
  # wrapGAppsHook so the closure stays exactly "what was already here".
  typelibs = lib.makeSearchPath "lib/girepository-1.0" [
    gtk4
    pango.out
    gdk-pixbuf
    graphene
    harfbuzz
    gobject-introspection
    glib.out
    gtk4-layer-shell
  ];

  palette = writeText "reverie-palette.json" theme.json;

  # The program itself is Python (./src), and a shell wrapper round it. The
  # wrapper is shellchecked by `writeShellApplication`; this is what looks at
  # the Python. Every module is compiled, and then imported — with the same
  # typelibs and palette the daemon gets, no display, nothing running. A typo
  # in the daemon fails the build here, instead of showing as a service that
  # will not start on the rebuilt system.
  #
  # (unchecked-hash: the store resets every file's time, which would make an
  # ordinary .pyc look stale and be recompiled, in memory, at every start.)
  src = runCommand "reverie-src" { nativeBuildInputs = [ python ]; } ''
    cp -r ${./src} $out
    chmod -R u+w $out
    cd $out
    export HOME=$TMPDIR GI_TYPELIB_PATH=${typelibs} REVERIE_PALETTE=${palette}
    python3 -m compileall -q --invalidation-mode unchecked-hash .
    for module in *.py; do
      python3 -c "import ''${module%.py}"
    done
  '';

  # The keys and layer rules (./hyprland.nix), for `try` and `untry` below.
  hyprland = import ./hyprland.nix;
  inherit (hyprland)
    toBind
    binds
    holds
    releases
    layerRules
    ;

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
in
writeShellApplication {
  name = "reverie";
  # hyprctl, pw-play, playerctl, nvidia-smi, nmcli and systemctl come
  # from the session PATH on purpose: each is optional at runtime (the
  # daemon checks) and naming them here would pin builds this host may not
  # use. grim is named because the HUD's backdrop is built on it.
  runtimeInputs = [
    python
    socat
    coreutils
    grim
    jq
    util-linux
  ];
  text = ''
    export GI_TYPELIB_PATH="${typelibs}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
    export REVERIE_PALETTE="${palette}"
    # The HUD's chips are islands in the sense theme/metrics.nix defines
    # (0.85 bg, a 10% fg hairline, a floating rounded box), so they take the
    # island radius from there rather than restating 12.
    export REVERIE_ISLAND_RADIUS="${toString metrics.islandRadius}"
    ${lib.optionalString (glass != null) ''export REVERIE_GLASS="${lib.getExe glass}"''}
    ${lib.optionalString (
      glass != null && glassWindows != null
    ) "export REVERIE_GLASS_WINDOWS=${lib.escapeShellArg glassWindows}"}
    ${lib.optionalString (
      wallpaperState != null
    ) "export REVERIE_WALLPAPER_STATE=${lib.escapeShellArg wallpaperState}"}
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
        export LD_PRELOAD="${gtk4-layer-shell}/lib/libgtk4-layer-shell.so''${LD_PRELOAD:+:$LD_PRELOAD}"
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

  # For the module: the same keys and rules this was built with.
  passthru = { inherit hyprland; };

  meta = {
    description = "A second shell drawn by hand: HUD, title cards, spotlight, menu";
    platforms = lib.platforms.linux;
  };
}
