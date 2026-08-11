{ config, lib, pkgs, ... }:

# ALTERNATIVE to modules/nixos/mouseless.nix — import one or the other, never
# both (mouseless.nix grants `input` to the whole login session, which would
# make everything below pointless).
#
# Same app, same Flatpak, same keyd exclusion (that lives in keyd.nix and
# applies either way). The only difference is who holds the `input` group.
#
#   mouseless.nix         dani holds `input` for the whole session, so every
#                         process running as dani can read every keystroke.
#   mouseless-scoped.nix  only this one systemd unit holds it. The login
#                         session does not.
#
# Why this works at all, since it looks like it shouldn't: `flatpak run` execs
# bwrap in the calling process — no setuid helper, nothing that resets
# credentials — and bwrap never calls setgroups(2). It only writes "deny" to
# /proc/self/setgroups, which blocks *future* setgroups() calls and leaves the
# existing set alone. Inside the sandbox `id` reports the group as 65534
# (nogroup) because it is unmapped in the namespace's gid_map, but the kernel
# compares raw kgid_t values in in_group_p() with no namespace translation, so
# the access still passes. Verified on this machine against /run/docker.sock.
#
# Start it from the Hyprland session (the Wayland socket it needs only exists
# there); the polkit rule below is what lets dani do that without sudo:
#
#   systemctl start mouseless
#
let
  user = "dani";

  mouseless-session = pkgs.writeShellApplication {
    name = "mouseless-session";
    runtimeInputs = with pkgs; [ flatpak systemd coreutils gnused ];
    text = ''
      runtime="/run/user/$(id -u)"
      export XDG_RUNTIME_DIR="$runtime"
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus"

      # The graphical session's own recorded environment — uwsm imports it into
      # the systemd --user manager at login, so DISPLAY and WAYLAND_DISPLAY are
      # the real per-boot values rather than something we guessed.
      #
      # Read a fixed allowlist and nothing else. Any process in the session can
      # rewrite that manager environment, and this unit holds a group the
      # session deliberately does not — so passing an arbitrary variable
      # through, LD_PRELOAD above all, would hand `input` straight back to
      # whatever we are trying to contain. None of the four below can execute
      # code; the worst they can do is point the overlay at the wrong display.
      senv="$(systemctl --user show-environment)"

      pick() {
        printf '%s\n' "$senv" | sed -n "s/^$1=//p" | head -n1
      }

      WAYLAND_DISPLAY="$(pick WAYLAND_DISPLAY)"
      DISPLAY="$(pick DISPLAY)"
      HYPRLAND_INSTANCE_SIGNATURE="$(pick HYPRLAND_INSTANCE_SIGNATURE)"
      xauth="$(pick XAUTHORITY)"

      export WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE

      # Hyprland's XWayland runs cookieless here, so XAUTHORITY is usually
      # absent. Exporting it empty would send X clients looking for a file
      # called "" instead of falling back, so only set it if it is real.
      if [ -n "$xauth" ]; then
        export XAUTHORITY="$xauth"
      fi

      if [ -z "$WAYLAND_DISPLAY" ]; then
        echo "mouseless: no WAYLAND_DISPLAY in the session environment - is Hyprland running?" >&2
        exit 1
      fi

      exec flatpak run net.sonuscape.mouseless "$@"
    '';
  };
in
{
  services.flatpak.enable = true;
  hardware.uinput.enable = true;

  # Note what is NOT here: users.users.dani.extraGroups. That is the whole
  # point of this file.
  systemd.services.mouseless = {
    description = "Mouseless, with input access scoped to this unit";

    # Deliberately not wantedBy any target. There is no Wayland socket to
    # attach to until dani logs in, so this is started by hand from the
    # session, not at boot.
    serviceConfig = {
      Type = "simple";
      User = user;
      Environment = [ "HOME=${config.users.users.${user}.home}" ];

      # systemd runs as root, so it can hand the process groups the user does
      # not otherwise hold. A systemd *user* service cannot do this — that is
      # why this is a system unit despite being a desktop app.
      SupplementaryGroups = [ "input" "uinput" ];

      ExecStart = lib.getExe mouseless-session;
      Restart = "no";

      # No PrivateTmp / ProtectHome hardening: XWayland's socket lives in
      # /tmp/.X11-unix and the app's config lives under ~, so both would break
      # the thing outright.
    };
  };

  # A system unit is root-managed by default. This lets dani — and only dani,
  # only from a local active session, and only for this one unit — start and
  # stop it without sudo.
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "mouseless.service" &&
          subject.user == "${user}" && subject.local && subject.active) {
        return polkit.Result.YES;
      }
    });
  '';
}
