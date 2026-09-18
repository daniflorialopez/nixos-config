{ config, pkgs, inputs, lib, theme, ... }:

let
  unstablePkgs = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;

    # Claude Code is marked as unfree in nixpkgs.
    config.allowUnfree = true;
  };
in

{
  home.packages = with pkgs; [
    unstablePkgs.claude-code
    # Codex is free (Apache-2.0), but it ships releases far faster than the
    # stable channel tracks: 0.92.0 there vs 0.146.0 on unstable.
    unstablePkgs.codex

    obsidian
    virt-manager   # GUI; the backend is managed on NixOS side
    vscodium
    jetbrains.idea
    python3
  ];

  # Tokyo Night, same role mapping as zellij: blue for the active pane
  # frame, orange only for "look here" (search), #283457 selection wash
  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        nerdFontsVersion = "3";
        theme = {
          activeBorderColor = [ theme.hex.accent "bold" ];
          inactiveBorderColor = [ theme.hex.slate ];
          searchingActiveBorderColor = [ theme.hex.attention "bold" ];
          optionsTextColor = [ theme.hex.accent ];
          selectedLineBgColor = [ theme.hex.selection ];
          cherryPickedCommitFgColor = [ theme.hex.accent ];
          cherryPickedCommitBgColor = [ theme.hex.selection ];
          markedBaseCommitFgColor = [ theme.hex.accent ];
          markedBaseCommitBgColor = [ theme.hex.warning ];
          unstagedChangesColor = [ theme.hex.critical ];
          defaultFgColor = [ theme.hex.fg ];
        };
      };
    };
  };

  programs.git = {
    enable = true;
    settings.user.name = "Daniel Floria Lopez";
    settings.user.email = "daniflorialopez@gmail.com";

    lfs = {
      enable = true;
    };
  };

  # --- Neovim + practical runtime tools ---
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    # THIS LINE IS LOAD-BEARING. Do not remove it without reading this.
    #
    # ~/.config/nvim is NOT owned by Nix — it is seeded once from the
    # lazyvim-starter input by home.activation.lazyvimStarter below, and
    # ~/.config/nvim/init.lua is a real file containing `require("config.lazy")`.
    #
    # From Home Manager 26.05, programs.neovim writes xdg.configFile
    # "nvim/init.lua" whenever its auto-populated `initLua` is non-empty — and
    # it is ALWAYS non-empty now, because the provider lines
    # (loaded_node_provider / loaded_perl_provider / ruby_host_prog /
    # python3_host_prog) are seeded into it unconditionally. With
    # home-manager.backupFileExtension = "hm-backup", the first switch would
    # rename the LazyVim init.lua to init.lua.hm-backup and symlink a four-line
    # provider stub in its place. lazy.nvim would never bootstrap and nvim would
    # come up bare — with no error, no assertion and no failed activation.
    #
    # sideloadInitLua moves those provider lines into a wrapper flag
    # (--cmd 'lua dofile(...)') instead of a config file, which leaves
    # xdg.configFile."nvim/init.lua".enable = false and the seeded tree intact.
    # Verified by evaluation, not assumed.
    sideloadInitLua = true;

    # Pinned explicitly because 26.05 made both stateVersion-gated (legacy true,
    # current false). home.stateVersion is 25.05, so the values below are what
    # was already in effect — stating them keeps behaviour identical and stops
    # an eval warning on every rebuild. Flip to false if the nvim closure
    # matters more than the providers; nothing in this LazyVim setup uses them.
    withPython3 = true;
    withRuby = true;

    # Tools LazyVim commonly uses (search, file picking, etc.)
    extraPackages = with pkgs; [
      git
      ripgrep
      fd
      fzf
      curl
      unzip
      gzip
      
      #Treesitter requirements
      gnutar
      nodejs
      tree-sitter
      stdenv.cc # C compiler wrapper
      gnumake   # `make` often needed for builds

      # clipboard requirements
      wl-clipboard
      xclip
    ];
  };

  # Optional but nice: ensure these are set globally for CLI tools (git commit, etc.)
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  # --- Nix-managed LazyVim overrides (loaded by LazyVim) ---
  #
  # This file is generated declaratively by Home Manager.
  # LazyVim will load it via a one-time injected `pcall(require, "config.nix")`.
  xdg.configFile."nvim/lua/config/nix.lua" = {
    force = true;
    text = ''
      vim.opt.clipboard = "unnamedplus"
    '';
  };

  # --- Seed LazyVim starter into a WRITABLE ~/.config/nvim ---
  #
  # IMPORTANT:
  # - We seed ONLY ONCE (first rebuild after you add this).
  # - We do NOT re-sync every rebuild, so your local edits/plugins won’t be deleted.
  # - If you ever want to re-seed from upstream starter, delete:
  #     ~/.config/nvim/.seeded-by-nix-lazyvim
  #
  home.activation.lazyvimStarter = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -eu

    NVIM_DIR="$HOME/.config/nvim"
    MARKER="$NVIM_DIR/.seeded-by-nix-lazyvim"

    mkdir -p "$NVIM_DIR"

    if [ ! -e "$MARKER" ]; then
      echo "Seeding LazyVim starter into $NVIM_DIR"

      # Copy from flake input into a writable directory.
      # Do NOT preserve perms/owner/group from the Nix store.
      ${pkgs.rsync}/bin/rsync -r \
        --no-perms --no-owner --no-group \
        --exclude '.git/' \
        ${inputs.lazyvim-starter}/ "$NVIM_DIR/"

      # Ensure everything is writable by the user (lazy.nvim updates lazy-lock.json)
      chmod -R u+rwX "$NVIM_DIR" || true

      # Create marker so we don't overwrite user changes on future rebuilds
      touch "$MARKER"
    else
      # Ensure lockfile remains writable (in case it ever got messed up)
      if [ -f "$NVIM_DIR/lazy-lock.json" ]; then
        chmod u+rw "$NVIM_DIR/lazy-lock.json" || true
      fi
    fi
  '';

  home.activation.lazyvimNixOverrides = lib.hm.dag.entryAfter [ "lazyvimStarter" ] ''
    set -eu

    NVIM_DIR="$HOME/.config/nvim"
    OPTIONS="$NVIM_DIR/lua/config/options.lua"
    INIT="$NVIM_DIR/init.lua"
    LINE='pcall(require, "config.nix")'

    if [ -f "$OPTIONS" ]; then
      if ! grep -Fq "$LINE" "$OPTIONS"; then
        printf '\n-- Nix-managed overrides\n%s\n' "$LINE" >> "$OPTIONS"
      fi
    elif [ -f "$INIT" ]; then
      if ! grep -Fq "$LINE" "$INIT"; then
        printf '\n-- Nix-managed overrides\n%s\n' "$LINE" >> "$INIT"
      fi
    fi
  '';
}

