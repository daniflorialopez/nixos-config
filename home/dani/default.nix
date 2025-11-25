{ config, pkgs, ... }:

{
  imports = [
    ./shell
    ./programs
    ./wm/hyprland.nix
  ];

  home.username = "dani";
  home.homeDirectory = "/home/dani";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
}

