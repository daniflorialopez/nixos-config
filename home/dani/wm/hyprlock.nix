{ lib, ... }:

let
  # One palette source: home/dani/theme/palette.nix.
  theme = import ../theme/palette.nix { inherit lib; };
in
{
  # Lock screen: Tokyo Night over a blurred screenshot (matches whatever
  # wallpaper is active), sunset gradient ring on the password field.
  # Requires security.pam.services.hyprlock on the system side to unlock.
  programs.hyprlock = {
    enable = true;

    settings = {
      # Only keys hyprlock 0.9.2 actually registers. Verified against the running
      # binary: `strings $(readlink -f (command -v hyprlock)) | grep '^general:'`
      # yields exactly fail_timeout, fractional_scaling, hide_cursor,
      # ignore_empty_input, immediate_render, screencopy_mode, text_trim.
      #
      # Two keys used to live here and were silently doing nothing, because
      # hyprlock logs "Proceeding ignoring faulty entries" on an unknown key
      # rather than failing:
      #   - disable_loading_bar: gone from the config entirely.
      #   - grace: became a CLI flag in v0.9.0 ("CLI grace parameter replaces
      #     config option"). It is now passed as `hyprlock --grace 2` on the
      #     $mod+Escape bind only — deliberately NOT on hypridle's lock_cmd,
      #     since a grace period on the lock-before-suspend path would leave the
      #     machine briefly unlockable-by-any-key after it wakes.
      general = {
        hide_cursor = true;
        # Refuse an empty password instead of running it through PAM, so Enter
        # on an empty field is a no-op rather than a counted failed attempt.
        ignore_empty_input = true;
      };

      background = [
        {
          monitor = "";
          path = "screenshot";
          blur_passes = 3;
          blur_size = 6;
          noise = 0.0117;
          contrast = 0.9;
          brightness = 0.6;
          vibrancy = 0.17;
        }
      ];

      input-field = [
        {
          monitor = "";
          size = "320, 55";
          outline_thickness = 3;
          dots_size = 0.28;
          dots_spacing = 0.2;
          dots_center = true;
          outer_color = "${theme.cssRgba "accent" "1.0"} ${theme.cssRgba "attention" "1.0"} 45deg";
          inner_color = (theme.cssRgba "bg" "0.85");
          font_color = (theme.cssRgb "fg");
          fade_on_empty = false;
          # #737aa2 is the contrast floor for hint text (see terminal calibration)
          placeholder_text = "<span foreground='##${theme.noHash.hint}'>Password…</span>";
          check_color = (theme.cssRgba "warning" "1.0");
          fail_color = (theme.cssRgba "critical" "1.0");
          fail_text = "$FAIL <b>($ATTEMPTS)</b>";
          position = "0, -80";
          halign = "center";
          valign = "center";
        }
      ];

      label = [
        {
          monitor = "";
          text = "$TIME";
          font_size = 90;
          font_family = "CaskaydiaMono Nerd Font";
          color = (theme.cssRgb "fg");
          position = "0, 160";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          # same date wording as the SDDM greeter: "Saturday 18 July"
          text = ''cmd[update:60000] date +"%A %-d %B"'';
          font_size = 20;
          font_family = "CaskaydiaMono Nerd Font";
          color = (theme.cssRgba "subtle" "1.0");
          position = "0, 60";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };

  # No idle auto-lock by choice: locking is manual (Super+Escape).
  # Hypridle only ensures the session is locked when suspending and
  # wakes the displays properly after resume.
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
    };
  };
}
