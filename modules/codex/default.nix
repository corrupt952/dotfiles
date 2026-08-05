{ config, lib, pkgs, ... }:

let
  codexHome =
    if config.home.preferXdgDirectories then
      "${config.xdg.configHome}/codex"
    else
      "${config.home.homeDirectory}/.codex";
  codexHomeRelative = lib.removePrefix "${config.home.homeDirectory}/" codexHome;

  weztermNotifyCommand = "${config.home.homeDirectory}/.local/libexec/wezterm-notify-hook";
  weztermNotifyHandler = {
    type = "command";
    command = weztermNotifyCommand;
    timeout = 3;
  };
  weztermNotifyEvent = {
    hooks = [ weztermNotifyHandler ];
  };

  hooks = {
    description = "Report Codex lifecycle state to WezTerm.";
    hooks = {
      SessionStart = [ weztermNotifyEvent ];
      PermissionRequest = [ weztermNotifyEvent ];
      UserPromptSubmit = [ weztermNotifyEvent ];
      Stop = [ weztermNotifyEvent ];
      SessionEnd = [ weztermNotifyEvent ];
    };
  };

  jsonFormat = pkgs.formats.json { };
in
{
  # The Codex app manages and updates the CLI. Home Manager owns only the
  # integration files here, leaving config.toml writable for runtime state
  # such as project trust, MCP configuration, and UI notices.
  programs.codex = {
    enable = true;
    package = null;
  };

  home.file."${codexHomeRelative}/hooks.json".source =
    jsonFormat.generate "codex-hooks" hooks;
}
