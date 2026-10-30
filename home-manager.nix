{ identity, ... }:

{
  home = {
    inherit (identity) homeDirectory username;
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;
}
