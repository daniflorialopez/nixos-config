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
{ pkgs, ... }:
let
  style = pkgs.writeText "swayosd-style.css" ''
    window#osd {
      background: rgba(26, 27, 38, 0.85);
      border: 1px solid rgba(192, 202, 245, 0.10);
      border-radius: 12px;
      padding: 12px 20px;
    }

    image, label {
      color: #c0caf5;
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
      background: rgba(86, 95, 137, 0.35);
    }

    progress {
      min-height: inherit;
      border-radius: inherit;
      border: none;
      background: #7aa2f7;
    }
  '';
in
{
  services.swayosd = {
    enable = true;
    stylePath = "${style}";
  };
}
