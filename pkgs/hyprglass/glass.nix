# `glass` — the switch for liquid glass, and the only thing that knows how it
# is switched.
#
# Glass is a choice made at the keyboard, not in the Nix config (ADR-005: such
# choices live in ~/.local/state/theme/). So this command keeps a two-field
# state there — on or off, and which look — and writes, next to it, one small
# file for each program that has to follow:
#
#   glass.conf   Hyprland sources it (wm/glass.nix). On, it declares the
#                plugin, so Hyprland itself loads it — at every start and on
#                every reload — and unloads it when the file is empty again.
#   glass.css    three backgrounds by name, solid as designed when off and
#                see-through when on: `bg_alpha`, the "island" of the bar
#                and the volume pill; `popup_bg`, the launcher's box; and
#                `confirm_bg`, the box of the power and capture menus.
#   glass.toml   Alacritty imports it: a see-through background when on.
#   glass.mako   mako includes it: a see-through notification when on, and
#                nothing when off, so that the colour it has without glass
#                is said in one place only, mako's own config.
#
#   glass on | off | toggle        glass look liquid|frosted|clear|next
#   glass status [json]            glass refresh   (rewrite the files; what
#                                  runs at every activation, see wm/glass.nix)
#
# Three things that are not in the plugin's README, found in a nested
# Hyprland, shape the on-file:
#
#   - Hyprland's own blur is painted behind every window and covers the glass
#     entirely, so blur is switched off per window. (Layers are different:
#     there the glass replaces the blur by itself.) Except a truly
#     fullscreen window: Hyprland draws no decorations for those, the glass
#     is one, and without either a see-through terminal is just a hole.
#     Where reverie runs it lays a sheet of real glass under such a window
#     (`fullscreen = "underlay"`: its namespace is listed and that is all);
#     anywhere else the window gets Hyprland's blur back ("blur").
#   - Glass shows only through what is transparent, and by design almost
#     nothing here is: hence the two other files.
#   - In real fullscreen Hyprland draws a window at `fullscreen_opacity`
#     (1.0 here), not at the opacity it has as a window (0.94). On a
#     see-through window that is a visible step: less of the glass comes
#     through its background and its text is brighter ("between full-screen
#     and normal mode there is a difference between the colour intensity",
#     Dani, 2026-11-23). So the windows named in `windows` keep, fullscreen,
#     the opacity they have as windows. Measured: the same spots of the
#     same terminal, windowed and fullscreen, are then within one step of
#     255 of each other; without the rule, up to four.
#   - A preset of our own, named in `default_preset`, earns a warning toast
#     at every load: the plugin checks the name before it has read the
#     definition. Redefining a setting of one of ITS presets under its own
#     name merges into it and passes the check, so the liquid look is the
#     plugin's `glass` with one value changed, not a new name.
#
# If it ever takes the session down: Hyprland comes back in safe mode, which
# loads no config and therefore no plugin. From there or from a TTY,
# `glass off`, then load the config again.
{
  lib,
  writeShellApplication,
  hyprland,
  jq,
  coreutils,
  systemd,
  hyprglass,
  # The island and the popup background, off and on (CSS colours), and how
  # solid the terminal's background is while glass is on.
  islandOff ? "rgba(26, 27, 38, 0.85)",
  islandOn ? "rgba(26, 27, 38, 0.30)",
  popupOff ? "rgba(22, 22, 30, 0.90)",
  popupOn ? "rgba(22, 22, 30, 0.60)",
  confirmOff ? "rgba(22, 22, 30, 0.97)",
  confirmOn ? "rgba(22, 22, 30, 0.70)",
  # A notification's background while glass is on (mako's #RRGGBBAA).
  notifyOn ? "#1a1b2699",
  # What a see-through window gets behind it in real fullscreen: "blur", or
  # "underlay" where something (reverie) puts a layer named
  # reverie-glass-under there for the plugin to make glass of.
  fullscreen ? "blur",
  terminalOpacity ? "0.65",
  # The see-through windows (a Hyprland regex on the class) and the opacity
  # Hyprland gives a focused window: together, the fullscreen rule above.
  windows ? null,
  windowOpacity ? null,
}:

writeShellApplication {
  name = "glass";
  runtimeInputs = [
    hyprland
    jq
    coreutils
    systemd
  ];
  text = ''
    plugin=${hyprglass}/lib/libhyprglass.so
    looks="liquid frosted clear"
    # Activation runs this from a system unit, which has no session variables.
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    dir="''${XDG_STATE_HOME:-$HOME/.local/state}/theme"
    state="$dir/glass.json"

    on=false
    look=liquid
    if [ -r "$state" ]; then
      on=$(jq -r 'if .on == true then "true" else "false" end' "$state" 2> /dev/null || echo false)
      look=$(jq -r '.look // "liquid"' "$state" 2> /dev/null || echo liquid)
    fi
    case " $looks " in *" $look "*) ;; *) look=liquid ;; esac

    # A look is a preset of the plugin's: its frosted and its plain plate as
    # they come, and its liquid one with the colour fringes turned down — at
    # full strength they put a rainbow on a palette that has no such hues.
    preset() {
      case "$look" in
        liquid) echo glass ;;
        frosted) echo subtle ;;
        clear) echo clear ;;
      esac
    }

    # Replace a file only when its content changes: the programs watching
    # these should not be woken for nothing. `changed` collects the names —
    # which is why nothing is ever PIPED into this: the receiving end of a
    # pipe is a subshell, and what it remembers is gone when it ends.
    changed=""
    put() {
      local tmp
      tmp=$(mktemp "$1.XXXXXX")
      cat > "$tmp"
      if cmp -s "$tmp" "$1"; then
        rm -f "$tmp"
      else
        mv -f "$tmp" "$1"
        changed="$changed ''${1##*/}"
      fi
    }

    write() {
      mkdir -p "$dir"
      put "$state" < <(jq -n --argjson on "$on" --arg look "$look" '{on: $on, look: $look}')
      if [ "$on" = true ]; then
        put "$dir/glass.conf" <<EOF
    # Liquid glass is ON. Written by \`glass\`; do not edit, it is rewritten.
    plugin = $plugin
    windowrule = no_blur true, match:class .*
    ${lib.optionalString (
      fullscreen == "blur"
    ) "windowrule = no_blur false, match:fullscreen_state_internal 2"}
    ${lib.optionalString (
      windows != null && windowOpacity != null
    ) "windowrule = opacity 1.0 1.0 ${windowOpacity}, match:class ${windows}"}
    # reverie's menu deck fades itself, by drawing fainter, and so has
    # no_anim. The glass behind it cannot follow that — it is whole wherever
    # the surface is not empty — and stayed as a dark box until the deck was
    # gone. On glass the deck leaves it to the compositor instead (its
    # src/menu.py), which fades glass and deck in together and, on the way
    # out, drops the glass first.
    layerrule = no_anim false, match:namespace reverie-menu
    layerrule = animation fade, match:namespace reverie-menu
    plugin:hyprglass {
        default_theme = dark
        default_preset = $(preset)
        preset = name:glass, chromatic_aberration:0.12
        # The glass of the panels that are read — the launcher, the menu
        # deck, a notification. Its own kind, whatever look is chosen for
        # the rest: darker, and always blurred, so that nothing behind runs
        # through the text.
        preset = name:menu, inherits:subtle, blur_strength:1.6, brightness:0.55, adaptive_dim:0.6
        # What reverie's HUD stands on when its look is "glass": the chosen
        # look itself, less the pale tint the plugin lays over its frosted
        # and its plain plate (13% of a blue-grey). Behind a window that is
        # the frost; behind a whole screen of thin type it is a grey veil,
        # and no darkening of the wallpaper underneath gets below it.
        preset = name:hud, inherits:$(preset), chromatic_aberration:0.12, tint_color:0x00000000
        layers {
            enabled = 1
            namespaces = waybar, swayosd, walker, notifications, reverie-menu, reverie-hud-glass${
              lib.optionalString (fullscreen == "underlay") ", reverie-glass-under"
            }
            namespace_presets = walker:menu, notifications:menu, reverie-menu:menu, reverie-hud-glass:hud
            # The launcher's box casts a shadow, and to the plugin a shadow
            # is something to put glass behind. The box is more solid than
            # its shadow ever gets; this is the line between the two (and
            # the same number Hyprland's own blur rule uses for it).
            namespace_mask_thresholds = walker=0.4
        }
    }
    EOF
        put "$dir/glass.css" <<EOF
    @define-color bg_alpha ${islandOn};
    @define-color popup_bg ${popupOn};
    @define-color confirm_bg ${confirmOn};
    EOF
        put "$dir/glass.toml" <<EOF
    [window]
    opacity = ${terminalOpacity}
    EOF
        put "$dir/glass.mako" <<EOF
    background-color=${notifyOn}
    EOF
      else
        put "$dir/glass.conf" <<< "# Liquid glass is off. Written by \`glass\`."
        put "$dir/glass.css" <<EOF
    @define-color bg_alpha ${islandOff};
    @define-color popup_bg ${popupOff};
    @define-color confirm_bg ${confirmOff};
    EOF
        put "$dir/glass.toml" <<< "# Liquid glass is off. Written by \`glass\`."
        put "$dir/glass.mako" <<< "# Liquid glass is off. Written by \`glass\`."
      fi
    }

    # The running session follows. Each step is allowed to find nobody home:
    # from a TTY there is no Hyprland, in zen there is no bar.
    hypr() {
      if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        hyprctl "$@" > /dev/null 2>&1 || true
      else
        for instance in $(hyprctl instances -j 2> /dev/null | jq -r '.[].instance' 2> /dev/null); do
          hyprctl -i "$instance" "$@" > /dev/null 2>&1 || true
        done
      fi
    }
    follow() {
      hypr reload config-only
      if [ "$on" = false ] && hyprctl plugin list 2> /dev/null | grep -q '^Plugin hyprglass '; then
        hypr plugin unload "$plugin"     # one loaded by hand, not by the file
      fi
      if systemctl --user is-active -q waybar.service 2> /dev/null; then
        systemctl --user reload waybar.service 2> /dev/null || true
      fi
      # mako reads its config again when told to, and keeps what it is
      # showing (a restart would drop it). What `makoctl reload` sends.
      busctl --user call org.freedesktop.Notifications /fr/emersion/Mako \
        fr.emersion.Mako Reload > /dev/null 2>&1 || true
      # These two read their stylesheet once, when they start.
      systemctl --user try-restart swayosd.service walker.service 2> /dev/null || true
    }

    case "''${1:-status}" in
      on | off | toggle)
        case "$1" in
          on) on=true ;;
          off) on=false ;;
          toggle) if [ "$on" = true ]; then on=false; else on=true; fi ;;
        esac
        write
        follow
        ;;
      look)
        want=''${2:-next}
        if [ "$want" = next ]; then
          # shellcheck disable=SC2086
          set -- $looks $looks
          while [ "$1" != "$look" ]; do shift; done
          want=$2
        fi
        case " $looks " in
          *" $want "*) look=$want ;;
          *) echo "glass: no look '$want' (there are: $looks)" >&2; exit 2 ;;
        esac
        write
        if [ "$on" = true ]; then hypr reload config-only; fi
        ;;
      refresh)
        write
        # A new generation can bring new rules (another surface, another
        # plugin path) while glass is on. Hyprland only reads them on a
        # reload, and nothing else is going to ask for one.
        case "$changed" in
          *glass.conf*) hypr reload config-only ;;
        esac
        exit 0
        ;;
      status)
        if [ "''${2:-}" = json ]; then
          jq -cn --argjson on "$on" --arg look "$look" '{on: $on, look: $look}'
          exit 0
        fi
        ;;
      *)
        echo "usage: glass on | off | toggle | look <$looks | next> | status [json] | refresh" >&2
        exit 2
        ;;
    esac
    if [ "$on" = true ]; then echo "glass on · look $look"; else echo "glass off · look $look"; fi
  '';

  meta = {
    description = "The switch for liquid glass (hyprglass): on, off, which look";
    platforms = lib.platforms.linux;
  };
}
