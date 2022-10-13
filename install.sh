#!/usr/bin/env zsh

# Load functions
source "$(dirname "$(dirname "$0")")/.config/zsh/.zshenv"
source "$(dirname "$(dirname "$0")")/.config/zsh/.zshrc.functions"

set -Ceuo pipefail

if os::is_ubuntu; then
  builder::execute sudo apt-get update
  builder::package ca-certificates build-essential locales-all git curl wget x11-xkb-utils fonts-ipafont fonts-ipaexfont
fi

# Homebrew or Linuxbrew
local BREW_PATH
if os::is_darwin; then
  BREW_PATH=$HOME/.brew
  if [ ! -d $BREW_PATH ]; then
    builder::directory $BREW_PATH
    builder::execute 'curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C "$BREW_PATH"'
  fi
elif os::is_ubuntu; then
  BREW_PATH=/home/linuxbrew/.linuxbrew
  if [ ! -d $BREW_PATH ]; then
    builder::execute 'bash <(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)'
  fi
fi
builder::execute "$BREW_PATH/bin/brew bundle --file=$PWD/Brewfile --cleanup"

builder::directory $XDG_CONFIG_HOME
builder::directory $XDG_CACHE_HOME
builder::directory $HOME/bin
builder::directory $HOME/.local
builder::link $PWD/bin $DOT_BIN_PATH

# Zsh
builder::link $PWD/.zshenv $HOME/.zshenv
builder::link $PWD/.config/zsh $XDG_CONFIG_HOME/zsh
builder::touch $XDG_CONFIG_HOME/zsh/.zshrc.local
builder::git https://github.com/zdharma-continuum/zinit $ZINIT_HOME
# zeno
builder::link $PWD/.config/zeno $XDG_CONFIG_HOME/zeno
# tmux
builder::link $PWD/.tmux.conf $HOME/.tmux.conf
builder::link $PWD/.config/tmux $XDG_CONFIG_HOME/tmux
# Git
builder::link $PWD/.gitconfig $HOME/.gitconfig
builder::link $PWD/.config/git $XDG_CONFIG_HOME/git
builder::touch $XDG_CONFIG_HOME/git/local
# Direnv
builder::link $PWD/.direnvrc $HOME/.direnvrc
# Ruby
builder::link $PWD/.gemrc $HOME/.gemrc
builder::link $PWD/.irbrc $HOME/.irbrc

# win32yanc
if os::is_wsl; then
  local win32yank_path=$HOME/bin/win32yank.exe
  if [ ! -e "$win32yank_path" ]; then
    wget -O tmp/win32yank.zip https://github.com/equalsraf/win32yank/releases/download/v0.0.4/win32yank-x64.zip
    unzip -d tmp tmp/win32yank.zip
    mv tmp/win32yank.exe "$win32yank_path"
    chmod u+x "$win32yank_path"
    rm -f tmp/win32yank.zip tmp/LICENSE tmp/README.md
  fi
fi
