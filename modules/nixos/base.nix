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

    # Trying bgrt (was: breeze, the NixOS-branded default).
    #
    # bgrt *is* spinner - its ImageDir points at spinner's own directory, and
    # the only difference is UseFirmwareBackground, so picking between the two
    # is purely "with or without the firmware's boot logo". This machine does
    # publish one: /sys/firmware/acpi/bgrt/image is a valid 670x134 LEGION
    # wordmark. Both also carry NixOS's snowflake watermark, which the module
    # overlays into the spinner theme directory.
    #
    # No themePackages change needed - the module's theme dir already includes
    # plymouth's own themes alongside breeze.
    plymouth = {
      enable = true;
      theme = "bgrt";
    };

    # Suppress routine kernel chatter, but retain errors.
    consoleLogLevel = 3;

    # Don't dump initrd activity onto the screen.
    initrd.verbose = false;

    # `quiet` also makes systemd normally stay quiet while still
    # showing status automatically when something fails or takes too long.
    #
    # udev.log_level=3 (err) silences systemd-udevd's "Starting systemd-udevd
    # version N" line, which was flashing up as a text console just before the
    # splash. Neither `quiet` nor initrd.verbose suppresses it: the scripted
    # stage-1 tees its fifo to the *saved console fd* as well as to /dev/kmsg,
    # so that output reaches the screen directly and never passes through
    # printk's loglevel. Worse, it is the write itself that matters - fbcon
    # logs "Deferring console take-over" and holds the firmware logo until
    # something writes to the console, at which point it takes over and the
    # logo is replaced by a text VT. Silencing udevd at the source keeps the
    # takeover deferred until plymouth is up.
    kernelParams = [
      "quiet"
      "udev.log_level=3"
    ];
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

