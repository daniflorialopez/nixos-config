{
  lib,
  ...
}:
{
  imports = [
    ../../modules/nixos/desktop/sddm.nix
    ../../modules/nixos/desktop/hyprland.nix
    ../../modules/nixos/desktop/cinnamon.nix
  ];

  # Hyprland as default, Cinnamon selectable as fallback in greeter
  services.displayManager.defaultSession = lib.mkForce "hyprland-uwsm";
}
