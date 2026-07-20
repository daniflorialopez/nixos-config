# home/dani/wm/waybar.nix
#
# Form change: full-width dock -> three floating glass islands
# (left / center / right). Everything else follows the existing design
# system: Tokyo Night via palette.css, radius 12 (= window rounding),
# side margins 12 (= gaps_out), blue accent (the sunset gradient stays
# on window borders), orange #ff9e64 as the attention tier. The
# `blur, waybar` + `ignorezero, waybar` layerrules already in
# hyprland.nix do the rest: the islands get glass, the space between
# them stays clear.
#
# New modules, all "silent when healthy":
#   - custom/backup:    invisible unless ~/BACKUP-FAILED.txt has content,
#                       then a red pill. Click opens the log, right-click
#                       acknowledges (truncates) it.
#   - custom/tailscale: invisible while up; dim icon when down (backups
#                       at 20:00 depend on the tailnet, so down = actionable).
#   - custom/gpu:       NVIDIA temp on legionix; self-hides on danix-hp/VM.
#   - mpris:            appears only while something plays (playerctl).
#   - hyprland/window:  muted title next to the workspaces for context.
#   - tray:             invisible while empty.

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

      printf '{"text":"   %s","tooltip":"%s","class":"%s"}\n' \
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

  # restic.nix appends a line here on every failed backup
  backupSentinel = pkgs.writeShellApplication {
    name = "waybar-backup-health";
    runtimeInputs = [ pkgs.coreutils pkgs.gnused ];
    text = ''
      f="$HOME/BACKUP-FAILED.txt"
      if [ -s "$f" ]; then
        n="$(wc -l < "$f" | tr -d ' ')"
        last="$(tail -n1 "$f" | sed 's/"/\\"/g')"
        printf '{"text":"󰁯  backup failed","class":"failed","tooltip":"%s failure(s) logged\\nlast: %s\\n\\nclick: open log · right-click: acknowledge"}\n' \
          "$n" "$last"
      else
        # empty text = module invisible; the bar is quiet while backups work
        printf '{"text":"","tooltip":""}\n'
      fi
    '';
  };

  # Backups go rest:https over the tailnet, so tailscale being down is
  # actionable -> only then does the module appear
  tailscaleStatus = pkgs.writeShellApplication {
    name = "waybar-tailscale";
    runtimeInputs = [ pkgs.tailscale pkgs.jq ];
    text = ''
      state="$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "NoDaemon"')" || state="NoDaemon"
      if [ "$state" = "Running" ]; then
        printf '{"text":"","tooltip":""}\n'
      else
        printf '{"text":"󰦞","class":"down","tooltip":"tailscale: %s"}\n' "$state"
      fi
    '';
  };

  # Self-hides on hosts without the NVIDIA driver (danix-hp, danixos-vm)
  gpuStatus = pkgs.writeShellApplication {
    name = "waybar-gpu";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      export PATH="$PATH:/run/current-system/sw/bin"
      if ! command -v nvidia-smi >/dev/null 2>&1; then
        printf '{"text":"","tooltip":""}\n'
        exit 0
      fi
      out="$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null)" || {
        printf '{"text":"","tooltip":""}\n'
        exit 0
      }
      temp="$(printf '%s' "$out" | cut -d, -f1 | tr -d ' ')"
      util="$(printf '%s' "$out" | cut -d, -f2 | tr -d ' ')"
      mem="$(printf '%s'  "$out" | cut -d, -f3 | tr -d ' ')"
      class="ok"
      [ "$temp" -ge 80 ] && class="hot"
      printf '{"text":"󰾲 %s°","class":"%s","tooltip":"GPU %s%% · %s MiB VRAM"}\n' \
        "$temp" "$class" "$util" "$mem"
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
      height = 34;
      spacing = 0;
      # islands align with gaps_out = 12; a touch tighter on top
      margin-top = 8;
      margin-left = 12;
      margin-right = 12;

      modules-left = [
        "hyprland/workspaces"
        "hyprland/window"
      ];

      modules-center = [
        "clock"
      ];

      modules-right = [
        "custom/backup"
        "custom/tailscale"
        "mpris"
        "custom/gpu"
        "custom/kblayout"
        "bluetooth"
        "network"
        "pulseaudio"
        "battery"
        "tray"
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

      "hyprland/window" = {
        format = "{title}";
        max-length = 44;
        separate-outputs = true;   # each bar shows its own monitor's window
        rewrite = {
          "(.*) — Mozilla Firefox" = "󰈹  $1";
          "(.*) - Obsidian .*" = "󰎚  $1";
        };
      };

      clock = {
        format = "{:%A  %H:%M}";
        # same date wording as hyprlock / the SDDM greeter
        format-alt = "{:%A %-d %B  ·  %H:%M}";
        tooltip-format = "<tt>{calendar}</tt>";
        calendar = {
          mode = "month";
          format = {
            today = "<span color='#7aa2f7'><b>{}</b></span>";
            weekdays = "<span color='#565f89'>{}</span>";
            months = "<span color='#c0caf5'><b>{}</b></span>";
          };
        };
      };

      "custom/backup" = {
        exec = "${backupSentinel}/bin/waybar-backup-health";
        return-type = "json";
        interval = 60;
        format = "{}";
        on-click = "alacritty -e less +G $HOME/BACKUP-FAILED.txt";
        on-click-right = "truncate -s 0 $HOME/BACKUP-FAILED.txt";
      };

      "custom/tailscale" = {
        exec = "${tailscaleStatus}/bin/waybar-tailscale";
        return-type = "json";
        interval = 30;
        format = "{}";
      };

      mpris = {
        format = "{status_icon}  {artist} · {title}";
        format-paused = "{status_icon}  {artist} · {title}";
        status-icons = { playing = "󰝚"; paused = "󰏤"; };
        max-length = 36;
        on-click = "playerctl play-pause";
        on-scroll-up = "playerctl next";
        on-scroll-down = "playerctl previous";
      };

      "custom/gpu" = {
        exec = "${gpuStatus}/bin/waybar-gpu";
        return-type = "json";
        interval = 10;
        format = "{}";
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
        tooltip-format = "{timeTo} · {power:.1f} W";
      };

      tray = {
        spacing = 8;
        icon-size = 16;
      };
    };

    style = ''
      @import "palette.css";

      * {
        border: none;
        border-radius: 0;
        min-height: 0;
        font-family: "CaskaydiaMono Nerd Font";
        font-size: 13px;
        font-weight: 500;
      }

      /* Floating islands: the window itself is fully transparent; the
         layerrule pair (blur + ignorezero) keeps blur on the islands only */
      window#waybar {
        background: transparent;
        color: @subtle;
      }

      .modules-left,
      .modules-center,
      .modules-right {
        background: @bg_alpha;
        border: 1px solid @border;
        border-radius: 12px;   /* = decoration.rounding */
        padding: 0 8px;
      }

      tooltip {
        background: @bg;
        color: @fg;
        border: 1px solid @border;
        border-radius: 12px;
      }

      #workspaces button {
        background: transparent;
        color: @muted;
        padding: 0 9px;
        margin: 4px 2px;
        border-radius: 8px;
      }

      #workspaces button:hover {
        background: alpha(@fg, 0.06);
        color: @fg;
        box-shadow: none;
      }

      #workspaces button.active {
        background: alpha(@accent, 0.16);
        color: @fg;
      }

      /* a window elsewhere demands attention: the sunset "look here"
         tier (like zellij's attention frame), distinct from the blue
         position marker */
      #workspaces button.urgent {
        background: alpha(@attention, 0.18);
        color: @attention;
      }

      #workspaces button.persistent:not(.empty) {
        color: @subtle;
      }

      #window {
        color: @muted;
        font-style: italic;
        padding: 0 12px 0 6px;
      }

      #clock {
        color: @fg;
        letter-spacing: 0.2px;
        padding: 0 14px;
      }

      #mpris,
      #custom-gpu,
      #custom-tailscale,
      #custom-kblayout,
      #bluetooth,
      #network,
      #pulseaudio,
      #battery,
      #tray {
        background: transparent;
        color: @subtle;
        padding: 0 10px;
        margin: 0;
      }

      #mpris { color: @muted; font-style: italic; }
      #custom-kblayout { min-width: 26px; }
      #custom-gpu.hot { color: @critical; }
      #custom-tailscale.down { color: @muted; }

      #bluetooth.off,
      #bluetooth.disabled {
        color: @muted;
      }

      #bluetooth.connected {
        color: @accent;
      }

      #battery.warning {
        color: @warning;
      }

      #battery.critical {
        color: @critical;
        animation: blink 1.2s steps(2) infinite;
      }

      /* The one loud thing on the bar, and only when it's earned:
         critical fill, dark text, blinking — the smoke alarm */
      #custom-backup.failed {
        background: @critical;
        color: @bg;
        font-weight: 700;
        border-radius: 8px;
        margin: 5px 8px 5px 2px;
        padding: 0 12px;
        animation: blink 1.2s steps(2) infinite;
      }

      @keyframes blink {
        to { opacity: 0.55; }
      }
    '';
  };
}
