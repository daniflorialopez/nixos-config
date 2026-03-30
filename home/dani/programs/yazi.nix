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
        { url = "*.pdf"; use = [ "pdf" "open" ]; }
        { url = "*.csv"; use = [ "edit" "spreadsheet" "open" ]; }
        { url = "*.toml"; use = "edit"; }
        { url = "*.yaml"; use = "edit"; }
        { url = "*.yml"; use = "edit"; }
        { url = "*.json"; use = "edit"; }
        { url = "*.nix"; use = "edit"; }

        # MIME-based rules
        { mime = "application/pdf"; use = [ "pdf" "open" ]; }
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
