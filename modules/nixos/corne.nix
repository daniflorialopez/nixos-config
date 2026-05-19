# modules/nixos/corne.nix
{ pkgs, ... }:

{
  # Enables QMK udev rules for non-root flashing/access.
  hardware.keyboard.qmk.enable = true;

  environment.systemPackages = with pkgs; [
    via
    qmk
    qmk-udev-rules
    usbutils
    evtest
    wev
  ];

  services.udev.packages = with pkgs; [
    via
    qmk-udev-rules
  ];
  
  # Vial/VIA need hidraw access on Linux.
  # Vial's own docs recommend a Vial-specific hidraw rule using its serial marker.
  services.udev.extraRules = ''
    # Vial keyboards
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"

    # Optional broader VIA fallback. Keep disabled unless VIA/Vial cannot see the board.
    # KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
  '';
}
