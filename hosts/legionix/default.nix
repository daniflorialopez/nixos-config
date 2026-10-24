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
    ../../modules/nixos/nix-ld.nix
    ../../modules/nixos/restic.nix
    ../../modules/nixos/bluetooth.nix

    ../../modules/nixos/disko.nix
    ../../modules/nixos/tlp.nix
    ../../modules/nixos/battery-conservation.nix
    ../../modules/nixos/fonts.nix
    ../../modules/nixos/keyd.nix
    # Pick exactly one. mouseless.nix grants `input` to the whole login
    # session; mouseless-scoped.nix grants it to one systemd unit instead.
    ../../modules/nixos/mouseless.nix
    #../../modules/nixos/mouseless-scoped.nix
    ../../modules/nixos/corne.nix
    #../../modules/nixos/keyd-vibranium-practice.nix
    ../../modules/nixos/hardware-health.nix
    ../../modules/nixos/diagnostics.nix 
 
    # desktop environment
    ./desktop.nix
    ./gpu.nix
    ./rescue.nix
  ];

  networking.hostName = "legionix";

  # systemd stage 1, adopted here first and on its own (modules/nixos/base.nix
  # keeps the scripted initrd as the default for the other hosts). The disk is
  # still unencrypted, so a stage-1 failure is unambiguous and booting the
  # previous generation is a complete rescue. It is also the ground the LUKS
  # remote unlock has to be rebuilt on before 26.11 drops the scripted initrd.
  boot.initrd.systemd.enable = true;

  # This NVMe also holds Windows (p3 MSR, p4 NTFS, p5 recovery), and the
  # Windows Boot Manager lives on the shared ESP (p1). Windows stays, so disko
  # must never wipe or re-identify anything here:
  #
  # - destroy = false: disko's destroy stage skips this disk entirely, so even
  #   nixos-anywhere's default (destroy-then-format) mode cannot erase it.
  # - Pinned partition GUIDs: on a partition that already exists, disko's
  #   format stage re-applies name, type and GUID, and without a pinned uuid
  #   the GUID is RANDOM. The firmware's boot entries (and Windows' own boot
  #   data) find the ESP by that GUID. These are the live values
  #   (lsblk -o PARTUUID, checked 2026-10-24); labels, types and flags already
  #   match the layout, so with these pinned that step changes nothing.
  #
  # A pinned uuid also switches disko's own references to
  # /dev/disk/by-partuuid/..., which would rewrite the fstab and the initrd for
  # the same partitions. `device` keeps them on by-partlabel, as before, so the
  # guard changes nothing about how this machine boots.
  #
  # The Windows partitions are deliberately not declared: disko only ever
  # touches the partitions it is told about. Rehearsed as Drill 4 in
  # docs/luks-runbook.md.
  disko.devices.disk.main = {
    device = "/dev/disk/by-id/nvme-SAMSUNG_MZVL21T0HCLR-00BL2_S64NNX0T568436";
    destroy = false;
    content.partitions = {
      boot = {
        uuid = "81c38c7d-d7f7-4150-828d-78c6b0c4ccef";
        device = "/dev/disk/by-partlabel/disk-main-BOOT";
      };
      legionix = {
        uuid = "a1a69706-77f3-4137-9434-feb7efce2598";
        device = "/dev/disk/by-partlabel/disk-main-legionix";
      };
    };
  };
}

