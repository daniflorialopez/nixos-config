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
#   HUD        hold $mod+G and the monitor becomes an instrument panel: clock,
#              a day arc carrying today's focus history, gauges that are real
#              glass lenses (they bend a snapshot of the desktop behind them),
#              and every workspace as a scale map of its windows. Let go and
#              it is gone. $mod SHIFT+G pins it, and then the map takes clicks
#              and the number keys jump. This is "kill the bar" —
#   zen        — and zen (in the $mod+R menu) actually does it: waybar stops, cards
#              announce workspace changes instead, the HUD is a key-hold away.
#   cards      a film title card on every workspace switch: the number,
#              large, arriving from the direction you moved.
#   spotlight  (menu) the desktop dims and the focused window sits in a
#              pool of light that TRAVELS to wherever focus goes next.
#   ripples    a ring outward where a window opens, inward where one closes.
#   pulse      sound: the workspaces are a pentatonic scale, so moving through
#              them plays a phrase. fade: windows dim the longer they are
#              ignored and come straight back on focus.
#   undo       $mod SHIFT+T reopens the window you just closed, on its
#              workspace and (if it floated) in its place.
#   dream      (menu) a flow field of light drifts over the dimmed
#              desktop until a key is pressed. `dream auto on` starts it when
#              hypridle says you have gone.
#   strata     `reverie strata` renders a wallpaper from the last seven days
#              of git history — a ridge per day, as tall as the day was busy,
#              a star per commit — under a sky that follows the clock.
#
#   reverie hud show|hide|pin|glass on|off     reverie zen on|off|toggle
#   reverie cards|ripples on|off               reverie spotlight on|off|toggle
#   reverie pulse [sound|fade] on|off          reverie dream [auto on|off]
#   reverie undo · status · quit               reverie strata [--no-apply]
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
  # 2026-11-18, 97 binds):
  #   1. only keys whose WHOLE family is unused — G, T and R have no $mod,
  #      $mod SHIFT, $mod CTRL or $mod ALT bind anywhere;
  #   2. letters, not punctuation: they need no keycode workaround for the
  #      us/es layouts and sit on the Corne's base layer;
  #   3. a chord only for what needs one. Hold-to-glance needs a key; reopening
  #      a window is reflex. Modes (zen, spotlight, dream, the toggles) are
  #      chosen, not hit, so they live in one menu.
  #
  #   $mod+G         Glance — the HUD while held. A slip from $mod+H costs a
  #                  peek that ends when the key comes up.
  #   $mod SHIFT+G   the same panel, pinned as a switcher
  #   $mod SHIFT+T   reopen the closed window: $mod+W closes like a browser
  #                  tab, so its inverse is the browser's inverse
  #   $mod+R         the Reverie menu: every mode and toggle, with its state
  binds = [
    { mods = "$mod"; key = "G"; desc = "Glance - HUD while held"; cmd = "hud show"; }
    { mods = "$mod SHIFT"; key = "G"; desc = "Glance - pin the HUD as a switcher"; cmd = "hud pin"; }
    { mods = "$mod SHIFT"; key = "T"; desc = "Reopen the last closed window"; cmd = "undo"; }
    { mods = "$mod"; key = "R"; desc = "Reverie menu"; cmd = "menu"; }
  ];
  # Release half of hold-to-glance. If the modifier comes up before the key,
  # this never fires; the HUD lets itself out after 10 s (reverie/hud.py).
  # The keybinds palette skips release binds, so this adds no row there.
  releases = [
    { mods = "$mod"; key = "G"; desc = "Glance (release)"; cmd = "hud hide"; }
  ];

  # The Reverie menu: label, the status word that says whether it is on (or a
  # fixed hint), and what picking the row does.
  menuRows = [
    { label = "Spotlight"; state = "spotlight"; action = "spotlight toggle"; }
    { label = "Zen - no bar"; state = "zen"; action = "zen toggle"; }
    { label = "Title cards"; state = "cards"; action = "cards toggle"; }
    { label = "Ripples"; state = "ripples"; action = "ripples toggle"; }
    { label = "Sound"; state = "sound"; action = "pulse sound toggle"; }
    { label = "Fade idle windows"; state = "fade"; action = "pulse fade toggle"; }
    { label = "Glass lenses"; state = "glass"; action = "hud glass toggle"; }
    { label = "Font"; value = "font"; action = "font toggle"; }
    { label = "Dream when idle"; state = "dream auto"; action = "dream auto toggle"; }
    { label = "Dream"; hint = "now"; action = "dream"; }
    { label = "Strata wallpaper"; hint = "show"; action = "@strata"; }
    { label = "Own wallpaper"; hint = "restore"; action = "@wall"; }
    { label = "Demo"; hint = "30 s"; action = "@demo"; }
  ];
  menuLines = lib.concatMapStringsSep "\n" (
    r:
    if r ? state then
      ''printf '%-26s%s\n' ${lib.escapeShellArg r.label} "$(is ${lib.escapeShellArg r.state})"''
    else if r ? value then
      ''printf '%-26s%s\n' ${lib.escapeShellArg r.label} "$(val ${lib.escapeShellArg r.value})"''
    else
      ''printf '%-26s%s\n' ${lib.escapeShellArg r.label} ${lib.escapeShellArg r.hint}''
  ) menuRows;
  menuActions = lib.concatMapStringsSep " " (r: lib.escapeShellArg r.action) menuRows;

  layerRules = [
    # The HUD is glass like the rest of the chrome; the others draw their own
    # scrims. All of them animate themselves on springs, so the compositor's
    # layer animation would only fight them.
    "blur true, match:namespace reverie-hud"
    "ignore_alpha 0, match:namespace reverie-hud"
    "no_anim true, match:namespace reverie-hud"
    # The title card is an island too: blurred like the bar, and only where
    # it is drawn (everything around it is fully transparent).
    "blur true, match:namespace reverie-card"
    "ignore_alpha 0, match:namespace reverie-card"
    "no_anim true, match:namespace reverie-card"
    "no_anim true, match:namespace reverie-dream"
    "no_anim true, match:namespace reverie-fx"
  ];

  toBind = exe: b: "${b.mods}, ${b.key}, ${b.desc}, exec, ${exe} ${b.cmd}";

  # The runtime spelling: hyprctl does not expand the config's $mod.
  live = b: b // { mods = builtins.replaceStrings [ "$mod" ] [ "SUPER" ] b.mods; };
  tryLines = lib.concatStringsSep "\n" (
    map (b: ''hyprctl keyword bindd "${toBind "$self" (live b)}" >/dev/null'') binds
    ++ map (b: ''hyprctl keyword binddr "${toBind "$self" (live b)}" >/dev/null'') releases
    ++ map (r: ''hyprctl keyword layerrule "${r}" >/dev/null'') layerRules
  );
  untryLines = lib.concatMapStringsSep "\n" (
    b: ''hyprctl keyword unbind "${(live b).mods}, ${b.key}" >/dev/null''
  ) binds;

  reverie = pkgs.writeShellApplication {
    name = "reverie";
    # hyprctl, pw-play, playerctl, nvidia-smi, nmcli, awww and systemctl come
    # from the session PATH on purpose: each is optional at runtime (the
    # daemon checks) and naming them here would pin builds this host may not
    # use. grim is named because the glass HUD is built on it.
    runtimeInputs = [ python pkgs.socat pkgs.git pkgs.coreutils pkgs.grim pkgs.jq pkgs.util-linux ];
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
          exec python3 ${src}/main.py
          ;;

        strata)
          out="''${XDG_CACHE_HOME:-$HOME/.cache}/reverie/strata.png"
          mkdir -p "$(dirname "$out")"
          python3 ${src}/strata.py "$out.tmp.png" >/dev/null
          mv "$out.tmp.png" "$out"
          if [ "''${2:-}" != "--no-apply" ]; then
            # Shown, not recorded: ~/.local/state/wallpaper/current is left
            # alone, so `wall-apply` (or the next login) restores your pick.
            awww img "$out" --transition-type grow --transition-pos 0.78,0.72 \
              --transition-duration 1.4
          fi
          echo "$out"
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
          ${tryLines}
          echo "reverie is live for this session:"
          echo "  hold SUPER+G      glance: the HUD while held"
          echo "  SUPER+SHIFT+G     pin it (then 1-9 / click a window)"
          echo "  SUPER+SHIFT+T     reopen the last closed window"
          echo "  SUPER+R           menu: spotlight, zen, cards, sound, dream, strata, demo"
          echo "  $self untry       put it all back"
          ;;

        untry)
          ${untryLines}
          send quit || true
          ;;

        menu)
          # walker's dmenu, the way the keybinds palette uses it: -i prints the
          # index of the chosen row. walker comes from the session PATH.
          st="$(send status)"
          is() { if grep -q "$1 on" <<<"$st"; then echo on; else echo off; fi; }
          val() { sed -n "s/.*$1 \([a-z]*\).*/\1/p" <<<"$st"; }
          actions=(${menuActions})
          idx="$(
            {
              ${menuLines}
            } | walker -d -i -p 'Reverie' --theme dani-soft
          )" || exit 0
          case "$idx" in *[!0-9]* | "") exit 0 ;; esac
          action="''${actions[$idx]:-}"
          case "$action" in
            "") ;;
            @strata) "$self" strata >/dev/null ;;
            @wall) wall-apply ;;
            @demo) "$self" demo ;;
            *)
              read -ra words <<<"$action"
              send "''${words[@]}" >/dev/null
              ;;
          esac
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
            if command -v wall-apply >/dev/null; then wall-apply >/dev/null 2>&1 || true; fi
          }
          trap restore EXIT INT TERM

          echo "1/5  the HUD — clock, focus arc, glass gauges, workspace map"
          send hud show >/dev/null
          sleep 5
          send hud hide >/dev/null
          sleep 1

          echo "2/5  title cards and sound — three workspaces, three notes"
          send cards on >/dev/null
          send pulse sound on >/dev/null
          cur="$(hyprctl activeworkspace -j | jq -r .id)"
          sleep 1.2
          for ws in $((cur + 1)) $((cur + 2)) "$cur"; do
            hyprctl dispatch workspace "$ws" >/dev/null
            sleep 1.3
          done

          echo "3/5  spotlight — the light follows focus"
          send spotlight on >/dev/null
          sleep 4
          send spotlight off >/dev/null
          sleep 1

          echo "4/5  strata — this week's commits as a mountain range"
          "$self" strata >/dev/null
          sleep 6

          echo "5/5  dream — any key ends it"
          send dream >/dev/null
          sleep 7
          if hyprctl layers | grep -q reverie-dream; then send dream >/dev/null; fi
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
        Description = "reverie: HUD, title cards, spotlight, pulse, dream";
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

    # Opt-in: `systemctl --user start reverie-strata.timer`. Deliberately has
    # no WantedBy — a rebuild must not start replacing the wallpaper by itself.
    services.reverie-strata = {
      Unit.Description = "reverie: re-render the strata wallpaper";
      Service = {
        Type = "oneshot";
        ExecStart = "${lib.getExe reverie} strata";
      };
    };
    timers.reverie-strata = {
      Unit.Description = "reverie: keep the strata sky in step with the clock";
      Timer = {
        OnActiveSec = 0;
        OnUnitActiveSec = "20min";
      };
    };
  };

  # Presence. hypridle already runs (wm/hyprlock.nix) with no listeners; this
  # adds one that only TELLS the daemon you have gone and come back. It locks
  # nothing and dims nothing. The focus ledger stops counting while you are
  # away, and `dream auto on` uses the same signal.
  services.hypridle.settings.listener = [
    {
      timeout = 180;
      on-timeout = "reverie away";
      on-resume = "reverie back";
    }
  ];

  wayland.windowManager.hyprland.settings = {
    bindd = map (toBind "reverie") binds;
    binddr = map (toBind "reverie") releases;
    layerrule = layerRules;
  };
}
