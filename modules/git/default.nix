{ config, lib, pkgs, ... }:

let
  gitSsh = pkgs.writeShellApplication {
    name = "git-ssh";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssh
    ];
    text = builtins.readFile ./ssh.sh;
  };

  gitSelectBranch = pkgs.writeShellApplication {
    name = "git-select-branch";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.fzf
      pkgs.gawk
      pkgs.git
      pkgs.gnugrep
    ];
    text = builtins.readFile ./select-branch.sh;
  };

  gitDeleteBranch = pkgs.writeShellApplication {
    name = "git-delete-branch";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.fzf
      pkgs.gawk
      pkgs.git
      pkgs.gnugrep
    ];
    text = builtins.readFile ./delete-branch.sh;
  };

  gitPrePush = pkgs.writeShellApplication {
    name = "pre-push";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.git-lfs
    ];
    text = builtins.readFile ./pre-push.sh;
  };

  gitConfigHome = "${config.xdg.configHome}/git";
in
{
  home.packages = [ pkgs.vim ];

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
    };
  };

  programs.git = {
    enable = true;
    lfs.enable = true;

    includes = [
      { path = "${gitConfigHome}/local"; }
    ];

    ignores = lib.filter (line: line != "") (
      lib.splitString "\n" (builtins.readFile ./ignore)
    );

    settings = {
      alias = {
        pick = "cherry-pick";
        cfg = "config";
        cl = "clone";
        pu = "pull";
        ps = "push";
        rv = "revert";
        st = "status --short --branch";

        r = "reset --soft HEAD";
        r1 = "reset --soft HEAD~";
        r2 = "reset --soft HEAD~~";
        r3 = "reset --soft HEAD~~~";
        rh = "reset --hard HEAD";
        rh1 = "reset --hard HEAD~";
        rh2 = "reset --hard HEAD~~";
        rh3 = "reset --hard HEAD~~~";

        s = "stash";
        sp = "stash pop";
        sl = "stash list";

        m = "checkout master";
        co = "checkout";
        nco = "checkout -B";
        rvf = "checkout HEAD";

        a = "add .";
        aa = "add --all";
        "add-all" = "add --all";
        ap = "add --patch";
        "add-patch" = "add --patch";

        fp = "fetch --prune";

        b = "branch";
        ba = "branch --all";
        "branch-all" = "branch --all";
        bd = "branch -D";
        "branch-delete" = "branch -D";

        d = "diff --color-words";
        di = "diff --color-words";
        dh = "diff --color-words HEAD";
        "diff-head" = "diff --color-words HEAD";
        ds = "diff --stat";
        "diff-stat" = "diff --stat";
        ddi = "diff --color-words --diff-algorithm=default";
        pdi = "diff --color-words --diff-algorithm=patience";
        hdi = "diff --color-words --diff-algorithm=histogram";

        ci = "commit";
        eci = "commit --allow-empty";
        "empty-commit" = "commit --allow-empty";
        aci = "commit --amend";
        "ammend-commit" = "commit --amend";

        ol = "log --pretty=oneline";
        onelog = "log --pretty=oneline";
        gl = "log --graph";
        "graph-log" = "log --graph";
        t = "log --graph --pretty=oneline --abbrev-commit --decorate";
        tree = "log --graph --pretty=oneline --abbrev-commit --decorate";

        n = "now --stat";
        fselect = "!${gitConfigHome}/scripts/git-select-branch";
        fdelete = "!${gitConfigHome}/scripts/git-delete-branch";
        env = "!git config --get-regexp '^user.'";
      };

      apply.whitespace = "fix";

      color = {
        ui = true;
        diff = true;
        branch = true;
        interactive = true;
        status = true;
      };

      "color \"branch\"" = {
        current = "red";
        local = "white";
        remote = "yellow";
      };

      core = {
        editor = lib.getExe pkgs.vim;
        hooksPath = "${gitConfigHome}/hooks";
        precomposeunicode = true;
        quotepath = false;
        sshCommand = "${gitConfigHome}/scripts/git-ssh";
        whitespace = "-indent-with-non-tab,trailing-space,cr-at-eol";
      };

      commit.verbose = true;
      diff.algorithm = "histogram";
      help.autocorrect = "prompt";
      fetch.prune = true;
      init.defaultBranch = "main";
      merge.conflictstyle = "zdiff3";
      push.default = "nothing";
      rebase.autoSquash = true;
      rebase.autoStash = true;
      rebase.missingCommitsCheck = "warn";
      rerere = {
        autoupdate = true;
        enabled = true;
      };
      ssh.variant = "ssh";
    } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      credential.helper = "osxkeychain";
    };
  };

  xdg.configFile = {
    "git/hooks/pre-push".source = lib.getExe gitPrePush;
    "git/scripts/git-delete-branch".source = lib.getExe gitDeleteBranch;
    "git/scripts/git-select-branch".source = lib.getExe gitSelectBranch;
    "git/scripts/git-ssh".source = lib.getExe gitSsh;
  };
}
