{ pkgs, ... }:

let
  cursorPackage = pkgs.bibata-cursors;
  cursorName = "Bibata-Modern-Ice";
  cursorSize = 32;
in
{
  # gtk.enable lives in theme.nix with the rest of the GTK theming
  home.pointerCursor = {
    package = cursorPackage;
    name = cursorName;
    size = cursorSize;
    gtk.enable = true;
  };
}
