{ ... }:
{
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
}
