#!/bin/sh -o noglob

# Link files maxdepth 1
symlink_files() {
    find $1 -type f -maxdepth 1 -name '*' -o -name '.*' | xargs -I FILE ln -sf FILE $2
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

# Donwload Neovim
nvim_path=${home_cache_path}/nvim
if [ ! -d ${nvim_path} ]; then
    # TODO: md5 check
    # TODO: support linux

    nvim_archive_url='https://github.com/neovim/neovim/releases/download/v0.3.7/nvim-macos.tar.gz'
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
symlink_files ${pwd_nvim_cfg_dir_path}/ ${nvim_cfg_dir_path}/
symlink_files ${pwd_nvim_cfg_dir_path}/ftplugin/ ${nvim_cfg_dir_path}/ftplugin
ln -sf ${pwd_nvim_cfg_dir_path}/filetype.vim ${nvim_cfg_dir_path}/
ln -sf ${pwd_nvim_cfg_dir_path}/.dein.toml ${nvim_cfg_dir_path}/
ln -sf ${pwd_nvim_cfg_dir_path}/.dein_lazy.toml ${nvim_cfg_dir_path}/

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
symlink_files ${pwd_git_cfg_dir_path}/ ${git_cfg_dir_path}/
touch ${git_cfg_dir_path}/local

# Put zsh configuration
ln -sf ${PWD}/.zshenv ${HOME}/
zdir=${home_config_path}/zsh
[ ! -d ${zdir} ] && mkdir ${zdir}
symlink_files ${PWD}/.config/zsh/ ${zdir}
touch ${zdir}/.zshrc.local

# Put zsh functions
zsh_function_dir=${zdir}/functions
[ ! -d ${zsh_function_dir} ] && mkdir ${zsh_function_dir}
symlink_files ${PWD}/.config/zsh/functions/ ${zsh_function_dir}

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

# Wallpaper
wallpaper_cfg_dir_path=${home_config_path}/wallpaper
pwd_wallpaper_cfg_dir_path=${PWD}/.config/wallpaper
[ ! -d ${wallpaper_cfg_dir_path} ] && mkdir ${wallpaper_cfg_dir_path}
symlink_files ${pwd_wallpaper_cfg_dir_path} ${wallpaper_cfg_dir_path}/

# irb
ln -sf ${PWD}/.irbrc ${HOME}/

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
