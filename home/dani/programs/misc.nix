{ pkgs, ... }:

{
  home.packages = with pkgs; [
    libreoffice
    pcmanfm # or another file manager like thunar, nautilus, nemo, dolphin...
  ];
}

