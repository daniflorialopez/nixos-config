{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./partitions.nix

    # common system modules
    ../../modules/nixos/base.nix
    ../../modules/nixos/virtualisation.nix
    ../../modules/nixos/security.nix
    ../../modules/nixos/gaming.nix
    ../../modules/nixos/disko.nix
    ../../modules/nixos/tlp.nix
    ../../modules/nixos/fonts.nix
 
    # choose your desktop
    # ../../modules/nixos/desktop/hyprland.nix
    ../../modules/nixos/desktop/cinnamon.nix
  ];

  networking.hostName = "danix-hp";
}

