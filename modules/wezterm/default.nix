{ lib, pkgs, ... }:

{
  home.packages = [ pkgs.jetbrains-mono ];

  # wezterm.sh's precmd hook forks `hostname` on every prompt when this is
  # unset. Pre-resolving it here means the fork happens once per shell start.
  home.sessionVariables = {
    WEZTERM_HOSTNAME = "\${WEZTERM_HOSTNAME:-$(hostname)}";
  };

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
