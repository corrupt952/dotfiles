#!/usr/bin/env bash

# Load functions
source "$(dirname "$(dirname "$0")")/.config/zsh/.zshrc.functions"

set -o pipefail
set -o errexit

###
# Define functions
symlink_files() {
  find $1  -maxdepth 1 -type f -name '*' -o -name '.*' | xargs -I FILE ln -sf FILE $2
}

# make ~/.config
home_config_path=${HOME}/.config
[ ! -d ${home_config_path} ] && mkdir ${home_config_path}

# make ~/.cache
home_cache_path=${HOME}/.cache
[ ! -d ${home_cache_path} ] && mkdir ${home_cache_path}

# make ~/bin
home_bin_path=${HOME}/bin
[ ! -d ${home_bin_path} ] && mkdir ${home_bin_path}
symlink_files ${PWD}/bin ${home_bin_path}

# Put Neovim configurations
nvim_cfg_dir_path=${home_config_path}/nvim
pwd_nvim_cfg_dir_path=${PWD}/.config/nvim
[ ! -d ${nvim_cfg_dir_path} ] && mkdir ${nvim_cfg_dir_path}
[ ! -d ${nvim_cfg_dir_path}/ftplugin ] && mkdir ${nvim_cfg_dir_path}/ftplugin
symlink_files ${pwd_nvim_cfg_dir_path} ${nvim_cfg_dir_path}/
symlink_files ${pwd_nvim_cfg_dir_path}/ftplugin ${nvim_cfg_dir_path}/ftplugin
ln -sf ${pwd_nvim_cfg_dir_path}/filetype.vim ${nvim_cfg_dir_path}/
ln -sf ${pwd_nvim_cfg_dir_path}/dein.toml ${nvim_cfg_dir_path}/
ln -sf ${pwd_nvim_cfg_dir_path}/dein_lazy.toml ${nvim_cfg_dir_path}/

# Put Tmux configurations
tmux_cfg_dir_path=${home_config_path}/tmux
pwd_tmux_cfg_dir_path=${PWD}/.config/tmux
ln -sf ${PWD}/.tmux.conf ${HOME}/
[ ! -d ${tmux_cfg_dir_path} ] && mkdir ${tmux_cfg_dir_path}
symlink_files ${pwd_tmux_cfg_dir_path} ${tmux_cfg_dir_path}/

# Put Git conifugrations
git_cfg_dir_path=${home_config_path}/git
pwd_git_cfg_dir_path=${PWD}/.config/git
ln -sf ${PWD}/.gitconfig ${HOME}/
[ ! -d ${git_cfg_dir_path} ] && mkdir ${git_cfg_dir_path}
symlink_files ${pwd_git_cfg_dir_path} ${git_cfg_dir_path}/
touch ${git_cfg_dir_path}/local

# Put zsh configuration
ln -sf ${PWD}/.zshenv ${HOME}/
zdir=${home_config_path}/zsh
[ ! -d ${zdir} ] && mkdir ${zdir}
symlink_files ${PWD}/.config/zsh ${zdir}
touch ${zdir}/.zshrc.local

# Put zsh functions
zsh_function_dir=${zdir}/functions
[ ! -d ${zsh_function_dir} ] && mkdir ${zsh_function_dir}
symlink_files ${PWD}/.config/zsh/functions ${zsh_function_dir}

###
# irbrc
ln -sf ${PWD}/.irbrc ${HOME}/

###
# for macOS
if os::is_darwin; then
  ###
  # Powerline Fonts
  if [ "$(ls ${HOME}/Library/Fonts | grep -i powerline)" == "" ]; then
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
  $brew_dir_path/bin/brew bundle --file ./brewfiles/darwin/Brewfile
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
  /home/linuxbrew/.linuxbrew/bin/brew bundle --file ./brewfiles/ubuntu/Brewfile
fi
