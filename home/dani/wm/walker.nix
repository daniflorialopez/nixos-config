{ inputs, ... }:

{
  imports = [
    inputs.walker.homeManagerModules.default
  ];

  programs.elephant = {
    providers = [
      "desktopapplications"
      "providerlist"
      "runner"
      "calc"
      "windows"
      "clipboard"
      "symbols"
    ];
  };

  programs.walker = {
    enable = true;
    runAsService = true;

    config = {
      theme = "dani-soft";

      close_when_open = true;
      force_keyboard_focus = true;

      placeholders."default" = {
        input = "Search apps, commands, clipboard…";
        list = "No results";
      };

      providers = {
        default = [
          "desktopapplications"
          "runner"
          "calc"
        ];

        empty = [ "desktopapplications" ];

        prefixes = [
          { prefix = ";"; provider = "providerlist"; }
          { prefix = ">"; provider = "runner"; }
          { prefix = "="; provider = "calc"; }
          { prefix = ":"; provider = "clipboard"; }
          { prefix = "."; provider = "symbols"; }
          { prefix = "$"; provider = "windows"; }
        ];

        actions = {
          desktopapplications = [
            { action = "start"; default = true; bind = "Return"; }
          ];

          runner = [
            { action = "run"; default = true; bind = "Return"; }
          ];

          calc = [
            { action = "copy"; default = true; bind = "Return"; }
          ];
        };
      };

      keybinds = {
        close = [ "Escape" ];
        next = [ "Down" "ctrl j" ];
        previous = [ "Up" "ctrl k" ];
        quick_activate = [ "F1" "F2" "F3" "F4" ];
      };
    };
  };

  

  xdg.configFile."walker/themes/dani-soft/style.css".text = ''
    @define-color window_bg_color rgba(17, 17, 27, 0.97);
    @define-color panel_bg_color rgba(30, 30, 46, 0.93);
    @define-color accent_bg_color rgba(137, 180, 250, 0.14);
    @define-color accent_line_color rgba(137, 180, 250, 0.24);
    @define-color theme_fg_color #cdd6f4;
    @define-color subtext_color rgba(205, 214, 244, 0.62);
    @define-color border_color rgba(255, 255, 255, 0.07);
    @define-color walker_outer_border rgba(56, 189, 248, 0.96);
    @define-color walker_outer_glow rgba(56, 189, 248, 0.26);

    * {
      all: unset;
    }

    scrollbar {
      opacity: 0;
    }

    .box-wrapper {
      background: @window_bg_color;
      border: 2px solid @walker_outer_border;
      border-radius: 20px;
      padding: 16px;
      box-shadow:
        0 0 0 1px rgba(56, 189, 248, 0.16),
        0 0 24px @walker_outer_glow,
        0 18px 50px rgba(0, 0, 0, 0.30),
        0 8px 24px rgba(0, 0, 0, 0.16);
    }

    .search-container {
      margin-bottom: 10px;
    }

    .input {
      background: @panel_bg_color;
      color: @theme_fg_color;
      border: 1px solid transparent;
      border-radius: 14px;
      padding: 12px 14px;
      min-height: 26px;
      caret-color: @theme_fg_color;
      font-size: 15px;
    }

    .input:focus,
    .input:active {
      border-color: @accent_line_color;
    }

    .input placeholder {
      color: @subtext_color;
    }

    .list {
      color: @theme_fg_color;
    }

    .item-box {
      border-radius: 14px;
      padding: 10px 12px;
    }

    child:hover .item-box,
    child:selected .item-box,
    row:selected .item-box {
      background: @accent_bg_color;
    }

    .item-text {
      color: @theme_fg_color;
      font-size: 14px;
      font-weight: 600;
    }

    .item-subtext {
      color: @subtext_color;
      font-size: 12px;
    }

    .item-image,
    .item-image-text {
      margin-right: 10px;
    }

    .normal-icons {
      -gtk-icon-size: 18px;
    }

    .large-icons {
      -gtk-icon-size: 30px;
    }

    .item-quick-activation {
      margin-left: 10px;
      padding: 4px 8px;
      border-radius: 8px;
      background: rgba(255, 255, 255, 0.05);
      color: @subtext_color;
      font-size: 11px;
      font-weight: 700;
    }

    .placeholder,
    .elephant-hint {
      color: @subtext_color;
    }

    .keybinds,
    .keybinds-wrapper {
      margin-top: 8px;
      padding-top: 8px;
      border-top: 1px solid rgba(255, 255, 255, 0.05);
      color: @subtext_color;
      font-size: 11px;
      opacity: 0.55;
    }

    .keybind-bind {
      font-weight: 700;
    }

    .keybind-label {
      padding: 2px 6px;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.04);
    }

    .preview {
      border: 1px solid rgba(255, 255, 255, 0.06);
      border-radius: 12px;
      padding: 10px;
      background: rgba(255, 255, 255, 0.02);
      color: @theme_fg_color;
    }
  '';
}
