{
  lib,
  config,
  inputs,
  ...
}: let
  hostname = config.networking.hostName;
in {
  imports = [
    inputs.disko.nixosModules.disko
  ];

  # Same layout as disko.nix, but the btrfs partition lives inside a
  # LUKS2 container. Rehearsed in danixos-vm first; legionix switches
  # its import from disko.nix to this module on migration day.
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        content = lib.mkDefault {
          type = "gpt";
          partitions = {
            boot = {
              name = "BOOT";
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };

            "${hostname}" = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted"; # unlocked as /dev/mapper/crypted
                settings = {
                  # SSD TRIM through the encryption layer; matches the
                  # discard=async mounts below. Leaks only which blocks
                  # are free, not their contents - fine for this threat
                  # model (laptop theft, not forensics)
                  allowDiscards = true;
                  # skip the kernel workqueues; faster on NVMe
                  bypassWorkqueues = true;
                };
                # Install-time only: nixos-anywhere copies the passphrase
                # here (--disk-encryption-keys) for the initial luksFormat.
                # At every boot the passphrase is typed at the console.
                passwordFile = "/tmp/disk.key";
                content = {
                  type = "btrfs";
                  extraArgs = ["-f"]; # Override existing partition
                  # Subvolumes must set a mountpoint in order to be mounted,
                  # unless their parent is mounted
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                      mountOptions = ["compress=zstd" "discard=async" "autodefrag"];
                    };
                    "/root-blank" = {};
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = ["compress=zstd" "noatime" "discard=async" "autodefrag"];
                    };
                    "/persist" = {
                      mountpoint = "/persist";
                      mountOptions = ["compress=zstd" "discard=async" "autodefrag"];
                    };
                    "/swap" = {
                      mountpoint = "/swap";
                      mountOptions = ["noatime"];
                    };
                    "/snapshots" = {};
                    "/snapshots/root" = {};
                    "/snapshots/persist" = {};
                  };
                };
              };
            };
          };
        };
      };
    };
  };
  fileSystems."/".neededForBoot = true;
  fileSystems."/nix".neededForBoot = true;
  fileSystems."/persist".neededForBoot = true;
}
