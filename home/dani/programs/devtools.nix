{ config, pkgs, inputs, lib, ... }:

{
  home.packages = with pkgs; [
    obsidian
    virt-manager   # GUI; the backend is managed on NixOS side
    vscodium
    jetbrains.idea-community  # TODO or jetbrains.idea-ultimate, if unfree + license
  ];

  programs.git.enable = true;


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
    ];
  };

  # Optional but nice: ensure these are set globally for CLI tools (git commit, etc.)
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
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
}

