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

  # No "safe graphics" specialisation: on this laptop the panel is wired to
  # the NVIDIA GPU (BIOS discrete-only, no iGPU), and nouveau-on-Ampere is too
  # fragile to be a trustworthy fallback (tested 2026-07-29 — every variant
  # either left the panel frozen or crashed the session). The reliable rescue
  # is the one systemd-boot gives for free: boot a previous generation. See
  # docs/rescue-blackscreen.md (paged on the box with `rescue`).
}
