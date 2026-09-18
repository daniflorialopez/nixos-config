{ config, pkgs, theme, metrics, ... }:
let
  # The single palette source. See home/dani/theme/palette.nix; the build-time
  # contrast/hue gate lives next to it in home/dani/theme/default.nix.

  # Two type tiers, deliberately. The shell/chrome tier (waybar, mako, walker,
  # hyprlock, SDDM, the terminal) stays 100% CaskaydiaMono — that is the
  # design-system rule and it is what gives the desktop its voice. Application
  # UI is a different tier: menus, dialogs and portal file choosers are dense
  # proportional text, and a monospace there costs real readability for no
  # stylistic gain.
  #
  # "Inter Variable" is the family name nixpkgs' inter-4.1 actually publishes.
  # It is NOT "Inter" — see the note in modules/nixos/fonts.nix.
  uiFont = "Inter Variable 10";
  monoFamily = "CaskaydiaMono Nerd Font Mono";
in
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
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
      gtk-font-name = uiFont;
    };
    # stateVersion-gated in 26.05: gtk4.theme used to follow gtk.theme
    # unconditionally, and its new default is null. Pinned to the old behaviour,
    # which is what is in effect at stateVersion 25.05 — adopting null would
    # drop adw-gtk3's GTK4 CSS import and visibly change pavucontrol and the
    # portal dialogs.
    gtk4.theme = config.gtk.theme;

    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
      gtk-font-name = uiFont;
      # adw-gtk3 ships no GTK4 CSS, so plain-GTK4 apps (e.g. pavucontrol)
      # would fall back to built-in light; name the built-in theme so its
      # dark variant resolves. libadwaita apps ignore this and use dconf.
      gtk-theme-name = "Default";
    };
  };

  # This block is the *authority* for GTK appearance, not a restatement of
  # settings.ini — and the distinction is load-bearing.
  #
  # settings.ini is only read by apps that read settings.ini. Everything going
  # through the xdg-desktop-portal Settings interface — every libadwaita app,
  # every portal dialog — reads dconf, and dconf wins there. Proof, before this
  # change:
  #
  #   busctl --user call org.freedesktop.portal.Desktop \
  #     /org/freedesktop/portal/desktop org.freedesktop.portal.Settings \
  #     Read ss org.gnome.desktop.interface font-name
  #   -> "Ubuntu 10"
  #
  # No file in this repo set that. It was residue from the Cinnamon era, and it
  # was the real font of every unstyled GTK surface on the machine. Because the
  # repo declared only color-scheme, the remaining keys agreed with settings.ini
  # purely by coincidence — so changing gtk.theme here would have half-applied,
  # with portal-reading apps keeping the old value.
  #
  # Declaring them makes Home Manager the owner of the keys that actually decide.
  dconf.settings."org/gnome/desktop/interface" = {
    # libadwaita apps ignore gtk-theme and follow this preference instead
    color-scheme = "prefer-dark";
    font-name = uiFont;
    document-font-name = "Inter Variable 11";
    monospace-font-name = "${monoFamily} 11";
    # Kept in step with home.pointerCursor (wm/cursor.nix) on purpose: a stale
    # dconf cursor-theme is followed by anything reading through the portal, so
    # leaving it undeclared means the cursor can silently diverge from the one
    # the rest of the session uses.
    cursor-theme = "Bibata-Modern-Ice";
    cursor-size = metrics.cursorSize;
  };

  # Qt apps follow suit
  qt = {
    enable = true;
    platformTheme.name = "adwaita";
    style = {
      name = "adwaita-dark";
      package = pkgs.adwaita-qt;
    };
  };

  # Shared palette (GTK CSS variables) for Waybar.
  #
  # GENERATED from home/dani/theme/palette.nix — this file is now an output, not
  # a definition. It used to be the closest thing the repo had to a canonical
  # palette (docs/design-system.md said so) while having exactly one consumer and
  # being re-typed by hand everywhere else.
  #
  # The CSS variable names are kept verbatim because waybar/style.css references
  # them, but two of them were misleading and now point at the correctly-named
  # role: `@muted` is the `slate` role (#565f89), not the `muted` role (#a0a5c0),
  # and `@border` is a 10% wash of `fg`.
  xdg.configFile."waybar/palette.css".text = ''
    @define-color bg ${theme.hex.bg};
    @define-color bg_alpha ${theme.cssRgba "bg" "0.85"};
    @define-color surface ${theme.cssRgba "surface" "0.70"};
    @define-color fg ${theme.hex.fg};
    @define-color subtle ${theme.hex.subtle};
    @define-color muted ${theme.hex.slate};
    @define-color accent ${theme.hex.accent};
    @define-color warning ${theme.hex.warning};
    @define-color critical ${theme.hex.critical};
    @define-color attention ${theme.hex.attention};
    @define-color border ${theme.cssRgba "fg" "0.10"};
  '';
}
