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
    gdu
    smartmontools

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
    lazygit

    # misc
    unzip
    zip
    file
    rlwrap
    wev
    yazi
    parted
    byobu
  ];

  home.sessionVariables = {
    EDITOR    = "nvim";
    VISUAL    = "nvim";
    PAGER     = "less -R";
    MANPAGER  = "less -R";
  };
}

