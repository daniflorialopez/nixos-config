{ pkgs, ... }:

let
  # One way for system services to say "I failed" in the desktop session:
  # a system-bus signal that systembus-notify (a user service in the
  # graphical session) turns into a mako notification. %i is the failed
  # unit's name, passed in by `onFailure = [ "notify-failure@%n.service" ]`.
  dbusNotify = summary: body: ''
    ${pkgs.dbus}/bin/dbus-send --system / net.nuetzlich.SystemNotifications.Notify \
      "string:${summary}" "string:${body}"
  '';
in
{
  services.smartd = {
    enable = true;
    autodetect = true;

    # smartd's defaults are `wall` (terminal broadcast) and an X11 popup on
    # display ":" - neither reaches a Wayland session, so a failing disk
    # used to warn nobody. This also enables services.systembus-notify,
    # the user-side listener that hands the message to mako. (Upstream warns
    # any local user could spam notifications this way: single-user machine.)
    notifications.systembus-notify.enable = true;
  };

  # btrfs checksums every block but only verifies on read; a monthly scrub
  # reads everything, so silent corruption surfaces while the backups still
  # hold good copies. Only "/": /nix, /persist and /swap are subvolumes of
  # the same filesystem, and the default (every btrfs mount) would scrub it
  # four times over. Runs as btrfs-scrub--.service; Persistent catches up
  # after the machine was off.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # Firmware updates from Linux (LVFS). legionix's UEFI publishes an ESRT
  # with three updatable components, so capsule updates are possible; whether
  # Lenovo ships this Legion's BIOS on LVFS is another matter - if not, BIOS
  # updates stay a Lenovo Vantage job on Windows, while NVMe/USB/dock firmware
  # may still come through here. Only listing is automatic (a refresh timer
  # fetches metadata); installing is always a deliberate `fwupdmgr update`,
  # and never on battery or away from a reliable power socket.
  services.fwupd.enable = true;

  systemd.services."notify-failure@" = {
    description = "Tell the desktop session that %i failed";
    serviceConfig.Type = "oneshot";
    scriptArgs = "%i";
    script = dbusNotify "$1 failed" "Check: journalctl -u $1 -e";
  };

  # The periodic jobs nothing else watches. restic keeps its own notifier
  # (restic.nix), which also feeds the waybar backup pill.
  systemd.services."btrfs-scrub--".onFailure = [ "notify-failure@%n.service" ];
  systemd.services.nh-clean.onFailure = [ "notify-failure@%n.service" ];
}
