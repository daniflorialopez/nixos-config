{ config, pkgs, ... }:

{
  services.hyprpaper = {
    enable = true;
    settings = { 
      ipc = true; 
      splash = false; 
    };
  };

  home.file."Pictures/Wallpapers" = {
    source = ../assets/wallpapers;
    force = true;
  };
 
  dconf.settings = {
    "org/Waytrogen/Waytrogen" = {
      wallpaper-folder = "${config.home.homeDirectory}/Pictures/Wallpapers";
    };
  };

  home.packages = with pkgs; [
    waytrogen
  ];

  wayland.windowManager.hyprland.settings.bind = [
    "$mod CTRL, W, exec, waytrogen"
  ];
}
