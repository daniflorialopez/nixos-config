{ pkgs, ... }:

{
  home.packages = with pkgs; [
    kdePackages.kdenlive
    obs-studio
    spotify
    # TODO youtube-music, whatsapp, vesktop may be from flatpak or other pkgs
  ];
}

