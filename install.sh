#!/bin/sh

# make ~/.config
home_config_path=${HOME}/.config
[ ! -d ${home_config_path} ] && mkdir ${home_config_path}

# make ~/.cache
home_cache_path=${HOME}/.cache
[ ! -d ${home_cache_path} ] && mkdir ${home_cache_path}

# make ~/bin
home_bin_path=${HOME}/bin
[ ! -d ${home_bin_path} ] && mkdir ${home_bin_path}
find ${PWD}/bin/* -type f | xargs -I BIN ln -sf BIN ${home_bin_path}

# Donwload Neovim
nvim_path=${home_cache_path}/nvim
if [ ! -d ${nvim_path} ]; then
    # TODO: md5 check
    # TODO: support linux

    nvim_archive_url='https://github.com/neovim/neovim/releases/download/v0.3.1/nvim-macos.tar.gz'
    nvim_archive_digest=''
    nvim_archive_path=${PWD}/tmp/nvim.tar.gz
    wget -O ${nvim_archive_path} ${nvim_archive_url}

    [ ! -d ${nvim_path} ] && mkdir ${nvim_path}
    tar xvf ${nvim_archive_path} -C ${nvim_path} --strip-components 1

    rm -f ${nvim_archive_path}
fi
nvim_bin_path=${home_bin_path}/nvim
if [ ! -x ${nvim_bin_path} ]; then
    ln -s ${nvim_path}/bin/nvim ${nvim_bin_path}
fi

# Put Neovim configurations
nvim_cfg_dir_path=${home_config_path}/nvim
pwd_nvim_cfg_dir_path=${PWD}/.config/nvim
[ ! -d ${nvim_cfg_dir_path} ] && mkdir ${nvim_cfg_dir_path}
[ ! -d ${nvim_cfg_dir_path}/ftplugin ] && mkdir ${nvim_cfg_dir_path}/ftplugin
find ${pwd_nvim_cfg_dir_path}/.* -type f | xargs -I PLUG ln -sf PLUG ${nvim_cfg_dir_path}/
ln -sf ${pwd_nvim_cfg_dir_path}/filetype.vim ${nvim_cfg_dir_path}/
ln -sf ${pwd_nvim_cfg_dir_path}/.dein.toml ${nvim_cfg_dir_path}/
ln -sf ${pwd_nvim_cfg_dir_path}/.dein_lazy.toml ${nvim_cfg_dir_path}/

# Put Tmux configurations
tmux_cfg_dir_path=${home_config_path}/tmux
pwd_tmux_cfg_dir_path=${PWD}/.config/tmux
ln -sf ${PWD}/.tmux.conf ${HOME}/
[ ! -d ${tmux_cfg_dir_path} ] && mkdir ${tmux_cfg_dir_path}
find ${pwd_tmux_cfg_dir_path} -type f | xargs -I PLUG ln -sf PLUG ${tmux_cfg_dir_path}/

# Put Git conifugrations
git_cfg_dir_path=${home_config_path}/git
pwd_git_cfg_dir_path=${PWD}/.config/git
ln -sf ${PWD}/.gitconfig ${HOME}/
[ ! -d ${git_cfg_dir_path} ] && mkdir ${git_cfg_dir_path}
find ${pwd_git_cfg_dir_path} -type f | xargs -I PLUG ln -sf PLUG ${git_cfg_dir_path}/
touch ${git_cfg_dir_path}/local

# Put zsh configuration
ln -sf ${PWD}/.zshenv ${HOME}/
zdir=${home_config_path}/zsh
[ ! -d ${zdir} ] && mkdir ${zdir}
find ${PWD}/.config/zsh -type f -name ".[^.]*" | xargs -I FILE ln -sf FILE ${zdir}
touch ${zdir}/.zshrc.local

# Powerline Fonts
if [ "$(uname)" == 'Darwin'  ]; then
    if [ "$(ls ${HOME}/Library/Fonts | grep -i powerline)" == "" ]; then
        echo 'Installing powerline fonts...'
        git clone https://github.com/powerline/fonts.git
        cd fonts && ./install.sh && cd .. && rm -rf fonts
    fi

    if [ ! -d ${HOME}/.brew ]; then
        echo 'Installing homebrew...'
        brew_dir=${HOME}/.brew
        mkdir $brew_dir && curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C $brew_dir
    fi
fi

# rbenv
rbenv_dir_path=${HOME}/.rbenv
if [ ! -d ${rbenv_dir_path} ]; then
    echo 'Installing rbenv...'
    git clone https://github.com/rbenv/rbenv.git ${rbenv_dir_path}
    git clone git://github.com/sstephenson/ruby-build.git ${rbenv_dir_path}/plugins/ruby-build
fi

# irb
ln -sf ${PWD}/.irbrc ${HOME}/

# pyenv
pyenv_dir_path=${HOME}/.pyenv
if [ ! -d ${pyenv_dir_path} ]; then
    echo 'Installing pyenv...'
    git clone https://github.com/yyuu/pyenv.git ${pyenv_dir_path}
    git clone https://github.com/yyuu/pyenv-virtualenv.git ${pyenv_dir_path}/plugins/pyenv-virtualenv
fi

# tfenv
tfenv_dir_path=${HOME}/.tfenv
if [ ! -d ${tfenv_dir_path} ]; then
    echo 'Installing tfenv...'
    git clone https://github.com/kamatama41/tfenv.git ${tfenv_dir_path}
fi

# goenv
goenv_dir_path=${HOME}/.goenv
if [ ! -d "${goenv_dir_path}" ]; then
    echo 'Installing goenv...'
    git clone https://github.com/syndbg/goenv.git ${goenv_dir_path}
fi
