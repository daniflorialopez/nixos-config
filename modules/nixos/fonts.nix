{
  pkgs,
  ...
}:

{
  fonts = {
    fontconfig.enable = true;
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only  # optional, but helps with icons/glyph coverage
    ];
  };
}
