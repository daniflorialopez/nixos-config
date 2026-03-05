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

  # Wofi reads from ~/.config/wofi/style.css (we also drop palette there)
  xdg.configFile."wofi/palette.css".text = ''
    @define-color bg #1e1e2e;
    @define-color fg #cdd6f4;
    @define-color muted #a6adc8;
    @define-color accent #89b4fa;

    @define-color bg_alpha rgba(30, 30, 46, 0.96);
    @define-color surface rgba(49, 50, 68, 0.75);
    @define-color border rgba(205, 214, 244, 0.12);
  '';

  xdg.configFile."wofi/style.css".text = ''
    window {
      background-color: @bg_alpha;
      border: 1px solid @border;
      border-radius: 16px;
      box-shadow: 0 12px 40px rgba(0, 0, 0, 0.45);
      opacity: 1 !important;
   }

    #outer-box { 
      background-color: #1e1e2e;
      border-radius: 16px;
      padding: 10px;
      opacity: 1 !important;
    }

    #input {
      margin: 0 0 10px 0;
      padding: 10px 12px;
      background-color: @surface;
      color: @fg;
      border-radius: 12px;
      border: 1px solid @border;
    }

    #inner-box { margin: 0; }
    #entry {
      padding: 10px 12px;
      border-radius: 12px;
      color: @fg;
    }
    #entry:selected {
      background-color: rgba(137, 180, 250, 0.18);
    }

    #text { color: @fg; }
    #text:selected { color: @fg; }
  '';
}
