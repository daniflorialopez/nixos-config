{ pkgs, ... }:
{
  # Dark theming for GTK apps (pcmanfm, pavucontrol, blueman, ...)
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
      # adw-gtk3 ships no GTK4 CSS, so plain-GTK4 apps (e.g. pavucontrol)
      # would fall back to built-in light; name the built-in theme so its
      # dark variant resolves. libadwaita apps ignore this and use dconf.
      gtk-theme-name = "Default";
    };
  };

  # libadwaita apps ignore gtk-theme and follow this preference instead
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  # Qt apps follow suit
  qt = {
    enable = true;
    platformTheme.name = "adwaita";
    style = {
      name = "adwaita-dark";
      package = pkgs.adwaita-qt;
    };
  };

  # Shared palette (GTK CSS variables) for Waybar — Tokyo Night, matching
  # the Alacritty colorscheme so the desktop chrome and terminal agree.
  xdg.configFile."waybar/palette.css".text = ''
    @define-color bg #1a1b26;
    @define-color bg_alpha rgba(26, 27, 38, 0.85);
    @define-color surface rgba(36, 40, 59, 0.70);
    @define-color fg #c0caf5;
    @define-color subtle #a9b1d6;
    @define-color muted #565f89;
    @define-color accent #7aa2f7;
    @define-color warning #e0af68;
    @define-color critical #f7768e;
    @define-color attention #ff9e64;
    @define-color border rgba(192, 202, 245, 0.10);
  '';
}
