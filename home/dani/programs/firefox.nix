{ pkgs, ... }:

let
  commonSettings = {
    # keep theme choice local to each profile or device
    "services.sync.prefs.sync.extensions.activeThemeID" = false;

    # dark by default inside Firefox
    "ui.systemUsesDarkTheme" = 1;

    # Website appearance: Dark.
    # 0 = dark, 1 = light, 2 = system, 3 = browser
    "layout.css.prefers-color-scheme.content-override" = 0;
  };
in
{
  programs.firefox = {
    enable = true;

    policies = {
      Extensions = {
        Install = [
          "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
          "https://addons.mozilla.org/firefox/downloads/latest/vimium-ff/latest.xpi"
          "https://addons.mozilla.org/firefox/downloads/latest/auto-tab-discard/latest.xpi"

        ];
      };

      # Leave extension updates enabled.
      ExtensionUpdate = true;
    };

    profiles = {
      personal = {
        id = 0;
        name = "personal";
        isDefault = true;
        settings = commonSettings;
      };

      work = {
        id = 1;
        name = "work";
        settings = commonSettings;
      };

      lab = {
        id = 2;
        name = "lab";
        settings = commonSettings;
      };
    };
  };
}
