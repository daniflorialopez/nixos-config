{ pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    # withUWSM = true; # once you’re on a release that has it and want it
    xwayland.enable = true;
  };

  environment.systemPackages = with pkgs; [
    kitty  # or your preferred terminal, needed by default Hyprland config
  ];

  # Optional: make Electron apps use Wayland:
  # environment.sessionVariables.NIXOS_OZONE_WL = "1";
}

