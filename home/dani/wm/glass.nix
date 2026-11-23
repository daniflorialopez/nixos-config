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
#   walker     the launcher's box likewise: 0.90 off, 0.60 on, over a
#              darker glass of its own that does not follow the chosen look;
#              and the power and capture menus' box, 0.97 off, 0.70 on
#   Alacritty  imports glass.toml: its background opacity while glass is on
#   mako       includes glass.mako: a notification is 0.88 solid off, 0.60 on,
#              over the same darker glass as the launcher
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
  confirmOff = theme.cssRgba "bgDeep" "0.97";
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
      default = "0.60";
      description = ''
        How solid the launcher's box is while glass is on; off it is 0.90.
        What shows through the rest is the darker "menu" glass, not the
        chosen look.
      '';
    };

    confirmAlpha = lib.mkOption {
      type = lib.types.str;
      default = "0.70";
      description = ''
        How solid the box of the power and capture menus is while glass is
        on; off it is 0.97. More solid than the launcher's: what is asked
        there is whether to shut the machine down.
      '';
    };

    fullscreen = lib.mkOption {
      type = lib.types.enum [
        "blur"
        "underlay"
      ];
      default = "blur";
      description = ''
        What a see-through window has behind it in real fullscreen, where
        Hyprland draws no decorations and so no glass: Hyprland's own blur,
        or the plugin's glass on a layer that reverie puts under the window
        (wm/reverie.nix sets this where it is enabled).
      '';
    };

    terminalOpacity = lib.mkOption {
      type = lib.types.str;
      default = "0.65";
      description = "Alacritty's background opacity while glass is on; off it is 1.0.";
    };

    windows = lib.mkOption {
      type = lib.types.str;
      default = "^(Alacritty|scratch-.*)$";
      description = ''
        The windows that are see-through while glass is on, as a regex on
        their class: Alacritty, under its own name and under the scratchpads'
        (wm/hyprland.nix). Said once, here, for the two things that have to
        know: the rule that keeps their opacity in fullscreen, and reverie,
        which lays glass under them there.
      '';
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
        launcher's), and `confirm_bg`, that of the power and capture menus.
      '';
    };
  };

  config = lib.mkMerge [
    {
      programs.glass = {
        command = pkgs.callPackage ../../../pkgs/hyprglass/glass.nix {
          hyprglass = cfg.plugin;
          inherit islandOff popupOff confirmOff;
          confirmOn = theme.cssRgba "bgDeep" cfg.confirmAlpha;
          islandOn = theme.cssRgba "bg" cfg.islandAlpha;
          popupOn = theme.cssRgba "bgDeep" cfg.popupAlpha;
          notifyOn = theme.hexA "bg" "99"; # 0.60, like the launcher's box
          inherit (cfg) terminalOpacity fullscreen windows;
          windowOpacity = toString (
            lib.attrByPath [ "decoration" "active_opacity" ] 1.0
              config.wayland.windowManager.hyprland.settings
          );
        };
        islandBackground = fromState "@define-color bg_alpha ${islandOff};";
        popupBackground = fromState ''
          @define-color popup_bg ${popupOff};
          @define-color confirm_bg ${confirmOff};'';
      };
    }

    (lib.mkIf cfg.enable {
      home.packages = [ cfg.command ];

      # Last in the file, so that what it says wins over the rules above it.
      wayland.windowManager.hyprland.extraConfig = ''
        source = ${stateDir}/glass.conf
      '';

      programs.alacritty.settings.general.import = [ "${stateDir}/glass.toml" ];

      # After `background-color` in the file mako reads (Home Manager writes
      # the keys in alphabetical order, and mako takes the later of two), so
      # what the include says wins while glass is on; off, it says nothing.
      services.mako.settings.include = "${stateDir}/glass.mako";

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
      systemd.user.services.mako.Service.ExecStartPre = refresh;
    })
  ];
}
