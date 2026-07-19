{ pkgs, ... }:

{
  # Don't manage user passwords declaratively (keeps passwords out of git)
  users.mutableUsers = true;

  users.users.dani = {
    isNormalUser = true;
    # gamemode: renice privileges only apply to group members
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "docker" "gamemode" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGSZH6iO1s9ne9mPCOOPrBdNftkJVNMFdymjXeOiufe dani@danarchy"
    ]; 
    shell = pkgs.fish;
  };
}
