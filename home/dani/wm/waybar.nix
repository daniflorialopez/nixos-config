{ pkgs, ... }:
let
  kbLayoutScript = pkgs.writeShellApplication {
    name = "waybar-kblayout";
    runtimeInputs = [ pkgs.hyprland pkgs.jq ];
    text = ''
      data="$(hyprctl -j devices)"

      keymap="$(
        printf '%s' "$data" \
          | jq -r '
              .keyboards[]
              | select(.name == "keyd-virtual-keyboard")
              | .active_keymap
            ' \
          | head -n1
      )"

      [ -n "$keymap" ] || keymap="$(
        printf '%s' "$data" \
          | jq -r '
              .keyboards[]
              | select(.name == "at-translated-set-2-keyboard")
              | .active_keymap
            ' \
          | head -n1
      )"

      [ -n "$keymap" ] || keymap="$(
        printf '%s' "$data" \
          | jq -r '.keyboards[0].active_keymap // empty'
      )"

      case "$keymap" in
        "English (US)"|"English")
          short="US"
          class="us"
          ;;
        "Spanish"|"Spanish; Castilian"|"Spanish (Latin American)")
          short="ES"
          class="es"
          ;;
        "")
          short="??"
          class="unknown"
          keymap="No keyboard layout found"
          ;;
        *)
          short="$keymap"
          class="unknown"
          ;;
      esac

      printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
        "$short" "$keymap" "$class"
    '';
  };

  kbCycleScript = pkgs.writeShellApplication {
    name = "waybar-kblayout-next";
    runtimeInputs = [ pkgs.hyprland ];
    text = ''
      hyprctl switchxkblayout keyd-virtual-keyboard next
    '';
  };
in
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 32;
      spacing = 0;

      modules-left = [
        "hyprland/workspaces"
      ];

      modules-center = [
        "clock"
      ];

      modules-right = [
        "custom/kblayout"
        "network"
        "pulseaudio"
        "battery"
      ];

      "hyprland/workspaces" = {
        format = "{id}";
        sort-by = "number";
        disable-scroll = true;
        all-outputs = false;
        move-to-monitor = true;

        persistent-workspaces = {
          "*" = [ 1 2 3 4 5 ];
        };
      };

      clock = {
        format = "{:%A  %H:%M}";
        tooltip-format = "<big>{:%A, %d %B %Y}</big>";
      };

      "custom/kblayout" = {
        exec = "${kbLayoutScript}/bin/waybar-kblayout";
        return-type = "json";
        interval = 1;
        format = "{}";
        on-click = "${kbCycleScript}/bin/waybar-kblayout-next";
      };

      network = {
        format-wifi = "󰖩  {essid}";
        format-ethernet = "󰈀  wired";
        format-disconnected = "󰖪  offline";
        tooltip-format = "{ifname} · {ipaddr}";
      };

      pulseaudio = {
        format = "{icon} {volume}%";
        format-muted = "󰖁  mute";
        format-icons = {
          default = [ "󰕿" "󰖀" "󰕾" ];
        };
        scroll-step = 5;
        on-click = "pavucontrol";
      };

      battery = {
        states = {
          warning = 30;
          critical = 15;
        };
        format = "{icon} {capacity}%";
        format-charging = "󰂄 {capacity}%";
        format-plugged = "󰂄 {capacity}%";
        format-icons = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
      };

    };

    style = ''
      * {
        border: none;
        border-radius: 0;
        min-height: 0;
        font-family: "JetBrainsMono Nerd Font", "Symbols Nerd Font", sans-serif;
        font-size: 13px;
      }

      window#waybar {
        background: rgba(16, 18, 22, 0.94);
        color: #d7dce2;
        border-bottom: 1px solid rgba(215, 220, 226, 0.08);
      }

      tooltip {
        background: #111318;
        color: #e6ebf2;
        border: 1px solid rgba(230, 235, 242, 0.10);
      }

      #workspaces {
        margin-left: 10px;
      }

      #workspaces button {
        background: transparent;
        color: #7d8594;
        padding: 0 10px;
        margin: 0 6px 0 0;
        border-bottom: 2px solid transparent;
      }

      #workspaces button:hover {
        background: rgba(255, 255, 255, 0.04);
        color: #e6ebf2;
        box-shadow: none;
      }

      #workspaces button.active {
        color: #f8fafc;
        border-bottom: 2px solid #98a2b3;
      }

      #clock,
      #custom-kblayout,
      #network,
      #pulseaudio,
      #battery {
        background: transparent;
        color: #cfd6df;
        padding: 0 10px;
        margin: 0;
      }

      #clock {
        color: #f4f7fb;
        font-weight: 600;
        letter-spacing: 0.2px;
      }

      #custom-kblayout {
        min-width: 26px;
        color: #b9c2cd;
        font-weight: 700;
      }

      #network,
      #pulseaudio,
      #battery {
        color: #c7ced8;
      }

      #battery.warning {
        color: #d8b56d;
      }

      #battery.critical {
        color: #d17c88;
      }

      .modules-right {
        margin-right: 10px;
      }
    '';
  };
}
