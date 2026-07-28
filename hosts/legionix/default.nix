{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix

    # common system modules
    ../../modules/nixos/users/dani.nix
    ../../modules/nixos/access.nix
    ../../modules/nixos/base.nix
    ../../modules/nixos/virtualisation.nix
    ../../modules/nixos/security.nix
    ../../modules/nixos/gaming.nix
    ../../modules/nixos/efootball-block.nix
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/restic.nix
    ../../modules/nixos/bluetooth.nix

    ../../modules/nixos/disko.nix
    ../../modules/nixos/tlp.nix
    ../../modules/nixos/fonts.nix
    ../../modules/nixos/keyd.nix
    ../../modules/nixos/corne.nix
    #../../modules/nixos/keyd-vibranium-practice.nix
    ../../modules/nixos/hardware-health.nix
    ../../modules/nixos/diagnostics.nix 
 
    # desktop environment
    ./desktop.nix
    ./gpu.nix
  ];

  networking.hostName = "legionix";

  disko.devices.disk.main.device = "/dev/disk/by-id/nvme-SAMSUNG_MZVL21T0HCLR-00BL2_S64NNX0T568436";
}

