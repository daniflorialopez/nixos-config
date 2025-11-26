{ pkgs, ... }:

{
  home.packages = with pkgs; [
    obsidian
    virt-manager   # GUI; the backend is managed on NixOS side
    vscodium
    jetbrains.idea-community  # TODO or ultimate, if unfree + license
  ];

  programs.git.enable = true;

  programs.neovim = {
    enable = true;
    # TODO integrate LazyVim later via plugins
  };
}

