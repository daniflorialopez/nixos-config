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
  
  # Mako: HM config + systemd service
  services.mako.enable = true;     # writes config + installs package
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
