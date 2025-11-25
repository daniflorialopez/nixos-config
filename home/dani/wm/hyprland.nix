{ pkgs, ... }:

{
  home.packages = with pkgs; [
    wl-kbptr
  ];

  # Later:
  # xdg.configFile."hypr/hyprland.conf".source = ./hyprland.conf;
}

