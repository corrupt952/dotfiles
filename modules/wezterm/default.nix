{ lib, pkgs, ... }:

{
  home.packages = [ pkgs.jetbrains-mono ];

  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
  };

  targets.darwin.copyApps.enable = pkgs.stdenv.hostPlatform.isDarwin;

  xdg.configFile = {
    "wezterm/wezterm.lua".source = ./wezterm.lua;
    "wezterm/appearance.lua".source = ./appearance.lua;
    "wezterm/notification.lua".source = ./notification.lua;
    "wezterm/smart_paste.lua".source = ./smart_paste.lua;
    "wezterm/tmux.lua".source = pkgs.replaceVars ./tmux.lua {
      fd = lib.getExe pkgs.fd;
    };
  };
}
