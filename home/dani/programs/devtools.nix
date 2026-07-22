{ config, pkgs, inputs, lib, ... }:

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
          activeBorderColor = [ "#7aa2f7" "bold" ];
          inactiveBorderColor = [ "#565f89" ];
          searchingActiveBorderColor = [ "#ff9e64" "bold" ];
          optionsTextColor = [ "#7aa2f7" ];
          selectedLineBgColor = [ "#283457" ];
          cherryPickedCommitFgColor = [ "#7aa2f7" ];
          cherryPickedCommitBgColor = [ "#283457" ];
          markedBaseCommitFgColor = [ "#7aa2f7" ];
          markedBaseCommitBgColor = [ "#e0af68" ];
          unstagedChangesColor = [ "#f7768e" ];
          defaultFgColor = [ "#c0caf5" ];
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

