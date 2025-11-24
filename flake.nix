{
  description = "A simple NixOS flake";

  inputs = {
    # NixOS official package source, using the nixos-25.05 branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      
      inputs.nixpkgs.follows = "nixpkgs";
    }; 
  };

  outputs = inputs@{ nixpkgs, home-manager, ... }: {
    # Please replace my-nixos with your hostname
    nixosConfigurations.danixos-vm = nixpkgs.lib.nixosSystem {
      modules = [
        # Import the previous configuration.nix we used,
        # so the old configuration file still takes effect
        ./configuration.nix
        
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;

          home-manager.users.dani = import ./home.nix;

        }
      ];
    };
  };
}
