{ pkgs, ... }:

{
  home.packages = with pkgs; [
    firefox
    google-chrome
    chromium
    ungoogled-chromium
    brave
  ];
}

