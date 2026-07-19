{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix

    # LUKS2 + btrfs layout (the legionix migration rehearsal)
    ../../modules/nixos/disko-luks.nix

    # common system modules
    ../../modules/nixos/users/dani.nix
    ../../modules/nixos/access.nix
    ../../modules/nixos/base.nix
    ../../modules/nixos/virtualisation.nix
    ../../modules/nixos/security.nix
    ../../modules/nixos/gaming.nix

    # choose your desktop
    # ../../modules/nixos/desktop/hyprland.nix
    ../../modules/nixos/desktop/cinnamon.nix
  ];

  networking.hostName = "danixos-vm";

  # virtio disk inside libvirt (stable across VM rebuilds, unlike by-id)
  disko.devices.disk.main.device = "/dev/vda";
}

