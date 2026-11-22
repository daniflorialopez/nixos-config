{
  config,
  lib,
  pkgs,
  theme,
  ...
}:

# LIQUID GLASS on this desktop (the hyprglass plugin, pkgs/hyprglass).
#
# Two switches, on purpose. This one, in the Nix config, decides whether the
# machine CAN do glass: it installs the plugin and the `glass` command and
# makes Hyprland, the bar, the volume pill and the terminal listen to the
# command's state. Whether glass IS on is the other switch, flipped at the
# keyboard (`glass toggle`, or the Glass tile in reverie's menu) and kept in
# ~/.local/state/theme/ like every other runtime choice (ADR-005). With this
# enabled and that one off — which is how it starts — nothing looks different.
#
# What follows the command, and how (the command's own header says why):
#   Hyprland   sources glass.conf: the plugin and its rules, or nothing
#   waybar     \  their "island" background comes from glass.css instead of
#   swayosd    /  being a constant: 0.85 solid off, see-through on
#   walker     the launcher's box likewise: 0.90 off, half see-through on
#              (the power menu states its own, nearly solid, and keeps it)
#   Alacritty  imports glass.toml: its background opacity while glass is on
#
# The terminal is the one deliberate break with shell/alacritty.nix's rule
# that Hyprland owns all window opacity: glass is only seen through a window
# whose background is see-through while its text is not, and the compositor
# cannot do that for it. It holds only while glass is on.
let
  cfg = config.programs.glass;
  stateDir = "${config.xdg.stateHome}/theme";
  islandOff = theme.cssRgba "bg" "0.85";
  popupOff = theme.cssRgba "bgDeep" "0.90";
  # Where glass is enabled, the stylesheets take these colours from the
  # command's state file; where it is not, they are the constants they were.
  fromState =
    constants: if cfg.enable then ''@import url("file://${stateDir}/glass.css");'' else constants;
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

    islandAlpha = lib.mkOption {
      type = lib.types.str;
      default = "0.30";
      description = "How solid an island (bar group, volume pill) is while glass is on; off it is 0.85.";
    };

    popupAlpha = lib.mkOption {
      type = lib.types.str;
      default = "0.50";
      description = "How solid the launcher's box is while glass is on; off it is 0.90.";
    };

    popupAlphaClear = lib.mkOption {
      type = lib.types.str;
      default = "0.72";
      description = ''
        The same under the clear look, which does not blur: what is behind
        the box would otherwise run sharp through its text.
      '';
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

    islandBackground = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = ''
        The CSS line that defines the named colour `bg_alpha`, the island
        background, for the stylesheets that draw islands: the constant when
        glass is not enabled here, an import of the command's state file when
        it is.
      '';
    };

    popupBackground = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = ''
        The same for `popup_bg`, the background of a popup box (the
        launcher's).
      '';
    };
  };

  config = lib.mkMerge [
    {
      programs.glass = {
        command = pkgs.callPackage ../../../pkgs/hyprglass/glass.nix {
          hyprglass = cfg.plugin;
          inherit islandOff popupOff;
          islandOn = theme.cssRgba "bg" cfg.islandAlpha;
          popupOn = theme.cssRgba "bgDeep" cfg.popupAlpha;
          popupOnClear = theme.cssRgba "bgDeep" cfg.popupAlphaClear;
          inherit (cfg) terminalOpacity;
        };
        islandBackground = fromState "@define-color bg_alpha ${islandOff};";
        popupBackground = fromState "@define-color popup_bg ${popupOff};";
      };
    }

    (lib.mkIf cfg.enable {
      home.packages = [ cfg.command ];

      # Last in the file, so that what it says wins over the rules above it.
      wayland.windowManager.hyprland.extraConfig = ''
        source = ${stateDir}/glass.conf
      '';

      programs.alacritty.settings.general.import = [ "${stateDir}/glass.toml" ];

      # The three files have to exist before anything reads them: a missing
      # `source` is a Hyprland config error, a missing CSS import leaves the
      # islands without a background. Written at every activation (which is
      # also when a new plugin path or new rules get into them — the command
      # reloads Hyprland itself if they did), and again before the GTK
      # programs start, in case the state directory was cleared in between.
      home.activation.glassState = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
        run ${refresh}
      '';
      systemd.user.services.waybar.Service.ExecStartPre = refresh;
      systemd.user.services.swayosd.Service.ExecStartPre = refresh;
      systemd.user.services.walker.Service.ExecStartPre = refresh;
    })
  ];
}
