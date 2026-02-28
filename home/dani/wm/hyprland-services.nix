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
      * { font-size: 12px; min-height: 0; }

      window#waybar {
        background: rgba(0,0,0,0.35);
        color: #fff;
        border-radius: 10px;
      }

      #workspaces button {
        padding: 0 7px;
        margin: 4px 2px;
        border-radius: 8px;
        background: transparent;
        border: 0;
        color: inherit;
      }

      #workspaces button.active {
        background: rgba(255,255,255,0.15);
      }

      #workspaces button.empty {
        opacity: 0.35;
      }

      #clock, #pulseaudio, #network, #battery, #tray {
        padding: 0 10px;
        margin: 4px 0;
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
