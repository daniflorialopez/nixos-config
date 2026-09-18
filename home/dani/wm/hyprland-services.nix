{ config, pkgs, theme, scene, metrics, ... }:
let
  # One palette source: home/dani/theme/palette.nix.

  target = config.wayland.systemd.target; # defaults to "graphical-session.target"

  # Same derivation wallpaper.nix uses — imported rather than reimplemented so
  # a re-dock repaints through exactly the path login does, fallback included.
  inherit (import ./wall-apply.nix { inherit pkgs config scene; }) wallApply;

  # Dock/undock workspace repair. Undocking is fine on its own — Hyprland
  # migrates HDMI-A-1's workspaces to eDP-1 when the monitor vanishes —
  # but on re-dock nothing moves them back, leaving everything piled on
  # the laptop screen. This listens on Hyprland's event socket and, when
  # HDMI-A-1 (re)appears, returns its workspaces (1, 4-10, per the
  # workspace rules in hyprland.nix). Also runs once at startup, which
  # covers logging in docked and makes it a no-op on HDMI-less hosts.
  dockHandler = pkgs.writeShellApplication {
    name = "hypr-dock-handler";
    runtimeInputs = (with pkgs; [ hyprland jq socat coreutils systemd ]) ++ [ wallApply ];
    text = ''
      repin() {
        hyprctl monitors -j | jq -e 'any(.[]; .name == "HDMI-A-1")' >/dev/null || return 0
        hyprctl workspaces -j | jq -r '.[].id' | while read -r ws; do
          case "$ws" in
            1|4|5|6|7|8|9|10)
              hyprctl dispatch moveworkspacetomonitor "$ws HDMI-A-1" >/dev/null
              ;;
          esac
        done
      }

      repin

      sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
      socat -U - "UNIX-CONNECT:$sock" | while read -r line; do
        case "$line" in
          # v2 only. Hyprland 0.55.4 emits BOTH `monitoradded>>HDMI-A-1` and
          # `monitoraddedv2>>ID,HDMI-A-1,DESCRIPTION` for one physical connect
          # (both names are in the binary; verified with `strings` on
          # .Hyprland-wrapped), and the old `monitoradded*HDMI-A-1*` pattern
          # matched both — `*` happily absorbs the `v2`. So a single replug ran
          # this whole body twice: two sleeps, two repin passes, two waybar
          # restarts, and two full wallpaper decodes. Pinning the name to v2's
          # second field matches exactly once.
          monitoraddedv2*,HDMI-A-1,*)
            sleep 1   # let the monitor rule (mode/position) settle first
            repin
            # waybar duplicates bar surfaces on a re-added output (seen
            # live: three stacked bars after replug); a restart redraws
            # one bar per monitor
            systemctl --user try-restart waybar.service || true
            # A newly bound output has no wallpaper on it. awww would try its
            # own per-output cache here, but that cache is keyed by awww
            # version and holds a path, so it is exactly the thing not to
            # depend on (see wall-apply.nix). Repainting is cheap and the
            # result is the same image the other output is already showing.
            # `|| true` so a wallpaper failure never kills the watcher loop.
            wall-apply || true
            ;;
        esac
      done
    '';
  };
in
{
  
  # The walker HM module enables xdg.portal with only the hyprland backend,
  # which shadows the system portal setup (NIX_XDG_DESKTOP_PORTAL_DIR points
  # at the per-user profile). Without the gtk backend the portal serves no
  # Settings interface, so GTK4 apps (e.g. pavucontrol) never see the dark
  # preference. Add gtk and prefer hyprland for what it implements.
  xdg.portal = {
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.hyprland.default = [ "hyprland" "gtk" ];
  };

  # Mako: HM config + systemd service
  services.mako = {
    enable = true;                 # writes config + installs package
    settings = {
      # Tokyo Night, matching waybar (see waybar/palette.css)
      font = "CaskaydiaMono Nerd Font 11";
      # app icons resolve from the same theme GTK uses (theme.nix)
      icon-path = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark";
      max-icon-size = 40;
      background-color = (theme.hexA "bg" "e0");
      text-color = theme.hex.fg;
      border-color = theme.hex.accent;
      border-size = 2;
      # NOT metrics.islandRadius, though it is the same number today. mako is a
      # framed notification, not a glass island: an accent border at 2px that
      # switches with urgency, over an opaque-ish 0.88 surface. It belongs to the
      # popup family and the two must be free to diverge. (a441a36's message said
      # this note existed; it did not, until now.)
      border-radius = 12;
      padding = "12,16";
      margin = toString metrics.outerMargin;   # the same outer margin a window gets
      width = 380;
      max-visible = 5;
      default-timeout = 0;         # persist until dismissed (Super+')
      progress-color = "over ${theme.hex.surface}";

      "urgency=low".border-color = theme.hex.slate;
      "urgency=critical".border-color = theme.hex.critical;

      # Do-not-disturb: notifications arriving in this mode are hidden but
      # never expire (default-timeout=0), so they all appear when the mode
      # is left — leaving DND shows what was missed. Toggled by the waybar
      # bell or Super+N (dnd-toggle, defined in waybar.nix).
      "mode=dnd".invisible = true;
    };
  };
  # The HM mako module deliberately ships no unit of its own in 25.11 (it only
  # does home.packages, dbus.packages and the config file), so this one is
  # required. Two notes worth keeping:
  #
  # - No X-Restart-Triggers on purpose. The module already attaches
  #   `onChange = makoctl reload` to mako/config, so settings edits do land
  #   without a restart — and a restart would be actively worse here, because
  #   default-timeout = 0 means undismissed notifications are still on screen
  #   and a restart drops them. Reload keeps them.
  # - ExecStart follows services.mako.package rather than pkgs.mako, so
  #   overriding the package can't leave one mako binary running against
  #   another one's generated config. They resolve to the same store path
  #   today; this is about not making that an invariant.
  systemd.user.services.mako = {
    Unit = {
      Description = "Mako notifications";
      PartOf = [ target ];
      After = [ target ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "${config.services.mako.package}/bin/mako";
      Restart = "on-failure";
    };
    Install.WantedBy = [ target ];
  };

  systemd.user.services.hypr-dock-handler = {
    Unit = {
      Description = "Re-pin workspaces to HDMI-A-1 on dock";
      PartOf = [ target ];
      After = [ target ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "${dockHandler}/bin/hypr-dock-handler";
      # `always`, not `on-failure`. The script's last command is
      #   socat -U - UNIX-CONNECT:$sock | while read -r line; do ... done
      # so if socat ever exits cleanly - Hyprland restarting, the socket going
      # away - the pipeline exits 0, the script exits 0, and under on-failure
      # systemd leaves the unit `inactive (dead)` with no restart and nothing in
      # the journal. From then on a re-dock silently leaves every workspace piled
      # on the laptop panel and produces duplicate waybar surfaces, with no clue
      # as to why. A watcher loop that has stopped watching is a failure whatever
      # its exit code says.
      Restart = "always";
      RestartSec = 2;
    };
    Install.WantedBy = [ target ];
  };

  # Hyprsunset: warm color temperature after dark. Identity during the
  # day so the calibrated palette stays true; two warm steps at night —
  # gentle at dusk, deeper before bed. Runs as a user service bound to
  # the session; `hyprctl hyprsunset identity` kills it manually when
  # doing color-sensitive work at night.
  services.hyprsunset = {
    enable = true;
    settings = {
      profile = [
        {
          time = "7:30";
          identity = true;
        }
        {
          time = "21:00";
          temperature = 4200;
        }
        {
          time = "23:30";
          temperature = 3700;
        }
      ];
    };
  };

  # Polkit agent (for auth dialogs)
  systemd.user.services.polkit-gnome-agent = {
    Unit = {
      Description = "Polkit GNOME Authentication Agent";
      PartOf = [ target ];
      After = [ target ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
    };
    Install.WantedBy = [ target ];
  };
}
