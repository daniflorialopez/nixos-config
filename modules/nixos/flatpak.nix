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
    runtimeInputs = [ pkgs.flatpak ];
    text = ''
      rc=0

      # Try every remote rather than aborting on the first failure: they are
      # independent, and giving up early would leave a half-registered set that
      # looks fine until something needs the missing one.
      add() {
        if ! flatpak remote-add --user --if-not-exists "$1" "$2"; then
          echo "flatpak-remotes: could not add '$1' (network down?), will retry next boot" >&2
          rc=1
        fi
      }

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: url: "add ${name} ${url}") remotes)}

      exit "$rc"
    '';
  };
in
{
  services.flatpak.enable = true;

  systemd.services.flatpak-remotes = {
    description = "Register Flatpak remotes for ${user}";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = user;
      Environment = [ "HOME=${config.users.users.${user}.home}" ];
      ExecStart = lib.getExe flatpak-remotes-init;
    };
  };
}
