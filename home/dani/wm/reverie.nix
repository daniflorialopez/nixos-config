{
  config,
  lib,
  pkgs,
  theme,
  metrics,
  ...
}:

# REVERIE on this desktop. EXPERIMENTAL, branch rice/reverie.
#
# The program is a package of its own (pkgs/reverie: what it is and does is
# at the top of package.nix; `nix build .#reverie`). This is the part that is
# configuration: it puts the command on the PATH, runs the daemon with the
# session, tells it when you have gone and come back, and declares its keys
# and its surfaces' rules in the Hyprland config.
let
  reverie = pkgs.callPackage ../../../pkgs/reverie/package.nix { inherit theme metrics; };

  # The package's own lists (pkgs/reverie/hyprland.nix), so that what is
  # declared here and what `reverie try` registers are the same thing.
  inherit (reverie.hyprland)
    toBind
    binds
    holds
    releases
    layerRules
    ;

  target = config.wayland.systemd.target;
in
{
  home.packages = [ reverie ];

  systemd.user = {
    services.reverie = {
      Unit = {
        Description = "reverie: HUD, title cards, spotlight, pulse";
        PartOf = [ target ];
        After = [ target ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };
      Service = {
        ExecStart = "${lib.getExe reverie} daemon";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ target ];
    };
  };

  # Presence. hypridle already runs (wm/hyprlock.nix) with no listeners; this
  # adds one that only TELLS the daemon you have gone and come back. It locks
  # nothing and dims nothing: the focus ledger stops counting while you are
  # away, so an empty chair is not booked as an hour in the terminal.
  services.hypridle.settings.listener = [
    {
      timeout = 180;
      on-timeout = "reverie away";
      on-resume = "reverie back";
    }
  ];

  wayland.windowManager.hyprland.settings = {
    bindd = map toBind binds;
    bindde = map toBind holds;
    binddr = map toBind releases;
    layerrule = layerRules;
  };
}
