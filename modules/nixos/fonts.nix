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
  ];
}

