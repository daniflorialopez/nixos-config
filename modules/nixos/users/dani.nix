{ pkgs, ... }:

{
  # Don't manage user passwords declaratively (keeps passwords out of git)
  users.mutableUsers = true;

  users.users.dani = {
    isNormalUser = true;
    # gamemode: renice privileges only apply to group members
    # video: swayosd writes /sys/class/backlight nodes its udev rule
    # opened to the group (brightness OSD)
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "docker" "gamemode" "video" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGSZH6iO1s9ne9mPCOOPrBdNftkJVNMFdymjXeOiufe dani@danarchy"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICs56p3R01JJSho9vxH2sr8vqZjjVXqCmgwpNsHpE4N6 dani@legionix"
    ];
    shell = pkgs.fish;
  };
}
