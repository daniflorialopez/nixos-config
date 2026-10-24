{ pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    withUWSM = true; # once on a release that has it and want it
    xwayland.enable = true; # keep compatibility for X11-only apps
  };

  # Needed for the GTK dark-mode preference (HM dconf settings; libadwaita
  # apps read color-scheme through the gtk portal)
  programs.dconf.enable = true;

  # Without a PAM service, hyprlock cannot validate the password to unlock
  security.pam.services.hyprlock = { };

  # What the Hyprland session relies on, declared here instead of inherited.
  # Until now every one of these was switched on only by desktop/cinnamon.nix
  # (checked with definitionsWithLocations, 2026-10-25), so dropping Cinnamon
  # would silently have taken away the keyring and Secret Service (browser and
  # IDE credentials), the SSH agent behind SSH_AUTH_SOCK, removable-media
  # mounting, the trash, and battery reporting. Declaring them is a no-op today.
  services.gnome.gnome-keyring.enable = true; # Secret Service; unlocked at login via PAM
  services.gnome.gcr-ssh-agent.enable = true; # SSH_AUTH_SOCK=/run/user/<uid>/gcr/ssh
  services.udisks2.enable = true; # mounting removable drives (udiskie, file managers)
  services.gvfs.enable = true; # trash, MTP phones, network locations in file managers
  services.upower.enable = true; # battery state for waybar and critical-battery action

  # Real-time scheduling for PipeWire. Without it PipeWire logs
  # "RTKit error: org.freedesktop.DBus.Error.ServiceUnknown" and runs its audio
  # threads at normal priority, so heavy load (games, builds) can crackle.
  security.rtkit.enable = true;

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

  # swayosd's brightness path writes /sys/class/backlight itself; its
  # packaged udev rule opens the node to the video group (the server
  # runs per-user from home-manager, which can't install udev rules)
  services.udev.packages = [ pkgs.swayosd ];
}

