{ config, lib, pkgs, ... }:

let
  codexHome =
    if config.home.preferXdgDirectories then
      "${config.xdg.configHome}/codex"
    else
      "${config.home.homeDirectory}/.codex";
  codexHomeRelative = lib.removePrefix "${config.home.homeDirectory}/" codexHome;
in
{
  # The Codex app manages and updates the CLI. Home Manager owns only the
  # integration files here, leaving config.toml writable for runtime state
  # such as project trust, MCP configuration, and UI notices.
  programs.codex = {
    enable = true;
    package = null;
    context = ../agent-rules.md;
  };
}
