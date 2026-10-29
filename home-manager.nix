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
      _1password-cli
      bat
      btop
      cocoapods
      container
      git-filter-repo
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
