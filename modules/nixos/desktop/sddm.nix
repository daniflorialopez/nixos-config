{ ... }:
{
  services.xserver.enable = true; # needed for Cinnamon - X11 session

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true; # wayland-capable greeter - Hyprland session
  };
}
