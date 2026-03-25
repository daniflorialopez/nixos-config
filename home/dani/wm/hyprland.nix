{ 
  config, 
  pkgs, 
  ... 
}:

let
  screenshotSatty = pkgs.writeShellApplication {
    name = "screenshot-satty";
    runtimeInputs = with pkgs; [
      grim
      slurp
      satty
      wl-clipboard
      coreutils
    ];
    text = ''
      set -eu

      outdir="$HOME/Pictures/Screenshots"
      mkdir -p "$outdir"

      region="$(slurp -c '#ff0000ff')" || exit 0
      outfile="$outdir/satty-$(date +%Y%m%d-%H%M%S).png"

      export GSK_RENDERER=ngl

      grim -g "$region" -t ppm - | satty \
        --filename - \
        --fullscreen \
        --initial-tool crop \
        --copy-command wl-copy \
        --output-filename "$outfile"
    '';
  };
in

{
  imports = [
    ./hyprland-services.nix
    ./theme.nix
    ./walker.nix
    ./waybar.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;

    systemd.enable = false; # because my system uses `programs.hyprland.withUWSM = true`

    settings = {
      monitor = [ 
        "HDMI-A-1, 2560x1440@59.95, 0x0, 1"
        "eDP-1, 2560x1440@165, 2560x0, 1"
      ];

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
        "$mod, Tab, cyclenext,"
        "$mod SHIFT, Tab, cyclenext, prev"

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

        # --- Change keyboard layout ---
        "$mod SHIFT, Z, exec, hyprctl switchxkblayout current next"
      ];

      bindd = [
        # Basic binds
        "$mod, Return, Alacritty, exec, $terminal"
        "$mod, Space, Walker and Elephant, exec, walker"
        "$mod, W, Kill Program, killactive"
        # "$mod, M, exit"
        "$mod, F, Full width, fullscreen, 1"
        "$mod ALT, F, Force full screen, fullscreen, 0"
        # "$mod, Space, togglefloating"
        "$mod, M, File Manager, exec, $fileManager"
        "$mod SHIFT, O, Obsidian, exec, obsidian"

        # Different Firefox profiles: personal, lab, work
        "$mod, B, Firefox personal profile, exec, $browser -p personal"
        "$mod SHIFT, B, Firefox lab profile, exec, $browser -p lab"
        "$mod CTRL, B, Firefox work profile, exec, $browser -p work"

        # Screenshots
        ", Print, Screenshot with Satty, exec, screenshot-satty"

        # wl-kbptr
        "$mod SHIFT, M, wl-kbptr mouse actions, exec, wl-kbptr"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      input = {
        kb_layout = "us,es";
        # kb_options = "grp:ctrls_toggle,caps:super";
        kb_options = "caps:super";
        follow_mouse = 1;
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
        };
      };

      general = {
        gaps_in = 6;
        gaps_out = 12;

        border_size = 3;

        "col.active_border" = "rgba(00a6ffff)";
        "col.inactive_border" = "rgba(6c7086aa)";
      };

      decoration = {
        active_opacity = 1.0;
        inactive_opacity = 0.94;
        fullscreen_opacity = 1.0;

        blur = {
          enabled = true;
          size = 6;
          passes = 2;
          ignore_opacity = true;
          new_optimizations = true;
          xray = false;
          noise = 0.0117;
          contrast = 0.89;
          brightness = 0.82;
          vibrancy = 0.10;
        };

        rounding = 12;
        shadow = {
          enabled = true;
          range = 1;
          sharp = true;
          render_power = 4;
          ignore_window = true;
          color = "rgba(000000aa)";
          color_inactive = "rgba(00000055)";
          offset = "0 0";
          scale = 1.0;
        };
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
      };

      windowrulev2 = [
        "float, class:^(org\\.Waytrogen\\.Waytrogen)$"
        "center, class:^(org\\.Waytrogen\\.Waytrogen)$"
        "size 1200 800, class:^(org\\.Waytrogen\\.Waytrogen)$"
      ];
    };
  };
  
  home.packages = with pkgs; [
    # essentials
    alacritty
    hyprpaper

    # clipboard + screenshots
    grim
    slurp
    wl-clipboard
    screenshotSatty
    satty

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

