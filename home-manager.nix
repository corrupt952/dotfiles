{ identity, pkgs, workspaceIdentities, xckitPackage, closestPackage, tmuxistPackage, sallyportPackage, ... }:

{
  imports = [
    ./modules/claude
    ./modules/fzf-direnv
    ./modules/git
    ./modules/opencode
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
