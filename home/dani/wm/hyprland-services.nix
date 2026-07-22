{ config, pkgs, lib, inputs, ... }:
let
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  target = config.wayland.systemd.target; # defaults to "graphical-session.target"
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
