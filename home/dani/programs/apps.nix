{ pkgs, ... }:
let
  zathuraPkg = pkgs.zathura.override {
    plugins = with pkgs.zathuraPkgs; [
      zathura_pdf_mupdf
    ];
  };
in
{
  home.packages = with pkgs; [
    # File manager / archive manager
    pcmanfm
    file-roller

    # PDF viewers
    zathuraPkg
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
    poppler_utils
    fd
    ripgrep
    fzf
    zoxide
    imagemagick
  ];
}
