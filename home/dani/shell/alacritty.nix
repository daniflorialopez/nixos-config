{
  ...
}:

{
  programs.alacritty = {
    enable = true;

    settings = {

      env = {
        TERM = "xterm-256color";
      };

      font = {
        normal = { family = "CaskaydiaMono Nerd Font Mono"; style = "Regular"; };
        bold   = { family = "CaskaydiaMono Nerd Font Mono"; style = "Bold"; };
        italic = { family = "CaskaydiaMono Nerd Font Mono"; style = "Italic"; };
        size = 13.0;
      };

      window = {
        opacity = 0.96;
        padding = {
          x = 8;
          y = 8;
        };
      };

      colors = {
        primary = {
          background = "0x1a1b26";
          foreground = "0xa9b1d6";
        };

        cursor = {
          text = "0x1a1b26";
          cursor = "0xc0caf5";
        };

        selection = {
          text = "0xc0caf5";
          background = "0x7aa2f7";
        };

        normal = {
          black = "0x32344a";
          red = "0xf7768e";
          green = "0x9ece6a";
          yellow = "0xe0af68";
          blue = "0x7aa2f7";
          magenta = "0xad8ee6";
          cyan = "0x449dab";
          white = "0x787c99";
        };

        bright = {
          black = "0x444b6a";
          red = "0xff7a93";
          green = "0xb9f27c";
          yellow = "0xff9e64";
          blue = "0x7da6ff";
          magenta = "0xbb9af7";
          cyan = "0x0db9d7";
          white = "0xacb0d0";
        };
      };

      keyboard.bindings = [
        { key = "Insert"; mods = "Shift";   action = "Paste"; }
        { key = "Insert"; mods = "Control"; action = "Copy";  }
        { key = "C"; mods = "Super"; action = "Copy"; }
        { key = "V"; mods = "Super"; action = "Paste"; }
      ];

      terminal = {
        osc52 = "OnlyCopy";
      };


    };
  };
}

