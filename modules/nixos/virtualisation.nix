{ config, pkgs, ... }:

{
  virtualisation = {
    libvirtd.enable = true;
    docker.enable = true;
    podman.enable = true;
  };

  programs.virt-manager.enable = true;
}

