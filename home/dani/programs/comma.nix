{ ... }:
{
  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;

  home.sessionVariables.COMMA_CACHING = "1";
}
