# `glass` — liquid glass as a trial: on by hand, gone at the next login.
#
# Nothing in the configuration loads the plugin (package.nix). This command
# loads it into the running Hyprland and sets up the three things without
# which it shows nothing, all of them runtime state that `glass off`, a
# logout or a reboot takes away again:
#
#   - Hyprland's own blur is painted behind every window and covers the
#     glass completely, so it is switched off per window (a rule for new
#     windows, the property on the ones already open). The bar, the
#     notifications and reverie keep their blur.
#   - Glass is only seen through what is transparent. The windows here are
#     88-94 % opaque, which leaves almost nothing to see through; so the
#     open Alacritty terminals get a see-through background (their text
#     stays solid) for as long as the trial is on.
#   - A preset. `glass` is the liquid one (refraction and colour fringes at
#     the edges), `subtle` and `default` are frosted, `clear` is a plain
#     transparent plate, `high_contrast` is dark and tinted.
#
#   nix run .#glass -- on [preset]     nix run .#glass -- preset <name>
#   nix run .#glass -- off             nix run .#glass -- status
#
# A plugin runs inside the compositor: if it crashes, the session goes with
# it. Save what is open before the first `on`.
{
  writeShellApplication,
  hyprland,
  jq,
  gnugrep,
  hyprglass,
}:

writeShellApplication {
  name = "glass";
  runtimeInputs = [
    hyprland
    jq
    gnugrep
  ];
  text = ''
    plugin=${hyprglass}/lib/libhyprglass.so
    presets="glass subtle default clear high_contrast"
    # How see-through the terminals' background is while the trial is on.
    opacity=''${GLASS_TERMINAL_OPACITY:-0.55}

    loaded() { hyprctl plugin list | grep -q '^Plugin hyprglass '; }

    # Every open window: Hyprland's blur off (1) or back to what the config
    # says (unset). Setting it also repaints the window, which a change of
    # preset alone does not always do.
    windows() {
      hyprctl clients -j | jq -r '.[].address' | while read -r address; do
        hyprctl dispatch setprop "address:$address" no_blur "$1" > /dev/null
      done
    }

    # Each Alacritty of this session listens on a socket of its own.
    terminals() {
      command -v alacritty > /dev/null || return 0
      for socket in "''${XDG_RUNTIME_DIR:-/run/user/$UID}/Alacritty-''${WAYLAND_DISPLAY:-none}-"*.sock; do
        [ -S "$socket" ] || continue
        alacritty msg -s "$socket" config -w -1 "$@" 2> /dev/null || true
      done
    }

    known() {
      case " $presets " in
        *" $1 "*) ;;
        *) echo "glass: no preset '$1' (there are: $presets)" >&2; exit 2 ;;
      esac
    }

    case "''${1:-status}" in
      on)
        preset=''${2:-glass}
        known "$preset"
        if ! loaded; then
          hyprctl plugin load "$plugin"
          loaded || { echo "glass: Hyprland did not take the plugin" >&2; exit 1; }
          # Loading re-reads the config, so the rule goes in after it.
          hyprctl keyword windowrule 'no_blur true, match:class .*' > /dev/null
        fi
        hyprctl keyword plugin:hyprglass:default_preset "$preset" > /dev/null
        windows 1
        terminals "window.opacity=$opacity"
        echo "glass on, preset $preset. Back to normal: glass off"
        ;;
      preset)
        known "''${2:?which preset? ($presets)}"
        loaded || { echo "glass: not on" >&2; exit 1; }
        hyprctl keyword plugin:hyprglass:default_preset "$2" > /dev/null
        windows 1
        ;;
      off)
        terminals --reset
        windows unset
        if loaded; then
          hyprctl plugin unload "$plugin"
        fi
        # Drops the runtime rule; the config itself knows nothing of glass.
        hyprctl reload > /dev/null
        echo "glass off"
        ;;
      status)
        if loaded; then
          echo "on, preset $(hyprctl -j getoption plugin:hyprglass:default_preset | jq -r .str)"
        else
          echo "off"
        fi
        ;;
      *)
        echo "usage: glass on [preset] | preset <name> | off | status   (presets: $presets)" >&2
        exit 2
        ;;
    esac
  '';

  meta.description = "Liquid glass (hyprglass) as a hand-loaded trial on the running Hyprland";
}
