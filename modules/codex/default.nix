{ pkgs, ... }:
let
  jsonFormat = pkgs.formats.json { };

  marketplace = {
    name = "labee-standards";
    interface.displayName = "Labee Standards";
    plugins = map (name: {
      inherit name;
      source = {
        source = "git-subdir";
        url = "https://github.com/LabeeHive/standards.git";
        path = "./plugins/${name}";
        ref = "main";
      };
      policy = {
        installation = "AVAILABLE";
        authentication = "ON_INSTALL";
      };
      category = "Developer Tools";
    }) [
      "labee-core"
      "labee-swift"
      "labee-marketing"
      "labee-authoring"
    ];
  };
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

  home.file.".agents/plugins/marketplace.json".source =
    jsonFormat.generate "labee-standards-marketplace" marketplace;
}
