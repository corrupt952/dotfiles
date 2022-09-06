#!/usr/bin/env zsh

# Load functions
source "$(dirname "$(dirname "$0")")/.config/zsh/.zshenv"
source "$(dirname "$(dirname "$0")")/.config/zsh/.zshrc.functions"

set -Ceuo pipefail

if os::is_ubuntu; then
  builder::execute sudo apt-get update
  builder::package ca-certificates
  builder::package build-essential
  builder::package locales-all
  builder::package git
  builder::package curl
  builder::package wget

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
fi

builder::directory $DOT_CONFIG_PATH
builder::directory $DOT_CACHE_PATH
builder::directory $HOME/bin
builder::link $PWD/bin $DOT_BIN_PATH

# Zsh
builder::link $PWD/.zshenv $HOME/.zshenv
builder::link $PWD/.config/zsh $DOT_CONFIG_PATH/zsh
builder::touch $DOT_CONFIG_PATH/zsh/.zshrc.local
# tmux
builder::link $PWD/.tmux.conf $HOME/.tmux.conf
builder::link $PWD/.config/tmux $DOT_CONFIG_PATH/tmux
# Git
builder::link $PWD/.gitconfig $HOME/.gitconfig
builder::link $PWD/.config/git $DOT_CONFIG_PATH/git
builder::touch $DOT_CONFIG_PATH/git/local
# Direnv
builder::link $PWD/.direnvrc $HOME/.direnvrc
# Ruby
builder::link $PWD/.gemrc $HOME/.gemrc
builder::link $PWD/.irbrc $HOME/.irbrc

# Homebrew or Linuxbrew
local BREW_PATH
if os::is_darwin; then
  BREW_PATH=$HOME/.brew
  if [ ! -d $BREW_PATH ]; then
    builder::directory $BREW_PATH
    builder::execute curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C "$BREW_PATH"
  fi
elif os::is_ubuntu; then
  BREW_PATH=/home/linuxbrew/.linuxbrew
  if [ ! -d $BREW_PATH ]; then
    builder::execute /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
  fi
fi
builder::execute "$BREW_PATH/bin/brew bundle --file=$PWD/Brewfile"
