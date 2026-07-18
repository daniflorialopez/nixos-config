{ pkgs, ... }:

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

    # Tokyo Night accents (see home/dani/wm/theme.nix for the palette)
    theme = {
      mgr = {
        cwd = { fg = "#ff9e64"; bold = true; };
        hovered = { fg = "#1a1b26"; bg = "#7aa2f7"; bold = true; };
        preview_hovered = { fg = "#1a1b26"; bg = "#565f89"; };
        find_keyword = { fg = "#e0af68"; bold = true; };
        find_position = { fg = "#ff9e64"; };
        marker_selected = { fg = "#9ece6a"; bg = "#9ece6a"; };
        marker_copied = { fg = "#e0af68"; bg = "#e0af68"; };
        marker_cut = { fg = "#f7768e"; bg = "#f7768e"; };
        tab_active = { fg = "#1a1b26"; bg = "#7aa2f7"; };
        tab_inactive = { fg = "#c0caf5"; bg = "#24283b"; };
        border_style = { fg = "#565f89"; };
      };

      status = {
        mode_normal = { fg = "#1a1b26"; bg = "#7aa2f7"; bold = true; };
        mode_select = { fg = "#1a1b26"; bg = "#9ece6a"; bold = true; };
        mode_unset = { fg = "#1a1b26"; bg = "#ff9e64"; bold = true; };
        progress_label = { fg = "#c0caf5"; bold = true; };
        progress_normal = { fg = "#7aa2f7"; bg = "#1a1b26"; };
        progress_error = { fg = "#f7768e"; bg = "#1a1b26"; };
      };
    };

    settings = {
      opener = {
        edit = [
          {
            run = "${pkgs.neovim}/bin/nvim \"$@\"";
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
