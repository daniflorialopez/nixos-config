{ config, pkgs, ... }:

let
  dir = "${config.home.homeDirectory}/Pictures/Wallpapers";
in
{
  services.hyprpaper = {
    enable = true;
    settings = { ipc = true; splash = false; };
  };

  home.packages = with pkgs; [
    findutils
  ];

  wayland.windowManager.hyprland.settings.bind = [
    "$mod SHIFT, W, exec, sh -lc 'f=$(find \"${dir}\" -maxdepth 1 -type f \\( -iname \"*.jpg\" -o -iname \"*.jpeg\" -o -iname \"*.png\" -o -iname \"*.webp\" \\) | sort | wofi --dmenu --prompt Wallpaper); [ -n \"$f\" ] && hyprctl hyprpaper reload ,\"$f\"'"
  ];
}
