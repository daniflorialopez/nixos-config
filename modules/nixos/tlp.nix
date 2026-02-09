{ config, pkgs, lib, ... }:

{
  # TLP (power management)
  services.power-profiles-daemon.enable = false; # conflicts with TLP

  services.tlp = {
    enable = true;
    settings = {
      USB_AUTOSUSPEND = "0"; # disable USB autosuspend (helps with sleeping mice)
    };
  };

  # Also disable autosuspend at the kernel level (optional but often effective)
  boot.kernelParams = [ "usbcore.autosuspend=-1" ]; # -1 disables
}

