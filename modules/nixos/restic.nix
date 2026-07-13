{ config, pkgs, inputs, ... }:

{
  age.secrets.restic-password.file = ../../secrets/restic-password.age;
  age.secrets.restic-env.file = ../../secrets/restic-env.age;

  services.restic.backups.remote = {
    initialize = true;

    passwordFile = config.age.secrets.restic-password.path;
    environmentFile = config.age.secrets.restic-env.path;

    paths = [ "/home/dani" ];

    exclude = [
      "/home/dani/.cache"
      "/home/dani/.local/share/Trash"
      "/home/dani/.local/share/Steam"
      "/home/dani/.steam"
      "/home/dani/.mozilla/firefox/*/cache*"
      "/home/dani/.mozilla/firefox/*/storage/default/*/cache"
      "/home/dani/.config/google-chrome/*/Cache"
      "/home/dani/.config/chromium/*/Cache"
      "/home/dani/Downloads"
      "**/node_modules"
      "**/.venv"
      "**/venv"
      "**/target"
      "**/.cargo/registry"
      "**/.cargo/git"
      "**/build"
      "**/dist"
      "**/.next"
      "**/.turbo"
      "**/__pycache__"
      "**/*.pyc"
      "**/.direnv"
      "**/result"
    ];

    timerConfig = {
      OnCalendar = "*-*-* 20:00:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
  };

  # Alert when the nightly backup fails: desktop notification, plus a
  # marker file in the home directory in case no graphical session is
  # running when the failure happens.
  systemd.services.restic-backup-failure-notify = {
    serviceConfig = {
      Type = "oneshot";
      User = "dani";
    };
    environment.DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
    script = ''
      echo "restic-backups-remote FAILED on $(date)" >> /home/dani/BACKUP-FAILED.txt
      ${pkgs.libnotify}/bin/notify-send --urgency=critical "Backup failed" \
        "restic-backups-remote failed. Check: journalctl -u restic-backups-remote -e" || true
    '';
  };

  systemd.services.restic-backups-remote.onFailure = [ "restic-backup-failure-notify.service" ];

  environment.systemPackages = [
    pkgs.restic
    inputs.agenix.packages.${pkgs.system}.default
  ];
}
