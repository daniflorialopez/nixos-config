{ pkgs, ... }:

{
  home.packages = with pkgs; [
    libreoffice
    thunar # or another file manager like nautilus, nemo, dolphin...
  ];
}

