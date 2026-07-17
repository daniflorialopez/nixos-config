{ ... }:
{
  # Shared palette (GTK CSS variables) for Waybar — Tokyo Night, matching
  # the Alacritty colorscheme so the desktop chrome and terminal agree.
  xdg.configFile."waybar/palette.css".text = ''
    @define-color bg #1a1b26;
    @define-color bg_alpha rgba(26, 27, 38, 0.94);
    @define-color surface rgba(36, 40, 59, 0.70);
    @define-color fg #c0caf5;
    @define-color subtle #a9b1d6;
    @define-color muted #565f89;
    @define-color accent #7aa2f7;
    @define-color warning #e0af68;
    @define-color critical #f7768e;
    @define-color border rgba(192, 202, 245, 0.10);
  '';
}
