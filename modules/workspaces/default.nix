{ config, lib, ... }:

let
  cfg = config.workspaces;
  inherit (lib) mkOption types;

  identityType = types.submodule (
    { name, ... }:
    {
      options = {
        directory = mkOption {
          type = types.strMatching "[a-zA-Z0-9._-]+";
          default = name;
          description = "Directory name below ~/Workspace.";
        };

        git = mkOption {
          default = null;
          description = "Machine-local Git identity for this workspace.";
          type = types.nullOr (types.submodule {
            options = {
              name = mkOption { type = types.str; };
              email = mkOption { type = types.str; };
              signingKey = mkOption {
                type = types.nullOr types.str;
                default = null;
              };
            };
          });
        };

        sallyport = mkOption {
          default = null;
          description = "Machine-local Sallyport environment for this workspace.";
          type = types.nullOr (types.submodule {
            options = {
              expand = mkOption {
                type = types.bool;
                default = false;
              };
              env = mkOption {
                type = types.attrsOf types.str;
                default = { };
              };
            };
          });
        };
      };
    }
  );

  identityNames = builtins.attrNames cfg.identities;
  identityDirectories = map (name: cfg.identities.${name}.directory) identityNames;
  workspacePath = workspace:
    "${config.home.homeDirectory}/Workspace/${workspace.directory}";
  gitProfilePath = workspace:
    "${config.xdg.configHome}/git/profiles/${workspace.directory}";

  gitIdentities = lib.filterAttrs (_: workspace: workspace.git != null) cfg.identities;
  sallyportIdentities = lib.filterAttrs (
    _: workspace: workspace.sallyport != null
  ) cfg.identities;

  gitProfileSettings = workspace:
    let
      inherit (workspace) git;
      signingEnabled = git.signingKey != null;
    in
    {
      user = {
        inherit (git) email name;
      } // lib.optionalAttrs signingEnabled {
        inherit (git) signingKey;
      };
    } // lib.optionalAttrs signingEnabled {
      commit.gpgSign = true;
      gpg.format = "ssh";
      "gpg \"ssh\"".program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
      tag.gpgSign = true;
    };

  gitProfileFiles = lib.mapAttrs' (
    _: workspace:
    lib.nameValuePair "git/profiles/${workspace.directory}" {
      text = lib.generators.toGitINI (gitProfileSettings workspace);
    }
  ) gitIdentities;

  gitLocalSettings = lib.mapAttrs' (
    _: workspace:
    lib.nameValuePair "includeIf \"gitdir:${workspacePath workspace}/\"" {
      path = gitProfilePath workspace;
    }
  ) gitIdentities;

  sallyportFiles = lib.mapAttrs' (
    _: workspace:
    lib.nameValuePair "Workspace/${workspace.directory}/.sallyport.jsonc" {
      text = builtins.toJSON {
        inherit (workspace.sallyport) env expand;
      };
    }
  ) sallyportIdentities;
in
{
  options.workspaces = {
    identities = mkOption {
      type = types.attrsOf identityType;
      default = { };
      description = "Machine-local workspace, Git, and Sallyport identities.";
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = builtins.length identityDirectories
            == builtins.length (lib.unique identityDirectories);
          message = "workspaces.identities must use unique directory values.";
        }
      ];
    }

    (lib.mkIf (identityDirectories != [ ]) {
      home.activation.createWorkspaceDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p ${lib.concatMapStringsSep " " lib.escapeShellArg (
          map (directory: "${config.home.homeDirectory}/Workspace/${directory}") identityDirectories
        )}
      '';
    })

    (lib.mkIf (gitIdentities != { }) {
      xdg.configFile = gitProfileFiles // {
        "git/local".text = lib.generators.toGitINI gitLocalSettings;
      };
    })

    (lib.mkIf (sallyportIdentities != { }) {
      home.file = sallyportFiles;
    })
  ];
}
