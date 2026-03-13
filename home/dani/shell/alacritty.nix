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
        padding = { x = 14; y = 14; };
        # decorations = "None";
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

