{
  pkgs,
  ...
}:
{
  services.xserver.enable = true; # needed for Cinnamon - X11 session

  environment.systemPackages = with pkgs.kdePackages; [
    plasma-desktop
  ];

  services.displayManager.sddm = {
    enable = true;
    package = pkgs.kdePackages.sddm;
    theme = "breeze";
    wayland.enable = true; # wayland-capable greeter - Hyprland session

    # enableHidpi = true # only if there is a HiDPI screen
    
    settings = {
      Theme = {
        CursorTheme = "breeze_cursors";
        # CursorSize = 24; # optional
      };
    };

    extraPackages = with pkgs.kdePackages; [
      plasma-desktop
    ];
  };
}
