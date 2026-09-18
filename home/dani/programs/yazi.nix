{ config, pkgs, theme, ... }:

let
  zathuraPkg = pkgs.zathura.override {
    plugins = with pkgs.zathuraPkgs; [
      zathura_pdf_mupdf
    ];
  };
in
{
  programs.yazi = {
    enable = true;

    # stateVersion-gated in 26.05 ("yy" legacy, "y" current). Pinned to the
    # value already in effect. Cosmetic — nothing in this repo calls the
    # wrapper; yazi is invoked by name from the scratchpad and from cli.nix.
    shellWrapperName = "yy";

    # Tokyo Night accents (see home/dani/wm/theme.nix for the palette)
    theme = {
      mgr = {
        cwd = { fg = theme.hex.attention; bold = true; };
        hovered = { fg = theme.hex.bg; bg = theme.hex.accent; bold = true; };
        preview_hovered = { fg = theme.hex.bg; bg = theme.hex.slate; };
        find_keyword = { fg = theme.hex.warning; bold = true; };
        find_position = { fg = theme.hex.attention; };
        marker_selected = { fg = theme.hex.success; bg = theme.hex.success; };
        marker_copied = { fg = theme.hex.warning; bg = theme.hex.warning; };
        marker_cut = { fg = theme.hex.critical; bg = theme.hex.critical; };
        tab_active = { fg = theme.hex.bg; bg = theme.hex.accent; };
        tab_inactive = { fg = theme.hex.fg; bg = theme.hex.surface; };
        border_style = { fg = theme.hex.slate; };
      };

      status = {
        mode_normal = { fg = theme.hex.bg; bg = theme.hex.accent; bold = true; };
        mode_select = { fg = theme.hex.bg; bg = theme.hex.success; bold = true; };
        mode_unset = { fg = theme.hex.bg; bg = theme.hex.attention; bold = true; };
        progress_label = { fg = theme.hex.fg; bold = true; };
        progress_normal = { fg = theme.hex.accent; bg = theme.hex.bg; };
        progress_error = { fg = theme.hex.critical; bg = theme.hex.bg; };
      };
    };

    settings = {
      opener = {
        edit = [
          {
            run = "${config.programs.neovim.finalPackage}/bin/nvim \"$@\"";
            block = true;
            desc = "Neovim";
            for = "linux";
          }
        ];

        open = [
          {
            run = "${pkgs.xdg-utils}/bin/xdg-open \"$1\"";
            orphan = true;
            desc = "Open";
            for = "linux";
          }
        ];

        reveal = [
          {
            run = "${pkgs.pcmanfm}/bin/pcmanfm \"$(dirname \"$1\")\"";
            orphan = true;
            desc = "Reveal in PCManFM";
            for = "linux";
          }
        ];

        pdf = [
          {
            run = "${zathuraPkg}/bin/zathura \"$1\"";
            orphan = true;
            desc = "Zathura";
            for = "linux";
          }
        ];

        pdf_okular = [
          {
            run = "${pkgs.kdePackages.okular}/bin/okular \"$1\"";
            orphan = true;
            desc = "Okular";
            for = "linux";
          }
        ];

        image = [
          {
            run = "${pkgs.imv}/bin/imv \"$1\"";
            orphan = true;
            desc = "imv";
            for = "linux";
          }
        ];

        play = [
          {
            run = "${pkgs.mpv}/bin/mpv \"$1\"";
            orphan = true;
            desc = "mpv";
            for = "linux";
          }
        ];

        spreadsheet = [
          {
            run = "${pkgs.libreoffice}/bin/libreoffice --calc \"$1\"";
            orphan = true;
            desc = "LibreOffice Calc";
            for = "linux";
          }
        ];

        archive = [
          {
            run = "${pkgs.file-roller}/bin/file-roller \"$1\"";
            orphan = true;
            desc = "File Roller";
            for = "linux";
          }
        ];
      };

      open.prepend_rules = [
        # Strong explicit matches first
        { url = "*.pdf"; use = [ "pdf" "pdf_okular" "open" ]; }
        { url = "*.csv"; use = [ "edit" "spreadsheet" "open" ]; }
        { url = "*.toml"; use = "edit"; }
        { url = "*.yaml"; use = "edit"; }
        { url = "*.yml"; use = "edit"; }
        { url = "*.json"; use = "edit"; }
        { url = "*.nix"; use = "edit"; }

        # MIME-based rules
        { mime = "application/pdf"; use = [ "pdf" "pdf_okular" "open" ]; }
        { mime = "text/*"; use = "edit"; }
        { mime = "application/json"; use = "edit"; }
        { mime = "application/*+json"; use = "edit"; }
        { mime = "application/xml"; use = "edit"; }

        { mime = "image/*"; use = [ "image" "open" ]; }
        { mime = "video/*"; use = [ "play" "open" ]; }
        { mime = "audio/*"; use = [ "play" "open" ]; }

        { mime = "application/vnd.ms-excel"; use = [ "spreadsheet" "open" ]; }
        { mime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"; use = [ "spreadsheet" "open" ]; }
        { mime = "application/vnd.oasis.opendocument.spreadsheet"; use = [ "spreadsheet" "open" ]; }

        { mime = "application/zip"; use = [ "archive" "open" ]; }
        { mime = "application/x-7z-compressed"; use = [ "archive" "open" ]; }
        { mime = "application/vnd.rar"; use = [ "archive" "open" ]; }
        { mime = "application/x-rar"; use = [ "archive" "open" ]; }
        { mime = "application/x-tar"; use = [ "archive" "open" ]; }
        { mime = "application/gzip"; use = [ "archive" "open" ]; }
        { mime = "application/x-gzip"; use = [ "archive" "open" ]; }
        { mime = "application/x-bzip2"; use = [ "archive" "open" ]; }
        { mime = "application/x-xz"; use = [ "archive" "open" ]; }
      ];
    };
  };
}
