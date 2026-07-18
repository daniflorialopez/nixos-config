{
  pkgs,
  ...
}:
let
  # The same mountain-sunset wallpaper hyprpaper uses, so login, lock
  # and desktop are one continuous scene
  wallpaper = ../../../home/dani/assets/wallpapers/wallhaven-jevzkp.jpg;

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

      Background = "${wallpaper}";
      CropBackground = "true";
      DimBackground = "0.0";

      HeaderTextColor = "#c0caf5";
      DateTextColor = "#a9b1d6"; # subordinate to the clock, like hyprlock
      TimeTextColor = "#c0caf5";

      FormBackgroundColor = "#1a1b26";
      BackgroundColor = "#1a1b26";
      DimBackgroundColor = "#1a1b26";

      LoginFieldBackgroundColor = "#24283b";
      PasswordFieldBackgroundColor = "#24283b";
      LoginFieldTextColor = "#c0caf5";
      PasswordFieldTextColor = "#c0caf5";
      UserIconColor = "#a9b1d6";
      PasswordIconColor = "#a9b1d6";

      PlaceholderTextColor = "#737aa2";
      WarningColor = "#f7768e";

      LoginButtonTextColor = "#1a1b26";
      LoginButtonBackgroundColor = "#7aa2f7";
      SystemButtonsIconsColor = "#a9b1d6";
      SessionButtonTextColor = "#a9b1d6";
      VirtualKeyboardButtonTextColor = "#a9b1d6";

      DropdownTextColor = "#c0caf5";
      DropdownSelectedBackgroundColor = "#283457";
      DropdownBackgroundColor = "#1a1b26";

      HighlightTextColor = "#1a1b26";
      HighlightBackgroundColor = "#7aa2f7";
      HighlightBorderColor = "#7aa2f7";

      HoverUserIconColor = "#ff9e64";
      HoverPasswordIconColor = "#ff9e64";
      HoverSystemButtonsIconsColor = "#ff9e64";
      HoverSessionButtonTextColor = "#ff9e64";
      HoverVirtualKeyboardButtonTextColor = "#ff9e64";

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
}
