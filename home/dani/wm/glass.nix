{
  config,
  lib,
  pkgs,
  ...
}:

# LIQUID GLASS on this desktop (the hyprglass plugin, pkgs/hyprglass).
#
# Two switches, on purpose. This one, in the Nix config, decides whether the
# machine CAN do glass: it installs the plugin and the `glass` command and
# makes Hyprland and the terminal listen to the command's state. Whether glass IS on is the other switch, flipped at the
# keyboard (`glass toggle`, or the Glass tile in reverie's menu) and kept in
# ~/.local/state/theme/ like every other runtime choice (ADR-005). With this
# enabled and that one off — which is how it starts — nothing looks different.
#
# What follows the command, and how (the command's own header says why):
#   Hyprland   sources glass.conf: the plugin and its rules, or nothing
#   Alacritty  imports glass.toml: its background opacity while glass is on
#
# The terminal is the one deliberate break with shell/alacritty.nix's rule
# that Hyprland owns all window opacity: glass is only seen through a window
# whose background is see-through while its text is not, and the compositor
# cannot do that for it. It holds only while glass is on.
let
  cfg = config.programs.glass;
  stateDir = "${config.xdg.stateHome}/theme";
  refresh = "${lib.getExe cfg.command} refresh";
in
{
  options.programs.glass = {
    enable = lib.mkEnableOption "liquid glass (hyprglass) and the `glass` command that switches it";

    plugin = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../pkgs/hyprglass/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../pkgs/hyprglass/package.nix { }";
      description = "The hyprglass plugin, built against this nixpkgs' Hyprland.";
    };

    terminalOpacity = lib.mkOption {
      type = lib.types.str;
      default = "0.65";
      description = "Alacritty's background opacity while glass is on; off it is 1.0.";
    };

    command = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "The `glass` command, built with the values above.";
    };
  };

  config = lib.mkMerge [
    {
      programs.glass.command = pkgs.callPackage ../../../pkgs/hyprglass/glass.nix {
        hyprglass = cfg.plugin;
        inherit (cfg) terminalOpacity;
      };
    }

    (lib.mkIf cfg.enable {
      home.packages = [ cfg.command ];

      # Last in the file, so that what it says wins over the rules above it.
      wayland.windowManager.hyprland.extraConfig = ''
        source = ${stateDir}/glass.conf
      '';

      programs.alacritty.settings.general.import = [ "${stateDir}/glass.toml" ];

      # The files have to exist before anything reads them: a missing
      # `source` is a Hyprland config error. Written at every activation
      # (which is also when a new plugin path or new rules get into them),
      # before the step that reloads Hyprland.
      home.activation.glassState = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
        run ${refresh}
      '';
    })
  ];
}
