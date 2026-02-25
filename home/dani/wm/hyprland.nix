{ 
  config, 
  pkgs, 
  ... 
}:

{
  wayland.windowManager.hyprland = {
    enable = true;

    systemd.enable = false; # because my system uses `programs.hyprland.withUWSM = true`

    settings = {
      monitor = [ ",preferred,auto,1" ];

      "$mod" = "SUPER";

      exec-once = [
        # Polkit prompts (wifi passwords, admin actions, etc.)
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"

        "waybar"
        "mako"
        "nm-applet --indicator"
        "hyprpaper"
      ];

      bind = [
        "$mod, Return, exec, alacritty"
        "$mod, D, exec, wofi --show drun"
        "$mod, Q, killactive"
        "$mod, M, exit"
        "$mod, F, fullscreen"
        "$mod, Space, togglefloating"

        # Screenshot area to clipboard
        ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
        };
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
      };
    };
  };

  home.packages = with pkgs; [
    # essentials
    alacritty
    wofi
    waybar
    mako
    hyprpaper

    # clipboard + screenshots
    wl-clipboard
    grim
    slurp

    # tray / network
    networkmanagerapplet
    
    # comfort tools
    pavucontrol
    brightnessctl
    playerctl

    # other utilities
    wl-kbptr

  ];

}

