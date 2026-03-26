{ ... }:

{
  hardware.graphics.enable = true;

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    open = true;
    modesetting.enable = true;
    nvidiaSettings = true;
    powerManagement.enable = true;
  };
}
