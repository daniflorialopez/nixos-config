{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # improved core utils
    eza
    fd
    ripgrep
    fzf
    zoxide
    jq
    yq
    tree

    # system and monitoring (btop lives in btop.nix with its theme)
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
    nftables # `nft` CLI

    # file transfer / sync
    rsync

    # security
    gnupg

    # version control (lazygit lives in devtools.nix as programs.lazygit
    # so its Tokyo Night theme travels with the package)
    git

    # misc
    unzip
    zip
    file
    rlwrap
    wev
    yazi
    parted
    byobu
    poppler-utils
    qpdf
  ];

  # "ansi" maps bat's syntax colors onto the terminal's 16-color palette,
  # i.e. the calibrated Tokyo Night in alacritty.nix — instead of the
  # default Monokai, which fights the scheme
  programs.bat = {
    enable = true;
    config.theme = "ansi";
  };

  home.sessionVariables = {
    EDITOR    = "nvim";
    VISUAL    = "nvim";
    PAGER     = "less -R";
    MANPAGER  = "less -R";
  };
}

