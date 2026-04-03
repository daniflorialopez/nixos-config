{ config, pkgs, ... }:

{
  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "en_US.UTF-8";

  networking.networkmanager.enable = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  programs.fish.enable = true;
 
  # Lock root account so it can't log with a password
  users.users.root.hashedPassword = "!";
  
  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = true;


  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false; # once keys work everywhere
      PubkeyAuthentication = true;
    };    
  };

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

