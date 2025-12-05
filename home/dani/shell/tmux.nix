{ config, pkgs, ... }:

{
  programs.tmux = {
    enable = true;

    clock24 = true;
    mouse = true;
    baseIndex = 1;
    historyLimit = 10000;
    escapeTime = 0;
    keyMode = "vi";
    terminal = "screen-256color";

    extraConfig = ''
      # Prefix: use C-Space instead of C-b
      set -g prefix C-Space
      unbind C-b
      bind C-Space send-prefix

      # Splits: | and - (with prefix)
      unbind '"'
      unbind %
      bind | split-window -h
      bind - split-window -v

      # Pane navigation without prefix using Alt + h/j/k/l
      bind -n M-h select-pane -L
      bind -n M-j select-pane -D
      bind -n M-k select-pane -U
      bind -n M-l select-pane -R

      # Pane resize without prefix using Ctrl + Shift + h/j/k/l
      bind -n M-H resize-pane -L 2
      bind -n M-J resize-pane -D 2
      bind -n M-K resize-pane -U 2
      bind -n M-L resize-pane -R 2


      # Reload config
      bind r source-file ~/.tmux.conf \; display-message "Reloaded tmux.conf"

      # Use vi keys in copy mode
      setw -g mode-keys vi

      # --- Status bar (not ugly version) ---

      set -g status-interval 5
      set -g status-justify centre
      set -g status-bg default
      set -g status-fg colour244

      # Left: session name
      set -g status-left-length 20
      set -g status-left '#[bold]#S#[default] '

      # Right: time
      set -g status-right-length 40
      set -g status-right '#[fg=colour244]%Y-%m-%d %H:%M #[default]'

      # Window list: current vs inactive
      setw -g window-status-format ' #I:#W '
      setw -g window-status-current-format '#[bold]#I:#W#[default]'
      '';
  };
}

