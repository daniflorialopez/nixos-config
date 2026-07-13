# Recipient config for agenix.
#
# Each entry maps a `.age` file to the list of public keys allowed to decrypt
# it. Host keys let a machine decrypt secrets at activation time; user keys let
# you (interactively) decrypt/edit them with the `agenix` CLI.
#
# To edit a secret: cd secrets && nix run github:ryantm/agenix -- -e <name>.age
# To rekey after changing recipients: cd secrets && nix run github:ryantm/agenix -- -r

let
  # User keys (for editing secrets)
  dani-legionix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICs56p3R01JJSho9vxH2sr8vqZjjVXqCmgwpNsHpE4N6 dani@legionix";
  dani-danarchy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGSZH6iO1s9ne9mPCOOPrBdNftkJVNMFdymjXeOiufe dani@danarchy";
  users = [ dani-legionix dani-danarchy ];

  # Host keys (for decryption at runtime, per machine)
  legionix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICaNI6gRS8tch/TzvtRvOvcPSM1Yo3zGt6L/ZLrFa1+L root@legionix";
in
{
  "restic-password.age".publicKeys = users ++ [ legionix ];
  "restic-env.age".publicKeys = users ++ [ legionix ];
}
