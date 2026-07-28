{ config, pkgs, inputs, ... }:

let
  # Shared smoke alarm for any restic unit: desktop notification plus a
  # line in ~/BACKUP-FAILED.txt — the file the waybar backup pill watches,
  # so backup failures and check failures surface through the same signal.
  failureNotify = unit: {
    serviceConfig = {
      Type = "oneshot";
      User = "dani";
    };
    environment.DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
    script = ''
      echo "${unit} FAILED on $(date)" >> /home/dani/BACKUP-FAILED.txt
      ${pkgs.libnotify}/bin/notify-send --urgency=critical "Backup failed" \
        "${unit} failed. Check: journalctl -u ${unit} -e" || true
    '';
  };
in
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

    # If the repo is locked (e.g. a manual restic run overlapping the timer),
    # wait up to 30m for the lock instead of failing immediately.
    extraBackupArgs = [ "--retry-lock 30m" ];

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
      "--retry-lock 30m"
    ];
  };

  systemd.services.restic-backup-failure-notify = failureNotify "restic-backups-remote";
  systemd.services.restic-check-failure-notify = failureNotify "restic-check-remote";

  systemd.services.restic-backups-remote.onFailure = [ "restic-backup-failure-notify.service" ];

  # Weekly integrity check: verifies the repo structure and actually reads
  # back a random 5% of the pack data, so silent corruption in the remote
  # repo is caught within weeks instead of on restore day. Separate from
  # the nightly backup (runCheck would re-read data every night — needless
  # bandwidth); --retry-lock rides out an overlapping backup run.
  systemd.services.restic-check-remote = {
    onFailure = [ "restic-check-failure-notify.service" ];
    serviceConfig = {
      Type = "oneshot";
      CacheDirectory = "restic-check-remote";
      CacheDirectoryMode = "0700";
      EnvironmentFile = config.age.secrets.restic-env.path;
    };
    environment.RESTIC_CACHE_DIR = "/var/cache/restic-check-remote";
    script = ''
      ${pkgs.restic}/bin/restic check \
        --password-file ${config.age.secrets.restic-password.path} \
        --read-data-subset=5% \
        --retry-lock 30m
    '';
  };

  systemd.timers.restic-check-remote = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Sunday midday: far from the nightly 20:00 backups, machine likely on
      OnCalendar = "Sun *-*-* 12:00:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };

  environment.systemPackages = [
    pkgs.restic
    inputs.agenix.packages.${pkgs.system}.default
  ];
}
