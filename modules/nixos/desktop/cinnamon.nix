{ config, pkgs, ... }:

{
  services.xserver = {
    enable = true;
    desktopManager.cinnamon.enable = true;
    displayManager.lightdm.enable = true; # or gdm, sddm, etc.
  };
}

