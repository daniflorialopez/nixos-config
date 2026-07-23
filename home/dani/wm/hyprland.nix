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

      region="$(slurp -c '#ff9e64ff')" || exit 0
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

  # Searchable keybinds palette: reads the live binds from hyprctl (so it
  # also covers binds declared outside this file, e.g. whatsapp.nix),
  # renders "CHORD  description" in walker's dmenu and executes the
  # chosen bind. Descriptions come from bindd; plain binds fall back to
  # showing their dispatcher.
  keybindsMenu = pkgs.writeShellApplication {
    name = "keybinds-menu";
    # walker comes from the session PATH (flake package), not nixpkgs
    runtimeInputs = with pkgs; [
      hyprland
      jq
      gawk
      gnused
      coreutils
    ];
    text = ''
      tsv="$(hyprctl binds -j | jq -r '
        .[]
        | select(.mouse | not)
        | [(.modmask | tostring), .key, (.keycode | tostring), .description, .dispatcher, .arg]
        | @tsv
      ')"

      display="$(awk -F'\t' '
        function mods(m,    s) {
          s = ""
          if (int(m / 64) % 2) s = s "SUPER+"
          if (int(m / 4) % 2)  s = s "CTRL+"
          if (int(m / 8) % 2)  s = s "ALT+"
          if (m % 2)           s = s "SHIFT+"
          return s
        }
        {
          key = $2
          if (key == "") key = "code:" $3
          if (key == "code:48") key = "\047"
          if (key == "code:61") key = "/"
          desc = $4
          if (desc == "") desc = $5 ($6 == "" ? "" : " " $6)
          printf "%-24s %s\n", mods($1) key, desc
        }
      ' <<<"$tsv")"

      idx="$(walker -d -i -p 'Keybinds' <<<"$display")" || exit 0
      case "$idx" in *[!0-9]* | "") exit 0 ;; esac

      line="$(sed -n "$((idx + 1))p" <<<"$tsv")"
      dispatcher="$(printf '%s' "$line" | cut -f5)"
      arg="$(printf '%s' "$line" | cut -f6)"

      if [ -n "$arg" ]; then
        exec hyprctl dispatch "$dispatcher" "$arg"
      else
        exec hyprctl dispatch "$dispatcher"
      fi
    '';
  };
in

{
  imports = [
    ./hyprland-services.nix
    ./clipboard.nix
    ./hyprlock.nix
    ./theme.nix
    ./walker.nix
    ./waybar.nix
    ./cursor.nix
  ];

  home.file.".config/uwsm/env-hyprland".text = ''
    export AQ_DRM_DEVICES="/dev/dri/card1"
    export AQ_FORCE_LINEAR_BLIT=0
  '';

  wayland.windowManager.hyprland = {
    enable = true;

    systemd.enable = false; # because my system uses `programs.hyprland.withUWSM = true`

    settings = {
      monitor = [ 
        "HDMI-A-1, 2560x1440@60, 0x0, 1"
        "eDP-1, 2560x1440@60, 2560x0, 1"
      ];

      "$mod" = "SUPER";
      "$terminal" = "alacritty";
      "$fileManager" = "pcmanfm";
      "$browser" = "firefox";

      exec-once = [
      ];

      # Everything is bindd (bind + description): the descriptions feed
      # the keybinds palette ($mod+/), so a plain bind here would show
      # up as a bare dispatcher in the menu.
      bindd = [
        # Workspaces
        "$mod, 1, Workspace 1, workspace, 1"
        "$mod, 2, Workspace 2, workspace, 2"
        "$mod, 3, Workspace 3, workspace, 3"
        "$mod, 4, Workspace 4, workspace, 4"
        "$mod, 5, Workspace 5, workspace, 5"
        "$mod, 6, Workspace 6, workspace, 6"
        "$mod, 7, Workspace 7, workspace, 7"
        "$mod, 8, Workspace 8, workspace, 8"
        "$mod, 9, Workspace 9, workspace, 9"
        "$mod, 0, Workspace 10, workspace, 10"

        # Move to workspaces
        "$mod SHIFT, 1, Move window to workspace 1, movetoworkspace, 1"
        "$mod SHIFT, 2, Move window to workspace 2, movetoworkspace, 2"
        "$mod SHIFT, 3, Move window to workspace 3, movetoworkspace, 3"
        "$mod SHIFT, 4, Move window to workspace 4, movetoworkspace, 4"
        "$mod SHIFT, 5, Move window to workspace 5, movetoworkspace, 5"
        "$mod SHIFT, 6, Move window to workspace 6, movetoworkspace, 6"
        "$mod SHIFT, 7, Move window to workspace 7, movetoworkspace, 7"
        "$mod SHIFT, 8, Move window to workspace 8, movetoworkspace, 8"
        "$mod SHIFT, 9, Move window to workspace 9, movetoworkspace, 9"
        "$mod SHIFT, 0, Move window to workspace 10, movetoworkspace, 10"

        # --- Scratchpad (special workspace) ---
        # "$mod, S, togglespecialworkspace,"
        # "$mod SHIFT, S, movetoworkspace, special"

        # Window actions
        # "$mod SHIFT, Space, togglefloating,"
        # "$mod, P, pseudo,"          # pseudo-tiling
        # "$mod, J, togglesplit,"     # dwindle split direction
        "$mod, Tab, Cycle next window, cyclenext"
        "$mod SHIFT, Tab, Cycle previous window, cyclenext, prev"

        # --- Focus (vim keys) ---
        "$mod, h, Focus left, movefocus, l"
        "$mod, l, Focus right, movefocus, r"
        "$mod, k, Focus up, movefocus, u"
        "$mod, j, Focus down, movefocus, d"

        # --- Move window (vim keys) ---
        "$mod SHIFT, h, Move window left, movewindow, l"
        "$mod SHIFT, l, Move window right, movewindow, r"
        "$mod SHIFT, k, Move window up, movewindow, u"
        "$mod SHIFT, j, Move window down, movewindow, d"

        # --- Resize active window (vim keys) ---
        "$mod CTRL, h, Resize narrower, resizeactive, -30 0"
        "$mod CTRL, l, Resize wider, resizeactive, 30 0"
        "$mod CTRL, k, Resize shorter, resizeactive, 0 -30"
        "$mod CTRL, j, Resize taller, resizeactive, 0 30"

        # --- Focus (arrow keys) ---
        "$mod, left, Focus left, movefocus, l"
        "$mod, right, Focus right, movefocus, r"
        "$mod, up, Focus up, movefocus, u"
        "$mod, down, Focus down, movefocus, d"

        # --- Move window (arrow keys) ---
        "$mod SHIFT, left, Move window left, movewindow, l"
        "$mod SHIFT, right, Move window right, movewindow, r"
        "$mod SHIFT, up, Move window up, movewindow, u"
        "$mod SHIFT, down, Move window down, movewindow, d"

        # --- Resize active window (arrow keys) ---
        "$mod CTRL, left, Resize narrower, resizeactive, -30 0"
        "$mod CTRL, right, Resize wider, resizeactive, 30 0"
        "$mod CTRL, up, Resize shorter, resizeactive, 0 -30"
        "$mod CTRL, down, Resize taller, resizeactive, 0 30"

        # --- Media keys (PipeWire + playerctl) ---
        ", XF86AudioRaiseVolume, Volume up, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, Volume down, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86AudioMute, Toggle mute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioPlay, Play / pause, exec, playerctl play-pause"
        ", XF86AudioNext, Next track, exec, playerctl next"
        ", XF86AudioPrev, Previous track, exec, playerctl previous"

        # --- Brightness ---
        ", XF86MonBrightnessUp, Brightness up, exec, brightnessctl set +10%"
        ", XF86MonBrightnessDown, Brightness down, exec, brightnessctl set 10%-"

        # --- Change keyboard layout ---
        "$mod SHIFT, Z, Next keyboard layout, exec, hyprctl switchxkblayout current next"

        # Basic binds
        "$mod, Return, Alacritty, exec, $terminal"
        "$mod, Space, Walker and Elephant, exec, walker"
        "$mod, W, Kill Program, killactive"
        # "$mod, M, exit"
        # mode 0 = true fullscreen: ignores waybar's reserved strip and
        # goes edge-to-edge, with the glass bar floating over it as a HUD.
        # mode 1 (maximize) respects the reserved strip instead, which
        # looks broken against the floating islands (hard square edge
        # butting against a mostly-empty reserved strip) - kept on the
        # alt bind for the rare case a maximize-not-fullscreen is wanted.
        "$mod, F, True full screen, fullscreen, 0"
        "$mod ALT, F, Maximize (keeps bar strip), fullscreen, 1"
        # "$mod, Space, togglefloating"
        "$mod, M, File Manager, exec, $fileManager"
        "$mod SHIFT, O, Obsidian, exec, obsidian"

        # Different Firefox profiles: personal, lab, work
        "$mod, B, Firefox personal profile, exec, $browser -p personal"
        "$mod SHIFT, B, Firefox lab profile, exec, $browser -p lab"
        "$mod CTRL, B, Firefox work profile, exec, $browser -p work"

        # Screenshots
        ", Print, Screenshot with Satty, exec, screenshot-satty"

        # Clipboard history (elephant provider; see clipboard.nix)
        "$mod, V, Clipboard history, exec, walker -m clipboard"
        "$mod SHIFT, V, Wipe clipboard history, exec, clipboard-wipe"

        # Keybinds palette (code:61 = the / key on the us layout, same physical key on es)
        "$mod, code:61, Keybinds palette, exec, keybinds-menu"

        # wl-kbptr
        "$mod SHIFT, M, wl-kbptr mouse actions, exec, wl-kbptr"

        # Lock screen
        "$mod, Escape, Lock screen, exec, hyprlock"

        # Notifications (code:48 = the ' key on the us layout, same physical key on es)
        "$mod, code:48, Dismiss newest notification, exec, makoctl dismiss"
        "$mod SHIFT, code:48, Dismiss all notifications, exec, makoctl dismiss -a"
        "$mod CTRL, code:48, Restore last dismissed notification, exec, makoctl restore"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      input = {
        kb_layout = "us,es";
        # kb_options = "grp:ctrls_toggle,caps:super";
        kb_options = "shift:both_capslock_cancel";
        follow_mouse = 1;
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
        };
      };

      general = {
        gaps_in = 6;
        gaps_out = 12;

        border_size = 2;

        # Neutral slate borders (picked over the old sunset gradient in a
        # live A/B, 2026-07-22): the gradient painted a different hue on
        # each edge and read as noise. Focus is signaled by value, not
        # hue — active slate vs near-invisible gutter — Windows-calm.
        # The sunset now lives only in the attention tier (waybar urgent/
        # backup, zellij frame_highlight, walker border, btop graphs).
        "col.active_border" = "rgba(565f89ff)";
        "col.inactive_border" = "rgba(3b426188)";
      };

      decoration = {
        # Clear glass: real transparency on every window so the wallpaper
        # stays visible; blur kept whisper-light (size 3, one pass) so the
        # mountains/sunset remain recognizable and only fine detail softens
        active_opacity = 0.94;
        inactive_opacity = 0.88;
        fullscreen_opacity = 1.0;

        blur = {
          enabled = true;
          size = 3;
          passes = 1;
          ignore_opacity = true;
          new_optimizations = true;
          xray = false;
          noise = 0.0117;
          contrast = 1.0;
          brightness = 1.0;
          vibrancy = 0.15;
        };

        rounding = 12;
        shadow = {
          enabled = true;
          range = 14;
          render_power = 3;
          color = "rgba(00000066)";
          color_inactive = "rgba(00000033)";
          offset = "0 3";
        };
      };

      # Glass for the chrome too: blur behind waybar, walker and mako
      # (ignorezero keeps fully-transparent regions, e.g. rounded
      # corners, from being blurred into grey halos)
      layerrule = [
        "blur, waybar"
        "ignorezero, waybar"
        "blur, walker"
        "ignorealpha 0.4, walker"
        "blur, notifications"
        "ignorezero, notifications"
      ];

      animations = {
        enabled = true;

        bezier = [
          # fast start, gentle landing — snappy without feeling abrupt
          "easeOutQuint, 0.23, 1, 0.32, 1"
        ];

        # durations are in deciseconds
        animation = [
          "windows, 1, 3, easeOutQuint, popin 92%"
          "windowsOut, 1, 2.5, easeOutQuint, popin 92%"
          "fade, 1, 2.5, default"
          "border, 1, 4, default"
          "workspaces, 1, 3.5, easeOutQuint, slide"
          "specialWorkspace, 1, 3, easeOutQuint, slidevert"
          "layers, 1, 2.5, easeOutQuint, popin 93%"
        ];
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;

        vfr = true;
      };

      workspace = [
        "f[1], gapsout:0, gapsin:0"

        "1, monitor:HDMI-A-1, default:true, persistent:true"
        "2, monitor:eDP-1, default:true, persistent:true"
        "3, monitor:eDP-1, persistent:true"
        "4, monitor:HDMI-A-1, persistent:true"
        "5, monitor:HDMI-A-1, persistent:true"
        "6, monitor:HDMI-A-1"
        "7, monitor:HDMI-A-1"
        "8, monitor:HDMI-A-1"
        "9, monitor:HDMI-A-1"
        "10, monitor:HDMI-A-1"
      ];

      windowrulev2 = [
        "float, class:^(org\\.Waytrogen\\.Waytrogen)$"
        "center, class:^(org\\.Waytrogen\\.Waytrogen)$"
        "size 1200 800, class:^(org\\.Waytrogen\\.Waytrogen)$"
        "float, class:^(firefox)$, title:^(Save As|Guardar como).*$"
        "size 70% 75%, class:^(firefox)$, title:^(Save As|Guardar como).*$"
        "center 1, class:^(firefox)$, title:^(Save As|Guardar como).*$"
        "bordersize 0, fullscreenstate:1 *"
        "rounding 0, fullscreenstate:1 *"

        # Media stays true-color: the glass treatment (0.94/0.88 + blur)
        # washes out video, photos and PDFs when windowed/unfocused, so
        # viewers and the screenshot editor render at full opacity
        "opacity 1.0 override 1.0 override, class:^(mpv|imv|org\\.pwmt\\.zathura|com\\.gabm\\.satty|com\\.obsproject\\.Studio)$"
        "opacity 1.0 override 1.0 override, title:^(Picture-in-Picture)$"
      ];
    };
  };
  
  home.packages = with pkgs; [
    # essentials
    alacritty

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
    keybindsMenu

  ];

}

