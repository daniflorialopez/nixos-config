{ pkgs, ... }:

{
  home.packages = with pkgs; [
    kdenlive
    obs-studio
    spotify
    # TODO youtube-music, whatsapp, vesktop may be from flatpak or other pkgs
  ];
}

