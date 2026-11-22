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

  # reverie (home/dani/wm/reverie.nix): the HUD, title cards, spotlight and
  # menu. Experimental, and only ever run on this machine, so this is the
  # one host that turns it on.
  home-manager.users.dani.services.reverie.enable = true;
}
