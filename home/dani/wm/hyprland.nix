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

  # hyprpicker colour picker: pick a pixel, copy its hex to the clipboard,
  # confirm with a toast. -a autocopies; stdout carries the value for the
  # notification.
  colorPick = pkgs.writeShellApplication {
    name = "color-pick";
    runtimeInputs = with pkgs; [ hyprpicker libnotify ];
    text = ''
      col="$(hyprpicker -a -f hex)" || exit 0
      [ -n "$col" ] || exit 0
      notify-send -t 2500 "Colour picked" "$col · copied to clipboard"
    '';
  };

  # Plain-Hyprland scratchpads (no pyprland): toggle a named special
  # workspace, and on first use spawn the app into it and own its geometry
  # directly. We float/size/centre here rather than via windowrules because
  # static rules race Chromium's late-set Wayland app-id (WhatsApp opened at
  # the wrong size); driving it from here is deterministic and app-agnostic.
  # Usage: scratchpad <name> <width%> <height%> <command…>
  scratchpad = pkgs.writeShellApplication {
    name = "scratchpad";
    runtimeInputs = with pkgs; [ hyprland jq coreutils ];
    text = ''
      name="$1"; wpct="$2"; hpct="$3"
      shift 3
      ws="special:$name"

      # Already spawned: just toggle its visibility.
      if hyprctl clients -j | jq -e --arg ws "$ws" 'any(.[]; .workspace.name == $ws)' >/dev/null; then
        hyprctl dispatch togglespecialworkspace "$name"
        exit 0
      fi

      # First use: reveal the special workspace and spawn the app into it.
      hyprctl dispatch togglespecialworkspace "$name"
      hyprctl dispatch exec "[workspace special:$name] $*"

      # Wait for the window to map, then float + size + centre it.
      addr=""
      for _ in $(seq 1 100); do
        addr="$(hyprctl clients -j | jq -r --arg ws "$ws" \
          'first(.[] | select(.workspace.name == $ws)) | .address // empty')"
        [ -n "$addr" ] && break
        sleep 0.05
      done
      [ -n "$addr" ] || exit 0

      dims="$(hyprctl monitors -j | jq -r --argjson wp "$wpct" --argjson hp "$hpct" \
        'first(.[] | select(.focused))
         | "\(((.width / .scale) * $wp / 100) | floor) \(((.height / .scale) * $hp / 100) | floor)"')"
      tw="''${dims%% *}"; th="''${dims##* }"

      hyprctl --batch "dispatch focuswindow address:$addr ; dispatch setfloating address:$addr ; dispatch resizewindowpixel exact $tw $th,address:$addr ; dispatch centerwindow"
    '';
  };

  # Quick-note buffer for the scratchpad: nvim on a fixed scratch file
  # (creating the notes dir if needed). Wrapped so the scratchpad command
  # stays a simple word list — no nested quoting through hyprctl exec.
  quickNote = pkgs.writeShellApplication {
    name = "quick-note";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      mkdir -p "$HOME/notes"
      # -n: no swap file. This nvim outlives its window — dismissing the
      # scratchpad only hides it — so it is still alive at logout and gets
      # signalled, and nvim deliberately *preserves* the swap when it dies
      # that way. The next open then greets you with E325. Autosave makes
      # the swap redundant: `update` writes only when modified, and
      # FocusLost fires when Super+S hides the window, so dismissing saves.
      exec nvim -n \
        -c 'autocmd InsertLeave,TextChanged,FocusLost <buffer> silent! update' \
        "$HOME/notes/scratch.md"
    '';
  };

  # Bitwarden as a Chromium PWA (same pattern as whatsapp-web) — the web
  # vault in its own isolated profile. Chosen over bitwarden-desktop, which
  # bundles an Electron flagged insecure and would need a system-wide
  # permittedInsecurePackages override just to build.
  bitwardenWeb = pkgs.writeShellApplication {
    name = "bitwarden-web";
    runtimeInputs = [ pkgs.chromium ];
    text = ''
      exec chromium \
        --ozone-platform-hint=auto \
        --enable-wayland-ime \
        --password-store=basic \
        --app=https://vault.bitwarden.com \
        --user-data-dir="${config.home.homeDirectory}/.local/share/chromium-bitwarden" \
        "$@"
    '';
  };

  # Super+S entry point: if a scratchpad is currently shown, hide it (so the
  # same key both summons and dismisses); otherwise open the picker — a
  # walker icon-tile grid rendered from the elephant "menus:scratchpads"
  # menu (defined in xdg.configFile below). walker is on the session PATH.
  scratchpadToggle = pkgs.writeShellApplication {
    name = "scratchpad-toggle";
    runtimeInputs = [ pkgs.hyprland pkgs.jq ];
    text = ''
      active="$(hyprctl monitors -j | jq -r '[.[].specialWorkspace.name | select(startswith("special:"))][0] // ""')"
      if [ -n "$active" ]; then
        hyprctl dispatch togglespecialworkspace "''${active#special:}"
      else
        # dani-grid is the board's own theme: window geometry lives in a
        # theme's layout.xml, and the shared one is a fixed 600x570 box that
        # leaves a 12-icon grid swimming in dead space. --theme must be passed
        # on *every* walker bind (they all are) because walker only sets the
        # theme when the flag is present and never resets it, so an unpinned
        # launcher would inherit whichever theme ran last.
        # --nohints drops the keybind hint bar and --nosearch the search entry:
        # on a 12-icon board both are noise. Both have to be flags, not layout
        # properties — walker re-shows the hint bar whenever the selection
        # changes, and deleting the GtkEntry from layout.xml would leave the
        # board empty (the initial query is fired by the entry's "changed"
        # signal, so with no entry nothing ever asks elephant for the items).
        # Neither flag leaks the way --theme does: walker sets both from the
        # command line on every invocation and restores the search entry on
        # close, so the Super+Space launcher is unaffected.
        exec walker -m menus:scratchpads --theme dani-grid --nohints --nosearch
      fi
    '';
  };

  # Searchable keybinds palette: reads the live binds from hyprctl (so it
  # also covers binds declared outside this file, e.g. whatsapp.nix),
  # renders "CHORD  description" grouped under topic headers in walker's
  # dmenu, and executes the chosen bind. Topics are inferred from the
  # dispatcher (and the command for exec binds); the ten per-digit
  # workspace binds collapse into one row each, and chords that trigger
  # the same action (vim keys + arrows) merge into a single row.
  # Headers and collapsed rows are inert: selecting them just closes.
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

      map="$(mktemp)"
      trap 'rm -f "$map"' EXIT

      display="$(awk -F'\t' -v MAP="$map" '
        function mods(m,    s) {
          s = ""
          if (int(m / 64) % 2) s = s "SUPER+"
          if (int(m / 4) % 2)  s = s "CTRL+"
          if (int(m / 8) % 2)  s = s "ALT+"
          if (m % 2)           s = s "SHIFT+"
          return s
        }
        function keylabel(k, kc) {
          if (k == "") k = "code:" kc
          if (k == "code:48") return "\047"
          if (k == "code:61") return "/"
          if (k == "left") return "←"
          if (k == "right") return "→"
          if (k == "up") return "↑"
          if (k == "down") return "↓"
          return k
        }
        function topic(dsp, a) {
          if (dsp == "workspace" || dsp == "movetoworkspace") return "Workspaces"
          if (dsp == "movefocus" || dsp == "cyclenext") return "Focus"
          if (dsp ~ /^(movewindow|resizeactive|killactive|fullscreen|togglefloating|pseudo|togglesplit|togglespecialworkspace)/) return "Windows"
          if (dsp == "exec") {
            if (a ~ /wpctl|playerctl|output-volume/) return "Media"
            if (a ~ /clipboard/) return "Clipboard"
            if (a ~ /-m windows|scratchpad/) return "Windows"
            if (a ~ /brightness|hyprlock|makoctl|dnd-toggle|switchxkblayout|screenshot|wl-kbptr|keybinds-menu|color-pick/) return "System"
            return "Apps"
          }
          return "Other"
        }
        function addrow(t, chord, desc, dsp, a,    i) {
          i = ++rn[t]
          c[t, i] = chord; d[t, i] = desc; md[t, i] = dsp; ma[t, i] = a
        }
        {
          m = $1; dsp = $5; a = $6
          desc = $4
          if (desc == "") desc = dsp (a == "" ? "" : " " a)
          t = topic(dsp, a)

          # ten per-digit rows -> one summary row (inert: pressing the
          # chord yourself is faster than picking a workspace in a menu)
          if (dsp == "workspace" && $2 ~ /^[0-9]$/) {
            if (!wsdone++) addrow(t, mods(m) "1…0", "Switch to workspace 1-10", "", "")
            next
          }
          if (dsp == "movetoworkspace" && $2 ~ /^[0-9]$/) {
            if (!mwsdone++) addrow(t, mods(m) "1…0", "Move window to workspace 1-10", "", "")
            next
          }

          # same action reachable from several chords (vim keys + arrows):
          # append the extra key to the first row instead of a new row
          sig = m SUBSEP desc SUBSEP dsp SUBSEP a
          if (sig in sigat) {
            split(sigat[sig], p, SUBSEP)
            c[p[1], p[2]] = c[p[1], p[2]] " / " keylabel($2, $3)
            next
          }
          addrow(t, mods(m) keylabel($2, $3), desc, dsp, a)
          sigat[sig] = t SUBSEP rn[t]
        }
        END {
          n = split("Apps Clipboard Workspaces Focus Windows Media System Other", order, " ")
          pad = "                              "
          for (o = 1; o <= n; o++) {
            t = order[o]
            if (!rn[t]) continue
            printf "── %s ──\n", t
            print "" > MAP
            for (i = 1; i <= rn[t]; i++) {
              w = 26 - length(c[t, i]); if (w < 1) w = 1
              printf "%s%s%s\n", c[t, i], substr(pad, 1, w), d[t, i]
              printf "%s\t%s\n", md[t, i], ma[t, i] > MAP
            }
          }
        }
      ' <<<"$tsv")"

      idx="$(walker -d -i -p 'Keybinds' --theme dani-soft <<<"$display")" || exit 0
      case "$idx" in *[!0-9]* | "") exit 0 ;; esac

      sel="$(sed -n "$((idx + 1))p" "$map")"
      dispatcher="$(printf '%s' "$sel" | cut -f1)"
      arg="$(printf '%s' "$sel" | cut -s -f2)"
      [ -n "$dispatcher" ] || exit 0

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
    ./swayosd.nix
    ./mouseless.nix
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
        "HDMI-A-1, 2560x1440@75, 0x0, 1"
        "eDP-1, 2560x1440@165, 2560x0, 1"
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

        # --- Scratchpads: Super+S opens a walker picker; if one is already
        # showing, Super+S hides it instead (scratchpad-toggle) ---
        "$mod, S, Scratchpads, exec, scratchpad-toggle"

        # Window actions
        # "$mod SHIFT, Space, togglefloating,"
        # "$mod, P, pseudo,"          # pseudo-tiling (P is now clipboard history)
        # "$mod, J, togglesplit,"     # dwindle split direction
        # Tab opens a searchable window switcher (walker's windows provider);
        # Shift+Tab keeps a quick raw reverse-cycle for fast two-window flicks
        "$mod, Tab, Window switcher, exec, walker -m windows --theme dani-soft"
        "$mod SHIFT, Tab, Cycle to previous window, cyclenext, prev"

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

        # --- Media keys (swayosd OSD + playerctl) ---
        ", XF86AudioRaiseVolume, Volume up, exec, swayosd-client --output-volume raise"
        ", XF86AudioLowerVolume, Volume down, exec, swayosd-client --output-volume lower"
        ", XF86AudioMute, Toggle mute, exec, swayosd-client --output-volume mute-toggle"
        ", XF86AudioPlay, Play / pause, exec, playerctl play-pause"
        ", XF86AudioNext, Next track, exec, playerctl next"
        ", XF86AudioPrev, Previous track, exec, playerctl previous"

        # --- Brightness (same 10% steps as the old brightnessctl binds;
        # '=' keeps clap from reading the leading dash as a flag) ---
        ", XF86MonBrightnessUp, Brightness up, exec, swayosd-client --brightness=+10"
        ", XF86MonBrightnessDown, Brightness down, exec, swayosd-client --brightness=-10"

        # --- Change keyboard layout ---
        "$mod SHIFT, Z, Next keyboard layout, exec, hyprctl switchxkblayout current next"

        # Basic binds
        "$mod, Return, Alacritty, exec, $terminal"
        "$mod, Space, Walker and Elephant, exec, walker --theme dani-soft"
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
        # M is the pointer-tool cluster now: $mod+M is Mouseless (bound in
        # wm/mouseless.nix), $mod SHIFT+M is wl-kbptr, so the file manager
        # moves one modifier out.
        "$mod ALT, M, File Manager, exec, $fileManager"
        "$mod SHIFT, O, Obsidian, exec, obsidian"

        # Different Firefox profiles: personal, lab, work
        "$mod, B, Firefox personal profile, exec, $browser -p personal"
        "$mod SHIFT, B, Firefox lab profile, exec, $browser -p lab"
        "$mod CTRL, B, Firefox work profile, exec, $browser -p work"

        # Screenshots
        ", Print, Screenshot with Satty, exec, screenshot-satty"

        # Pickers (Super+. mirrors walker's '.' symbols prefix; D = dropper)
        "$mod, Period, Emoji & symbols, exec, walker -m symbols --theme dani-soft"
        "$mod, D, Colour picker (hyprpicker), exec, color-pick"

        # Clipboard history (elephant provider; see clipboard.nix).
        # Not on V: keyd rewrites Super+C/V to Ctrl/Shift+Insert before
        # Hyprland sees them (keyd.nix), so any $mod+V bind is dead.
        "$mod, P, Clipboard history, exec, walker -m clipboard --theme dani-soft"
        "$mod SHIFT, P, Wipe clipboard history, exec, clipboard-wipe"

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
        # dnd-toggle comes from waybar.nix (shared with the bar's bell icon)
        "$mod, N, Toggle do-not-disturb, exec, dnd-toggle"
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
        # backup, zellij frame_highlight, btop graphs — walker's frame
        # joined the slate tier on 2026-07-24).
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
        "blur, swayosd"
        "ignorezero, swayosd"

        # Mouseless puts its hint overlay on wlr-layer-shell, so the `layers`
        # animation below would pop it in over ~250ms — long enough that the
        # labels land after you have started typing them. It wants to be
        # instant, not pretty.
        "noanim, mouseless-overlay"
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
        # (Scratchpad geometry — float/size/centre — is owned by the
        # `scratchpad` helper, not windowrules: see the let block above.)
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
  
  # The Super+S scratchpad picker (an elephant "menus" menu, rendered by
  # walker as a 4-column icon-tile grid — see wm/walker.nix). Each entry's
  # `open` action calls the scratchpad helper with a target width%/height%;
  # the helper spawns the app into its special workspace and sizes it.
  # scratchpad is given by absolute path because the elephant service that
  # runs the action doesn't inherit the graphical session PATH (the apps it
  # spawns via `hyprctl dispatch exec` do, so those stay bare names).
  xdg.configFile."elephant/menus/scratchpads.toml".text = ''
    name = "scratchpads"
    name_pretty = "Scratchpads"
    icon = "view-restore"

    # Order matters: walker fills the grid row by row, four to a row, so the
    # first four are the most-used (Bluetooth, btop, quick note, WhatsApp) and
    # land in the top row. The rest follow. Twelve entries = exactly 4 x 3,
    # which is the size layout.xml sizes the window to — adding a thirteenth
    # starts a fourth row and the board scrolls.
    [[entries]]
    text = "Bluetooth"
    icon = "bluetooth"
    actions = { "open" = "${scratchpad}/bin/scratchpad bt 55 60 blueman-manager" }

    [[entries]]
    text = "btop"
    icon = "utilities-system-monitor"
    actions = { "open" = "${scratchpad}/bin/scratchpad sysmon 60 65 alacritty --class scratch-sysmon -e btop" }

    [[entries]]
    text = "Quick note"
    icon = "accessories-text-editor"
    actions = { "open" = "${scratchpad}/bin/scratchpad note 55 60 alacritty --class scratch-note -e quick-note" }

    [[entries]]
    text = "WhatsApp"
    icon = "whatsapp"
    actions = { "open" = "${scratchpad}/bin/scratchpad whatsapp 40 66 whatsapp-web" }

    [[entries]]
    text = "Bitwarden"
    icon = "bitwarden"
    actions = { "open" = "${scratchpad}/bin/scratchpad bitwarden 42 72 bitwarden-web" }

    [[entries]]
    text = "Terminal"
    icon = "utilities-terminal"
    actions = { "open" = "${scratchpad}/bin/scratchpad term 60 62 alacritty --class scratch-term --working-directory ${config.home.homeDirectory}" }

    [[entries]]
    text = "Files"
    icon = "folder"
    actions = { "open" = "${scratchpad}/bin/scratchpad files 65 68 alacritty --class scratch-files -e yazi" }

    [[entries]]
    text = "Audio"
    icon = "multimedia-volume-control"
    actions = { "open" = "${scratchpad}/bin/scratchpad audio 48 58 pavucontrol" }

    [[entries]]
    text = "Calendar"
    icon = "org.gnome.Calendar"
    actions = { "open" = "${scratchpad}/bin/scratchpad cal 62 68 gnome-calendar" }

    [[entries]]
    text = "GPU"
    icon = "nvidia-settings"
    actions = { "open" = "${scratchpad}/bin/scratchpad gpu 60 65 alacritty --class scratch-gpu -e nvtop" }

    [[entries]]
    text = "Wi-Fi"
    icon = "network-wireless"
    actions = { "open" = "${scratchpad}/bin/scratchpad wifi 55 60 nm-connection-editor" }

    [[entries]]
    text = "Weather"
    icon = "org.gnome.Weather"
    actions = { "open" = "${scratchpad}/bin/scratchpad weather 55 62 gnome-weather" }
  '';

  home.packages = with pkgs; [
    # essentials
    alacritty

    # clipboard + screenshots
    grim
    slurp
    wl-clipboard
    screenshotSatty
    satty
    colorPick
    hyprpicker
    scratchpad
    quickNote
    bitwardenWeb
    scratchpadToggle

    # scratchpad apps not already on the system (nm-connection-editor ships
    # with networkmanagerapplet, yazi/pavucontrol/gnome-calendar already present)
    nvtopPackages.nvidia
    gnome-weather

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

