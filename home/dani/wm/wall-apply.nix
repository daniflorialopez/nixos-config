# The one place that turns "which wallpaper is selected" into "what is actually
# on screen". Shared rather than inlined, because three separate things have to
# perform exactly this reconciliation and they must not drift apart:
#
#   - wall-set, straight after recording a new choice
#   - the awww unit's ExecStartPost, at login and after a crash restart
#   - hypr-dock-handler, when an output is (re)connected
#
# Deliberately NOT `awww restore`. awww does keep a per-output cache and restore
# does read it, but it is the wrong thing to build on:
#
#   - the cache lives in ~/.cache/awww/<version>/, so upgrading awww invalidates
#     it wholesale — and awww prunes the old version's directory on startup, so
#     the first login after a bump comes up black with nothing to recover from
#   - it records a path, not an image, so deleting the file turns restore into a
#     silent no-op that leaves the previous frame up
#   - `awww restore` exits 0 even when it restored nothing whatsoever (verified
#     against an emptied cache: two warnings on stderr, status 0), so no unit can
#     branch on it
#
# ~/.local/state/wallpaper/current is written by wall-set, lives outside the
# cache, and survives awww upgrades. That is the authority here; awww's cache is
# left as the incidental optimisation it is.
{ pkgs, config }:

rec {
  stateFile = "${config.home.homeDirectory}/.local/state/wallpaper/current";

  # A store path, not "${wallpaperDir}/default.png". The library is a writable
  # directory the user owns — nothing stops default.png being renamed, replaced
  # with something unreadable, or deleted — and the moment the wallpaper daemon
  # is the thing that failed there is no desktop left to repair it from. This
  # one is read-only, content-addressed, and rolls back with the generation.
  fallback = "${../assets/wallpapers}/default.png";

  package = pkgs.awww;

  wallApply = pkgs.writeShellApplication {
    name = "wall-apply";
    runtimeInputs = [ pkgs.coreutils package ];
    text = ''
      set -eu

      img=""
      if [ -r "${stateFile}" ]; then
        img=$(cat "${stateFile}")
      fi

      if [ -z "$img" ] || [ ! -f "$img" ]; then
        img="${fallback}"
      fi

      # awww-daemon implements no sd_notify, so the unit cannot be Type=notify
      # and ExecStartPost is reached while the daemon is still binding its
      # socket. `awww img` against a missing socket is a hard error rather than
      # a retry, so wait for the daemon to actually answer before asking it for
      # anything. Four seconds is ~20x what it took to come up when measured.
      ready=0
      for _ in $(seq 40); do
        if awww query >/dev/null 2>&1; then
          ready=1
          break
        fi
        sleep 0.1
      done

      if [ "$ready" -eq 0 ]; then
        echo "wall-apply: awww-daemon did not answer within 4s" >&2
        exit 1
      fi

      # --resize crop is what hyprpaper's `fit_mode = cover` meant, and is
      # stated rather than left to the default because it is load-bearing: any
      # other mode letterboxes the 21:9 wallpapers in the library.
      #
      # 75 fps is HDMI-A-1's exact refresh; eDP-1 runs 165 but the transition is
      # composited on the CPU into wl_shm buffers, and a 2560x1440 frame is
      # ~14 MB, so matching the slower panel halves a second's worth of memcpy
      # for a difference nobody can see in a one-second crossfade.
      awww img "$img" \
        --resize crop \
        --transition-type fade \
        --transition-duration 1 \
        --transition-fps 75
    '';
  };
}
