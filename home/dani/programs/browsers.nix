{ pkgs, ... }:

{
  home.packages = with pkgs; [
    firefox
    # google-chrome  # TODO if you enabled unfree
  ];
}

