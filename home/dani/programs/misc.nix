{ pkgs, ... }:

{
  home.packages = with pkgs; [
    libreoffice
    pcmanfm # or another file manager like thunar, nautilus, nemo, dolphin...
    vesktop
    warpd # modal keyboard driven interface for mouse manipulation, it works also on wayland
  ];
}

