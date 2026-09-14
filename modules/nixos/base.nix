{ config, pkgs, ... }:

{
  imports = [ ./rebuild-ergonomics.nix ];

  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "en_US.UTF-8";

  networking.networkmanager.enable = true;

  boot = {
    loader = {
      systemd-boot = {
        enable = true;

        # Keep enough rollback generations for reliability,
        # without completely filling the boot menu.
        configurationLimit = 3;

        # Large/readable UEFI text on the Legion display.
        consoleMode = "0";

        # Leave `editor` at its default (true) for now.
        # This gives us another recovery mechanism if needed.
      };

      efi.canTouchEfiVariables = true;

      # Enough time to comfortably choose NixOS or Windows.
      timeout = 2;
    };
  };

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
    net-tools # ifconfig, netstat, route, arp
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

  system.stateVersion = "25.05"; # NEVER change
}

