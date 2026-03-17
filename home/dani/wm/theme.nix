{ ... }:
{
  # Shared palette (GTK CSS variables) for Waybar + Wofi
  xdg.configFile."waybar/palette.css".text = ''
    @define-color bg #1e1e2e;
    @define-color fg #cdd6f4;
    @define-color muted #a6adc8;
    @define-color accent #89b4fa;

    @define-color bg_alpha rgba(30, 30, 46, 0.72);
    @define-color surface rgba(49, 50, 68, 0.70);
    @define-color border rgba(205, 214, 244, 0.10);
  '';
}
