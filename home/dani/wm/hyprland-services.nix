{ config, pkgs, lib, inputs, ... }:
let
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  target = config.wayland.systemd.target; # defaults to "graphical-session.target"

  # Dock/undock workspace repair. Undocking is fine on its own — Hyprland
  # migrates HDMI-A-1's workspaces to eDP-1 when the monitor vanishes —
  # but on re-dock nothing moves them back, leaving everything piled on
  # the laptop screen. This listens on Hyprland's event socket and, when
  # HDMI-A-1 (re)appears, returns its workspaces (1, 4-10, per the
  # workspace rules in hyprland.nix). Also runs once at startup, which
  # covers logging in docked and makes it a no-op on HDMI-less hosts.
  dockHandler = pkgs.writeShellApplication {
    name = "hypr-dock-handler";
    runtimeInputs = with pkgs; [ hyprland jq socat coreutils systemd ];
    text = ''
      repin() {
        hyprctl monitors -j | jq -e 'any(.[]; .name == "HDMI-A-1")' >/dev/null || return 0
        hyprctl workspaces -j | jq -r '.[].id' | while read -r ws; do
          case "$ws" in
            1|4|5|6|7|8|9|10)
              hyprctl dispatch moveworkspacetomonitor "$ws HDMI-A-1" >/dev/null
              ;;
          esac
        done
      }

      repin

      sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
      socat -U - "UNIX-CONNECT:$sock" | while read -r line; do
        case "$line" in
          monitoradded*HDMI-A-1*)
            sleep 1   # let the monitor rule (mode/position) settle first
            repin
            # waybar duplicates bar surfaces on a re-added output (seen
            # live: three stacked bars after replug); a restart redraws
            # one bar per monitor
            systemctl --user try-restart waybar.service || true
            ;;
        esac
      done
    '';
  };
  wallApply = pkgs.writeShellApplication {
    name = "wall-apply";
    runtimeInputs = [ pkgs.hyprland ];
    text = ''
      set -eu

      mon="''${1:-}"
      img="''${2:-}"

      if [ -z "$img" ]; then
        echo "missing wallpaper path" >&2
        exit 1
      fi

      case "$mon" in
        ""|"All"|"all")
          hyprctl hyprpaper wallpaper "HDMI-A-1,$img,cover"
          hyprctl hyprpaper wallpaper "eDP-1,$img,cover"
          ;;
        *)
          hyprctl hyprpaper wallpaper "$mon,$img,cover"
          ;;
      esac
    '';
  };
in
{
  
  # The walker HM module enables xdg.portal with only the hyprland backend,
  # which shadows the system portal setup (NIX_XDG_DESKTOP_PORTAL_DIR points
  # at the per-user profile). Without the gtk backend the portal serves no
  # Settings interface, so GTK4 apps (e.g. pavucontrol) never see the dark
  # preference. Add gtk and prefer hyprland for what it implements.
  xdg.portal = {
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.hyprland.default = [ "hyprland" "gtk" ];
  };

  # Mako: HM config + systemd service
  services.mako = {
    enable = true;                 # writes config + installs package
    settings = {
      # Tokyo Night, matching waybar (see waybar/palette.css)
      font = "CaskaydiaMono Nerd Font 11";
      # app icons resolve from the same theme GTK uses (theme.nix)
      icon-path = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark";
      max-icon-size = 40;
      background-color = "#1a1b26e0";
      text-color = "#c0caf5";
      border-color = "#7aa2f7";
      border-size = 2;
      border-radius = 12;
      padding = "12,16";
      margin = "12";
      width = 380;
      max-visible = 5;
      default-timeout = 0;         # persist until dismissed (Super+')
      progress-color = "over #24283b";

      "urgency=low".border-color = "#565f89";
      "urgency=critical".border-color = "#f7768e";

      # Do-not-disturb: notifications arriving in this mode are hidden but
      # never expire (default-timeout=0), so they all appear when the mode
      # is left — leaving DND shows what was missed. Toggled by the waybar
      # bell or Super+N (dnd-toggle, defined in waybar.nix).
      "mode=dnd".invisible = true;
    };
  };
  systemd.user.services.mako = {
    Unit = {
      Description = "Mako notifications";
      PartOf = [ target ];
      After = [ target ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "${pkgs.mako}/bin/mako";
      Restart = "on-failure";
    };
    Install.WantedBy = [ target ];
  };

  systemd.user.services.hypr-dock-handler = {
    Unit = {
      Description = "Re-pin workspaces to HDMI-A-1 on dock";
      PartOf = [ target ];
      After = [ target ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "${dockHandler}/bin/hypr-dock-handler";
      Restart = "on-failure";
    };
    Install.WantedBy = [ target ];
  };

  # Hyprsunset: warm color temperature after dark. Identity during the
  # day so the calibrated palette stays true; two warm steps at night —
  # gentle at dusk, deeper before bed. Runs as a user service bound to
  # the session; `hyprctl hyprsunset identity` kills it manually when
  # doing color-sensitive work at night.
  services.hyprsunset = {
    enable = true;
    settings = {
      profile = [
        {
          time = "7:30";
          identity = true;
        }
        {
          time = "21:00";
          temperature = 4200;
        }
        {
          time = "23:30";
          temperature = 3700;
        }
      ];
    };
  };

  # Polkit agent (for auth dialogs)
  systemd.user.services.polkit-gnome-agent = {
    Unit = {
      Description = "Polkit GNOME Authentication Agent";
      PartOf = [ target ];
      After = [ target ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
    };
    Install.WantedBy = [ target ];
  };
}
