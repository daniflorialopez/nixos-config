{ config, pkgs, ... }:
let
  target = config.wayland.systemd.target; # defaults to "graphical-session.target"
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

  # Wallpaper restore
  systemd.user.services.wallpaper-restore = {
    Unit = {
      Description = "Restore wallpaper with Waytrogen";
      PartOf = [ target ];
      After = [ "hyprpaper.service" target ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.waytrogen}/bin/waytrogen --restore";
    };
    Install.WantedBy = [ target ];
  };
}
