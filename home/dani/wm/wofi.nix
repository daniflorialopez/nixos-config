{ pkgs, ... }:
{
  xdg.configFile."wofi/config".text = ''
    show=drun
    width=520
    allow_images=true
    prompt=Search…
    insensitive=true
    style=style.css
  '';
}
