{ config, lib, pkgs, ... }:

{
  imports = [ ./rebuild-ergonomics.nix ];

  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "en_US.UTF-8";

  networking.networkmanager.enable = true;

  boot = {
    loader = {
      systemd-boot = {
        enable = true;

        # Ten, not three, and the number is load-bearing rather than cosmetic.
        #
        # On legionix, booting a previous generation is not *a* recovery path, it
        # is one of only two that exist: there is no usable text console here
        # (/sys/class/vtconsole holds only a dummy device - the panel hangs off
        # the NVIDIA GPU and only lights under a real graphical modeset), and
        # there is deliberately no safe-graphics specialisation. The other path
        # is SSH over Tailscale. See docs/rescue-blackscreen.md.
        #
        # At three entries, a regression noticed a few switches later - which is
        # exactly how a bad kernel/driver pairing presents - is already
        # unrollable from the firmware menu. docs/rescue-blackscreen.md also told
        # you to expect ten, so this makes the doc true.
        #
        # It fits: /boot is 1022M with 940M free, and a generation costs ~47M
        # (12M kernel + 35M initrd). Ten distinct kernels would be ~470M, and in
        # practice generations sharing a kernel share the files - 24 generations
        # on disk currently occupy 83M of ESP between them.
        configurationLimit = 10;

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

    # Pinned FALSE by default since the 26.05 bump; hosts now opt in one at a
    # time, which is why this is mkDefault rather than a plain value.
    #
    # 26.05 flips this default: `mkEnableOption` (false) on 25.11 becomes
    # `default = true` (nixos/modules/system/boot/systemd/initrd.nix), and this
    # repo never set it — so the channel bump would silently swap the entire
    # initrd implementation on the same switch that moves the kernel six series
    # (6.12.93 -> 6.18.52) and the NVIDIA driver a full generation
    # (580.142 -> 595.71.05).
    #
    # Of those three, the initrd is the only one that can fail BEFORE any
    # graphical modeset, and legionix has no usable text console
    # (/sys/class/vtconsole is a dummy device), so a stage-1 failure here is
    # indistinguishable from a dead machine. Everything downstream of it — the
    # driver, EGL, SDDM, Hyprland — at least leaves sshd and Tailscale reachable.
    #
    # Pinning it makes the bump three variables instead of four, for the price
    # of one later reboot. Nothing suggests this host would actually struggle
    # with systemd stage 1 — plain btrfs by partlabel via disko, explicit
    # fsTypes, x-initrd.mount on the three neededForBoot mounts, no LUKS, no
    # initrd-ssh, no custom preLVM/postMount hooks — which is exactly why it
    # should be adopted on its own, as a revertable commit, where a failure is
    # unambiguous. Deprecated upstream with removal scheduled for 26.11, so this
    # is a deferral of months, not a permanent opt-out.
    #
    # Opt-in status: legionix adopted it alone (hosts/legionix/default.nix),
    # then danixos-vm once initrd-ssh.nix was ported off `postCommands` and
    # `udhcpc`, which systemd stage 1 rejects by assertion. danix-hp follows
    # the next time it is rebuilt. This pin must be gone before the 26.11 bump.
    initrd.systemd.enable = lib.mkDefault false;

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

