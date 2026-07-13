{ config, pkgs, ... }:

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

  environment.systemPackages = [ pkgs.restic ];
}
