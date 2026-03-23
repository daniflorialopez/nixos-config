{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    # ./partitions.nix

    # common system modules
    ../../modules/nixos/base.nix
    ../../modules/nixos/virtualisation.nix
    ../../modules/nixos/security.nix
    ../../modules/nixos/gaming.nix
    ../../modules/nixos/disko.nix
    ../../modules/nixos/tlp.nix
    ../../modules/nixos/fonts.nix
    ../../modules/nixos/keyd.nix
 
    # desktop environment
    ./desktop.nix
  ];

  networking.hostName = "legionix";
}

