{ pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    withUWSM = true; # once on a release that has it and want it
    xwayland.enable = true; # keep compatibility for X11-only apps
  };

  # Wayland portals (screen sharing, file pickers, etc)
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk
    ];
  };

  environment.systemPackages = with pkgs; [
    alacritty # or the preferred terminal, needed by default Hyprland config
  ];

  # Electron apps use Wayland:
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}

