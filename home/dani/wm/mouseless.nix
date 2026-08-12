{ lib, osConfig ? null, pkgs, ... }:

# Launcher guard and panic kill for Mouseless (system side:
# modules/nixos/mouseless.nix, imported by legionix only).
#
# Why this file exists. On 2026-08-12 Mouseless wedged every keyboard on this
# machine: keyd grabbed Mouseless's own virtual keyboard and fed its output
# back into the chain, which is the feedback loop the vendor explicitly warns
# about. modules/nixos/keyd.nix does exclude vendor 736e — but a stale,
# hand-written /etc/keyd/vibranium-f-practice.conf carrying a bare `[ids] *`
# matched those devices anyway and closed the loop. That file predates this
# flake managing keyd and is not produced by it.
#
# What makes that failure nasty is that nothing keyboard-shaped can undo it.
# An EVIOCGRAB makes the input core deliver events only to the grabbing
# handle, which bypasses the kernel's own `kbd` and `sysrq` input handlers —
# so Ctrl+Alt+F2 does not switch VT and Magic SysRq does not fire, however
# hard you press them. Mouseless grabs keyboards only, never pointers, so the
# mouse survives. That is the entire basis of the recovery story here:
#
#   - the bar button (custom/mouseless in waybar.nix) — mouse only, no typing
#   - `mouseless-panic` over SSH from the phone (Tailscale: legionix)
#   - the power button, which logind still sees, for a clean shutdown
let
  appId = "net.sonuscape.mouseless";

  # Only legionix pulls in modules/nixos/flatpak.nix (via mouseless.nix), so
  # this doubles as the host gate. danix-hp runs Hyprland and therefore loads
  # every other wm/ module, and would otherwise get a launcher for an app it
  # does not have.
  hasFlatpak = osConfig != null && (osConfig.services.flatpak.enable or false);

  mouseless-panic = pkgs.writeShellApplication {
    name = "mouseless-panic";
    runtimeInputs = with pkgs; [ coreutils flatpak gawk procps ];
    text = ''
      # Set this explicitly rather than trusting the environment. Without
      # XDG_RUNTIME_DIR, `flatpak ps` prints nothing *and exits 0*, so run
      # over SSH this would cheerfully report "not running" while the keyboard
      # is still dead — the one failure mode a panic script must not have.
      XDG_RUNTIME_DIR="/run/user/$(id -u)"
      export XDG_RUNTIME_DIR

      ids="$(flatpak ps --columns=instance,application 2>/dev/null \
             | awk -v app="${appId}" '$2 == app { print $1 }')" || ids=""

      if [ -z "$ids" ]; then
        echo "mouseless: not running"
        exit 0
      fi

      # Kill by instance id. `flatpak kill <app-id>` reports only one instance,
      # and `pkill -f` is worse than useless here: the pattern appears in the
      # invoking shell's own command line, so it kills the caller.
      printf '%s\n' "$ids" | while read -r id; do
        echo "mouseless: killing instance $id"
        flatpak kill "$id" || true
      done

      # flatpak kill is an uncatchable SIGKILL, so the app runs no cleanup.
      # That is fine, and is in fact the point: the kernel closes the evdev
      # fds on process death, which drops the EVIOCGRAB and returns the
      # keyboard whether or not the app was in a state to cooperate.
      pkill -RTMIN+11 waybar || true
    '';
  };

  mouseless-guarded = pkgs.writeShellApplication {
    name = "mouseless-guarded";
    runtimeInputs = with pkgs; [ coreutils flatpak libnotify util-linux ];
    text = ''
      XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      export XDG_RUNTIME_DIR

      # A mouseless:// deep link is meant to reach an already-running instance
      # (toggle-overlay, settings, ...), so it must pass straight through.
      # Taking the lock here would break every deep link while the app is up.
      if [ "$#" -gt 0 ]; then
        exec flatpak run ${appId} "$@"
      fi

      # Mouseless does ship its own single-instance flock, but it can only run
      # once python has started inside the sandbox — plausibly after the evdev
      # grab. This one refuses before any process exists at all. It is also the
      # only one that says so: the app's guard exits silently, which is exactly
      # what made a second launch look like nothing had happened.
      rc=0
      flock -n -E 99 "$XDG_RUNTIME_DIR/mouseless.lock" \
        flatpak run ${appId} || rc=$?

      if [ "$rc" -eq 99 ]; then
        # -t is not optional: mako sets default-timeout = 0, so an unqualified
        # notification sits on screen until dismissed.
        notify-send -t 4000 -u critical "Mouseless is already running" \
          "Not starting a second instance. Use the bar button, or run mouseless-panic, to stop it." \
          || true
        exit 0
      fi

      exit "$rc"
    '';
  };
in
lib.mkIf hasFlatpak {
  # mouseless-panic must be on PATH: waybar's on-click calls it by bare name,
  # and it is what gets typed over SSH when the keyboard is gone.
  home.packages = [ mouseless-guarded mouseless-panic ];

  # Shadow the Flatpak's exported desktop entry so the launcher routes through
  # the guard. This must be xdg.dataFile, NOT xdg.desktopEntries: the latter
  # goes through home.packages into /etc/profiles/per-user/dani/share, which
  # sits *after* ~/.local/share/flatpak/exports/share in XDG_DATA_DIRS and
  # would silently lose. XDG_DATA_HOME outranks every XDG_DATA_DIRS entry, and
  # walker's backend (elephant) keys desktop entries by basename, first
  # directory wins — so keeping the vendor's exact filename replaces the entry
  # rather than adding a second one.
  #
  # Known gap: elephant's `runner` provider also lists the plain binary
  # ~/.local/share/flatpak/exports/bin/net.sonuscape.mouseless from PATH, and
  # has no blacklist. That route still calls `flatpak run` directly and skips
  # this guard. Nothing host-side can intercept `flatpak run`, so the app's own
  # single-instance flock is what covers that path.
  xdg.dataFile."applications/${appId}.desktop".text = ''
    [Desktop Entry]
    Version=1.0
    Type=Application
    Name=Mouseless
    Comment=Lightning-fast mouse control with the keyboard
    Exec=${lib.getExe mouseless-guarded} %u
    Icon=${appId}
    Categories=Utility;
    Terminal=false
    MimeType=x-scheme-handler/mouseless;
  '';
}
