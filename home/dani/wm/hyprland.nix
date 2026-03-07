{ 
  config, 
  pkgs, 
  ... 
}:

{
  imports = [
    ./hyprland-services.nix
    ./theme.nix
    ./wofi.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;

    systemd.enable = false; # because my system uses `programs.hyprland.withUWSM = true`

    settings = {
      monitor = [ ",preferred,auto,1" ];

      "$mod" = "SUPER";
      "$terminal" = "alacritty";
      "$fileManager" = "pcmanfm";
      "$browser" = "firefox";

      exec-once = [
      ];

      bind = [
        # Workspaces
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"

        # Move to workspaces
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"

        # --- Scratchpad (special workspace) ---
        # "$mod, S, togglespecialworkspace,"
        # "$mod SHIFT, S, movetoworkspace, special"

        # Window actions
        # "$mod SHIFT, Space, togglefloating,"
        # "$mod, P, pseudo,"          # pseudo-tiling
        # "$mod, J, togglesplit,"     # dwindle split direction
        # "$mod, Tab, cyclenext,"
        # "$mod SHIFT, Tab, cyclenext, prev"

        # --- Focus (vim keys) ---
        "$mod, h, movefocus, l"
        "$mod, l, movefocus, r"
        "$mod, k, movefocus, u"
        "$mod, j, movefocus, d"

        # --- Move window (vim keys) ---
        "$mod SHIFT, h, movewindow, l"
        "$mod SHIFT, l, movewindow, r"
        "$mod SHIFT, k, movewindow, u"
        "$mod SHIFT, j, movewindow, d"

        # --- Resize active window (vim keys) ---
        "$mod CTRL, h, resizeactive, -30 0"
        "$mod CTRL, l, resizeactive, 30 0"
        "$mod CTRL, k, resizeactive, 0 -30"
        "$mod CTRL, j, resizeactive, 0 30"

        # --- Media keys (PipeWire + playerctl) ---
        ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"

        # --- Brightness ---
        ", XF86MonBrightnessUp, exec, brightnessctl set +10%"
        ", XF86MonBrightnessDown, exec, brightnessctl set 10%-"
      ];

      bindd = [
        # Basic binds
        "$mod, Return, Alacritty, exec, $terminal"
        "$mod, Space, Wofi, exec, wofi --show drun --style $HOME/.config/wofi/style.css"
        "$mod, Kill Program, W, killactive"
        # "$mod, M, exit"
        "$mod, F, Full width, fullscreen, 1"
        "$mod ALT, F, Force full screen, fullscreen, 0"
        # "$mod, Space, togglefloating"
        "$mod, M, File Manager, exec, $fileManager"
        "$mod, B, Browser, exec, $browser"

        # Screenshot area to clipboard
        ", Print, Print screen selection, exec, grim -g \"$(slurp -d)\" - | wl-copy"

        # wl-kbptr
        "$mod SHIFT, M, wl-kbptr mouse actions, exec, wl-kbptr"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      input = {
        kb_layout = "us,es";
        kb_options = "grp:alts_toggle,caps:super";
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
    # waybar
    # mako
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

    # fonts
    font-awesome

    # other utilities
    wl-kbptr

  ];

}

