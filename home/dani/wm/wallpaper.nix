{ config, pkgs, lib, inputs, ... }:
let
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  defaultWallpaper = "${config.home.homeDirectory}/Pictures/Wallpapers/default.png";

  selectedConf = "${config.home.homeDirectory}/.local/state/hypr/hyprpaper-selected.conf";
  stateFile = "${config.home.homeDirectory}/.local/state/wallpaper/current";
  logFile = "${config.home.homeDirectory}/.local/state/wallpaper/debug.log";

  wallApply = pkgs.writeShellApplication {
    name = "wall-apply";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.systemd ];
    text = ''
      set -eu

      mon="''${1:-}"
      img="''${2:-}"
      state="''${3:-}"

      if [ -z "$img" ] || [ ! -f "$img" ]; then
        echo "missing wallpaper path: $img" >&2
        exit 1
      fi

      mkdir -p "$(dirname "${selectedConf}")"
      mkdir -p "$(dirname "${stateFile}")"
      mkdir -p "$(dirname "${logFile}")"

      {
        echo "---- $(date --iso-8601=seconds) ----"
        echo "mon=$mon"
        echo "img=$img"
        echo "state=$state"
      } >> "${logFile}"

      if [ -z "$img" ] || [ ! -f "$img" ]; then
        echo "invalid wallpaper path: $img" >> "${logFile}"
        exit 1
      fi

      fit_mode="cover"
      case "$state" in
        *'"Hyprpaper":"Contain"'*) fit_mode="contain" ;;
        *'"Hyprpaper":"Tile"'*) fit_mode="tile" ;;
        *'"Hyprpaper":"Fill"'*) fit_mode="fill" ;;
      esac

      printf '%s\n' "$img" > "${stateFile}"

      cat > "${selectedConf}" <<EOF
wallpaper {
  monitor = HDMI-A-1
  path = $img
  fit_mode = $fit_mode
}

wallpaper {
  monitor = eDP-1
  path = $img
  fit_mode = $fit_mode
}
EOF

      systemctl --user restart hyprpaper.service >> "${logFile}" 2>&1
    '';

  };

  wallPicker = pkgs.writeShellApplication {
    name = "wall-picker";
    runtimeInputs = [ unstablePkgs.waytrogen wallApply ];
    text = ''
      exec ${lib.getExe unstablePkgs.waytrogen} --external-script ${lib.getExe wallApply}
    '';
  };
in 
{
  home.file."Pictures/Wallpapers" = {
    source = ../assets/wallpapers;
    force = true;
  };
 
  xdg.configFile."hypr/hyprpaper.conf".text = ''
    source = ${selectedConf}

    ipc = true
    splash = false
  '';

  systemd.user.services.hyprpaper = {
    Unit = {
      Description = "hyprpaper";
      ConditionEnvironment = "WAYLAND_DISPLAY";
      After = [ config.wayland.systemd.target ];
      PartOf = [ config.wayland.systemd.target ];
      X-Restart-Triggers = [
        "${config.xdg.configFile."hypr/hyprpaper.conf".source}"
      ];
    };

    Install.WantedBy = [ config.wayland.systemd.target ];

    Service = {
      ExecStartPre = pkgs.writeShellScript "hyprpaper-init-selected" ''
    set -eu
    mkdir -p "$(dirname "${selectedConf}")"
    if [ ! -f "${selectedConf}" ]; then
      cat > "${selectedConf}" <<EOF
wallpaper {
  monitor = HDMI-A-1
  path = ${defaultWallpaper}
  fit_mode = cover
}

wallpaper {
  monitor = eDP-1
  path = ${defaultWallpaper}
  fit_mode = cover
}
EOF
    fi
  '';
      ExecStart = "${lib.getExe unstablePkgs.hyprpaper}";
      Restart = "always";
      RestartSec = "10";
    };
  };

  dconf.settings = {
    "org/Waytrogen/Waytrogen" = {
      wallpaper-folder = "${config.home.homeDirectory}/Pictures/Wallpapers";
    };
  };

  home.packages = with pkgs; [
    unstablePkgs.waytrogen
    unstablePkgs.hyprpaper
    wallApply
    wallPicker
  ];

  wayland.windowManager.hyprland.settings.bind = [
    "$mod CTRL, W, exec, ${lib.getExe wallPicker}"
  ];
}
