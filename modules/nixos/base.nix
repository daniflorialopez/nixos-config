{ config, pkgs, ... }:

{
  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "en_US.UTF-8";

  networking.networkmanager.enable = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  programs.fish.enable = true;

  users.users.dani = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "docker" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGSZH6iO1s9ne9mPCOOPrBdNftkJVNMFdymjXeOiufe dani@danarchy"
    ]; 
    shell = pkgs.fish;
  };

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

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  system.stateVersion = "25.05"; # NEVER change
}

