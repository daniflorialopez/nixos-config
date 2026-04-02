{ ... }:

{
  hardware.graphics.enable = true;

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    open = false;
    modesetting.enable = true;
    nvidiaSettings = true;

    powerManagement.enable = true;
  };

  boot.extraModprobeConfig = ''
    options nvidia NVreg_EnableGpuFirmware=0
  '';
}
