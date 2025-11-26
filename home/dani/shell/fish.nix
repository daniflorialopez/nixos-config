{ config, pkgs, ... }:

{ 
  programs.fish = {
    enable = true;

    # Short aliases
    shellAbbrs = { 
      gs = "git status"; 
      ga = "git add";  
      gc = "git commit";  
      gl = "git log --oneline --graph --decorate";
      ll = "eza -lah";
      n = "nvim";
    };

    # Extra initialization when an interactive fish starts
    interactiveShellInit = ''
      # Editor + pager
      set -gx EDITOR nvim
      set -gx VISUAL nvim
      set -gx PAGER less

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
