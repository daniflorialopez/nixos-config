{ pkgs, theme, ... }:
let
  zathuraPkg = pkgs.zathura.override {
    plugins = with pkgs.zathuraPkgs; [
      zathura_pdf_mupdf
    ];
  };
in
{
  # Tokyo Night zathura; recolor=true renders pages dark by default
  # (Ctrl+R flips back to paper-white for print-faithful reading)
  programs.zathura = {
    enable = true;
    package = zathuraPkg;
    options = {
      font = "CaskaydiaMono Nerd Font 11";

      default-bg = theme.hex.bg;
      default-fg = theme.hex.fg;
      statusbar-bg = theme.hex.bg;
      statusbar-fg = theme.hex.subtle;
      inputbar-bg = theme.hex.bg;
      inputbar-fg = theme.hex.fg;

      completion-bg = theme.hex.surface;
      completion-fg = theme.hex.fg;
      completion-group-bg = theme.hex.bg;
      completion-group-fg = theme.hex.accent;
      completion-highlight-bg = theme.hex.selection;
      completion-highlight-fg = theme.hex.fg;

      index-bg = theme.hex.bg;
      index-fg = theme.hex.fg;
      index-active-bg = theme.hex.selection;
      index-active-fg = theme.hex.fg;

      notification-bg = theme.hex.bg;
      notification-fg = theme.hex.fg;
      notification-error-bg = theme.hex.bg;
      notification-error-fg = theme.hex.critical;
      notification-warning-bg = theme.hex.bg;
      notification-warning-fg = theme.hex.warning;

      # search hits: orange = "look here" (yazi find tier), blue = the
      # active hit (position accent), like waybar's urgent/active split
      highlight-color = "rgba(255, 158, 100, 0.4)";
      highlight-active-color = "rgba(122, 162, 247, 0.5)";

      render-loading-bg = theme.hex.bg;
      render-loading-fg = theme.hex.slate;

      recolor = true;
      recolor-keephue = true;
      recolor-lightcolor = theme.hex.bg;
      recolor-darkcolor = theme.hex.fg;
    };
  };

  # imv: dark canvas + palette overlay instead of the default black/white
  xdg.configFile."imv/config".text = ''
    [options]
    background = 1a1b26
    overlay_font = CaskaydiaMono Nerd Font Mono:11
    overlay_text_color = c0caf5
    overlay_background_color = 1a1b26
    overlay_background_alpha = d0
  '';

  home.packages = with pkgs; [
    # File manager / archive manager
    pcmanfm
    file-roller

    # PDF viewers (zathura is programs.zathura above)
    kdePackages.okular

    # Viewers / media
    imv
    mpv

    # Office
    libreoffice

    # Yazi helpers and preview dependencies
    file
    xdg-utils
    ffmpeg
    p7zip
    jq
    poppler-utils
    fd
    ripgrep
    fzf
    zoxide
    imagemagick
  ];
}
