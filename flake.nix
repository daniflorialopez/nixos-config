{
  description = "Dani's NixOS configuration";

  inputs = {
    # Main NixOS channel
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    # NixOS official package source, using the nixos-25.05 branch here
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      
      inputs.nixpkgs.follows = "nixpkgs";
    }; 
  };

  outputs = inputs@{ self, nixpkgs, home-manager, nixpkgs-stable, ... }:
  let
    system = "x86_64-linux";

    # Main package set
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    # Stable package set (what the template calls pkgs-stable)
    pkgs-stable = import nixpkgs-stable {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    nixosConfigurations."danixos-vm" = nixpkgs.lib.nixosSystem {
      inherit system;

      # Extra arguments available to all your modules
      specialArgs = {
        inherit pkgs pkgs-stable;
        inherit self;      # sometimes useful
        inherit home-manager;
      };

      modules = [
        # Import the previous configuration.nix we used,
        # so the old configuration file still takes effect
        ./configuration.nix
        
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;

          # Extra args visible to Home Manager modules (home.nix etc.)
          home-manager.extraSpecialArgs = {
            inherit pkgs-stable;
          };

          home-manager.users.dani = import ./home.nix;

        }
      ];
    };
  };
}
