{ config, lib, pkgs, ... }:

# Flatpak, plus the remotes that make it useful.
#
# Remotes are imperative state under ~/.local/share/flatpak, so they do not
# travel with the flake. A fresh install comes up with Flatpak enabled and zero
# remotes, and the first `flatpak install` then dies with
#
#   error: ... requires the runtime org.gnome.Platform/x86_64/50 which was not found
#
# which is exactly how this gap got noticed. So re-register them on every boot.
# `--if-not-exists` short-circuits on the name, making it a ~0.5s no-op that
# does not touch the network once the remote is already there.
let
  user = "dani";

  remotes = {
    # Runtimes live here — nearly every Flatpak needs it, including the GNOME
    # platform Mouseless is built against.
    flathub = "https://dl.flathub.org/repo/flathub.flatpakrepo";

    # Mouseless, GPG-signed by the vendor (see mouseless.nix).
    sonuscape = "https://dl.sonuscape.net/flatpak/sonuscape.flatpakrepo";
  };

  flatpak-remotes-init = pkgs.writeShellApplication {
    name = "flatpak-remotes-init";
    runtimeInputs = [ pkgs.flatpak pkgs.coreutils ];
    text = ''
      # Try every remote rather than aborting on the first failure: they are
      # independent, and giving up early would leave a half-registered set that
      # looks fine until something needs the missing one.
      #
      # Each remote gets a few attempts. network-online.target is reached before
      # DNS actually resolves on this machine - modules/nixos/base.nix disables
      # NetworkManager-wait-online to save ~5s off graphical.target - so the
      # first attempt routinely fails with "Could not resolve hostname" even
      # though the network comes up moments later. Ordering after
      # nss-lookup.target (see the unit below) plus a short retry turns that from
      # a guaranteed failure into a non-event.
      add() {
        local name="$1" url="$2"
        # `_` rather than a named counter: writeShellApplication runs shellcheck
        # and fails the build on SC2034 for an unused loop variable.
        for _ in 1 2 3 4 5; do
          if flatpak remote-add --user --if-not-exists "$name" "$url"; then
            return 0
          fi
          sleep 3
        done
        echo "flatpak-remotes: could not add '$name' after 5 attempts; will retry next boot" >&2
        return 1
      }

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: url: "add ${name} ${url} || true") remotes)}

      # Deliberately exit 0 even when a remote could not be registered.
      #
      # The script already handles that case correctly - it warns and retries on
      # the next boot - but it used to propagate rc=1 anyway, which left
      # flatpak-remotes.service permanently `failed` on a machine that is
      # otherwise clean. That is worse than it sounds: `systemctl --failed` is
      # the first thing you run when something is wrong, and a unit that is
      # always red destroys its value as a signal. A genuinely new failure had
      # nothing to stand out against.
      #
      # The failure is not silent - it is a warning in the journal, and the
      # missing remote is visible in `flatpak remotes`.
      exit 0
    '';
  };
in
{
  services.flatpak.enable = true;

  systemd.services.flatpak-remotes = {
    description = "Register Flatpak remotes for ${user}";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    # nss-lookup.target as well as network-online.target: base.nix disables
    # NetworkManager-wait-online, so network-online is reached while DNS is
    # still coming up and every remote-add fails to resolve its hostname.
    after = [ "network-online.target" "nss-lookup.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = user;
      Environment = [ "HOME=${config.users.users.${user}.home}" ];
      ExecStart = lib.getExe flatpak-remotes-init;
    };
  };
}
