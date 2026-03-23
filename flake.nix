{
  description = "Dani's NixOS + Home Manager config";

  inputs = {
    # Main NixOS channel – stick to release for now
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # Home Manager, following the same nixpkgs
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    lazyvim-starter = {
      url = "github:LazyVim/starter";
      flake = false;
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    elephant.url = "github:abenz1267/elephant";

    walker = {
      url = "github:abenz1267/walker";
      inputs.elephant.follows = "elephant";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      nix-index-database,
      ...
    }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.danixos-vm = nixpkgs.lib.nixosSystem {
        inherit system;

        # Extra args you want modules to see (if needed later)
        specialArgs = { inherit inputs; };

        modules = [
          # Host config (imports hardware + modules/nixos/*.nix)
          ./hosts/danixos-vm

          # Home Manager as a NixOS module
          home-manager.nixosModules.home-manager

          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.sharedModules = [
              nix-index-database.homeModules.default
            ];

            # Tell HM what extension to use when backing up conflicting files
            home-manager.backupFileExtension = "backup";

            # You can pass extra args to home modules if you want
            home-manager.extraSpecialArgs = { inherit inputs; };

            # Your home config entry point
            home-manager.users.dani = import ./home/dani;
          }
        ];
      };
      nixosConfigurations.danix-hp = nixpkgs.lib.nixosSystem {
        inherit system;

        # Extra args you want modules to see (if needed later)
        specialArgs = { inherit inputs; };

        modules = [
          # Host config (imports hardware + modules/nixos/*.nix)
          ./hosts/danix-hp

          # Home Manager as a NixOS module
          home-manager.nixosModules.home-manager

          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.sharedModules = [
              nix-index-database.homeModules.default
            ]; 

            # Tell HM what extension to use when backing up conflicting files
            home-manager.backupFileExtension = "backup";

            # You can pass extra args to home modules if you want
            home-manager.extraSpecialArgs = { inherit inputs; };

            # Your home config entry point
            home-manager.users.dani = import ./home/dani;
          }
        ];
      };
      nixosConfigurations.legionix = nixpkgs.lib.nixosSystem {
        inherit system;

        # Extra args you want modules to see (if needed later)
        specialArgs = { inherit inputs; };

        modules = [
          # Host config (imports hardware + modules/nixos/*.nix)
          ./hosts/legionix/

          # Home Manager as a NixOS module
          home-manager.nixosModules.home-manager

          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.sharedModules = [
              nix-index-database.homeModules.default
            ]; 

            # Tell HM what extension to use when backing up conflicting files
            home-manager.backupFileExtension = "backup";

            # You can pass extra args to home modules if you want
            home-manager.extraSpecialArgs = { inherit inputs; };

            # Your home config entry point
            home-manager.users.dani = import ./home/dani;
          }
        ];
      };
    };
}
