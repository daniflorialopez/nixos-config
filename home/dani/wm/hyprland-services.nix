{ config, pkgs, ... }:
let
  target = config.wayland.systemd.target; # defaults to "graphical-session.target"
in
{
  # Waybar (service + config) — recommended way
  programs.waybar = {
    enable = true;
    systemd.enable = true;         # creates waybar.service
    systemd.target = target;

    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 28;
      modules-left = [ "hyprland/workspaces" ];
      modules-center = [ "clock" ];
      modules-right = [ "pulseaudio" "network" "battery" "tray" ];
      
     
      "hyprland/workspaces" = { 
        format = "{name}";
        sort-by = "number";
        disable-scroll = true;

        persistent-workspaces = {
          "*" = [ 1 2 3 4 5 ];
        };

        all-outputs = false;
        move-to-monitor = true;
      };
      
      clock = { 
        format = "{:%a %H:%M}"; 
        tooltip = false; 
      };

      pulseaudio = {
        format = "󰕾 {volume}%";
        format-muted = "󰖁 muted";
        scroll-step = 5;
        on-click = "pavucontrol";
      };

      network = {
        format-wifi = "󰖩 {signalStrength}%";
        format-ethernet = "󰈀 eth";
        format-disconnected = "󰖪 down";
        tooltip = false;
      };

      battery = {
        states = { warning = 30; critical = 15; };
        format = "{icon} {capacity}%";
        format-icons = [ "󰁺" "󰁼" "󰁾" "󰂀" "󰂂" "󰁹" ];
        tooltip = false;
      };

      tray = { spacing = 10; };
    };

    style = ''
      @import "palette.css";

      * {
        border: none;
        min-height: 0;
        font-size: 12.5px;
      }

      window#waybar {
        background: transparent;
      }

      window#waybar > box {
        background: @bg_alpha;
        border: 1px solid @border;
        border-radius: 14px;
        padding: 4px 8px;
        margin: 6px 10px;
      }

      #workspaces button {
        background: transparent;
        color: @muted;
        padding: 4px 10px;
        margin: 0 3px;
        border-radius: 10px;
      }

      #workspaces button.active {
        background: rgba(137, 180, 250, 0.18);
        color: @fg;
      }

      #clock, #tray, #network, #pulseaudio, #battery {
        background: @surface;
        color: @fg;
        padding: 4px 10px;
        margin: 0 4px;
        border-radius: 10px;
        border: 1px solid @border;
      }
    ''; 
  };

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

  # NetworkManager tray applet
  systemd.user.services.nm-applet = {
    Unit = {
      Description = "NetworkManager Applet";
      PartOf = [ target ];
      After = [ target ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
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

  # Wallpaper init (avoids black background after reboot)
  systemd.user.services.wallpaper-init = {
    Unit = {
      Description = "Set wallpaper on Hyprland login";
      PartOf = [ target ];
      After = [ "hyprpaper.service" target ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.runtimeShell} -lc 'dir=\"$HOME/Pictures/Wallpapers\"; f=$(find \"$dir\" -maxdepth 1 -type f \\( -iname \"*.jpg\" -o -iname \"*.jpeg\" -o -iname \"*.png\" -o -iname \"*.webp\" \\) | sort | head -n1); [ -n \"$f\" ] && ${pkgs.hyprland}/bin/hyprctl hyprpaper reload ,\"$f\"'";
    };
    Install.WantedBy = [ target ];
  };
}
