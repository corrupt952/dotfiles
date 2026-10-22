{ identity, pkgs, workspaceIdentities, xckitPackage, closestPackage, tmuxistPackage, sallyportPackage, ... }:

{
  imports = [
    ./modules/claude
    ./modules/codex
    ./modules/fzf-direnv
    ./modules/git
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
      actionlint
      arp-scan
      automake
      bat
      btop
      cmake
      cocoapods
      container
      coreutils-prefixed
      curl
      duckdb
      gh
      git-filter-repo
      gnugrep
      gnupg
      gnused
      jq
      libtool
      markdownlint-cli2
      mas
      shellcheck
      statix
      swiftlint
      tig
      tree
      uv
      wget
      zizmor
      xckitPackage
      closestPackage
      tmuxistPackage
      sallyportPackage
    ];
  };

  programs.home-manager.enable = true;

  workspaces.identities = workspaceIdentities;
}
