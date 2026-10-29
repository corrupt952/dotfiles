{ identity, pkgs, ... }:

{
  nix = {
    package = pkgs.lix;

    gc = {
      automatic = true;
      interval = [
        {
          Weekday = 7;
          Hour = 3;
          Minute = 15;
        }
      ];
      options = "--delete-older-than 30d";
    };

    optimise = {
      automatic = true;
      interval = [
        {
          Weekday = 7;
          Hour = 4;
          Minute = 15;
        }
      ];
    };

    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  nixpkgs.hostPlatform = "aarch64-darwin";

  security.pam.services.sudo_local.enable = false;

  users.users.${identity.username} = {
    name = identity.username;
    home = identity.homeDirectory;
  };

  system = {
    primaryUser = identity.username;
    stateVersion = 6;
  };
}
