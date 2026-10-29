{ config, ... }:

let
  source = "${config.home.homeDirectory}/Workspace/corrupt952/dotfiles/modules/mise";
  link = name: config.lib.file.mkOutOfStoreSymlink "${source}/${name}";
in
{
  xdg.configFile = {
    "mise/config.toml".source = link "config.toml";
    "mise/mise.lock".source = link "mise.lock";
  };
}
