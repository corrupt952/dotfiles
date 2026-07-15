{ lib, pkgs, ... }:

let
  bat = lib.getExe pkgs.bat;
  fd = lib.getExe pkgs.fd;
  head = lib.getExe' pkgs.coreutils "head";
  tree = lib.getExe pkgs.tree;

  filesCommand = "${fd} --type f --hidden --follow --exclude .git --strip-cwd-prefix";
  directoriesCommand = "${fd} --type d --hidden --follow --exclude .git --strip-cwd-prefix";
in
{
  home.packages = [ pkgs.fd ];

  programs.fzf = {
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

  programs.direnv = {
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
}
