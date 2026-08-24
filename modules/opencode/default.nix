{ config, pkgs, ... }:

let
  weztermNotifyHook = "${config.home.homeDirectory}/.local/libexec/wezterm-notify-hook";
in
{
  programs.opencode = {
    enable = true;
    context = ../agent-rules.md;
  };

  xdg.configFile."opencode/plugins/wezterm-notify.ts".source =
    pkgs.replaceVars ./wezterm-notify.ts {
      inherit weztermNotifyHook;
    };
}
