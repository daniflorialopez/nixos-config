{ pkgs, ... }:

let
  cursorPackage = pkgs.bibata-cursors;
  cursorName = "Bibata-Modern-Ice";
  cursorSize = 32;
in
{
  gtk.enable = true;

  home.pointerCursor = {
    package = cursorPackage;
    name = cursorName;
    size = cursorSize;
    gtk.enable = true;
  };
}
