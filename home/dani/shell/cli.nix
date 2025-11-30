{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # improved core utils
    eza
    fd
    ripgrep
    bat
    fzf
    zoxide
    jq
    yq
    tree

    # system and monitoring
    btop
    htop
    lsof
    ncdu
    strace
    ltrace

    # networking
    curl
    wget
    mtr
    nmap
    iperf3
    dnsutils
    openssh
    netcat-gnu
    socat

    # file transfer / sync
    rsync

    # security
    gnupg

    # version control
    git

    # misc
    unzip
    zip
    file
    rlwrap

    # TODO Neovim/LazyVim will usually be configured via programs.neovim
  ];

  home.sessionVariables = {
    EDITOR    = "nvim";
    VISUAL    = "nvim";
    PAGER     = "less -R";
    MANPAGER  = "less -R";
  };

  # enable Alacritty as primary terminal
  programs.alacritty.enable = true;
}

