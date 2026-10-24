{ config, ... }:

{
  # Remote LUKS unlock: a tiny sshd inside the initrd, so a power cut or
  # reboot while away from the machine doesn't strand it at the
  # passphrase prompt. Rehearsed in danixos-vm; legionix imports this on
  # migration day together with disko-luks.nix.
  #
  # Wired network only: WiFi would need iwlwifi firmware + wpa in the
  # initrd, which is not worth the surface. The initrd sshd is separate
  # from the real one (access.nix): it allows root, because there is no
  # user database yet — the shell it lands in only exists to type the
  # passphrase.
  #
  # The host key must be readable BEFORE unlock, so it lives outside the
  # LUKS container and gets appended to the initrd on the unencrypted
  # ESP at bootloader-install time. Anyone with the disk can read it:
  # it only authenticates the host to prevent MITM on the passphrase,
  # never reuse it for anything else. Generate once per host (not in
  # the repo — secret material, and unique per machine):
  #
  #   sudo mkdir -p /etc/secrets/initrd
  #   sudo ssh-keygen -t ed25519 -N "" -f /etc/secrets/initrd/ssh_host_ed25519_key
  #
  # Unlock flow:  ssh -p 2222 root@<host-ip>  → passphrase prompt → boot
  # continues; the console prompt keeps working in parallel.
  #
  # Requires systemd stage 1 (boot.initrd.systemd.enable on the host). The
  # scripted-initrd version used postCommands + udhcpc, which systemd stage 1
  # rejects by assertion, and the scripted initrd goes away in 26.11.
  boot.initrd.network = {
    enable = true;

    ssh = {
      enable = true;
      # not 22: keeps the initrd host key from colliding with the real
      # sshd's entry in known_hosts for the same address
      port = 2222;
      hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
      # the same keys that open a normal session as dani
      authorizedKeys = config.users.users.dani.openssh.authorizedKeys.keys;
    };

    # Drop the initrd's lease before stage 2, as the scripted version did, so
    # NetworkManager starts from a clean interface. systemd stage 1 defaults
    # to keeping it.
    flushBeforeStage2 = true;
  };

  # Logging in lands straight in the passphrase prompt, and Ctrl-C drops to a
  # root shell - the same behaviour the scripted .profile hook had, which
  # Drill 2 depends on (luksHeaderRestore runs from that shell). Making the
  # agent itself the login shell would lose the shell; the initrd default,
  # nologin, would lose the login.
  boot.initrd.systemd.users.root.shell = "/bin/sh";
  boot.initrd.systemd.contents."/etc/profile".text = ''
    systemd-tty-ask-password-agent --query
  '';

  # DHCP on any wired NIC. Explicit because NetworkManager setups run with
  # networking.useDHCP = false, so the initrd inherits no DHCP config, and the
  # sshd would listen on an interface that never got an address.
  #
  # The no-cable case (legionix undocked) costs nothing: the initrd sshd only
  # orders after network.target, never network-online.target, so nothing waits
  # for a lease — the old `udhcpc -t 4 -T 2` bound is no longer needed.
  #
  # ClientIdentifier = "mac" makes the initrd ask for the SAME lease the booted
  # system gets. networkd's default is a DUID, NetworkManager sends the MAC, so
  # the DHCP server saw two different clients and handed the initrd a second
  # address (seen on the VM: initrd .168, system .167) - remote unlock would
  # then dial an address nothing is listening on.
  boot.initrd.systemd.network.networks."10-initrd-wired" = {
    matchConfig.Name = "en*";
    networkConfig.DHCP = "yes";
    dhcpV4Config.ClientIdentifier = "mac";
  };
}
