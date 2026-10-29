{
  description = "macOS and Home Manager workstation configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Pulled in solely to track a newer `container` package until the fix
    # lands in nixpkgs-26.05-darwin (see nixpkgs#445648 / apple/container#1329).
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, nixpkgs-unstable, nix-darwin, home-manager, ... }:
    let
      readIdentity = path:
        nixpkgs.lib.removeSuffix "\n" (builtins.readFile path);
      identity = {
        username = readIdentity ./machine-local/username;
        homeDirectory = readIdentity ./machine-local/home-directory;
      };
      workspaceIdentitiesPath = ./machine-local + "/identities.nix";
      workspaceIdentities =
        if builtins.pathExists workspaceIdentitiesPath then
          import workspaceIdentitiesPath
        else
          { };
      system = "aarch64-darwin";
      allowUnfreePredicate = pkg:
        builtins.elem (nixpkgs.lib.getName pkg) [
          "1password-cli"
          "zsh-abbr"
        ];
      # Track nixpkgs-unstable's `container` until nixpkgs-26.05-darwin picks up
      # a version with the CONTAINER_INSTALL_ROOT wrapProgram fix.
      containerOverlay = final: prev: {
        container = nixpkgs-unstable.legacyPackages.${system}.container;
      };
      pkgs = import nixpkgs {
        inherit system;
        # Keep unfree access limited to packages explicitly accepted here.
        config = { inherit allowUnfreePredicate; };
        overlays = [ containerOverlay ];
      };
    in
    {
      darwinConfigurations.workstation = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit identity; };
        modules = [
          ./darwin.nix
          home-manager.darwinModules.home-manager
          {
            nixpkgs.config = { inherit allowUnfreePredicate; };
            nixpkgs.overlays = [ containerOverlay ];

            home-manager = {
              extraSpecialArgs = { inherit identity workspaceIdentities; };
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "backup";
              users.${identity.username} = import ./home-manager.nix;
            };
          }
        ];
      };

      # Keep a standalone output for evaluation and recovery without darwin-rebuild.
      homeConfigurations.workstation = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit identity workspaceIdentities; };
        modules = [
          ./home-manager.nix
          {
            nix = {
              package = pkgs.lix;
              settings.experimental-features = [
                "nix-command"
                "flakes"
              ];
            };
          }
        ];
      };
    };
}
