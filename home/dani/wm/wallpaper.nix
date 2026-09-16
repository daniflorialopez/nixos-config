{ config, pkgs, lib, inputs, ... }:
let
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # The wallpaper library is a real, writable directory — deliberately not a
  # `home.file` symlink into the store. As a store link it was read-only, and
  # once .gitignore started excluding home/dani/assets/wallpapers it silently
  # lost every image that was not git-tracked, because a flake only copies
  # tracked files into the store. Now: Nix seeds the shipped defaults once, you
  # drop new wallpapers straight into this directory, and no rebuild is
  # involved — elephant notices the change and refreshes the picker.
  wallpaperDir = "${config.home.homeDirectory}/Pictures/Wallpapers";
  shippedWallpapers = ../assets/wallpapers;

  thumbDir = "${config.home.homeDirectory}/.cache/wallpaper-thumbs";

  defaultWallpaper = "${wallpaperDir}/default.png";

  selectedConf = "${config.home.homeDirectory}/.local/state/hypr/hyprpaper-selected.conf";
  stateFile = "${config.home.homeDirectory}/.local/state/wallpaper/current";
  logFile = "${config.home.homeDirectory}/.local/state/wallpaper/debug.log";

  # 16:9, and exactly the on-screen tile size — these must match the
  # width/height-request on the GtkPicture in walker.nix's dani-wall item
  # layout. A GtkPicture reports its texture's width as its natural width and a
  # GridView sizes cells to that, so a 2x thumbnail here silently doubles every
  # cell and the board ends up wider than the screen. Generating at 1:1 is also
  # the sharpest option on a scale-1.0 output, which is what both monitors are.
  #
  # Every tile is the same shape regardless of the source aspect ratio, and
  # walker never has to decode ~35 MB of JPEG to draw twenty tiles.
  thumbWidth = 288;
  thumbHeight = 162;

  wallThumbs = pkgs.writeShellApplication {
    name = "wall-thumbs";
    runtimeInputs = [ pkgs.coreutils pkgs.findutils pkgs.imagemagick ];
    text = ''
      set -eu

      lib="${wallpaperDir}"
      cache="${thumbDir}"

      [ -d "$lib" ] || exit 0
      mkdir -p "$cache"

      # NUL-delimited so filenames with spaces survive the round trip.
      mapfile -d "" -t sources < <(
        find "$lib" -maxdepth 1 -type f \
          \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
             -o -iname '*.webp' -o -iname '*.bmp' \) -print0 | sort -z
      )

      keep=()

      for src in "''${sources[@]}"; do
        key=$(printf '%s' "$src" | md5sum | cut -d' ' -f1)
        thumb="$cache/$key.jpg"
        keep+=("$key.jpg")

        # -nt covers "edited in place" as well as "never built yet"
        if [ ! -f "$thumb" ] || [ "$src" -nt "$thumb" ]; then
          # [0] takes the first frame, so an animated source yields one tile.
          # Braced because bare "$src[0]" reads as an array subscript (SC1087).
          # -thumbnail strips metadata; ^ then -extent is the cover crop.
          if ! magick "''${src}[0]" -auto-orient \
                 -thumbnail "${toString thumbWidth}x${toString thumbHeight}^" \
                 -gravity center -extent "${toString thumbWidth}x${toString thumbHeight}" \
                 -quality 88 "$thumb" 2> /dev/null; then
            continue
          fi
        fi

        name=$(basename "$src")
        printf '%s\t%s\t%s\n' "$thumb" "$src" "''${name%.*}"
      done

      # Drop thumbnails for wallpapers that are no longer in the library, so
      # deleting an image actually removes it from the picker's cache too.
      for stale in "$cache"/*.jpg; do
        [ -e "$stale" ] || continue
        base=$(basename "$stale")
        found=0
        for k in ''${keep[@]+"''${keep[@]}"}; do
          if [ "$k" = "$base" ]; then
            found=1
            break
          fi
        done
        [ "$found" -eq 1 ] || rm -f "$stale"
      done
    '';
  };

  wallSet = pkgs.writeShellApplication {
    name = "wall-set";
    runtimeInputs = [ pkgs.coreutils pkgs.systemd ];
    text = ''
      set -eu

      img="''${1:-}"

      if [ -z "$img" ] || [ ! -f "$img" ]; then
        echo "usage: wall-set <image>" >&2
        exit 1
      fi

      mkdir -p "$(dirname "${selectedConf}")"
      mkdir -p "$(dirname "${stateFile}")"

      {
        echo "---- $(date --iso-8601=seconds) ----"
        echo "img=$img"
      } >> "${logFile}"

      printf '%s\n' "$img" > "${stateFile}"

      # Both outputs get the same image: this config has never set them
      # independently, and hyprpaper needs each monitor named explicitly.
      cat > "${selectedConf}" <<EOF
wallpaper {
  monitor = HDMI-A-1
  path = $img
  fit_mode = cover
}

wallpaper {
  monitor = eDP-1
  path = $img
  fit_mode = cover
}
EOF

      systemctl --user restart hyprpaper.service >> "${logFile}" 2>&1
    '';
  };

  # The picker is a walker theme driven by an elephant menu, not a standalone
  # app. waytrogen used to fill this slot and was dropped: its 1.0 release
  # swapped GTK4 for Iced, which cannot take our GTK stylesheet, cannot use
  # CaskaydiaMono, and gives a grid with no arrow-key navigation. All three come
  # free here, along with fuzzy search and the live preview pane.
  #
  # Lua rather than a TOML menu because the entry list is the contents of a
  # directory: a TOML menu is fixed at build time, so adding a wallpaper would
  # mean a rebuild. RefreshOnChange re-runs GetEntries when the directory
  # changes, so a new drop shows up in the picker within about half a second.
  wallpapersMenu = ''
    Name = "wallpapers"
    NamePretty = "Wallpapers"
    Icon = "preferences-desktop-wallpaper"
    Description = "Set the desktop wallpaper"
    SearchName = true

    -- Cache with a watch on the library: GetEntries shells out to ImageMagick
    -- for any thumbnail that is missing, which is not something to do
    -- synchronously on every keystroke.
    Cache = true
    RefreshOnChange = { "${wallpaperDir}" }

    Action = '${lib.getExe wallSet} "%VALUE%"'

    function GetEntries()
      local entries = {}

      local handle = io.popen("${lib.getExe wallThumbs} 2>/dev/null")
      if not handle then
        return entries
      end

      for line in handle:lines() do
        local thumb, source, name = line:match("^([^\t]+)\t([^\t]+)\t(.*)$")
        if thumb and source then
          table.insert(entries, {
            Text = name,
            Value = source,
            -- absolute path => walker loads it as a GdkTexture into the
            -- GtkPicture in item_menus-wallpapers_grid.xml
            Icon = thumb,
            -- No Preview/PreviewType on purpose: walker only fills its preview
            -- pane on a selection *change*, so it came up empty on open, and an
            -- empty Preview box is transparent — a 400px hole in the card with
            -- the desktop showing through. The tiles are the preview here.
          })
        end
      end

      handle:close()

      return entries
    end
  '';
in
{
  # Replaces the old `home.file."Pictures/Wallpapers"`. Ordered after
  # linkGeneration, not merely after writeBoundary: linkGeneration is itself
  # only `after writeBoundary`, so as a sibling this could just as well have run
  # first, turned the link into a directory, and left linkGeneration trying to
  # rm -f the old symlink it no longer recognises.
  home.activation.wallpaperLibrary = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    set -eu

    LIB="${wallpaperDir}"

    # First run after the switch: drop the store symlink earlier generations
    # left behind so a real directory can take its place.
    if [ -L "$LIB" ]; then
      rm -f "$LIB"
    fi
    mkdir -p "$LIB"

    # Seed the wallpapers this repo ships, never overwriting what is already
    # there — after the first pass the directory is yours, not Nix's. Store
    # files are 0444, so copy them in writable.
    for src in ${shippedWallpapers}/*; do
      [ -f "$src" ] || continue
      dest="$LIB/$(basename "$src")"
      if [ ! -e "$dest" ]; then
        install -m 0644 "$src" "$dest"
      fi
    done
  '';

  # elephant scans ~/.config/elephant/menus/ exactly once, at startup, so this
  # menu only takes effect if elephant restarts *after* home-manager has linked
  # it. X-Restart-Triggers on the unit does not buy that ordering, and this is
  # not theoretical — on the switch that introduced this file (2026-09-15) the
  # trigger fired at 22:18:09 while linkGeneration wrote the menu at 22:19:03.
  # elephant rescanned a directory that did not contain it yet, and because that
  # early pass had already consumed the unit-file diff, home-manager's own
  # reloadSystemd 54s later restarted walker and left elephant alone. The picker
  # came up empty — `providers p=menus:wallpapers results=0` in the journal is
  # the giveaway — until elephant was restarted by hand.
  #
  # onChange keys off this file's *content* rather than the unit, and runs in
  # the onFilesChange activation step, which is ordered after linkGeneration:
  # the file is therefore always on disk before elephant rereads it.
  # try-restart rather than restart, so a rebuild from a TTY with no graphical
  # session leaves elephant stopped instead of failing to start it.
  #
  # (scratchpads.toml and logout.toml carry the same latent race; they get away
  # with it only because they almost never change.)
  xdg.configFile."elephant/menus/wallpapers.lua" = {
    text = wallpapersMenu;
    onChange = "${pkgs.systemd}/bin/systemctl --user try-restart elephant.service";
  };

  # Puts "Wallpapers" straight in the sidebar of every GTK file chooser, so
  # saving an image into the library from a browser is one click.
  xdg.configFile."gtk-3.0/bookmarks".text = ''
    file://${wallpaperDir} Wallpapers
  '';

  xdg.configFile."hypr/hyprpaper.conf".text = ''
    source = ${selectedConf}

    ipc = true
    splash = false
  '';

  systemd.user.services.hyprpaper = {
    Unit = {
      Description = "hyprpaper";
      ConditionEnvironment = "WAYLAND_DISPLAY";
      After = [ config.wayland.systemd.target ];
      PartOf = [ config.wayland.systemd.target ];
      X-Restart-Triggers = [
        "${config.xdg.configFile."hypr/hyprpaper.conf".source}"
      ];
    };

    Install.WantedBy = [ config.wayland.systemd.target ];

    Service = {
      ExecStartPre = pkgs.writeShellScript "hyprpaper-init-selected" ''
    set -eu
    mkdir -p "$(dirname "${selectedConf}")"
    if [ ! -f "${selectedConf}" ]; then
      cat > "${selectedConf}" <<EOF
wallpaper {
  monitor = HDMI-A-1
  path = ${defaultWallpaper}
  fit_mode = cover
}

wallpaper {
  monitor = eDP-1
  path = ${defaultWallpaper}
  fit_mode = cover
}
EOF
    fi
  '';
      ExecStart = "${lib.getExe unstablePkgs.hyprpaper}";
      Restart = "always";
      RestartSec = "10";
    };
  };

  home.packages = [
    unstablePkgs.hyprpaper
    wallSet
    wallThumbs
  ];

  wayland.windowManager.hyprland.settings.bindd = [
    # --nohints drops the keybind hint bar, --nosearch the search entry: on a
    # contact sheet you point at the picture you want, and a text field above a
    # wall of images was just a bar of dead chrome. Both have to be flags rather
    # than layout properties — walker re-shows the hint bar on every selection
    # change, and the entry has to stay in layout.xml (see dani-wall). Neither
    # leaks the way --theme does: walker sets them per invocation and restores
    # the entry on close, so Super+Space is unaffected.
    "$mod CTRL, W, Wallpaper picker, exec, walker -m menus:wallpapers --theme dani-wall --nohints --nosearch"
  ];
}
