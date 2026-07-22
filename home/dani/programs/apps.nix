{ pkgs, ... }:
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

      default-bg = "#1a1b26";
      default-fg = "#c0caf5";
      statusbar-bg = "#1a1b26";
      statusbar-fg = "#a9b1d6";
      inputbar-bg = "#1a1b26";
      inputbar-fg = "#c0caf5";

      completion-bg = "#24283b";
      completion-fg = "#c0caf5";
      completion-group-bg = "#1a1b26";
      completion-group-fg = "#7aa2f7";
      completion-highlight-bg = "#283457";
      completion-highlight-fg = "#c0caf5";

      index-bg = "#1a1b26";
      index-fg = "#c0caf5";
      index-active-bg = "#283457";
      index-active-fg = "#c0caf5";

      notification-bg = "#1a1b26";
      notification-fg = "#c0caf5";
      notification-error-bg = "#1a1b26";
      notification-error-fg = "#f7768e";
      notification-warning-bg = "#1a1b26";
      notification-warning-fg = "#e0af68";

      # search hits: orange = "look here" (yazi find tier), blue = the
      # active hit (position accent), like waybar's urgent/active split
      highlight-color = "rgba(255, 158, 100, 0.4)";
      highlight-active-color = "rgba(122, 162, 247, 0.5)";

      render-loading-bg = "#1a1b26";
      render-loading-fg = "#565f89";

      recolor = true;
      recolor-keephue = true;
      recolor-lightcolor = "#1a1b26";
      recolor-darkcolor = "#c0caf5";
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
