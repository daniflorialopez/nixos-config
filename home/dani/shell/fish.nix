{ config, pkgs, ... }:

{ 
  programs.fish = {
    enable = true;

    # Abbreviation
    shellAbbrs = { 
      gs  = "git status";
      ga  = "git add -A";
      gcm = "git commit -m";
      gl  = "git log --oneline --graph --decorate";
    };

    # Aliases
    shellAliases = {
      n = "nvim";   
      gl = "git log --oneline --graph --decorate";
      ll = "eza -lah --icons --group-directories-first";
      lg = "lazygit";

    };

    # Extra initialization when an interactive fish starts
    interactiveShellInit = ''
      # Remove the initial banner
      set -g fish_greeting ""

      # vi-style keybindings
      fish_vi_key_bindings

      # zoxide
      if type -q zoxide
        zoxide init fish | source
      end

      # fzf keybindings
      if type -q fzf
        if type -q fd
          set -gx FZF_DEFAULT_COMMAND 'fd --type f --hidden --follow --exclude .git'
        end
      end
    '';
  };
}
