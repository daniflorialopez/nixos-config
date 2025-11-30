{ config, pkgs, ... }:

{ 
  programs.fish = {
    enable = true;

    # Short aliases
    shellAbbrs = { 
      gcm = "git commit -m";  
    };

    # Aliases
    shellAliases = {
      n = "nvim";
      gs = "git status"; 
      ga = "git add -A";  
      gl = "git log --oneline --graph --decorate";
      ll = "eza -lah --icons --group-directories-first";
      lg = "lazygit";

    };

    # Extra initialization when an interactive fish starts
    interactiveShellInit = ''
      # zoxide
      if type -q zoxide
        zoxide init fish | source
      end

      # fzf keybindings
      if type -q fzf
        # TODO source scripts here 
      end

      #starship prompt
      if type -q starship
        starship init fish | source
      end
    '';
  };
}
