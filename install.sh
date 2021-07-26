#!/usr/bin/env bash

# shellcheck disable=SC1091
# Load functions
source "$(dirname "$(dirname "$0")")/.config/zsh/.zshrc.functions"

set -Ceuo pipefail

_link_files() {
  local src_path="$1"
  local dest_path="$2"
  find $src_path  -maxdepth 1 -type f -name '*' -o -name '.*' | xargs -I FILE ln -sf FILE $dest_path
}

_make_directory() {
  local dpath="$1"
  if [ ! -d $dpath ]; then
    mkdir -p $dpath
  fi
}

main() {
  # make ~/.config
  local config_path=$HOME/.config
  _make_directory $config_path

  # make ~/.cache
  local cache_path=$HOME/.cache
  _make_directory $cache_path

  # make ~/bin
  local bin_path=$HOME/bin
  _make_directory $bin_path
  _link_files $PWD/bin $bin_path

  # Put Neovim configurations
  local nvim_cfg_dir_path=$config_path/nvim
  local pwd_nvim_cfg_dir_path=$PWD/.config/nvim
  _make_directory $nvim_cfg_dir_path
  _make_directory $nvim_cfg_dir_path/ftplugin
  _link_files $pwd_nvim_cfg_dir_path $nvim_cfg_dir_path/
  _link_files $pwd_nvim_cfg_dir_path/ftplugin $nvim_cfg_dir_path/ftplugin
  ln -sf $pwd_nvim_cfg_dir_path/filetype.vim $nvim_cfg_dir_path/
  ln -sf $pwd_nvim_cfg_dir_path/dein.toml $nvim_cfg_dir_path/
  ln -sf $pwd_nvim_cfg_dir_path/dein_lazy.toml $nvim_cfg_dir_path/

  # Put Tmux configurations
  local tmux_cfg_dir_path=$config_path/tmux
  ln -sf $PWD/.tmux.conf $HOME/
  _make_directory $tmux_cfg_dir_path
  _link_files $PWD/.config/tmux $tmux_cfg_dir_path/

  # Put Git conifugrations
  local git_cfg_dir_path=$config_path/git
  ln -sf $PWD/.gitconfig $HOME/
  _make_directory $git_cfg_dir_path
  _link_files $PWD/.config/git $git_cfg_dir_path/
  touch $git_cfg_dir_path/local

  # Put zsh configuration
  ln -sf $PWD/.zshenv $HOME/
  local zdir=$config_path/zsh
  _make_directory $zdir
  _link_files $PWD/.config/zsh $zdir
  touch $zdir/.zshrc.local

  # direnv
  ln -sf $PWD/.direnvrc $HOME/

  # Ruby
  ln -sf $PWD/.gemrc $HOME/
  ln -sf $PWD/.irbrc $HOME/

  ###
  # for macOS
  if os::is_darwin; then
    ###
    # Powerline Fonts
    if [ "$(ls $HOME/Library/Fonts | grep -i powerline)" == "" ]; then
      logger:info 'Installing powerline fonts...'
      git clone https://github.com/powerline/fonts.git
      cd fonts && ./install.sh && cd .. && rm -rf fonts
    fi

    ###
    # Homebrew
    local brew_dir_path=$HOME/.brew
    if [ ! -d $brew_dir_path ]; then
      logger:info 'Installing homebrew...'
      mkdir $brew_dir_path \
        && curl -L https://github.com/Homebrew/brew/tarball/master \
        | tar xz --strip 1 -C $brew_dir_path
    fi
    $brew_dir_path/bin/brew bundle --no-lock --file ./brewfiles/darwin/Brewfile
  fi

  ###
  # For Linux
  if os::is_ubuntu; then
    ###
    # Install packages
    logger::info "Install system packages"
    sudo apt-get update \
      && sudo apt-get upgrade \
      && sudo apt-get install -y build-essential locales-all

    ###
    # Linuxbrew
    if [ ! -d /home/linuxbrew ]; then
      logger:info "Installing linuxbrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    fi
    /home/linuxbrew/.linuxbrew/bin/brew bundle --no-lock --file ./brewfiles/ubuntu/Brewfile
  fi

  if os::is_wsl; then
    local win32yank_path=$HOME/bin/win32yank.exe
    if [ ! -e $win32yank_path ]; then
      echo "hoge"
      wget -O tmp/win32yank.zip https://github.com/equalsraf/win32yank/releases/download/v0.0.4/win32yank-x64.zip
      unzip -d tmp tmp/win32yank.zip
      mv tmp/win32yank.exe $win32yank_path
      chmod u+x $win32yank_path
      rm -f tmp/win32yank.zip tmp/LICENSE tmp/README.md
    fi
  fi
}
main "$@"
