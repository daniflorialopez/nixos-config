{ ... }:
{
  # Lock screen: Tokyo Night over a blurred screenshot (matches whatever
  # wallpaper is active), sunset gradient ring on the password field.
  # Requires security.pam.services.hyprlock on the system side to unlock.
  programs.hyprlock = {
    enable = true;

    settings = {
      general = {
        disable_loading_bar = true;
        hide_cursor = true;
        grace = 2; # seconds after lock during which any key unlocks
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
          outer_color = "rgba(122, 162, 247, 1.0) rgba(255, 158, 100, 1.0) 45deg";
          inner_color = "rgba(26, 27, 38, 0.85)";
          font_color = "rgb(192, 202, 245)";
          fade_on_empty = false;
          placeholder_text = "<span foreground='##565f89'>Password…</span>";
          check_color = "rgba(224, 175, 104, 1.0)";
          fail_color = "rgba(247, 118, 142, 1.0)";
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
          color = "rgb(192, 202, 245)";
          position = "0, 160";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = ''cmd[update:60000] date +"%A, %d %B"'';
          font_size = 20;
          font_family = "CaskaydiaMono Nerd Font";
          color = "rgba(169, 177, 214, 1.0)";
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
