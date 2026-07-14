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

      printf '{"text":"   %s","tooltip":"%s","class":"%s"}\n' \
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

  btToggleScript = pkgs.writeShellApplication {
    name = "waybar-bt-toggle";
    runtimeInputs = [ pkgs.bluez pkgs.util-linux ];
    text = ''
      if bluetoothctl show | grep -q "Powered: yes"; then
        bluetoothctl power off
      else
        # The ideapad platform driver soft-blocks the adapter; clear it
        # before powering on (a seated user may write /dev/rfkill via uaccess)
        rfkill unblock bluetooth
        bluetoothctl power on
      fi
    '';
  };
in
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings.mainBar = {
      layer = "top";
      mode = "dock";
      exclusive = true;
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
        "bluetooth"
        "network"
        "pulseaudio"
        "battery"
      ];

      "hyprland/workspaces" = {
        format = "{id}";
        sort-by = "number";
        disable-scroll = true;
        all-outputs = false;
        move-to-monitor = false;

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

      bluetooth = {
        format = "󰂯";
        format-disabled = "󰂲";
        format-off = "󰂲";
        format-connected = "󰂱 {num_connections}";
        tooltip-format = "{controller_alias}\t{status}";
        tooltip-format-connected = "{controller_alias}\t{status}\n\n{device_enumerate}";
        tooltip-format-enumerate-connected = "{device_alias}";
        tooltip-format-enumerate-connected-battery = "{device_alias}\t{device_battery_percentage}%";
        on-click = "${btToggleScript}/bin/waybar-bt-toggle";
        on-click-right = "blueman-manager";
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
        font-family: "JetBrainsMono Nerd Font"; 
        font-size: 13px;
        font-weight: 500;
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

      #workspaces button.persistent:not(.empty) {
        color: #f8fafc;
      }

      #clock,
      #custom-kblayout,
      #bluetooth,
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
        letter-spacing: 0.2px;
      }

      #custom-kblayout {
        min-width: 26px;
        color: #b9c2cd;
      }

      #network,
      #pulseaudio,
      #battery {
        color: #c7ced8;
      }

      #bluetooth {
        color: #c7ced8;
      }

      #bluetooth.off,
      #bluetooth.disabled {
        color: #7d8594;
      }

      #bluetooth.connected {
        color: #f8fafc;
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
