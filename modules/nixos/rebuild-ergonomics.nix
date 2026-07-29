{ config, pkgs, ... }:

let
  # Build every host + flake check before switching. This repo is a
  # multi-host flake and a change must not break the non-NVIDIA host
  # (danix-hp) or the VM (danixos-vm); this catches that here instead of
  # after a switch. Defaults to ~/nixos-config; pass a flake path to override.
  checkAll = pkgs.writeShellApplication {
    name = "check-all";
    runtimeInputs = [ pkgs.nix ];
    text = ''
      flake="''${1:-$HOME/nixos-config}"
      echo "==> nix flake check $flake"
      nix flake check "$flake"
      for host in legionix danix-hp danixos-vm; do
        echo "==> building $host"
        nix build "$flake#nixosConfigurations.$host.config.system.build.toplevel" --no-link
      done
      echo "==> OK: all hosts build and flake check passed"
    '';
  };
in
{
  # Show the store closure diff on every `nixos-rebuild switch` — what
  # packages were added, removed, or changed version. `nh os switch` already
  # prints this; the activation hook covers plain `nixos-rebuild switch` too.
  # It runs during activation while /run/current-system still points at the
  # old system, diffing it against the one being activated ($systemConfig).
  system.activationScripts.nvd-diff = {
    supportsDryActivation = false;
    text = ''
      if [ -e /run/current-system ]; then
        ${pkgs.nvd}/bin/nvd --nix-bin-dir=${config.nix.package}/bin \
          diff /run/current-system "$systemConfig" || true
      fi
    '';
  };

  # nvd on PATH for manual diffs (e.g. `nvd diff /run/current-system <path>`);
  # check-all for the pre-switch all-hosts build.
  environment.systemPackages = [ pkgs.nvd checkAll ];
}
