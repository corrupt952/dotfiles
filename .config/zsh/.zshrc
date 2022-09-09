# zmodload zsh/zprof && zprof

##
# zcompile
if [ ! -e ${ZDOTDIR}/.zshrc.zwc -o ${ZDOTDIR}/.zshrc -nt ${ZDOTDIR}/.zshrc.zwc ]; then
  echo 'compiling .zshrc...'
  zcompile ${ZDOTDIR}/.zshrc
fi
if [ ! -e ${ZDOTDIR}/.zshrc.local.zwc -o ${ZDOTDIR}/.zshrc.local -nt ${ZDOTDIR}/.zshrc.local.zwc ]; then
  echo 'compiling .zshrc.local...'
  zcompile ${ZDOTDIR}/.zshrc.local
fi
if [ ! -e ${ZDOTDIR}/.zshrc.aliases.zwc -o ${ZDOTDIR}/.zshrc.aliases -nt ${ZDOTDIR}/.zshrc.aliases.zwc ]; then
  echo 'compiling .zshrc.aliases...'
  zcompile ${ZDOTDIR}/.zshrc.aliases
fi
if [ ! -e ${ZDOTDIR}/.zshrc.prompt.zwc -o ${ZDOTDIR}/.zshrc.prompt -nt ${ZDOTDIR}/.zshrc.prompt.zwc ]; then
  echo 'compiling .zshrc.prompt...'
  zcompile ${ZDOTDIR}/.zshrc.prompt
fi
if [ ! -e ${ZDOTDIR}/.zshrc.functions.zwc -o ${ZDOTDIR}/.zshrc.functions -nt ${ZDOTDIR}/.zshrc.functions.zwc ]; then
  echo 'compiling .zshrc.functions...'
  zcompile ${ZDOTDIR}/.zshrc.functions
fi

##
# color
autoload -Uz colors
colors
BLACK=$'\e[0;30m'
RED=$'\e[0;31m'
GREEN=$'\e[0;32m'
BLUE=$'\e[0;34m'
PURPLE=$'\e[0;35m'
CYAN=$'\e[0;36m'
LIGHT_GRAY=$'\e[0;37m'
LIGHT_RED=$'\e[1;31m'
LIGHT_GREEN=$'\e[1;32m'
YELLOW=$'\e[1;33m'
LIGHT_BLUE=$'\e[1;34m'
LIGHT_PURPLE=$'\e[1;35m'
LIGHT_CYAN=$'\e[1;36m'
WHITE=$'\e[1;37m'
DEFAULT_COLOR="${reset_color}"

##
# functions
[ -f ${ZDOTDIR}/.zshrc.functions ] && source ${ZDOTDIR}/.zshrc.functions

##
# zplug
# https://github.com/zplug/zplug
export ZPLUG_HOME=${HOME}/.cache/zplug
if [ ! -d ${ZPLUG_HOME} ]; then
  git clone https://github.com/zplug/zplug ${ZPLUG_HOME}
fi
if [ ! -e ${ZPLUG_HOME}/init.zsh.zwc -o ${ZPLUG_HOME}/init.zsh -nt ${ZPLUG_HOME}/init.zsh.zwc ]; then
  zcompile ${ZPLUG_HOME}/init.zsh
fi
source ${ZPLUG_HOME}/init.zsh
zplug "zsh-users/zsh-completions"
zplug "zsh-users/zsh-syntax-highlighting"
zplug "zsh-users/zsh-autosuggestions"
# if ! zplug check --verbose; then
#   zplug install
# fi
zplug load

##
# prompt
[ -f ${ZDOTDIR}/.zshrc.prompt ] && source ${ZDOTDIR}/.zshrc.prompt

##
# VCS
autoload -Uz vcs_info
zstyle ":vcs_info:*" enable git svn hg
zstyle ":vcs_info:*" formats "⭠ %b"
zstyle ":vcs_info:*" actionformats "[%b|%a]"
zstyle ":vcs_info:(svn)" branchformat "%b%r"
zstyle ":vcs_info:*" max-exports 6

##
# history
HISTFILE=${ZDOTDIR}/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt bang_hist
setopt extended_history
setopt share_history
setopt append_history
setopt hist_save_no_dups
setopt hist_ignore_all_dups
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_verify
setopt hist_no_store
setopt hist_expand
setopt hist_reduce_blanks

##
# complement
autoload -U compinit
compinit -d
zstyle ':completion:*' verbose yes
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

##
# change directory
setopt auto_cd
autoload -Uz add-zsh-hook
autoload -Uz chpwd_recent_dirs cdr
add-zsh-hook chpwd chpwd_recent_dirs

##
# options
setopt auto_pushd
setopt auto_list
setopt auto_menu
setopt list_packed
setopt list_types
setopt print_eight_bit
setopt equals
setopt magic_equal_subst
setopt prompt_subst

##
# Linuxbrew
if [ -d /home/linuxbrew ]; then
  eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)
fi

##
# Homebrew & Linuxbrew
if command::exist brew; then
  FZF_PATH=$(brew --prefix fzf)
  if [ -e $FZF_PATH ]; then
    source $FZF_PATH/shell/completion.zsh
    source $FZF_PATH/shell/key-bindings.zsh
  fi
fi

##
# direnv
if command::exist direnv; then
  eval "$(direnv hook zsh)"
fi

##
# rbenv
if command::exist rbenv; then
  eval "$(rbenv init - zsh)"
fi

##
# bindkeys
bindkey -e
bindkey "^[[Z" reverse-menu-complete
bindkey "^S" history-incremental-search-forward
bindkey "^R" fzf-history-widget
bindkey "^xb" widget::fzf::cdr
bindkey "^xo" widget::fzf::workspace

##
# alias
[ -f ${ZDOTDIR}/.zshrc.aliases ] && source ${ZDOTDIR}/.zshrc.aliases

##
# local
[ -f ${ZDOTDIR}/.zshrc.local ] && source ${ZDOTDIR}/.zshrc.local

# if (which zprof > /dev/null 2>&1) ;then
#   zprof
# fi

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
