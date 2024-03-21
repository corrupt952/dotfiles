#!/bin/bash

set -Ceuo pipefail

# TODO: load from .zshenv
export XDG_CONFIG_HOME=$HOME/.config
export XDG_CACHE_HOME=$HOME/.cache
export XDG_DATA_HOME=$HOME/.local/share
export XDG_STATE_HOME="$HOME/.local/state"
export ZINIT_HOME="$XDG_DATA_HOME/zinit/zinit.git"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"

# Homebrew or Linuxbrew
if [ "$(uname -s)" = "Darwin" ]; then
  BREW_PATH=$HOME/.brew
  if [ ! -d "$BREW_PATH" ]; then
    mkdir "$BREW_PATH"
    curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C "$BREW_PATH"
  fi
elif [ "$(uname -s)" = "Linux" ]; then
  [ -z "$(dpkg --get-selections | grep sudo)" ] && apt-get install -y sudo
  [ -z "$(dpkg --get-selections | grep curl)" ] && sudo apt-get install -y curl
  [ -z "$(dpkg --get-selections | grep git)" ] && sudo apt-get install -y git
  [ -z "$(dpkg --get-selections | grep g++)" ] && sudo apt-get install -y build-essential

  BREW_PATH=/home/linuxbrew/.linuxbrew
  if [ ! -d $BREW_PATH ]; then
    bash <(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)
  fi
fi

export PATH="$HOME/.local/share/aquaproj-aqua/bin:$BREW_PATH/bin:$PATH"
brew install aquaproj/aqua/aqua
aqua i
mitamae local recipe.rb