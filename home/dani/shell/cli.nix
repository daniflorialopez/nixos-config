{ pkgs, ... }:

{
  home.packages = with pkgs; [
    bat
    btop
    eza
    zoxide
    lazygit
    wev
    tree
    zip
    unzip
    ripgrep
    jq
    fzf
    mtr
    lsof
    gnupg
    socat
    # Neovim/LazyVim will usually be configured via programs.neovim
  ];

  # enable Alacritty as primary terminal
  programs.alacritty.enable = true;
}

