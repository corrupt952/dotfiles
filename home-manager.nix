{ identity, pkgs, ... }:

{
  imports = [
    ./modules/fzf-direnv
  ];

  home = {
    inherit (identity) homeDirectory username;
    stateVersion = "26.05";

    packages = with pkgs; [
      markdownlint-cli2
    ];
  };

  programs.home-manager.enable = true;
}
