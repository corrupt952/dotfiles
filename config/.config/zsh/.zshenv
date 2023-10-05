# Locale
export LANG=en_US.UTF-8

# Terminal
export TERM=xterm-256color
export GPG_TTY=$TTY

# XDG
export XDG_CONFIG_HOME=$HOME/.config
export XDG_CACHE_HOME=$HOME/.cache
export XDG_DATA_HOME=$HOME/.local/share
export XDG_STATE_HOME="$HOME/.local/state"

# PATH
setopt NO_GLOBAL_RCS
typeset -gU path
typeset -gU fpath
path=(/usr/local/bin /usr/bin /bin /usr/sbin /sbin)
fpath=($HOME/.config/zsh/functions "$fpath[@]")

# Dotfiles
export DOT_BIN_PATH=$HOME/.local/bin
path+=($DOT_BIN_PATH)

# Home directory
path+=($HOME/bin)

# zinit
export ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
path+=($ZINIT_HOME/bin)

# for Snapd
if [ -d /var/lib/snapd/snap ]; then
  path+=("/var/lib/snapd/snap/bin")
fi

# Homebrew or Linuxbrew
# for Homebrew
if [ -d $HOME/.brew ]; then
  fpath=(/usr/local/share/zsh/site-functions $fpath)
  path=($HOME/.brew/bin $HOME/.brew/sbin $path)
fi
if [ -d /home/linuxbrew/.linuxbrew ]; then
  fpath=(/home/linuxbrew/.linuxbrew/share/zsh/site-functions $fpath)
  path=("/home/linuxbrew/.linuxbrew/bin" "/home/linuxbrew/.linuxbrew/sbin" $path)
fi

# VSCode
if [ -d $HOME/.vscode-server ]; then
  for vspath in "$(ls -1d $HOME/.vscode-server/bin/*)"; do
    path+=("$vspath/bin")
  done
fi

# fzf
export FZF_DEFAULT_OPTS="--exact --cycle --ansi --height 70% --reverse"

# aqua
path=("${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}/bin" $path)

# Node.js
export N_PREFIX=$XDG_CACHE_HOME/n
path=($N_PREFIX/bin $path)

# Flutter
export FLUTTER_PREFIX=$XDG_CACHE_HOME/flutter
path=($FLUTTER_PREFIX/bin $path)

# Dart
path=($HOME/.dart-sdk/bin $path)

# zeno
export ZENO_HOME="$XDG_CONFIG_HOME/zeno"
export ZENO_ENABLE_SOCK=1
export ZENO_GIT_CAT="cat"
export ZENO_GIT_TREE="tree"

# Editor
if [[ -n "$(command -v code)" ]]; then
  export EDITOR="$(printf %q "$(command -v code)")"
else
  export EDITOR="$(printf %q "$(command -v vim)")"
fi

# XCode Command Line Tools
if [[ -n "$(command -v xcode-select)" ]]; then
  path+=($(xcode-select -p)/usr/bin)
fi
