{ pkgs, ... }:

{
  services.hyprpaper = {
    enable = true;
    settings = { 
      ipc = true; 
      splash = false; 
    };
  };

  home.packages = with pkgs; [
    waytrogen
  ];

  wayland.windowManager.hyprland.settings.bind = [
    "$mod ALT, W, exec, waytrogen"
  ];
}
