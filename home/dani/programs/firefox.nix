{ ... }:

{
  programs.firefox = {
    enable = true;

    profiles = {
      personal = {
        id = 0;
        isDefault = true;

        settings = {
          "extensions.activeThemeID" = "firefox-alpenglow@mozilla.org";
          "services.sync.prefs.sync.extensions.activeThemeID" = false;
        };
      };

      work = {
        id = 1;

        settings = {
          # Optional:
          "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org"; # uncomment this to pin built-in Dark declaratively.
          "services.sync.prefs.sync.extensions.activeThemeID" = false;
        };
      };

      lab = {
        id = 2;

        settings = {
          "extensions.activeThemeID" = "{d551e720-3100-43f5-8242-74a6c5cb7c34}";
          "services.sync.prefs.sync.extensions.activeThemeID" = false;
        };

      };
    };
  };
}
