{
  description = "Dani's NixOS + Home Manager config";

  inputs = {
    # Main NixOS channel – stick to release for now.
    # nixpkgs and home-manager must move together: HM's release check compares
    # its own release against pkgs.lib.trivial.release and warns loudly when
    # they differ, and upstream says a mismatch "is likely to cause errors".
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Home Manager, following the same nixpkgs
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
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

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
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

      # The design-token palette, built once and handed to BOTH module systems.
      # Passing it as a module argument rather than letting each file
      # `import ../../theme/palette.nix` keeps relative paths out of eleven
      # modules and, more importantly, makes it reachable from modules/nixos —
      # the SDDM greeter needs the same colours as the desktop, and before this
      # it would have had to reach up three directories into home/.
      theme = import ./theme/palette.nix { inherit (nixpkgs) lib; };

      # Every host is wired identically: hosts/<name> plus the shared
      # agenix + Home Manager plumbing. Keeping this in one place means
      # the VM really does mirror the real machines (the LUKS rehearsal
      # in danixos-vm depends on that symmetry).
      mkHost =
        name:
        nixpkgs.lib.nixosSystem {
          inherit system;

          # Extra args you want modules to see (if needed later)
          specialArgs = { inherit inputs theme; };

          modules = [
            # Host config (imports hardware + modules/nixos/*.nix)
            ./hosts/${name}

            # Secrets management
            inputs.agenix.nixosModules.default

            # Home Manager as a NixOS module
            home-manager.nixosModules.home-manager

            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              home-manager.sharedModules = [
                nix-index-database.homeModules.default
              ];

              # Tell HM what extension to use when backing up conflicting files
              home-manager.backupFileExtension = "hm-backup";

              # You can pass extra args to home modules if you want
              home-manager.extraSpecialArgs = { inherit inputs theme; };

              # Your home config entry point
              home-manager.users.dani = import ./home/dani;
            }
          ];
        };
    in
    {
      nixosConfigurations = {
        danixos-vm = mkHost "danixos-vm";
        danix-hp = mkHost "danix-hp";
        legionix = mkHost "legionix";
      };
    };
}
