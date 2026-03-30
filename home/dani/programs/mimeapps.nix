{ pkgs, ... }:

let
  zathuraPkg = pkgs.zathura.override {
    plugins = with pkgs.zathuraPkgs; [
      zathura_pdf_mupdf
    ];
  };

  nvimDesktop = "nvim-terminal.desktop";
  firefoxDesktop = "firefox-handler.desktop";
  pcmanfmDesktop = "pcmanfm-handler.desktop";
  zathuraDesktop = "zathura-handler.desktop";
  okularDesktop = "okular-handler.desktop";
  imvDesktop = "imv-handler.desktop";
  mpvDesktop = "mpv-handler.desktop";
  calcDesktop = "libreoffice-calc-handler.desktop";
  writerDesktop = "libreoffice-writer-handler.desktop";
  impressDesktop = "libreoffice-impress-handler.desktop";
  archiveDesktop = "archive-handler.desktop";
in
{
  xdg.enable = true;

  xdg.desktopEntries = {
    nvim-terminal = {
      name = "Neovim (Terminal)";
      comment = "Open text-like files in Neovim inside Alacritty";
      exec = "${pkgs.alacritty}/bin/alacritty -e ${pkgs.neovim}/bin/nvim %F";
      terminal = false;
      type = "Application";
      categories = [ "Utility" "TextEditor" ];
      mimeType = [
        "text/plain"
        "text/markdown"
        "text/x-log"
        "text/xml"
        "application/xml"
        "application/json"
        "application/toml"
        "application/x-yaml"
        "text/x-shellscript"
        "application/x-shellscript"
        "text/x-python"
        "text/x-java-source"
        "text/javascript"
        "application/javascript"
        "text/x-lua"
        "text/x-nix"
      ];
      settings = {
        NoDisplay = "true";
      };
    };

    firefox-handler = {
      name = "Firefox Handler";
      exec = "${pkgs.firefox}/bin/firefox %U";
      terminal = false;
      type = "Application";
      categories = [ "Network" "WebBrowser" ];
      mimeType = [
        "text/html"
        "application/xhtml+xml"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "x-scheme-handler/mailto"
        "x-scheme-handler/webcal"
      ];
      settings = {
        NoDisplay = "true";
      };
    };

    pcmanfm-handler = {
      name = "PCManFM Handler";
      exec = "${pkgs.pcmanfm}/bin/pcmanfm %U";
      terminal = false;
      type = "Application";
      categories = [ "System" "FileManager" ];
      mimeType = [ "inode/directory" ];
      settings = {
        NoDisplay = "true";
      };
    };

    zathura-handler = {
      name = "Zathura Handler";
      exec = "${zathuraPkg}/bin/zathura %U";
      terminal = false;
      type = "Application";
      categories = [ "Office" "Viewer" ];
      mimeType = [ "application/pdf" ];
      settings = {
        NoDisplay = "true";
      };
    };

    okular-handler = {
      name = "Okular";
      exec = "${pkgs.kdePackages.okular}/bin/okular %U";
      terminal = false;
      type = "Application";
      categories = [ "Office" "Viewer" ];
      mimeType = [ "application/pdf" ];

      # Intentionally no NoDisplay=true, so it can show up in “Open With”.
    };

    imv-handler = {
      name = "imv Handler";
      exec = "${pkgs.imv}/bin/imv %U";
      terminal = false;
      type = "Application";
      categories = [ "Graphics" "Viewer" ];
      mimeType = [
        "image/png"
        "image/jpeg"
        "image/gif"
        "image/webp"
        "image/bmp"
        "image/tiff"
        "image/svg+xml"
        "image/avif"
        "image/heic"
        "image/heif"
      ];
      settings = {
        NoDisplay = "true";
      };
    };

    mpv-handler = {
      name = "mpv Handler";
      exec = "${pkgs.mpv}/bin/mpv %U";
      terminal = false;
      type = "Application";
      categories = [ "AudioVideo" "Player" ];
      mimeType = [
        "audio/mpeg"
        "audio/flac"
        "audio/wav"
        "audio/ogg"
        "audio/opus"
        "audio/mp4"
        "video/mp4"
        "video/webm"
        "video/x-matroska"
        "video/quicktime"
        "video/x-msvideo"
        "video/mpeg"
      ];
      settings = {
        NoDisplay = "true";
      };
    };

    libreoffice-calc-handler = {
      name = "LibreOffice Calc Handler";
      exec = "${pkgs.libreoffice}/bin/libreoffice --calc %U";
      terminal = false;
      type = "Application";
      categories = [ "Office" "Spreadsheet" ];
      mimeType = [
        "text/csv"
        "application/csv"
        "application/vnd.ms-excel"
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        "application/vnd.oasis.opendocument.spreadsheet"
      ];
      settings = {
        NoDisplay = "true";
      };
    };

    libreoffice-writer-handler = {
      name = "LibreOffice Writer Handler";
      exec = "${pkgs.libreoffice}/bin/libreoffice --writer %U";
      terminal = false;
      type = "Application";
      categories = [ "Office" "WordProcessor" ];
      mimeType = [
        "application/msword"
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        "application/vnd.oasis.opendocument.text"
        "application/rtf"
      ];
      settings = {
        NoDisplay = "true";
      };
    };

    libreoffice-impress-handler = {
      name = "LibreOffice Impress Handler";
      exec = "${pkgs.libreoffice}/bin/libreoffice --impress %U";
      terminal = false;
      type = "Application";
      categories = [ "Office" "Presentation" ];
      mimeType = [
        "application/vnd.ms-powerpoint"
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        "application/vnd.oasis.opendocument.presentation"
      ];
      settings = {
        NoDisplay = "true";
      };
    };

    archive-handler = {
      name = "Archive Handler";
      exec = "${pkgs.file-roller}/bin/file-roller %U";
      terminal = false;
      type = "Application";
      categories = [ "Utility" "Archiving" ];
      mimeType = [
        "application/zip"
        "application/x-7z-compressed"
        "application/vnd.rar"
        "application/x-rar"
        "application/x-tar"
        "application/gzip"
        "application/x-gzip"
        "application/x-bzip2"
        "application/x-xz"
        "application/x-iso9660-image"
      ];
      settings = {
        NoDisplay = "true";
      };
    };
  };

  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      "text/html" = [ firefoxDesktop ];
      "application/xhtml+xml" = [ firefoxDesktop ];
      "x-scheme-handler/http" = [ firefoxDesktop ];
      "x-scheme-handler/https" = [ firefoxDesktop ];
      "x-scheme-handler/mailto" = [ firefoxDesktop ];
      "x-scheme-handler/webcal" = [ firefoxDesktop ];

      "inode/directory" = [ pcmanfmDesktop ];

      "text/plain" = [ nvimDesktop ];
      "text/markdown" = [ nvimDesktop ];
      "text/x-log" = [ nvimDesktop ];
      "application/json" = [ nvimDesktop ];
      "application/toml" = [ nvimDesktop ];
      "application/x-yaml" = [ nvimDesktop ];
      "text/xml" = [ nvimDesktop ];
      "application/xml" = [ nvimDesktop ];
      "text/x-shellscript" = [ nvimDesktop ];
      "application/x-shellscript" = [ nvimDesktop ];
      "text/x-python" = [ nvimDesktop ];
      "text/x-java-source" = [ nvimDesktop ];
      "text/javascript" = [ nvimDesktop ];
      "application/javascript" = [ nvimDesktop ];
      "text/x-lua" = [ nvimDesktop ];
      "text/x-nix" = [ nvimDesktop ];

      "application/pdf" = [ zathuraDesktop ];

      "image/png" = [ imvDesktop ];
      "image/jpeg" = [ imvDesktop ];
      "image/gif" = [ imvDesktop ];
      "image/webp" = [ imvDesktop ];
      "image/bmp" = [ imvDesktop ];
      "image/tiff" = [ imvDesktop ];
      "image/svg+xml" = [ imvDesktop ];
      "image/avif" = [ imvDesktop ];
      "image/heic" = [ imvDesktop ];
      "image/heif" = [ imvDesktop ];

      "audio/mpeg" = [ mpvDesktop ];
      "audio/flac" = [ mpvDesktop ];
      "audio/wav" = [ mpvDesktop ];
      "audio/ogg" = [ mpvDesktop ];
      "audio/opus" = [ mpvDesktop ];
      "audio/mp4" = [ mpvDesktop ];
      "video/mp4" = [ mpvDesktop ];
      "video/webm" = [ mpvDesktop ];
      "video/x-matroska" = [ mpvDesktop ];
      "video/quicktime" = [ mpvDesktop ];
      "video/x-msvideo" = [ mpvDesktop ];
      "video/mpeg" = [ mpvDesktop ];

      "text/csv" = [ calcDesktop ];
      "application/csv" = [ calcDesktop ];
      "application/vnd.ms-excel" = [ calcDesktop ];
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = [ calcDesktop ];
      "application/vnd.oasis.opendocument.spreadsheet" = [ calcDesktop ];

      "application/msword" = [ writerDesktop ];
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = [ writerDesktop ];
      "application/vnd.oasis.opendocument.text" = [ writerDesktop ];
      "application/rtf" = [ writerDesktop ];

      "application/vnd.ms-powerpoint" = [ impressDesktop ];
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" = [ impressDesktop ];
      "application/vnd.oasis.opendocument.presentation" = [ impressDesktop ];

      "application/zip" = [ archiveDesktop ];
      "application/x-7z-compressed" = [ archiveDesktop ];
      "application/vnd.rar" = [ archiveDesktop ];
      "application/x-rar" = [ archiveDesktop ];
      "application/x-tar" = [ archiveDesktop ];
      "application/gzip" = [ archiveDesktop ];
      "application/x-gzip" = [ archiveDesktop ];
      "application/x-bzip2" = [ archiveDesktop ];
      "application/x-xz" = [ archiveDesktop ];
      "application/x-iso9660-image" = [ archiveDesktop ];
    };

    associations.added = {
      "application/pdf" = [ okularDesktop ];
    };

  };
}
