{ 
  config, 
  pkgs, 
  lib, 
  osConfig ? null, 
  ... 
}:

let
  hyprEnabled = osConfig != null && (osConfig.programs.hyprland.enable or false);
in
{
  imports =
    [
      ./shell
      ./programs
    ]
    ++ lib.optionals hyprEnabled [
      ./wm/hyprland.nix
      ./wm/wallpaper.nix
    ];

  home.username = "dani";
  home.homeDirectory = "/home/dani";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
}

