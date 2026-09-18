{
  config,
  pkgs,
  lib,
  osConfig ? null,
  ...
}:

let
  # One palette source: home/dani/theme/palette.nix.
  theme = import ../theme/palette.nix { inherit lib; };

  # This whole wm/ tree is shared with danix-hp, which runs Hyprland on
  # `modesetting` + `fbdev` rather than the proprietary NVIDIA driver. Anything
  # that only makes sense under NVIDIA has to be gated, or it lands there too.
  isNvidia =
    osConfig != null
    && builtins.elem "nvidia" (osConfig.services.xserver.videoDrivers or [ ]);

  # The slurp selection rectangle wears the `attention` role: a screenshot crop
  # is a "look here" interaction, which is exactly what orange is reserved for.
  # (Comment lives here rather than in the script body — writeShellApplication
  # emits the body verbatim, so a # comment inside it lands in the built script.)
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

      region="$(slurp -c '#${theme.noHash.attention}ff')" || exit 0
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
            if (a ~ /brightness|hyprlock|makoctl|dnd-toggle|switchxkblayout|screenshot|wl-kbptr|keybinds-menu|color-pick|menus:logout/) return "System"
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

  # Both of these are Aquamarine's NVIDIA multi-GPU workarounds, straight off
  # the Hyprland NVIDIA wiki page. They were being written unconditionally,
  # which is wrong twice over:
  #
  #   1. danix-hp loads this same file and runs `modesetting`, where pinning
  #      Aquamarine to a hardcoded DRM node is at best pointless and at worst
  #      points it at a node that is not its GPU. Now gated on the host actually
  #      using the proprietary driver.
  #   2. The card INDEX is not a stable name. It happens to be right here -
  #      `ls /dev/dri` shows only card1 + renderD128, both at pci-0000:01:00.0 -
  #      but that is enumeration luck rather than a guarantee.
  #
  # OPEN QUESTION, deliberately not resolved blind: legionix is discrete-only
  # (BIOS has no iGPU; /sys/class/drm holds exactly one card, bound to nvidia),
  # and the wiki presents both of these as *multi-GPU* workarounds. So they may
  # be doing nothing here at all. Removing them is a compositor-device-selection
  # change on a machine with no text console, so it wants a deliberate test with
  # a known-good generation one menu pick away - not a drive-by deletion.
  # /dev/dri/by-path/pci-0000:01:00.0-card is the stable spelling to try at the
  # same time; it is untested against Aquamarine's device matching.
  home.file.".config/uwsm/env-hyprland" = lib.mkIf isNvidia {
    text = ''
      export AQ_DRM_DEVICES="/dev/dri/card1"
      export AQ_FORCE_LINEAR_BLIT=0
    '';
  };

  wayland.windowManager.hyprland = {
    enable = true;

    systemd.enable = false; # because my system uses `programs.hyprland.withUWSM = true`

    # Pinned, and worth understanding before changing.
    #
    # 26.05 added configType, stateVersion-gated: "hyprlang" below 26.05,
    # "lua" at or above it. home.stateVersion is 25.05, so hyprlang is already
    # what we get — but leaving it implicit means a future stateVersion bump
    # would silently re-render this entire `settings` block as hl.*() calls into
    # hyprland.lua instead of hyprland.conf.
    #
    # Staying on hyprlang is a real decision, not inertia: `hyprctl keyword` is
    # hyprlang-only from 0.55 (dispatchKeyword returns "keyword can't work with
    # non-legacy parsers. Use eval." under the Lua parser), and that is the
    # mechanism a future effect-profile system would be built on.
    configType = "hyprlang";

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

        # Lock screen. --grace is a CLI flag since hyprlock 0.9.0; the old
        # general.grace config key is unregistered and was silently ignored
        # (see the comment in wm/hyprlock.nix). 2s of "any key unlocks" covers
        # locking by reflex and immediately changing your mind.
        "$mod, Escape, Lock screen, exec, hyprlock --grace 2"
        "$mod SHIFT, Escape, Log out (confirm), exec, walker -m menus:logout --theme dani-confirm --nohints --nosearch"

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

      # The only bind on this machine that works while the session is locked.
      #
      # Hyprland's KeybindManager skips every non-locked bind while a session
      # lock is active, and before this there were zero locked binds here —
      # verified with `hyprctl binds -j | jq '[.[]|select(.locked)]|length'`,
      # which returned 0. So if hyprlock died while locked, nothing on the
      # keyboard did anything, and with no text console that is a hard power
      # cycle. Paired with misc.allow_session_lock_restore above, this relaunches
      # a lock client that can attach to the orphaned lock.
      #
      # `bindld` is locked + described: it fires while locked AND still appears
      # in the $mod+/ keybinds palette, so it is discoverable before it is
      # needed instead of being folklore. (Both spellings were checked against
      # the 0.55.4 binary with --verify-config.)
      #
      # The chord is deliberately awkward. It must never be hit by accident, and
      # it is only ever useful in one situation.
      bindld = [
        "$mod CTRL ALT, L, Relaunch lock screen (works while locked), exec, hyprlock"
      ];

      input = {
        kb_layout = "us,es";
        # kb_options = "grp:ctrls_toggle,caps:super";
        # compose:menu makes the Menu key act as Multi_key. The Corne keymap
        # types accented characters as Compose sequences (Compose ' a -> a),
        # so without this they arrive as literal punctuation plus a letter.
        kb_options = "shift:both_capslock_cancel,compose:menu";
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
        #
        # 2026-09-18, second live A/B: the flat active slate became a two-stop
        # VALUE ramp within the same hue. This is not a walk-back of the July
        # decision — it is that decision taken further. What July rejected was a
        # *hue* gradient (yellow → orange → red, a different colour on each
        # edge); the rule it wrote was "signal by value, not hue". Both stops
        # here are the same slate family and both are already in the palette:
        # #737aa2 is the contrast floor used for hint text, #3b4261 is the
        # inactive gutter colour at full alpha. The focused frame reads as a lit
        # bevel — bright at the top-left, falling to gutter-dark at the
        # bottom-right — and is brighter overall than the flat #565f89 it
        # replaces, so focus is *more* legible, not merely different.
        #
        # Gradients interpolate in OkLab, not sRGB, so the midpoint stays in the
        # slate family instead of going muddy.
        #
        # Never pair this with `animation = borderangle, ..., loop`: that pins
        # both panels at full refresh permanently, on battery, whether or not a
        # gradient border is even on screen. Showcase profile only, if ever.
        "col.active_border" = "${theme.hyprRgba "hint" "ff"} ${theme.hyprRgba "gutter" "ff"} 45deg";
        "col.inactive_border" = (theme.hyprRgba "gutter" "88");
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

        # 16 and power 4 are ONE change, not two, and the pairing is the point.
        #
        # rounding_power is the exponent of the superellipse the corner is cut
        # from: 2.0 is a circular arc (the default), ~4 is the squircle — the
        # curvature runs continuously into the straight edge instead of meeting
        # it at a discontinuity, which is what makes the 2px border stop looking
        # kinked at the corners.
        #
        # Raising the exponent alone would make corners visibly *tighter*, so
        # the radius goes up to compensate. The happy result is that r16/p4
        # clips LESS of the application's own content than r12/p2 did:
        # ~18.7 px² per corner against ~30.9 px², i.e. a larger, softer corner
        # that destroys ~40% fewer app pixels.
        #
        # Free: same fragment shader, one different uniform. No extra pass, no
        # change to blur damage expansion. Shadow and the blur clip follow
        # automatically because all three read the same exponent.
        rounding = 16;
        rounding_power = 4.0;

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
      # Grammar note (Hyprland 0.53+, so: since the 26.05 bump). Layer rules are
      # now `<effect> <value>, match:namespace <regex>`:
      #   - every effect needs an explicit value, so bare `blur` is
      #     "invalid field blur: missing a value"
      #   - the namespace needs a literal `match:namespace ` prefix
      #   - effect names are snake_case (`noanim` -> `no_anim`)
      #   - `ignorezero` was removed outright. `ignore_alpha 0` is its exact
      #     equivalent, not an approximation: the surface shader discards on
      #     `alpha <= value`, and 0 is what ignorezero meant.
      layerrule = [
        "blur true, match:namespace waybar"
        "ignore_alpha 0, match:namespace waybar"
        "blur true, match:namespace walker"
        "ignore_alpha 0.4, match:namespace walker"
        "blur true, match:namespace notifications"
        "ignore_alpha 0, match:namespace notifications"
        "blur true, match:namespace swayosd"
        "ignore_alpha 0, match:namespace swayosd"

        # Mouseless puts its hint overlay on wlr-layer-shell, so the `layers`
        # animation below would pop it in over ~250ms — long enough that the
        # labels land after you have started typing them. It wants to be
        # instant, not pretty.
        "no_anim true, match:namespace mouseless-overlay"
      ];

      animations = {
        enabled = true;

        bezier = [
          # fast start, gentle landing — snappy without feeling abrupt
          "easeOutQuint, 0.23, 1, 0.32, 1"
        ];

        # durations are in deciseconds
        #
        # Arrivals decelerate, departures leave at constant speed.
        #
        # easeOutQuint is an *arrival* curve and it was being used for
        # departures too. Measured on its actual travel profile: a closing
        # window collapses 77% of its distance in the first ~60ms and then
        # spends ~137ms creeping the last 3%. That dead tail is what read as
        # sluggish — not the duration. `linear` commits and is gone, so the
        # close reads faster even though the nominal time barely moves
        # (250 -> 140ms).
        #
        # This is also cheaper, not just nicer: windowsOut, layersOut and
        # fadeSwitch are all registered AVARDAMAGE_ENTIRE, so every frame of
        # them re-damages the whole window rect and re-runs blur over it.
        # Shortening them removes full-window re-composites from the three most
        # frequent events on the desktop.
        #
        # `linear` and `default` are the only curves hyprlang predeclares —
        # almostLinear/quick/easeInOutCubic are Lua-only defaults and would be
        # "no such bezier" here.
        animation = [
          "windows, 1, 3, easeOutQuint, popin 92%"
          "windowsOut, 1, 1.4, linear, popin 92%"
          "fade, 1, 2.5, default"
          # Split off from `fade` so the focus step (the 0.94 <-> 0.88 opacity
          # change this config sets) gets its own, shorter ramp. Previously it
          # inherited `fade`, whose `default` curve is 66% travelled at 25ms —
          # a pop with a long tail rather than a fade.
          "fadeSwitch, 1, 2, default"
          "border, 1, 4, default"
          "workspaces, 1, 3.5, easeOutQuint, slide"
          "specialWorkspace, 1, 3, easeOutQuint, slidevert"
          "layers, 1, 2.5, easeOutQuint, popin 93%"
          "layersOut, 1, 1.2, linear, popin 93%"
        ];
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;

        # Lets a NEW session-lock client attach to an existing lock.
        #
        # A recovery option, not a cosmetic one. ext-session-lock-v1 requires
        # the compositor to keep the session locked if the lock client dies —
        # deliberately, so that a crashing locker can never expose the desktop.
        # The consequence is that a hyprlock crash leaves a blank, locked screen
        # with no client and no way back in. On legionix that is fatal: there is
        # no usable text console (/sys/class/vtconsole holds only a dummy
        # device), so "switch to a TTY" does not exist here and the only remedy
        # is a hard power cycle.
        #
        # With this on, a fresh hyprlock can take over the orphaned lock. It is
        # useless on its own though — see bindld below, because while a session
        # is locked Hyprland skips every bind not marked locked.
        allow_session_lock_restore = true;

        # `vfr` used to live here. It moved to `debug:vfr` in 0.55 and
        # `misc:vfr` is now a hard error ("config option <misc:vfr> does not
        # exist."). Deliberately NOT re-added as `debug.vfr = true` — that is
        # already the default, so the line would be pure noise. VFR is still on.
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

      # `windowrulev2` is gone as of 0.53 — it survives only as a registered
      # handler that returns "windowrulev2 is deprecated", i.e. a hard parse
      # error. The grammar was reworked too:
      #   - matchers take a literal `match:<prop> <value>` form, space-separated
      #   - every effect needs an explicit value (`float` -> `float true`)
      #   - effect names are snake_case (`bordersize` -> `border_size`)
      #   - `fullscreenstate` split into two int props, and `*` is no longer a
      #     wildcard (the int matcher is std::stoi) — "any" is expressed by
      #     omitting the prop
      # Regex matching is unchanged, so the patterns port as-is, Nix `\\.`
      # escaping included.
      windowrule = [
        # (Scratchpad geometry — float/size/centre — is owned by the
        # `scratchpad` helper, not windowrules: see the let block above.)
        # (The wallpaper picker needs no rule: it is a walker layer surface
        # now, not a window — see dani-wall in wm/walker.nix.)

        # Portal file choosers — every GTK or Flatpak app dialog. They carry no
        # hint Hyprland reads as a dialog, so they tile into the layout and
        # arrive as a cramped 620px column.
        "float true, match:class ^(xdg-desktop-portal-gtk)$"
        "center true, match:class ^(xdg-desktop-portal-gtk)$"
        "size 50% 65%, match:class ^(xdg-desktop-portal-gtk)$"

        "float true, match:class ^(firefox)$, match:title ^(Save As|Guardar como).*$"
        "size 70% 75%, match:class ^(firefox)$, match:title ^(Save As|Guardar como).*$"
        # Was `center 1`, where the 1 meant "ignore the reserved area" and put
        # the dialog in the middle of the whole monitor rather than below
        # waybar's strip. That variant no longer exists — `center` is a plain
        # bool now and always centres in the work area, so this dialog lands a
        # little lower than it used to. Accepted knowingly; the only way back
        # would be an explicit `move` rule.
        "center true, match:class ^(firefox)$, match:title ^(Save As|Guardar como).*$"
        "border_size 0, match:fullscreen_state_internal 1"
        "rounding 0, match:fullscreen_state_internal 1"

        # Media stays true-color: the glass treatment (0.94/0.88 + blur)
        # washes out video, photos and PDFs when windowed/unfocused, so
        # viewers and the screenshot editor render at full opacity
        "opacity 1.0 override 1.0 override, match:class ^(mpv|imv|org\\.pwmt\\.zathura|com\\.gabm\\.satty|com\\.obsproject\\.Studio)$"
        "opacity 1.0 override 1.0 override, match:title ^(Picture-in-Picture)$"
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
  #
  # Declared through `programs.elephant.provider.menus.toml` rather than as an
  # xdg.configFile: elephant.service's X-Restart-Triggers hashes that option
  # and nothing hashes a raw config file, so written the other way an edit to
  # this board lands on switch while the running daemon keeps serving the old
  # twelve entries until something restarts it. See the same note on the
  # logout menu below.
  programs.elephant.provider.menus.toml.scratchpads = {
    name = "scratchpads";
    name_pretty = "Scratchpads";
    icon = "view-restore";

    # Order matters: walker fills the grid row by row, four to a row, so the
    # first four are the most-used (Bluetooth, btop, quick note, WhatsApp) and
    # land in the top row. The rest follow. Twelve entries = exactly 4 x 3,
    # which is the size layout.xml sizes the window to — adding a thirteenth
    # starts a fourth row and the board scrolls.
    entries = [
      { text = "Bluetooth"; icon = "bluetooth"; actions.open = "${scratchpad}/bin/scratchpad bt 55 60 blueman-manager"; }
      { text = "btop"; icon = "utilities-system-monitor"; actions.open = "${scratchpad}/bin/scratchpad sysmon 60 65 alacritty --class scratch-sysmon -e btop"; }
      { text = "Quick note"; icon = "accessories-text-editor"; actions.open = "${scratchpad}/bin/scratchpad note 55 60 alacritty --class scratch-note -e quick-note"; }
      { text = "WhatsApp"; icon = "whatsapp"; actions.open = "${scratchpad}/bin/scratchpad whatsapp 40 66 whatsapp-web"; }
      { text = "Bitwarden"; icon = "bitwarden"; actions.open = "${scratchpad}/bin/scratchpad bitwarden 42 72 bitwarden-web"; }
      { text = "Terminal"; icon = "utilities-terminal"; actions.open = "${scratchpad}/bin/scratchpad term 60 62 alacritty --class scratch-term --working-directory ${config.home.homeDirectory}"; }
      { text = "Files"; icon = "folder"; actions.open = "${scratchpad}/bin/scratchpad files 65 68 alacritty --class scratch-files -e yazi"; }
      { text = "Audio"; icon = "multimedia-volume-control"; actions.open = "${scratchpad}/bin/scratchpad audio 48 58 pavucontrol"; }
      { text = "Calendar"; icon = "org.gnome.Calendar"; actions.open = "${scratchpad}/bin/scratchpad cal 62 68 gnome-calendar"; }
      { text = "GPU"; icon = "nvidia-settings"; actions.open = "${scratchpad}/bin/scratchpad gpu 60 65 alacritty --class scratch-gpu -e nvtop"; }
      { text = "Wi-Fi"; icon = "network-wireless"; actions.open = "${scratchpad}/bin/scratchpad wifi 55 60 nm-connection-editor"; }
      { text = "Weather"; icon = "org.gnome.Weather"; actions.open = "${scratchpad}/bin/scratchpad weather 55 62 gnome-weather"; }
    ];
  };

  # The $mod SHIFT+Escape logout confirmation, as an elephant menu so the two
  # answers can carry icons - walker's dmenu mode takes plain lines only.
  # Cancel is first so the pre-selected card is the harmless one, and Escape
  # closes walker without running anything either way.
  #
  # The bind passes --nosearch, so there is no prompt line and no live filter
  # to mistype into; the two labelled cards are the whole interface. Keep the
  # entries' text unambiguous on its own, since nothing above them explains
  # what is being asked.
  #
  # Declared through `programs.elephant.provider.menus.toml` rather than as an
  # xdg.configFile, because elephant.service's X-Restart-Triggers hashes that
  # option and nothing hashes a raw config file. Written the other way the
  # menu file lands on switch but the running daemon never rereads it, so the
  # picker comes up empty until the next reboot - elephant logs the giveaway,
  # `providers p=menus:logout results=0`. (scratchpads.toml above still has
  # this problem; it just gets masked by how rarely the board changes.)
  #
  # Logging out restarts the display manager rather than stopping UWSM,
  # because SDDM will not bring the greeter back on its own; the reasoning
  # lives on logout-to-greeter.service in modules/nixos/desktop/sddm.nix.
  # Both commands are absolute paths for the same reason the scratchpad
  # helper above is: elephant runs the action and does not inherit the
  # graphical session PATH. polkit still resolves elephant's process to the
  # active local session, so the unit-scoped rule applies and there is no
  # password prompt on the way out.
  programs.elephant.provider.menus.toml.logout = {
    name = "logout";
    name_pretty = "Log out";
    icon = "system-log-out-symbolic";

    entries = [
      {
        text = "Cancel";
        icon = "window-close-symbolic";
        actions.open = "${pkgs.coreutils}/bin/true";
      }
      {
        text = "Log out";
        icon = "system-log-out-symbolic";
        actions.open = "${pkgs.systemd}/bin/systemctl start --no-block logout-to-greeter.service";
      }
    ];
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
