{ config, lib, pkgs, ... }:

let
  bat = lib.getExe pkgs.bat;
  fd = lib.getExe pkgs.fd;
in
{
  xdg.enable = true;

  home = {
    packages = [ pkgs.zsh-completions ];

    sessionPath = [
      "${config.home.homeDirectory}/.local/bin"
      "${config.home.homeDirectory}/bin"
    ];

    sessionVariables = {
      LANG = "en_US.UTF-8";
      SSH_AUTH_SOCK = "${config.home.homeDirectory}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
    };
  };

  programs.mise = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";

    zsh-abbr = {
      enable = true;

      abbreviations = {
        bvim = "vim -b";
        c = "code";
        clip = "command::clip";
        dk = "docker";
        dkc = "docker compose";
        g = "git";
        gd = "git fdelete";
        gr = "grep";
        gs = "git fselect";
        k = "kubectl";
        kctx = "kubectx";
        kns = "kubens";
        l = "ls";
        ll = "ls -lh";
        loop = "command::loop";
        reboot = "sudo reboot";
        reload = "exec zsh -l";
        shutdown = "sudo shutdown";
        tf = "terraform";
        tk = "tmuxist";
        vi = "vim";
      };

      globalAbbreviations = {
        G = "| grep";
        now = "$(date \"+%Y-%m-%dT%H:%M:%S%z\")";
        today = "$(date \"+%Y-%m-%d\")";
      };
    };

    autocd = true;
    defaultKeymap = "emacs";
    enableCompletion = true;

    # .zcompdump only exists between switches (home.activation.zshCompdumpReset
    # below removes it on every switch), so its presence means fpath hasn't
    # changed: skip compaudit via `-C`. Its absence means the first shell
    # after a switch, which pays for a real compaudit + rebuild.
    completionInit = ''
      autoload -Uz compinit
      if [[ -f "''${ZDOTDIR}/.zcompdump" ]]; then
        compinit -C
      else
        compinit
      fi
    '';

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      size = 100000;
      save = 100000;
      append = true;
      extended = true;
      ignoreAllDups = true;
      ignoreDups = true;
      ignoreSpace = true;
      saveNoDups = true;
      share = true;
    };

    setOptions = [
      "AUTO_LIST"
      "AUTO_MENU"
      "AUTO_PUSHD"
      "BANG_HIST"
      "HIST_FCNTL_LOCK"
      "HIST_NO_STORE"
      "HIST_REDUCE_BLANKS"
      "HIST_VERIFY"
      "LIST_PACKED"
      "LIST_TYPES"
      "MAGIC_EQUAL_SUBST"
      "NO_BEEP"
      "NOTIFY"
      "PRINT_EIGHT_BIT"
      "PROMPT_SUBST"
    ];

    shellAliases = {
      claude = "SHELL=/bin/bash claude";
      cp = "cp -i";
      df = "df -h";
      du = "du -h";
      ls = "ls -AG";
      mv = "mv -iv";
      rm = "rm -i";
    };

    envExtra = ''
      if [[ -r "$ZDOTDIR/.zshenv.local" ]]; then
        source "$ZDOTDIR/.zshenv.local"
      fi
    '';

    initContent = lib.mkMerge [
      (lib.mkOrder 600 ''
        zstyle ':completion:*' verbose yes
        zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

        command::clip() {
          if (( $# != 1 )); then
            print -u2 -- 'usage: command::clip <file>'
            return 2
          fi
          pbcopy < "$1"
        }

        command::loop() {
          while :; do
            eval "$*"
            sleep 1
          done
        }

        command_not_found_handler() {
          print -Pru2 -- "%F{red}(;_;)%f < Sorry, I didn't know %F{magenta}$1%f command."
          return 127
        }

        autoload -Uz add-zsh-hook chpwd_recent_dirs cdr
        add-zsh-hook chpwd chpwd_recent_dirs

        autoload -Uz colors
        colors
        autoload -Uz vcs_info
        zstyle ':vcs_info:*' enable git svn hg
        zstyle ':vcs_info:*' formats '* %b'
        zstyle ':vcs_info:*' actionformats '[%b|%a]'
        zstyle ':vcs_info:(svn)' branchformat '%b%r'
        zstyle ':vcs_info:*' max-exports 6

        zsh::prompt::segment() {
          local bg fg
          [[ -n "$1" ]] && bg="%K{$1}" || bg="%k"
          [[ -n "$2" ]] && fg="%F{$2}" || fg="%f"
          print -n -- "%{$bg%}%{$fg%} $3"
        }

        zsh::prompt::left() {
          zsh::prompt::segment "" white "%~"
          print -n -- "%{%k%}%{%f%}"
        }

        zsh::prompt::right() {
          zsh::prompt::segment "" red "''${_vcs_prompt_msg}%f"
          print -n -- "%{%k%}%{%f%}"
        }

        # vcs_info shells out to git (15-30ms/prompt here), so it runs in the
        # background via process substitution and only repaints via zle
        # reset-prompt once done. $target/_vcs_prompt_dir guard against a
        # slow job finishing after we've already cd'd elsewhere. Discarding
        # a stale job only drops our fd/handler, not the git process itself
        # (process substitution has no PID to kill) — harmless here since
        # vcs_info is cheap, so left as-is rather than worked around.
        typeset -g _vcs_prompt_msg=""
        typeset -g _vcs_prompt_fd=""
        typeset -g _vcs_prompt_dir=""

        zsh::prompt::vcs_async_start() {
          if [[ -n "$_vcs_prompt_fd" ]]; then
            zle -F "$_vcs_prompt_fd"
            exec {_vcs_prompt_fd}<&-
            _vcs_prompt_fd=""
          fi

          local target=$PWD
          exec {_vcs_prompt_fd}< <(
            cd -q -- "$target" 2>/dev/null || exit
            LANG=ja_JP.UTF-8 vcs_info 2>/dev/null
            print -r -- "''${vcs_info_msg_0_}"
          )
          _vcs_prompt_dir=$target
          zle -F "$_vcs_prompt_fd" zsh::prompt::vcs_async_done
        }

        zsh::prompt::vcs_async_done() {
          local fd=$1 line
          read -r -u $fd line
          zle -F "$fd"
          exec {fd}<&-
          [[ "$fd" == "$_vcs_prompt_fd" ]] || return
          _vcs_prompt_fd=""
          [[ "$_vcs_prompt_dir" == "$PWD" ]] && _vcs_prompt_msg=$line
          zle && zle reset-prompt
        }

        add-zsh-hook precmd zsh::prompt::vcs_async_start

        PROMPT='$(zsh::prompt::left)
        %{''${fg[cyan]}%}$%{''${reset_color}%} '
        RPROMPT='$(zsh::prompt::right)'
        PROMPT2='[%n]> '

        widget::fzf::cdr() {
          local selected
          selected=$(cdr -l | sed 's/^[^ ][^ ]*  *//' | fzf --select-1 --exit-0)
          [[ -n "$selected" ]] || return
          selected="''${selected/#\~/$HOME}"
          cd -- "$selected" || return
          zle reset-prompt
        }
        zle -N widget::fzf::cdr

        widget::fzf::workspace() {
          local selected
          selected=$(
            ${fd} --type d --min-depth 2 --max-depth 2 . "$HOME/Workspace" |
              fzf --select-1 --exit-0 \
                --preview '${bat} --color=always {}/README.md 2>&1'
          )
          [[ -n "$selected" ]] || return
          cd -- "$selected" || return
          zle reset-prompt
        }
        zle -N widget::fzf::workspace

        if (( $+commands[sallyport] )); then
          eval "$(sallyport hook zsh)"
        fi
      '')

      (lib.mkOrder 1100 ''
        bindkey '^[[Z' reverse-menu-complete
        bindkey '^S' history-incremental-search-forward
        bindkey '^R' fzf-history-widget
        bindkey '^xb' widget::fzf::cdr
        bindkey '^xo' widget::fzf::workspace
      '')

      (lib.mkOrder 1500 ''
        if [[ -r "$ZDOTDIR/.zshrc.local" ]]; then
          source "$ZDOTDIR/.zshrc.local"
        fi
      '')
    ];
  };

  # The nix store is immutable within a generation, so fpath only ever
  # changes right after a switch — see completionInit's use of this file.
  home.activation.zshCompdumpReset = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run rm -f $VERBOSE_ARG -- "${config.xdg.configHome}/zsh/.zcompdump"*
  '';
}
