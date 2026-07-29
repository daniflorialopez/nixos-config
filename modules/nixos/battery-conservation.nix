{ pkgs, ... }:

let
  node = "/sys/bus/platform/devices/VPC2004:00/conservation_mode";
in
{
  # Lenovo Legion battery longevity (ideapad_laptop). This laptop lives
  # docked at the wall, and a Li-ion cell held at 100% ages faster from
  # calendar wear at high voltage even though it barely cycles. The driver
  # exposes a single conservation-mode toggle that caps charging at ~60%,
  # the low-stress hold point. There are no adjustable charge thresholds on
  # this hardware (no charge_control_*_threshold nodes), so TLP can't help
  # here — this binary toggle is all the firmware offers.
  #
  # At boot: make the sysfs node group-writable (so the waybar click —
  # conservation-toggle in waybar.nix — can flip it without root) and enable
  # conservation by default, since capping at ~60% is the right daily state
  # for a docked machine. Before travel, click the waybar leaf to allow a
  # full charge and top up; note it re-enables on the next boot. The [ -e ]
  # guard makes the unit a harmless no-op on any host without the node.
  systemd.services.battery-conservation = {
    description = "Lenovo battery conservation: open the toggle to wheel, cap charge ~60%";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      node=${node}
      if [ -e "$node" ]; then
        ${pkgs.coreutils}/bin/chgrp wheel "$node"
        ${pkgs.coreutils}/bin/chmod g+w "$node"
        echo 1 > "$node"
      fi
    '';
  };
}
