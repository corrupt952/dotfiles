# functions
[ -f ${ZDOTDIR}/.zshrc.functions ] && source ${ZDOTDIR}/.zshrc.functions

# prompt
[ -f ${ZDOTDIR}/.zshrc.prompt ] && source ${ZDOTDIR}/.zshrc.prompt

# complement
autoload -U compinit && compinit
zstyle ':completion:*' verbose yes
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
setopt MAGIC_EQUAL_SUBST

# Options
setopt NOBEEP
setopt PROMPT_SUBST
setopt NOTIFY
setopt AUTO_PUSHD
setopt AUTO_LIST
setopt AUTO_MENU
setopt LIST_PACKED
setopt LIST_TYPES
setopt PRINT_EIGHT_BIT

# cd
setopt AUTO_CD
autoload -Uz add-zsh-hook
autoload -Uz chpwd_recent_dirs cdr
add-zsh-hook chpwd chpwd_recent_dirs

# history
HISTFILE=$ZDOTDIR/.zsh_history
HISTSIZE=5000
SAVEHIST=100000
setopt BANG_HIST
setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_NO_STORE
setopt HIST_VERIFY
setopt HIST_REDUCE_BLANKS
setopt HIST_SAVE_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS

# Homebrew & Linuxbrew
if [ -d /home/linuxbrew ]; then
  eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)
fi
if command::exist brew; then
  FZF_PATH=$(brew --prefix fzf)
  if [ -e $FZF_PATH ]; then
    source $FZF_PATH/shell/completion.zsh
    source $FZF_PATH/shell/key-bindings.zsh
  fi
fi
if command::exist asdf; then
  source $(brew --prefix asdf)/libexec/asdf.sh
fi
if command::exist aqua; then
  path=("${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}/bin" $path)
fi
if command::exist mise; then
  eval "$(mise activate bash)"
fi

# zinit
source $ZINIT_HOME/zinit.zsh
zinit ice blockf atpull'zinit creinstall -q .'
zinit light zsh-users/zsh-completions
zinit light zdharma-continuum/fast-syntax-highlighting
zinit light zsh-users/zsh-autosuggestions
__zeno_atload() {
  bindkey ' '  zeno-auto-snippet
  bindkey '^M' zeno-auto-snippet-and-accept-line
  bindkey '^P' zeno-completion
}
zinit wait lucid light-mode for \
    atload'__zeno_atload' \
    @'yuki-yano/zeno.zsh'

# bindkeys
bindkey -e
bindkey "^[[Z" reverse-menu-complete
bindkey "^S" history-incremental-search-forward
bindkey "^R" fzf-history-widget
bindkey "^xb" widget::fzf::cdr
bindkey "^xo" widget::fzf::workspace

# Aliases
alias du='du -h'
alias df='df -h'
alias cp='cp -i'
alias mv='mv -iv'
alias rm='rm -i'
alias ls="ls -AG"
alias docker='docker-wrapper'
alias ssh='ssh-wrapper'
alias claude='SHELL=/bin/bash claude'
command::exist compdef && compdef ssh-wrapper='ssh'

# Hooks
command::exist direnv && eval "$(direnv hook zsh)"

# local
[ -f ${ZDOTDIR}/.zshrc.local ] && source ${ZDOTDIR}/.zshrc.local
