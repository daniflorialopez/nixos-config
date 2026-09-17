{ pkgs, ... }:

let
  nf = pkgs.nerd-fonts;

  caskaydia =
    if nf ? "caskaydia-mono" then nf."caskaydia-mono"
    else if nf ? "cascadia-code" then nf."cascadia-code"
    else throw "Nerd Font package for Caskaydia/Cascadia not found under pkgs.nerd-fonts.";
in
{
  fonts.fontconfig.enable = true;

  fonts.packages = [
    caskaydia
    # The UI sans. Everything this repo *styles* asks for CaskaydiaMono by name,
    # but application UI that asks for nothing in particular - GTK menus and
    # dialogs, portal file choosers, Firefox chrome - was landing on whatever
    # fontconfig happened to pick. Until now that was 'Ubuntu 10', inherited
    # from a dconf key the Cinnamon era left behind (see home/dani/wm/theme.nix).
    pkgs.inter
  ];

  # NOTE: nixpkgs' inter-4.1 is a variable font whose family name is
  # "Inter Variable", NOT "Inter". Asking for "Inter" silently falls through to
  # DejaVu Sans with no error, which is exactly the failure this block exists to
  # stop. Verify after any bump with:
  #   fc-match "Inter Variable"
  fonts.fontconfig.defaultFonts = {
    # The important one. Nothing pointed the generic monospace alias at
    # CaskaydiaMono, so anything requesting plain `monospace` - GTK apps,
    # Chromium's fixed-width default - got DejaVu Sans Mono and rendered every
    # Nerd Font glyph as tofu.
    monospace = [ "CaskaydiaMono Nerd Font Mono" ];
    sansSerif = [ "Inter Variable" ];
    serif = [ "DejaVu Serif" ];
    emoji = [ "Noto Color Emoji" ];
  };
}

