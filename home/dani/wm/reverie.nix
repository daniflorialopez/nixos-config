{ config, lib, pkgs, theme, ... }:

# REVERIE — a second shell drawn by hand. EXPERIMENTAL, branch rice/reverie.
#
# rice/overdrive asked "how loud can the compositor get". This asks the
# opposite question from docs/rice/concepts.md: what would the desktop look
# like if it were built for time, motion and attention instead of for a still
# screenshot — and it answers with surfaces the compositor cannot draw.
#
# One small Python daemon (./reverie, GTK4 + gtk4-layer-shell + cairo) owns
# five things. All of them are off or invisible until asked for:
#
#   HUD     hold $mod+` and the monitor becomes an instrument panel: clock, a
#           day arc with the sun on it, gauges, and every workspace drawn as a
#           scale map of its windows (lighter = touched more recently). Let go
#           and it is gone. $mod SHIFT+` pins it. This is "kill the bar".
#   cards   a film title card on every workspace switch — the number, large,
#           arriving from the direction you moved, and what lives there.
#   pulse   sound: the workspaces are a pentatonic scale, so moving through
#           them plays a phrase. fade: windows dim the longer they go ignored
#           and come straight back on focus.
#   undo    $mod CTRL+Z reopens the window you just closed, on its workspace
#           and (if it floated) in its place.
#   dream   $mod CTRL+D: the desktop dims and a flow field of light drifts
#           over it until you touch a key.
#
# and one that is not a surface at all:
#
#   strata  `reverie strata` renders a wallpaper from the last seven days of
#           git history — a ridge per day, as tall as the day was busy, a star
#           per commit — under a sky that follows the clock.
#
#   reverie hud show|hide|toggle      reverie pulse [sound|fade] on|off
#   reverie cards on|off              reverie undo · dream · status
#   reverie strata [--no-apply]       (wall-apply puts your own wallpaper back)
#
# No new downloads: python3 + pygobject + pycairo + gtk4 + gtk4-layer-shell
# were all already in this machine's store (walker pulls in the GTK side), and
# every sound is synthesised from sines at first use. Springs, not beziers,
# drive all motion (reverie/common.py) so an interrupted animation turns
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

  reverie = pkgs.writeShellApplication {
    name = "reverie";
    # hyprctl, pw-play, playerctl, nvidia-smi, nmcli and awww come from the
    # session PATH on purpose: each is optional at runtime (the daemon checks)
    # and naming them here would pin builds this host may not use.
    runtimeInputs = [ python pkgs.socat pkgs.git pkgs.coreutils ];
    text = ''
      export GI_TYPELIB_PATH="${typelibs}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
      export REVERIE_PALETTE="${palette}"
      sock="''${XDG_RUNTIME_DIR:-/tmp}/reverie.sock"

      case "''${1:-status}" in
        daemon)
          # gtk4-layer-shell has to be loaded before libwayland-client, or GTK
          # creates ordinary xdg toplevels and every overlay becomes a window.
          export LD_PRELOAD="${pkgs.gtk4-layer-shell}/lib/libgtk4-layer-shell.so''${LD_PRELOAD:+:$LD_PRELOAD}"
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
        *)
          if [ ! -S "$sock" ]; then
            echo "reverie: daemon is not running (systemctl --user start reverie)" >&2
            exit 1
          fi
          printf '%s\n' "$*" | socat - "UNIX-CONNECT:$sock"
          ;;
      esac
    '';
  };

  target = config.wayland.systemd.target;
in
{
  home.packages = [ reverie ];

  systemd.user.services.reverie = {
    Unit = {
      Description = "reverie: HUD, title cards, pulse, dream";
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

  # Opt-in: `systemctl --user start reverie-strata.timer`. Deliberately has no
  # WantedBy — a rebuild must not start replacing the wallpaper by itself.
  systemd.user.services.reverie-strata = {
    Unit.Description = "reverie: re-render the strata wallpaper";
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe reverie} strata";
    };
  };
  systemd.user.timers.reverie-strata = {
    Unit.Description = "reverie: keep the strata sky in step with the clock";
    Timer = {
      OnActiveSec = 0;
      OnUnitActiveSec = "20min";
    };
  };

  wayland.windowManager.hyprland.settings = {
    bindd = [
      "$mod, grave, Reverie HUD (hold), exec, reverie hud show"
      "$mod SHIFT, grave, Reverie HUD (pin), exec, reverie hud toggle"
      "$mod CTRL, Z, Reopen the last closed window, exec, reverie undo"
      "$mod CTRL, D, Reverie dream, exec, reverie dream"
    ];
    # Release half of hold-to-show. If the modifier comes up before the key,
    # this never fires; the HUD lets itself out after 10 s (reverie/hud.py).
    binddr = [
      "$mod, grave, Reverie HUD (release), exec, reverie hud hide"
    ];

    layerrule = [
      # The HUD is glass like the rest of the chrome; the others draw their
      # own scrims. All three animate themselves on springs, so the
      # compositor's layer animation would only fight them.
      "blur true, match:namespace reverie-hud"
      "ignore_alpha 0, match:namespace reverie-hud"
      "no_anim true, match:namespace reverie-hud"
      "no_anim true, match:namespace reverie-card"
      "no_anim true, match:namespace reverie-dream"
    ];
  };
}
