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

    # Pinned because 26.05 made this stateVersion-gated: it was internal, and
    # its default moves from ~/.mozilla/firefox to $XDG_CONFIG_HOME/mozilla/
    # firefox at stateVersion 26.05. home.stateVersion is 25.05, so this is
    # already the effective value — stating it silences the warning and, more
    # importantly, means a future stateVersion bump cannot silently relocate all
    # three profiles and start Firefox from scratch.
    configPath = ".mozilla/firefox";

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
