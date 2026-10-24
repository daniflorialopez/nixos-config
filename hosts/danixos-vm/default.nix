{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix

    # LUKS2 + btrfs layout (the legionix migration rehearsal)
    ../../modules/nixos/disko-luks.nix
    # remote unlock over SSH from the initrd (rehearsal for legionix;
    # on migration day legionix also adds "r8169" below)
    ../../modules/nixos/initrd-ssh.nix

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

  # virtio disk inside libvirt (stable across VM rebuilds, unlike by-id).
  #
  # Same guard as legionix (see hosts/legionix/default.nix), because Drill 4
  # rehearses exactly that: the VM disk is laid out like legionix's, with
  # stand-in Windows partitions after the Linux one, and the reinstall must
  # leave them and the ESP's contents byte-identical. The GUIDs are the ones
  # the Drill 4 partitioning step creates (docs/luks-runbook.md).
  disko.devices.disk.main = {
    device = "/dev/vda";
    destroy = false;
    content.partitions = {
      boot = {
        uuid = "3acb876b-15b7-4003-99ec-54fb7f91c075";
        device = "/dev/disk/by-partlabel/disk-main-BOOT";
      };
      danixos-vm = {
        uuid = "dd22a36e-db15-452d-b76e-bee913608e6e";
        device = "/dev/disk/by-partlabel/disk-main-danixos-vm";
      };
    };
  };

  # virtio NIC in the initrd so the remote-unlock sshd has a network
  boot.initrd.availableKernelModules = [ "virtio_net" ];

  # initrd-ssh.nix is written for systemd stage 1 (base.nix keeps the scripted
  # initrd as the default for hosts that have not opted in)
  boot.initrd.systemd.enable = true;

  # Fresh installs (the rehearsal wipes this disk repeatedly) come up
  # with a usable console login; with mutableUsers this only applies
  # when the user is first created, so it never touches existing hosts
  users.users.dani.initialPassword = "changeme";
}

