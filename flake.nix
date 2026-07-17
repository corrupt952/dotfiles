{
  description = "macOS and Home Manager workstation configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    xckit = {
      url = "github:corrupt952/xckit/v0.2.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    closest = {
      url = "github:corrupt952/closest/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tmuxist = {
      url = "github:corrupt952/tmuxist/1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sallyport = {
      url = "git+ssh://git@github.com/corrupt952/sallyport?ref=refs/tags/v0.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, nix-darwin, home-manager, xckit, closest, tmuxist, sallyport, ... }:
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
      pkgs = import nixpkgs {
        inherit system;
        # Keep unfree access limited to packages explicitly accepted here.
        config = { inherit allowUnfreePredicate; };
      };
      xckitPackage = xckit.packages.${system}.default;
      closestPackage = closest.packages.${system}.default;
      tmuxistPackage = tmuxist.packages.${system}.default;
      sallyportPackage = sallyport.packages.${system}.default;
    in
    {
      darwinConfigurations.workstation = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit identity; };
        modules = [
          ./darwin.nix
          home-manager.darwinModules.home-manager
          {
            nixpkgs.config = { inherit allowUnfreePredicate; };

            home-manager = {
              extraSpecialArgs = { inherit identity workspaceIdentities xckitPackage closestPackage tmuxistPackage sallyportPackage; };
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
        extraSpecialArgs = { inherit identity workspaceIdentities xckitPackage closestPackage tmuxistPackage sallyportPackage; };
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
