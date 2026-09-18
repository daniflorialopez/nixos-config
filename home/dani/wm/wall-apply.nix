# The one place that turns "which wallpaper is selected" into "what is actually
# on screen". Shared rather than inlined, because three separate things have to
# perform exactly this reconciliation and they must not drift apart:
#
#   - wall-set, straight after recording a new choice
#   - the awww unit's ExecStartPost, at login and after a crash restart
#   - hypr-dock-handler, when an output is (re)connected
#
# Deliberately NOT awww's own cache. awww keeps a per-output cache and restores
# from it at daemon start, but it is the wrong thing to build on:
#
#   - it lives in ~/.cache/awww/<version>/, and awww prunes the previous
#     version's directory on startup, so the first login after an awww bump has
#     nothing to restore from
#   - it records a path, not an image, so deleting or corrupting the file leaves
#     the restore doing nothing useful
#   - `awww restore` exits 0 even when it restored nothing whatsoever (verified
#     against an emptied cache: two warnings on stderr, status 0), so no unit can
#     branch on it
#
# ~/.local/state/wallpaper/current is written by wall-set, lives outside the
# cache, and survives awww upgrades. That is the authority — and because awww's
# cache restore would otherwise race this script and win, the daemon is started
# with `--no-cache` so there is exactly one writer to the screen. See the
# ExecStart comment in wallpaper.nix.
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
      # 75 fps is a deliberate fixed ceiling, not a per-output refresh match.
      # The transition is composited on the CPU into wl_shm buffers and a
      # 2560x1440 frame is ~14 MB, so this bounds a second's worth of memcpy.
      # Nobody can distinguish 75 from 165 in a one-second crossfade, and the
      # other two hosts this module builds for have different panels anyway.
      apply() {
        awww img "$1" \
          --resize crop \
          --transition-type fade \
          --transition-duration 1 \
          --transition-fps 75
      }

      # Fall back on FAILURE TO APPLY, not merely on a missing path.
      #
      # The `[ ! -f ]` test above is necessary but nowhere near sufficient, and
      # on its own it guarded the wrong failure: a file that exists but cannot
      # be decoded takes the other branch, so the fallback that exists
      # precisely for "the wallpaper is broken" was unreachable in exactly that
      # case. Verified — pointing the state file at a text file named .png
      # makes awww img exit 1 with "Unrecognized format by image crate".
      if ! apply "$img"; then
        if [ "$img" = "${fallback}" ]; then
          echo "wall-apply: the store fallback itself failed to apply" >&2
          exit 1
        fi
        echo "wall-apply: $img failed to apply; using the store fallback" >&2
        apply "${fallback}"
      fi
    '';
  };
}
