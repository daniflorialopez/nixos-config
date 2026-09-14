{ inputs, pkgs, ... }:

let
  # Palette and shared chrome for both walker themes. walker gives every
  # theme its own CSS file and they do not inherit from one another, so the
  # common part lives here to stop dani-soft and dani-grid drifting apart.
  baseCss = ''
    /* Tokyo Night (see waybar/palette.css) */
    @define-color window_bg_color rgba(22, 22, 30, 0.90);
    @define-color panel_bg_color rgba(36, 40, 59, 0.85);
    @define-color accent_bg_color rgba(122, 162, 247, 0.14);
    @define-color accent_line_color rgba(122, 162, 247, 0.24);
    @define-color theme_fg_color #c0caf5;
    @define-color subtext_color rgba(169, 177, 214, 0.65);
    @define-color border_color rgba(255, 255, 255, 0.07);
    /* Popup frame left the sunset attention tier (2026-07-24): walker is
       user-invoked chrome, not an alert, so it wears the same neutral
       slate as the active window border — orange only means "needs you" */
    @define-color walker_outer_border rgba(86, 95, 137, 1.0);

    * {
      all: unset;
      /* Same family as the terminal. Note: Caskaydia's capitals
         (A/M/N/V/W) have flat-cut apexes by design - they can look
         "cropped" but nothing is being clipped */
      font-family: "CaskaydiaMono Nerd Font Mono";
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
      /* regular weight at the input's size: semibold makes Caskaydia's
         flat-topped capitals read as cropped at list sizes */
      font-size: 15px;
      font-weight: 400;
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

  # A yes/no confirmation on top of the shared chrome. The stock layout is a
  # 600x570 search board, which is absurd for two answers, so this theme
  # brings its own geometry: the window hugs its content.
  #
  # Pair with --nohints and --nosearch on the caller. --nosearch is a safety
  # property, not a cosmetic one: the entry is walker's only always-visible
  # text slot, so it was carrying the question - but it also stays live and
  # filtering. With a hidden caret, one stray keystroke narrowed the list to a
  # single answer and Return then fired it, which for "l" is the logout. The
  # answers are labelled; the question is not worth that.
  confirmCss = ''
    .box-wrapper {
      padding: 14px;
      border-radius: 16px;
      /* Nearly opaque, unlike the launcher's 0.90. A launcher can afford to
         show the desktop through it; a destructive confirmation cannot - at
         0.90 a busy window behind the dialog reads straight through the
         resting card and the question stops being legible. */
      background: rgba(22, 22, 30, 0.97);
    }

    /* The answers are two cards side by side, icon over label. This
       deliberately departs from the Super+S board, where only the selected
       tile wears a card: with twelve tiles the question is "where do I
       look", and eleven bare icons keep it calm. With two answers the
       question is "which one is armed", and a second button with no resting
       surface reads as missing rather than calm. */
    .item-box.menus-logout {
      margin: 5px;
      padding: 16px 12px 14px 12px;
      border-radius: 14px;
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid rgba(255, 255, 255, 0.09);
      transition:
        background 140ms ease,
        border-color 140ms ease;
    }

    child:hover .item-box.menus-logout {
      background: rgba(122, 162, 247, 0.09);
      border-color: rgba(122, 162, 247, 0.18);
    }

    child:selected .item-box.menus-logout {
      background: @accent_bg_color;
      border-color: @accent_line_color;
    }

    /* The icons are the -symbolic names, which GTK recolours to `color`, so
       icon and label carry the armed state together: muted at rest, full
       foreground when selected. Do NOT use the plain names here - Papirus
       ships actions/system-log-out.svg only up to 24px, so at a card-sized
       request GTK falls through to the 32px apps/ variant, which is a
       full-colour green glyph: the success role, on the destructive answer. */
    .menus-logout .item-image {
      -gtk-icon-size: 30px;
      /* the shared .item-image rule adds a right margin for list rows, which
         would knock the icon off-centre in a card */
      margin-right: 0;
      margin-bottom: 10px;
      color: @subtext_color;
      transition: color 140ms ease;
    }

    .menus-logout .item-text {
      color: @subtext_color;
      transition: color 140ms ease;
    }

    child:hover .item-box.menus-logout .item-image,
    child:selected .item-box.menus-logout .item-image,
    child:hover .item-box.menus-logout .item-text,
    child:selected .item-box.menus-logout .item-text {
      color: @theme_fg_color;
    }
  '';

  # Icon over label, both centred - the board's tile has no label at all, so
  # this cannot reuse it. A confirmation has to stay readable: two unlabelled
  # glyphs would make "which one was the destructive one" a guess.
  confirmItem = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <interface>
      <requires lib="gtk" version="4.0"></requires>
      <object class="GtkBox" id="ItemBox">
        <style>
          <class name="item-box"></class>
        </style>
        <property name="orientation">vertical</property>
        <property name="halign">fill</property>
        <property name="valign">fill</property>
        <child>
          <object class="GtkImage" id="ItemImage">
            <style>
              <class name="item-image"></class>
            </style>
            <property name="icon-size">large</property>
            <property name="halign">center</property>
            <property name="valign">center</property>
          </object>
        </child>
        <child>
          <object class="GtkLabel" id="ItemText">
            <style>
              <class name="item-text"></class>
            </style>
            <property name="halign">center</property>
            <property name="valign">center</property>
          </object>
        </child>
      </object>
    </interface>
  '';

  # walker's stock layout with the board geometry taken out: no height-request
  # so the window is exactly as tall as the prompt plus its answers, and a
  # width that fits a one-line question.
  confirmLayout = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <interface>
      <requires lib="gtk" version="4.0"></requires>
      <object class="GtkWindow" id="Window">
        <style>
          <class name="window"></class>
        </style>
        <property name="resizable">true</property>
        <property name="title">Walker</property>
        <child>
          <object class="GtkBox" id="BoxWrapper">
            <style>
              <class name="box-wrapper"></class>
            </style>
            <property name="overflow">hidden</property>
            <property name="orientation">horizontal</property>
            <property name="valign">center</property>
            <property name="halign">center</property>
            <property name="width-request">400</property>
            <child>
              <object class="GtkBox" id="Box">
                <style>
                  <class name="box"></class>
                </style>
                <property name="orientation">vertical</property>
                <property name="hexpand-set">true</property>
                <property name="hexpand">true</property>
                <property name="spacing">6</property>
                <child>
                  <!-- Hidden at runtime by --nosearch, but it must still be
                       here: walker fires the initial query from this entry's
                       "changed" signal, so a layout without it shows an empty
                       picker forever. -->
                  <object class="GtkBox" id="SearchContainer">
                    <style>
                      <class name="search-container"></class>
                    </style>
                    <property name="overflow">hidden</property>
                    <property name="orientation">horizontal</property>
                    <property name="halign">fill</property>
                    <property name="hexpand-set">true</property>
                    <property name="hexpand">true</property>
                    <child>
                      <object class="GtkEntry" id="Input">
                        <style>
                          <class name="input"></class>
                        </style>
                        <property name="halign">fill</property>
                        <property name="hexpand-set">true</property>
                        <property name="hexpand">true</property>
                      </object>
                    </child>
                  </object>
                </child>
                <child>
                  <object class="GtkBox" id="ContentContainer">
                    <style>
                      <class name="content-container"></class>
                    </style>
                    <property name="orientation">horizontal</property>
                    <property name="spacing">10</property>
                    <child>
                      <object class="GtkLabel" id="ElephantHint">
                        <style>
                          <class name="elephant-hint"></class>
                        </style>
                        <property name="label">Waiting for elephant...</property>
                        <property name="hexpand">true</property>
                        <property name="vexpand">true</property>
                        <property name="visible">false</property>
                        <property name="valign">0.5</property>
                      </object>
                    </child>
                    <child>
                      <object class="GtkLabel" id="Placeholder">
                        <style>
                          <class name="placeholder"></class>
                        </style>
                        <property name="label">No Results</property>
                        <property name="hexpand">true</property>
                        <property name="vexpand">true</property>
                        <property name="valign">0.5</property>
                      </object>
                    </child>
                    <child>
                      <object class="GtkScrolledWindow" id="Scroll">
                        <style>
                          <class name="scroll"></class>
                        </style>
                        <property name="can_focus">false</property>
                        <property name="overlay-scrolling">true</property>
                        <property name="hexpand">true</property>
                        <property name="vexpand">true</property>
                        <!-- 400px window - 14px padding - 2px border either
                             side, so the cards sit inside the frame evenly -->
                        <property name="max-content-width">368</property>
                        <property name="min-content-width">368</property>
                        <property name="max-content-height">180</property>
                        <property name="propagate-natural-height">true</property>
                        <property name="propagate-natural-width">true</property>
                        <property name="hscrollbar-policy">never</property>
                        <property name="vscrollbar-policy">automatic</property>
                        <child>
                          <!-- two answers, two columns. This must agree with
                               the `columns` entry in the walker config, which
                               is applied at runtime and overrides it. -->
                          <object class="GtkGridView" id="List">
                            <style>
                              <class name="list"></class>
                            </style>
                            <property name="max_columns">2</property>
                            <property name="min_columns">2</property>
                            <property name="can_focus">false</property>
                          </object>
                        </child>
                      </object>
                    </child>
                    <child>
                      <object class="GtkBox" id="Preview">
                        <style>
                          <class name="preview"></class>
                        </style>
                        <property name="visible">false</property>
                      </object>
                    </child>
                  </object>
                </child>
                <child>
                  <!-- kept only because the renderer requires these ids; the
                       hint bar itself is hidden by the nohints flag on the
                       caller, since walker re-shows it on selection changes -->
                  <object class="GtkBox" id="Keybinds">
                    <style>
                      <class name="keybinds"></class>
                    </style>
                    <property name="hexpand">true</property>
                    <child>
                      <object class="GtkBox" id="GlobalKeybinds">
                        <style>
                          <class name="global-keybinds"></class>
                        </style>
                        <property name="spacing">10</property>
                      </object>
                    </child>
                    <child>
                      <object class="GtkBox" id="ItemKeybinds">
                        <style>
                          <class name="item-keybinds"></class>
                        </style>
                        <property name="hexpand">true</property>
                        <property name="halign">end</property>
                        <property name="spacing">10</property>
                      </object>
                    </child>
                  </object>
                </child>
                <child>
                  <object class="GtkLabel" id="Error">
                    <style>
                      <class name="error"></class>
                    </style>
                    <property name="xalign">0</property>
                    <property name="visible">false</property>
                  </object>
                </child>
              </object>
            </child>
          </object>
        </child>
      </object>
    </interface>
  '';

  # The Super+S board on top of the shared chrome: 12 icon tiles, 4 x 3.
  # Bare icons on the window background - only the selected tile wears a card,
  # so the eye lands on it instead of on twelve competing panels. layout.xml
  # below sizes the window to exactly this board.
  gridCss = ''
    .item-box.menus-scratchpads {
      /* 100px tile + 6px margin either side = the 112px grid cell, so the
         tiles are square and the gutter is even in both directions */
      margin: 6px;
      padding: 18px;
      border-radius: 16px;
      /* transparent rather than absent: the border still takes its 1px, so
         nothing shifts by a pixel when the selection lands on a tile */
      background: transparent;
      border: 1px solid transparent;
      transition:
        background 140ms ease,
        border-color 140ms ease;
    }

    child:hover .item-box.menus-scratchpads {
      background: rgba(122, 162, 247, 0.07);
      border-color: rgba(122, 162, 247, 0.12);
    }

    child:selected .item-box.menus-scratchpads {
      background: @accent_bg_color;
      border-color: @accent_line_color;
    }

    .menus-scratchpads .item-image {
      -gtk-icon-size: 64px;
      /* the shared .item-image rule adds a right margin for list rows, which
         would knock the icon off-centre in a tile */
      margin-right: 0;
      /* unselected icons sit back a little; with no card behind them this is
         what carries the selection, together with the ring */
      opacity: 0.7;
      transition: opacity 140ms ease;
    }

    child:hover .item-box.menus-scratchpads .item-image,
    child:selected .item-box.menus-scratchpads .item-image {
      opacity: 1;
    }
  '';
  gridItem = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <interface>
      <requires lib="gtk" version="4.0"></requires>
      <object class="GtkBox" id="ItemBox">
        <style>
          <class name="item-box"></class>
        </style>
        <property name="orientation">vertical</property>
        <property name="halign">fill</property>
        <property name="valign">fill</property>
        <child>
          <object class="GtkImage" id="ItemImage">
            <style>
              <class name="item-image"></class>
            </style>
            <property name="icon-size">large</property>
            <property name="halign">center</property>
            <property name="valign">center</property>
            <property name="vexpand">true</property>
          </object>
        </child>
      </object>
    </interface>
  '';

  gridLayout = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <interface>
      <requires lib="gtk" version="4.0"></requires>
      <object class="GtkWindow" id="Window">
        <style>
          <class name="window"></class>
        </style>
        <property name="resizable">true</property>
        <property name="title">Walker</property>
        <child>
          <object class="GtkBox" id="BoxWrapper">
            <style>
              <class name="box-wrapper"></class>
            </style>
            <property name="overflow">hidden</property>
            <property name="orientation">horizontal</property>
            <property name="valign">center</property>
            <property name="halign">center</property>
            <!-- 448px of grid + the 16px wrapper padding either side. No
                 height-request, so the window is exactly as tall as the board
                 instead of the shared layout's fixed 570px. -->
            <property name="width-request">480</property>
            <child>
              <object class="GtkBox" id="Box">
                <style>
                  <class name="box"></class>
                </style>
                <property name="orientation">vertical</property>
                <property name="hexpand-set">true</property>
                <property name="hexpand">true</property>
                <property name="spacing">10</property>
                <child>
                  <object class="GtkBox" id="SearchContainer">
                    <style>
                      <class name="search-container"></class>
                    </style>
                    <property name="overflow">hidden</property>
                    <property name="orientation">horizontal</property>
                    <property name="halign">fill</property>
                    <property name="hexpand-set">true</property>
                    <property name="hexpand">true</property>
                    <child>
                      <object class="GtkEntry" id="Input">
                        <style>
                          <class name="input"></class>
                        </style>
                        <property name="halign">fill</property>
                        <property name="hexpand-set">true</property>
                        <property name="hexpand">true</property>
                      </object>
                    </child>
                  </object>
                </child>
                <child>
                  <object class="GtkBox" id="ContentContainer">
                    <style>
                      <class name="content-container"></class>
                    </style>
                    <property name="orientation">horizontal</property>
                    <property name="spacing">10</property>
                    <child>
                      <object class="GtkLabel" id="ElephantHint">
                        <style>
                          <class name="elephant-hint"></class>
                        </style>
                        <property name="label">Waiting for elephant...</property>
                        <property name="hexpand">true</property>
                        <property name="vexpand">true</property>
                        <property name="visible">false</property>
                        <property name="valign">0.5</property>
                      </object>
                    </child>
                    <child>
                      <object class="GtkLabel" id="Placeholder">
                        <style>
                          <class name="placeholder"></class>
                        </style>
                        <property name="label">No Results</property>
                        <property name="hexpand">true</property>
                        <property name="vexpand">true</property>
                        <property name="valign">0.5</property>
                      </object>
                    </child>
                    <child>
                      <object class="GtkScrolledWindow" id="Scroll">
                        <style>
                          <class name="scroll"></class>
                        </style>
                        <property name="can_focus">false</property>
                        <property name="overlay-scrolling">true</property>
                        <property name="hexpand">true</property>
                        <property name="vexpand">true</property>
                        <property name="max-content-width">448</property>
                        <property name="min-content-width">448</property>
                        <property name="max-content-height">400</property>
                        <property name="propagate-natural-height">true</property>
                        <property name="propagate-natural-width">true</property>
                        <property name="hscrollbar-policy">never</property>
                        <property name="vscrollbar-policy">automatic</property>
                        <child>
                          <object class="GtkGridView" id="List">
                            <style>
                              <class name="list"></class>
                            </style>
                            <property name="max_columns">4</property>
                            <property name="min_columns">4</property>
                            <property name="can_focus">false</property>
                          </object>
                        </child>
                      </object>
                    </child>
                    <child>
                      <object class="GtkBox" id="Preview">
                        <style>
                          <class name="preview"></class>
                        </style>
                        <property name="visible">false</property>
                      </object>
                    </child>
                  </object>
                </child>
                <child>
                  <!-- kept only because the renderer requires these ids; the
                       hint bar itself is hidden by the nohints flag on the
                       bind, since walker re-shows it on selection changes -->
                  <object class="GtkBox" id="Keybinds">
                    <style>
                      <class name="keybinds"></class>
                    </style>
                    <property name="hexpand">true</property>
                    <child>
                      <object class="GtkBox" id="GlobalKeybinds">
                        <style>
                          <class name="global-keybinds"></class>
                        </style>
                        <property name="spacing">10</property>
                      </object>
                    </child>
                    <child>
                      <object class="GtkBox" id="ItemKeybinds">
                        <style>
                          <class name="item-keybinds"></class>
                        </style>
                        <property name="hexpand">true</property>
                        <property name="halign">end</property>
                        <property name="spacing">10</property>
                      </object>
                    </child>
                  </object>
                </child>
                <child>
                  <object class="GtkLabel" id="Error">
                    <style>
                      <class name="error"></class>
                    </style>
                    <property name="xalign">0</property>
                    <property name="visible">false</property>
                  </object>
                </child>
              </object>
            </child>
          </object>
        </child>
      </object>
    </interface>
  '';
in
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
      "menus"
    ];
  };

  programs.walker = {
    enable = true;
    runAsService = true;

    # Patched build. Two independent upstream bugs, kept as separate patches so
    # either can be dropped on its own once upstream fixes it.
    #
    # walker-grid-key: upstream cannot theme a grid tile at all. It only ever
    # looks for item_<provider>.xml in a theme dir, never the _grid variant, and
    # the key it derives from a grid filename keeps the "_grid" suffix
    # ("menus:scratchpads_grid"), which nothing looks up. Both together mean a
    # custom grid layout is silently ignored and walker falls back to its
    # built-in icon+text tile. Without this the board renders as a labelled list.
    #
    # walker-window-per-theme: walker builds one window per theme, but tracks
    # visibility in a single global flag and resolves the current window by the
    # *requested* theme. Opening one picker while another is on screen closed
    # the wrong (never-visible) window, orphaning the open one — which then got
    # restyled, because the GTK CSS provider is global to the display. Without
    # this, Super+S over Super+Space (or the reverse) leaves a stray window
    # wearing the other picker's stylesheet until you press a bind twice.
    package = inputs.walker.packages.${pkgs.stdenv.system}.default.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./walker-grid-key.patch
        ./walker-window-per-theme.patch
      ];
    });

    config = {
      theme = "dani-soft";

      close_when_open = true;
      force_keyboard_focus = true;

      # Which providers render as an N-column grid instead of a list. This
      # REPLACES walker's default map, so symbols (emoji picker) is repeated
      # here to keep its 3-column grid; menus:scratchpads is the Super+S
      # icon-tile picker. Grid item layouts: the built-in default for
      # symbols, dani-grid's item_menus-scratchpads_grid.xml for the board.
      columns = {
        "symbols" = 3;
        # 4 x 3 for the 12 tiles, matching dani-grid's layout.xml. Note this is
        # applied at runtime and overrides the GridView columns set in the XML,
        # so the two must agree or the window width stops matching the grid.
        "menus:scratchpads" = 4;
        # the logout confirm: Cancel and Log out as two cards, not two rows
        "menus:logout" = 2;
      };

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

    # Written as walker themes rather than raw xdg.configFile entries on
    # purpose: the module folds `themes` into the unit's X-Restart-Triggers, so
    # editing a theme restarts walker on switch. walker scans themes once at
    # startup, so without that a theme edit stays invisible until the next
    # reboot — and an unknown --theme silently falls back to the built-in
    # default theme (a labelled list), which is exactly what that looks like.
    themes = {
      # the search pickers: shared chrome, walker's stock layout
      dani-soft.style = baseCss;

      # yes/no prompts (currently just the logout confirm): same chrome, own
      # window geometry so a two-item question isn't a 600x570 board
      dani-confirm = {
        style = baseCss + confirmCss;
        layouts = {
          "layout" = confirmLayout;
          "item_menus-logout_grid" = confirmItem;
        };
      };

      # the Super+S board: same chrome, plus its own window geometry
      dani-grid = {
        style = baseCss + gridCss;
        layouts = {
          "layout" = gridLayout;
          "item_menus-scratchpads_grid" = gridItem;
        };
      };
    };
  };
}
