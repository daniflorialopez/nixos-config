{
  config,
  pkgs,
  theme,
  scene,
  ...
}:
let
  # theme/scene.nix, so the greeter and the desktop's fallback are one value
  # rather than two pins that named different pictures. See that file.
  #
  # Pinned at build time rather than following ~/.local/state/wallpaper/current:
  # SDDM drops the greeter to uid 175 (`sddm`, no supplementary groups) before
  # any user session exists, and /home/dani is 0700 — so it has no *search*
  # permission on the path and can read neither the state file nor the image it
  # names, whatever the bits below are. A symlink does not help either; it is
  # resolved with the reader's credentials and hits the same wall one hop later.
  # Making the greeter follow the picker therefore needs bytes pushed out of
  # $HOME, which is a separate decision and is not taken here.

  # sddm-astronaut recolored to Tokyo Night: frosted center column over
  # the wallpaper (hyprlock's sibling), blue accents on dark surfaces,
  # orange only on hover. Session picker and user field are visible UI.
  sddmTheme = pkgs.sddm-astronaut.override {
    embeddedTheme = "astronaut";
    themeConfig = {
      ScreenWidth = "2560";
      ScreenHeight = "1440";

      Font = "CaskaydiaMono Nerd Font";
      FontSize = "14";
      RoundCorners = "12";
      HourFormat = "HH:mm";
      DateFormat = "dddd d MMMM";
      HeaderText = "";

      Background = "${scene.anchor}";
      CropBackground = "true";
      DimBackground = "0.0";

      HeaderTextColor = theme.hex.fg;
      DateTextColor = theme.hex.subtle; # subordinate to the clock, like hyprlock
      TimeTextColor = theme.hex.fg;

      FormBackgroundColor = theme.hex.bg;
      BackgroundColor = theme.hex.bg;
      DimBackgroundColor = theme.hex.bg;

      LoginFieldBackgroundColor = theme.hex.surface;
      PasswordFieldBackgroundColor = theme.hex.surface;
      LoginFieldTextColor = theme.hex.fg;
      PasswordFieldTextColor = theme.hex.fg;
      UserIconColor = theme.hex.subtle;
      PasswordIconColor = theme.hex.subtle;

      PlaceholderTextColor = theme.hex.hint;
      WarningColor = theme.hex.critical;

      LoginButtonTextColor = theme.hex.bg;
      LoginButtonBackgroundColor = theme.hex.accent;
      SystemButtonsIconsColor = theme.hex.subtle;
      SessionButtonTextColor = theme.hex.subtle;
      VirtualKeyboardButtonTextColor = theme.hex.subtle;

      DropdownTextColor = theme.hex.fg;
      DropdownSelectedBackgroundColor = theme.hex.selection;
      DropdownBackgroundColor = theme.hex.bg;

      HighlightTextColor = theme.hex.bg;
      HighlightBackgroundColor = theme.hex.accent;
      HighlightBorderColor = theme.hex.accent;

      HoverUserIconColor = theme.hex.attention;
      HoverPasswordIconColor = theme.hex.attention;
      HoverSystemButtonsIconsColor = theme.hex.attention;
      HoverSessionButtonTextColor = theme.hex.attention;
      HoverVirtualKeyboardButtonTextColor = theme.hex.attention;

      PartialBlur = "true";
      HaveFormBackground = "false";
      FormPosition = "center";

      HideVirtualKeyboard = "true";
      ForceLastUser = "true";
      PasswordFocus = "true";
    };
  };
in
{
  services.xserver.enable = true; # needed for Cinnamon - X11 session

  environment.systemPackages = [
    sddmTheme
    pkgs.bibata-cursors # same cursor as the desktop (home/dani/wm/cursor.nix)
  ];

  services.displayManager.sddm = {
    enable = true;
    package = pkgs.kdePackages.sddm;
    theme = "sddm-astronaut-theme";
    # X11 greeter: weston's kiosk shell stacks every greeter window on one
    # output (laptop panel stays black) and kwin is unstable on the closed
    # NVIDIA driver; the X11 greeter places one window per screen reliably.
    # Only the login screen runs on X11 - the Hyprland session stays Wayland.
    wayland.enable = false;

    settings = {
      Theme = {
        CursorTheme = "Bibata-Modern-Ice";
        CursorSize = 32;
      };
    };

    # Qt runtime modules the theme's QML needs under qt6 sddm
    extraPackages = with pkgs.kdePackages; [
      qt5compat
      qtsvg
      qtmultimedia
      qtvirtualkeyboard
    ];
  };

  # Logging out has to restart the whole display manager, because SDDM will
  # not put the greeter back on its own. When a uwsm session ends, uwsm's
  # foreground process inherits the compositor unit's exit status, which on
  # this machine is virtually always non-zero (Hyprland core-dumps on
  # teardown under the NVIDIA driver, or the unit hits TimeoutStopSec with a
  # process still alive). sddm-helper then exits 1, SDDM reads that as "the
  # session crashed" and simply sits there: greeter never restarts, X server
  # stays up on its own VT, and the screen the user is looking at is a dead
  # console. Observed 2026-09-08 22:57:48, twenty-four seconds of nothing
  # until Ctrl+Alt+Del. Restarting display-manager.service sidesteps SDDM's
  # state machine entirely and is the same path a reboot already takes.
  systemd.services.logout-to-greeter = {
    description = "Return to the login greeter";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.systemd.package}/bin/systemctl restart display-manager.service";
    };
    # deliberately NOT wantedBy anything - only ever started by the logout
    # menu's "Log out" action (home/dani/wm/hyprland.nix)
  };

  # Passwordless start of this single unit for the seated user, so the logout
  # bind doesn't raise a polkit password prompt on the way out. Scoped to the
  # exact unit and verb, and to a local active session in wheel.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "logout-to-greeter.service" &&
          action.lookup("verb") == "start" &&
          subject.isInGroup("wheel") && subject.local && subject.active) {
        return polkit.Result.YES;
      }
    });
  '';
}
