{ identity, pkgs, workspaceIdentities, ... }:

{
  imports = [
    ./modules/claude
    ./modules/codex
    ./modules/fzf-direnv
    ./modules/git
    ./modules/mise
    ./modules/ruby
    ./modules/tmux
    ./modules/workspaces
    ./modules/zsh
  ];

  home = {
    inherit (identity) homeDirectory username;
    stateVersion = "26.05";

    packages = with pkgs; [
      gnupg
      markdownlint-cli2
      statix
    ];
  };

  programs.home-manager.enable = true;

  workspaces.identities = workspaceIdentities;
}
