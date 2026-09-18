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
        # 1.0, NOT 0.96 — Hyprland owns window opacity, and this was quietly
        # fighting it.
        #
        # The two multiply. At 0.96 here against Hyprland's 0.94/0.88, the
        # terminal actually rendered at 0.902 focused / 0.845 unfocused, while
        # every other window on the desktop sat at 0.94/0.88. The design system
        # says focus is signalled by VALUE (docs/design-system.md, and the
        # 2026-07-22 border decision) — and a value signal cannot drift per
        # application, or the cue stops meaning one thing.
        #
        # Setting 1.0 hands the whole opacity budget to the compositor, so the
        # terminal now steps by exactly the same amount as everything else.
        # Blur is unaffected: decoration:blur:ignore_opacity is true, so the
        # glass behind the terminal does not depend on this value.
        opacity = 1.0;
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
          # dark-blue wash that keeps the text's own colors readable
          # (same #283457 fish uses for its selection); the old solid
          # #7aa2f7 fill put pale lavender on mid-blue at ~1.6:1
          text = "CellForeground";
          background = "0x283457";
        };

        normal = {
          black = "0x32344a";
          red = "0xf7768e";
          green = "0x9ece6a";
          yellow = "0xe0af68";
          blue = "0x7aa2f7";
          magenta = "0xad8ee6";
          # cyan reads as teal on purpose (tokyonight-moon family): Dani
          # can't tell blue-ish cyan from blue/white fast. white lightened
          # from canon 0x787c99 (4.2:1) for legibility
          cyan = "0x53c7ad";
          white = "0xa2a5b9";
        };

        bright = {
          # lightened from canon 0x444b6a (2.5:1) — bright black is what
          # CLIs use for "muted" text and it was nearly invisible
          black = "0x737aa2";
          red = "0xff7a93";
          green = "0xb9f27c";
          yellow = "0xff9e64";
          blue = "0x7da6ff";
          magenta = "0xbb9af7";
          cyan = "0x4fd6be";
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

