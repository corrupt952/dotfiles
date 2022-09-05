#!/usr/bin/env zsh

# Load functions
source "$(dirname "$(dirname "$0")")/.config/zsh/.zshenv"
source "$(dirname "$(dirname "$0")")/.config/zsh/.zshrc.functions"

set -Ceuo pipefail

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

if os::is_darwin; then
  # Homebrew
  local brew_dir_path=$HOME/.brew
  if [ ! -d "$brew_dir_path" ]; then
    builder::directory $brew_dir_path
    builder::execute curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C "$brew_dir_path"
  fi
  builder::execute "$brew_dir_path/bin/brew bundle --file=$PWD/Brewfile"
fi

# TODO: 
if os::is_ubuntu; then
  builder::execute apt-get update
  builder::package ca-certificates
  builder::package build-essential
  builder::package locales-all

  ##
  # Linuxbrew
  if [ ! -d /home/linuxbrew ]; then
    logger::info "Installing linuxbrew..."
    builder::execute /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
  fi
  builder::execute /home/linuxbrew/.linuxbrew/bin/brew bundle --no-lock --file ./brewfiles/ubuntu/Brewfile
fi

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
