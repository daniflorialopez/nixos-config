{ config, pkgs, ... }:

{ 
  programs.fzf = {
    enable = true;
    enableFishIntegration = false; # it is sourced later

    defaultCommand = "fd --type f --hidden --follow --exclude .git";

    historyWidgetOptions = [
      "--layout=reverse"
      "--height=40%"
      "--border"
    ];
  };

  programs.fish = {
    enable = true;

    # Abbreviation
    shellAbbrs = { 
      gs  = "git status";
      ga  = "git add -A";
      gcm = "git commit -m";
      gl  = "git log --oneline --graph --decorate";

      # Non-compliant packages with Comma syntax should follow the cowsay example below
      cowsay-run = "nix run nixpkgs#cowsay --";
      evtest-run = "sudo nix run nixpkgs#evtest --";
    };

    # Aliases
    shellAliases = {
      n = "nvim";   
      gl = "git log --oneline --graph --decorate";
      ll = "eza -lah --icons --group-directories-first";
      lg = "lazygit";
    };

    functions = {
      fish_greeting = ''
        set -l host (prompt_hostname)
        set -l user $USER
        set -l shell "fish"

        # Friendly aliases for ugly real hostnames
        switch $host
          case 'nixos-desktop'
            set host "desktop"
          case 'thinkpad'
            set host "laptop"
          case 'vps-01'
            set host "server"
        end

        # Detect remote session
        set -l is_remote 0
        if set -q SSH_TTY; or set -q SSH_CONNECTION; or set -q SSH_CLIENT
          set is_remote 1
        end

        # Restrained Tokyo Night palette
        set -l comment "#565f89"
        set -l fg      "#c0caf5"
        set -l blue    "#7aa2f7"
        set -l purple  "#bb9af7"

        set -l role "local"
        set -l role_color $comment
        if test $is_remote -eq 1
          set role "remote"
          set role_color $purple
        end

        set_color $comment
        printf "╭─ "

        set_color $fg
        printf "%s" $user

        set_color $comment
        printf "@"

        set_color --bold $blue
        printf "%s" $host

        set_color $comment
        printf " · "

        set_color $role_color
        printf "%s" $role

        set_color $comment
        printf " · "

        set_color $comment
        printf "%s" $shell

        set_color normal
        echo
      '';
    };

    # Extra initialization when an interactive fish starts
    interactiveShellInit = ''
      # vi-style keybindings
      fish_vi_key_bindings

      # zoxide
      if type -q zoxide
        zoxide init fish | source
      end

    '';

    shellInitLast = ''
      fzf --fish | source
    '';
  };
}
