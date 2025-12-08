{ config, pkgs, ... }:

let
  # Oh My Tmux, fetched once, pinned to a specific commit
  ohMyTmux = pkgs.fetchFromGitHub {
    owner = "gpakosz";
    repo  = ".tmux";

    # 1) Put a real commit hash here from https://github.com/gpakosz/.tmux
    #    For example: rev = "abcd1234....";
    rev    = "5b34d9a873b8bfe608004d59b08e81389ce7b6a9";

    # 2) Put the corresponding sha256 here (see instructions below)
    sha256 = "sha256-0suqQJvB7OfUuxw8ruRbBOSjv+hHy2mfwsvJKbg5csQ=";
  };
in
{
  programs.tmux = {
    enable = true;
    package = pkgs.tmux;

    # Nice defaults that don’t fight Oh My Tmux
    mouse        = true;      # scrolling, clicking panes
    keyMode      = "vi";      # vi-style keys in prompts / copy-mode
    historyLimit = 100000;
    escapeTime   = 0;         # better for Neovim, fzf, etc.
    baseIndex    = 1;         # windows start at 1
    clock24      = true;
    terminal     = "tmux-256color";

    # Plugins managed by Nix (no TPM needed)
    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = resurrect;
        extraConfig = ''
          # Better Neovim/Vim restore behavior
          set -g @resurrect-strategy-nvim 'session'
          set -g @resurrect-strategy-vim  'session'

          # Save pane scrollback contents too
          set -g @resurrect-capture-pane-contents 'on'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          # Auto-restore sessions on tmux start
          set -g @continuum-restore 'on'

          # Autosave every 15 minutes
          set -g @continuum-save-interval '15'
        '';
      }
      yank

      extrakto

      vim-tmux-navigator
    ];

    # Load Oh My Tmux as the base config
    extraConfig = ''
      # Make Oh My Tmux aware of its real config + local config
      set-environment -g TMUX_CONF "${ohMyTmux}/.tmux.conf"
      set-environment -g TMUX_CONF_LOCAL "$HOME/.tmux.conf.local"

      # Load Oh My Tmux
      source-file "${ohMyTmux}/.tmux.conf"
    '';
  };

  # Oh My Tmux automatically loads ~/.tmux.conf.local if it exists.
  # We let Home Manager manage that file for you.
  home.file.".tmux.conf.local".text = ''
    # ================= Prefix & Ergonomics =====================

    # Drop Oh My Tmux's dual-prefix (C-b + C-a) and use Ctrl-Space only
    set -gu prefix2
    unbind C-b
    unbind C-a
    set -g prefix C-Space
    bind C-Space send-prefix

    # Reload config quickly
    bind r source-file ~/.tmux.conf \; display-message "tmux.conf reloaded"

    # Ensure vi-style keys in copy-mode + status (redundant but explicit)
    setw -g mode-keys vi
    set -g status-keys vi

    # (Optional) you can add theme tweaks here later if you want.
    # This file is YOUR playground for Oh My Tmux overrides.
  '';
}

