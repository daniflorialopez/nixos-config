{ lib, ... }:

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

  # "Safe graphics" rescue boot entry (a second systemd-boot menu item,
  # baked into every generation). The whole display depends on the
  # proprietary nvidia module building and loading against the running
  # kernel — the usual way this laptop black-screens is a kernel bump that
  # the out-of-tree module can't follow, leaving no display and no way in
  # but a live USB. This entry negates the nvidia config above: it refuses
  # to load nvidia and rides the UEFI firmware framebuffer (simpledrm) to a
  # plain getty console you can read logs, edit the flake, and
  # `nixos-rebuild boot` a fix from.
  #
  # NOTE: this machine has no usable iGPU (BIOS is in discrete-only mode —
  # the Intel GPU isn't even on the PCI bus, and the panel is wired to the
  # NVIDIA GPU), so safe-graphics is a rescue *console*, not a fallback
  # desktop. A driverless framebuffer can't run an accelerated session.
  specialisation.safe-graphics.configuration = {
    system.nixos.tags = [ "safe-graphics" ];

    # Drop the nvidia X driver, which unwinds the hardware.nvidia kernel
    # machinery, and hard-blacklist the modules so nothing autoloads them;
    # simpledrm then takes the firmware framebuffer that already lit the panel.
    services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];
    boot.blacklistedKernelModules = [ "nvidia" "nvidia_modeset" "nvidia_drm" "nvidia_uvm" ];

    # No graphical greeter — it would only fail on a GPU with no accelerated
    # driver. A getty login prompt is the repair console.
    services.displayManager.sddm.enable = lib.mkForce false;
  };
}
