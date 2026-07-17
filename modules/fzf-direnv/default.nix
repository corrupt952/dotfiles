{ lib, pkgs, ... }:

let
  bat = lib.getExe pkgs.bat;
  fd = lib.getExe pkgs.fd;
  head = lib.getExe' pkgs.coreutils "head";
  tree = lib.getExe pkgs.tree;

  filesCommand = "${fd} --type f --hidden --follow --strip-cwd-prefix";
  directoriesCommand = "${fd} --type d --hidden --follow --strip-cwd-prefix";
in
{
  home.packages = [ pkgs.fd ];

  # Global fd ignore: every fd invocation (including fzf's defaultCommand) reads
  # this file, so exclusions live here once instead of inline per command.
  # --hidden stays in the fzf command: it is a traversal flag, not an ignore rule.
  xdg.configFile."fd/ignore".text = ''
    .git/
    node_modules/
  '';

  programs = {
    # ripgrep does not auto-discover a config; programs.ripgrep writes the file
    # and sets RIPGREP_CONFIG_PATH for us. CLI flags still override these.
    ripgrep = {
      enable = true;
      arguments = [
        "--smart-case"
        "--hidden"
        "--glob=!.git/"
      ];
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;

      defaultCommand = filesCommand;
      defaultOptions = [
        "--exact"
        "--cycle"
        "--ansi"
        "--height=70%"
        "--layout=reverse"
        "--border"
      ];

      fileWidgetCommand = filesCommand;
      fileWidgetOptions = [
        "--preview '${bat} --color=always --style=numbers --line-range=:200 -- {}'"
      ];

      changeDirWidgetCommand = directoriesCommand;
      changeDirWidgetOptions = [
        "--preview '${tree} -C -L 2 -- {} | ${head} -n 200'"
      ];

      historyWidgetOptions = [ "--sort" ];
    };

    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;

      stdlib = ''
        aws() {
          export AWS_PROFILE="$1"
        }

        use_bin() {
          PATH_add "$PWD/bin"
        }
      '';
    };
  };
}
