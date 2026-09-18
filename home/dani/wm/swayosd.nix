# home/dani/wm/swayosd.nix
#
# Volume/brightness OSD: the XF86 keys used to work silently. The XF86
# binds in hyprland.nix now go through swayosd-client, which applies the
# change AND pops the overlay; swayosd-server (HM user service) draws it.
#
# Brightness writes /sys/class/backlight directly, so the system side
# (modules/nixos/desktop/hyprland.nix) installs swayosd's udev rule and
# dani joins the video group — HM alone can't grant that.
#
# Styled to the design system: a glass Tokyo Night pill matching the
# waybar islands (same bg/border/radius; the blur + ignorezero layerrule
# pair lives in hyprland.nix next to waybar's).
{ pkgs, theme, metrics, ... }:
let
  # One palette source: home/dani/theme/palette.nix. Pure white/black washes
  # below stay literal on purpose — they are material effects (hairlines,
  # shadows, hover tints), not palette colours, and would not change with it.
  style = pkgs.writeText "swayosd-style.css" ''
    window#osd {
      background: ${theme.cssRgba "bg" "0.85"};
      border: 1px solid ${theme.cssRgba "fg" "0.10"};
      border-radius: ${metrics.px metrics.islandRadius};
      padding: 12px 20px;
    }

    image, label {
      color: ${theme.hex.fg};
      font-family: "CaskaydiaMono Nerd Font";
    }

    progressbar {
      min-height: 6px;
      border-radius: 999px;
      background: none;
      border: none;
    }

    trough {
      min-height: inherit;
      border-radius: inherit;
      border: none;
      background: ${theme.cssRgba "slate" "0.35"};
    }

    progress {
      min-height: inherit;
      border-radius: inherit;
      border: none;
      background: ${theme.hex.accent};
    }
  '';
in
{
  services.swayosd = {
    enable = true;
    stylePath = "${style}";
  };
}
