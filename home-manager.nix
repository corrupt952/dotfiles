{ identity, pkgs, workspaceIdentities, ... }:

{
  imports = [
    ./modules/fzf-direnv
    ./modules/workspaces
  ];

  home = {
    inherit (identity) homeDirectory username;
    stateVersion = "26.05";

    packages = with pkgs; [
      markdownlint-cli2
      statix
    ];
  };

  programs.home-manager.enable = true;

  workspaces.identities = workspaceIdentities;
}
