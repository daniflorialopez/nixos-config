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

    # Logging in lands straight in the passphrase prompt
    postCommands = ''
      echo 'cryptsetup-askpass' >> /root/.profile
    '';

    # Explicit: NetworkManager setups run with networking.useDHCP =
    # false, and the initrd only inherits DHCP from that — without this
    # the sshd would listen on an interface that never got an address.
    udhcpc.enable = true;
    # Bound the no-cable case (matters for legionix undocked, after the
    # boot-slack trimming) without losing the lease race: the VM rehearsal
    # showed 2 tries x 1s is marginal — one boot got a lease, the next got
    # "udhcpc: no lease, failing". 4 tries x 2s waits long enough for a
    # slow DHCP answer, ~8-10s worst case when no cable is plugged.
    udhcpc.extraArgs = [ "-t" "4" "-T" "2" ];
  };
}
