{ config, lib, pkgs, osConfig ? null, ... }:

# Screen recording and instant replay (gap item 10b). System side:
# modules/nixos/screen-recording.nix (the setcap capture helper).
#
#   ALT+Print          start / stop recording the monitor you are on
#   $mod SHIFT+Print   arm / disarm instant replay (keeps the last 30 s)
#   $mod+Print         save the replay buffer
#   $mod SHIFT+S       the Capture menu: all of the above plus the three
#                      screenshot subjects, as cards
#
# Files land in ~/Videos/Recordings and ~/Videos/Replays. A waybar leaf shows
# an orange dot while recording and a quiet replay marker while armed.
let
  # Only hosts that import screen-recording.nix get any of this: without the
  # setcap helper, gpu-screen-recorder falls back to a pkexec password prompt.
  enabled = osConfig != null && (osConfig.programs.gpu-screen-recorder.enable or false);

  # The system profile's binary, by absolute path: the replay unit runs with a
  # minimal PATH, and this is the build the module paired with its wrapper.
  gsr = "/run/current-system/sw/bin/gpu-screen-recorder";

  recordingsDir = "${config.home.homeDirectory}/Videos/Recordings";
  replaysDir = "${config.home.homeDirectory}/Videos/Replays";

  # Shared by both: Wayland has no "focused window" capture, so name the
  # monitor the user is on.
  focusedMonitor = ''hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' '';

  # Called by gpu-screen-recorder after it writes a file (-sc): $1 is the path,
  # $2 the kind (regular / replay). A short toast - the file is the result.
  savedHook = pkgs.writeShellApplication {
    name = "gsr-saved";
    runtimeInputs = [ pkgs.libnotify pkgs.procps ];
    text = ''
      case "''${2:-}" in
        replay) what="Replay" ;;
        *) what="Recording" ;;
      esac
      notify-send -t 4000 -i media-record "$what saved" "''${1/#$HOME/\~}"
      pkill -RTMIN+12 waybar || true
    '';
  };

  recordToggle = pkgs.writeShellApplication {
    name = "record-toggle";
    runtimeInputs = with pkgs; [ hyprland jq libnotify procps coreutils util-linux ];
    text = ''
      pidfile="$XDG_RUNTIME_DIR/record-toggle.pid"

      if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        # SIGINT = stop and save; the -sc hook announces the file
        kill -INT "$(cat "$pidfile")"
        rm -f "$pidfile"
        exit 0
      fi

      mkdir -p "${recordingsDir}"
      out="${recordingsDir}/rec-$(date +%Y%m%d-%H%M%S).mp4"
      mon="$(${focusedMonitor})"

      # setsid: the recorder must outlive this script and the bind that ran it
      setsid ${gsr} -w "$mon" -f 60 -a default_output -c mp4 \
        -sc ${lib.getExe savedHook} -o "$out" >/dev/null 2>&1 &
      echo $! > "$pidfile"

      notify-send -t 2000 -i media-record "Recording $mon" "ALT+Print again to stop"
      pkill -RTMIN+12 waybar || true
    '';
  };

  # The replay buffer: 30 s of the focused monitor (as of arming), kept in RAM.
  replayRun = pkgs.writeShellApplication {
    name = "gsr-replay";
    runtimeInputs = with pkgs; [ hyprland jq coreutils ];
    text = ''
      mkdir -p "${replaysDir}"
      exec ${gsr} -w "$(${focusedMonitor})" -f 60 -a default_output -c mp4 \
        -r 30 -replay-storage ram -sc ${lib.getExe savedHook} -o "${replaysDir}"
    '';
  };

  replayToggle = pkgs.writeShellApplication {
    name = "replay-toggle";
    runtimeInputs = with pkgs; [ systemd libnotify procps ];
    text = ''
      if systemctl --user is-active --quiet gsr-replay.service; then
        systemctl --user stop gsr-replay.service
        notify-send -t 2000 -i media-playback-stop "Instant replay off"
      else
        systemctl --user start gsr-replay.service
        notify-send -t 2000 -i media-record "Instant replay armed" "SUPER+Print saves the last 30 s"
      fi
      pkill -RTMIN+12 waybar || true
    '';
  };

  replaySave = pkgs.writeShellApplication {
    name = "replay-save";
    runtimeInputs = with pkgs; [ systemd libnotify ];
    text = ''
      if systemctl --user is-active --quiet gsr-replay.service; then
        systemctl --user kill --signal=SIGUSR1 gsr-replay.service
      else
        notify-send -t 3000 -i dialog-information "Instant replay is off" "SUPER+SHIFT+Print arms it"
      fi
    '';
  };

  # The Capture menu ($mod SHIFT+S): one front door for every capture
  # action, so none of the shortcuts has to be remembered.
  #
  # capture-state tells the Lua menu what is running, so the cards read
  # "Stop recording" / "Disarm replay" when those are live.
  captureState = pkgs.writeShellApplication {
    name = "capture-state";
    runtimeInputs = with pkgs; [ systemd coreutils ];
    text = ''
      pidfile="$XDG_RUNTIME_DIR/record-toggle.pid"
      if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        echo recording
      else
        echo idle
      fi
      if systemctl --user is-active --quiet gsr-replay.service; then
        echo armed
      else
        echo off
      fi
    '';
  };

  # What each card does. Screenshots wait for walker's layer to unmap first:
  # otherwise the frozen frame (and the monitor/window shots) would contain
  # the menu that launched them. elephant runs this with its own PATH, which
  # includes the home-manager profile, so the bare names below resolve.
  captureDo = pkgs.writeShellApplication {
    name = "capture-do";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      case "''${1:-}" in
        region|output|window) sleep 0.35; exec screenshot "$1" ;;
        record) exec record-toggle ;;
        replay) exec replay-toggle ;;
        save)   exec replay-save ;;
        *) echo "capture-do: unknown action ''${1:-}" >&2; exit 2 ;;
      esac
    '';
  };

  captureMenu = ''
    Name = "capture"
    NamePretty = "Capture"
    Icon = "camera-photo-symbolic"
    -- fixed order: elephant otherwise sorts A-Z, and the first card is the
    -- pre-selected one (see the power menu in wm/hyprland.nix)
    FixedOrder = true
    -- no Cache: GetEntries runs on every open, so the labels follow state
    Action = '${lib.getExe captureDo} %VALUE%'

    function GetEntries()
      local recording, armed = false, false
      local h = io.popen("${lib.getExe captureState}")
      if h then
        local state = h:read("*a") or ""
        h:close()
        recording = state:find("recording") ~= nil
        armed = state:find("armed") ~= nil
      end

      local function card(text, icon, value)
        return { Text = text, Icon = icon, Value = value }
      end

      return {
        card("Region", "selection-mode-symbolic", "region"),
        card("Monitor", "video-display-symbolic", "output"),
        card("Window", "focus-windows-symbolic", "window"),
        recording and card("Stop rec", "media-playback-stop-symbolic", "record")
                   or card("Record", "media-record-symbolic", "record"),
        armed and card("Replay off", "media-playback-stop-symbolic", "replay")
               or card("Replay", "media-playlist-repeat-symbolic", "replay"),
        card("Save replay", "document-save-symbolic", "save"),
      }
    end
  '';

  # Silent when idle: an orange dot while recording (attention: the screen is
  # being captured), a dim marker while the replay buffer is armed.
  recordingStatus = pkgs.writeShellApplication {
    name = "waybar-recording";
    runtimeInputs = with pkgs; [ systemd coreutils ];
    text = ''
      pidfile="$XDG_RUNTIME_DIR/record-toggle.pid"
      if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        printf '{"text":"● REC","class":"recording","tooltip":"Recording · ALT+Print to stop"}\n'
      elif systemctl --user is-active --quiet gsr-replay.service; then
        printf '{"text":"󰑙","class":"replay","tooltip":"Instant replay armed · SUPER+Print saves 30 s · SUPER+SHIFT+Print disarms"}\n'
      else
        printf '{"text":"","tooltip":""}\n'
      fi
    '';
  };
in
lib.mkMerge [
# The bar leaf is defined on every host (it hides itself when idle, like the
# gpu and efootball leaves), so waybar.nix can list it unconditionally.
{
  programs.waybar.settings.mainBar."custom/recording" = {
    exec = lib.getExe recordingStatus;
    return-type = "json";
    interval = 5;
    signal = 12; # pkill -RTMIN+12 from the scripts above
    format = "{}";
    on-click = "record-toggle";
  };
}
(lib.mkIf enabled {
  home.packages = [ recordToggle replayToggle replaySave ];

  # Written as a file with an onChange restart rather than through
  # programs.elephant.provider.menus: elephant scans menus once at startup, and
  # only an onChange (ordered after linkGeneration) guarantees the file exists
  # when it rescans - the race documented on wallpapers.lua in wallpaper.nix.
  xdg.configFile."elephant/menus/capture.lua" = {
    text = captureMenu;
    onChange = "${pkgs.systemd}/bin/systemctl --user try-restart elephant.service";
  };

  # Deliberately not WantedBy anything: armed by hand until its idle cost has
  # been measured (an always-running encoder plus a 30 s RAM buffer).
  systemd.user.services.gsr-replay = {
    Unit = {
      Description = "Instant replay buffer (gpu-screen-recorder)";
      PartOf = [ config.wayland.systemd.target ];
      After = [ config.wayland.systemd.target ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = lib.getExe replayRun;
      # SIGINT is "stop without saving" in replay mode - a clean stop
      KillSignal = "SIGINT";
      Restart = "on-failure";
    };
  };

  wayland.windowManager.hyprland.settings.bindd = [
    "ALT, Print, Start or stop screen recording, exec, record-toggle"
    "$mod SHIFT, Print, Arm or disarm instant replay, exec, replay-toggle"
    "$mod, Print, Save instant replay - last 30 s, exec, replay-save"
    # the front door to all of the above, Windows' snipping-tool chord
    "$mod SHIFT, S, Capture menu, exec, walker -m menus:capture --theme dani-confirm --nohints --nosearch"
  ];

})
]
