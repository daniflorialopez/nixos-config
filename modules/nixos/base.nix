{ config, pkgs, ... }:

{
  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "en_US.UTF-8";

  networking.networkmanager.enable = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # 1s menu instead of the default 5: still catchable with a keypress
  # for generation rollbacks, without the every-boot wait
  boot.loader.timeout = 1;

  # Don't block graphical.target ~5s waiting for the network: nothing
  # at login time needs it, Wi-Fi connects on its own moments later
  systemd.services.NetworkManager-wait-online.enable = false;

  # No swap meant memory spikes (VM + desktop + Steam) had nowhere to
  # bleed off and hard-locked the machine instead of degrading. zram
  # gives compressed RAM-backed swap as a relief valve for bursts.
  zramSwap.enable = true;

  programs.fish.enable = true;

  services.qemuGuest.enable = true;

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
  ];
  
  nixpkgs.config.allowUnfree = true;

  nix.settings.auto-optimise-store = true;
  
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep-since 14d --keep 10";
    };
  };

  # Deduplicate/optimise store a bit over time
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  # Limit how many boot entries are kept (doesn't free space by itself, but keeps boot menu tidy)
  boot.loader.systemd-boot.configurationLimit = 10;

  system.stateVersion = "25.05"; # NEVER change
}

