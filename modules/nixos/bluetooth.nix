{ ... }:

{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
    # Battery level reporting for headphones/mice over BT
    settings.General.Experimental = true;
  };

  # GUI manager (blueman-manager) for pairing; opened from the waybar module
  services.blueman.enable = true;
}
