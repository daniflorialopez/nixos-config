{ config, pkgs, ... }:

{
  virtualisation = {
    libvirtd.enable = true;
    docker = {
      enable = true;
      package = pkgs.docker_29;
    };
    podman.enable = true;
  };

  programs.virt-manager.enable = true;
}

