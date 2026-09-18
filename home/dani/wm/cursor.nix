{ pkgs, metrics, ... }:

let
  cursorPackage = pkgs.bibata-cursors;
  cursorName = "Bibata-Modern-Ice";
  cursorSize = metrics.cursorSize;
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
