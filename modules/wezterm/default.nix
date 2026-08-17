{ lib, pkgs, ... }:

let
  weztermNotifyHook = builtins.replaceStrings
    [
      "@bash@"
      "@date@"
      "@jq@"
      "@mkdir@"
      "@sqlite3@"
    ]
    [
      (lib.getExe pkgs.bash)
      (lib.getExe' pkgs.coreutils "date")
      (lib.getExe pkgs.jq)
      (lib.getExe' pkgs.coreutils "mkdir")
      (lib.getExe' pkgs.sqlite "sqlite3")
    ]
    (builtins.readFile ./wezterm-notify.sh);
in
{
  home = {
    packages = [ pkgs.jetbrains-mono ];

    file.".local/libexec/wezterm-notify-hook" = {
      text = weztermNotifyHook;
      executable = true;
    };

    # wezterm.sh's precmd hook forks `hostname` on every prompt when this is
    # unset. Pre-resolving it here means the fork happens once per shell start.
    sessionVariables = {
      WEZTERM_HOSTNAME = "\${WEZTERM_HOSTNAME:-$(hostname)}";
    };
  };

  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
  };

  targets.darwin.copyApps.enable = pkgs.stdenv.hostPlatform.isDarwin;

  xdg.configFile = {
    "wezterm/wezterm.lua".source = ./wezterm.lua;
    "wezterm/appearance.lua".source = ./appearance.lua;
    "wezterm/notification.lua".source = pkgs.replaceVars ./notification.lua {
      sqlite3 = lib.getExe' pkgs.sqlite "sqlite3";
    };
    "wezterm/smart_paste.lua".source = ./smart_paste.lua;
    "wezterm/tmux.lua".source = pkgs.replaceVars ./tmux.lua {
      fd = lib.getExe pkgs.fd;
    };
  };
}
