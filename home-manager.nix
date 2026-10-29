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
    ./modules/wezterm
    ./modules/workspaces
    ./modules/zsh
  ];

  home = {
    inherit (identity) homeDirectory username;
    stateVersion = "26.05";

    packages = with pkgs; [
      bat
      gnupg
      jq
      markdownlint-cli2
      statix
      tig
      tree
    ];
  };

  programs.home-manager.enable = true;

  workspaces.identities = workspaceIdentities;
}
