#!/bin/sh
ZSH_LOCAL_PATH=${HOME}/.zshrc.local

# make ~/.config
HOME_CONFIG_PATH=${HOME}/.config
[ ! -d ${HOME_CONFIG_PATH} ] && mkdir ${HOME_CONFIG_PATH}

# make ~/.cache
HOME_CACHE_PATH=${HOME}/.cache
[ ! -d ${HOME_CACHE_PATH} ] && mkdir ${HOME_CACHE_PATH}

# make ~/bin
HOME_BIN_PATH=${HOME}/bin
[ ! -d ${HOME_BIN_PATH} ] && mkdir ${HOME_BIN_PATH}
find ${PWD}/bin/* -type f | xargs -I BIN ln -sf BIN ${HOME_BIN_PATH}

# Donwload Neovim
NVIM_PATH=${HOME_CACHE_PATH}/nvim
if [ ! -d ${NVIM_PATH} ]; then
    NVIM_ARCHIVE_URL='https://github.com/neovim/neovim/releases/download/v0.3.1/nvim-macos.tar.gz'
    NVIM_ARCHIVE_DIGEST=''
    NVIM_ARCHIVE_PATH=${PWD}/tmp/nvim.tar.gz
    wget -O ${NVIM_ARCHIVE_PATH} ${NVIM_ARCHIVE_URL}
    # TOOD: md5 check

    [ ! -d ${NVIM_PATH} ] && mkdir ${NVIM_PATH}
    tar xvf ${NVIM_ARCHIVE_PATH} -C ${NVIM_PATH} --strip-components 1

    rm -f ${NVIM_ARCHIVE_PATH}
fi
NVIM_BIN_PATH=${HOME_BIN_PATH}/nvim
if [ ! -x ${NVIM_BIN_PATH} ]; then
    ln -s ${NVIM_PATH}/bin/nvim ${NVIM_BIN_PATH}
fi

# Put Tmux configurations
ln -sf ${PWD}/.tmux.conf ${HOME}/
ln -sf ${PWD}/.tmux.darwin.conf ${HOME}/
touch ${HOME}/.tmux.conf.local

# Put Git conifugrations
ln -sf ${PWD}/.gitignore ${HOME}/
ln -sf ${PWD}/.gitconfig ${HOME}/
touch ${HOME}/.gitconfig.local

# Put Vim(Neovim) configurations
ln -sf ${PWD}/.vimrc ${HOME}/
[ ! -d ${HOME}/.vim ] && mkdir ${HOME}/.vim
[ ! -d ${HOME}/.vim/ftplugin ] && mkdir ${HOME}/.vim/ftplugin
find ${PWD}/.vim/ftplugin/* -type f | xargs -I PLUG ln -sf PLUG ${HOME}/.vim/ftplugin/
ln -sf ${PWD}/.vim/filetype.vim ${HOME}/.vim/
ln -sf ${PWD}/.vim ${HOME_CONFIG_PATH}/nvim
ln -sf ${PWD}/.dein.toml ${HOME}/
ln -sf ${PWD}/.dein_lazy.toml ${HOME}/

# Zsh
ln -sf ${PWD}/.zshenv ${HOME}/
ZDIR=${HOME}/.zsh
[ ! -d ${ZDIR} ] && mkdir ${ZDIR}
find ${PWD}/.zsh -type f -name ".[^.]*" | xargs -I PLUG ln -sf PLUG ${ZDIR}

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

        echo 'Set homebrew environment variables...'
        echo '# Homebrew' >> ${ZSH_LOCAL_PATH}
        echo 'export PATH=${HOME}/.brew/sbin:${HOME}/.brew/bin:$PATH' >> ${ZSH_LOCAL_PATH}
    fi
fi

# rbenv
RBENV_DIR=${HOME}/.rbenv
if [ ! -d ${RBENV_DIR} ]; then
    echo 'Installing rbenv...'
    git clone https://github.com/rbenv/rbenv.git ${RBENV_DIR}
    git clone git://github.com/sstephenson/ruby-build.git ${RBENV_DIR}/plugins/ruby-build

    echo 'Set rbenv environment variables...'
    echo '# rbenv' >> ${ZSH_LOCAL_PATH}
    echo "export RBENV_ROOT=${RBENV_DIR}" >> ${ZSH_LOCAL_PATH}
    echo 'export PATH=${RBENV_ROOT}/bin:${RBENV_ROOT}/shims:$PATH' >> ${ZSH_LOCAL_PATH}
    echo 'eval "$(rbenv init -)"' >> ${ZSH_LOCAL_PATH}
fi

# irb
ln -sf ${PWD}/.irbrc ${HOME}/

# pyenv
PYENV_DIR=${HOME}/.pyenv
if [ ! -d ${PYENV_DIR} ]; then
    echo 'Installing pyenv...'
    git clone https://github.com/yyuu/pyenv.git ${PYENV_DIR}
    git clone https://github.com/yyuu/pyenv-virtualenv.git ${PYENV_DIR}/plugins/pyenv-virtualenv

    echo 'Set pyenv environment variables...'
    echo '# pyenv' >> ${ZSH_LOCAL_PATH}
    echo "export PYENV_ROOT=${PYENV_DIR}" >> ${ZSH_LOCAL_PATH}
    echo 'export PATH=${PYENV_ROOT}/bin:${PYENV_ROOT}/shims:${PATH}' >> ${ZSH_LOCAL_PATH}
    echo 'eval "$(pyenv init -)"' >> ${ZSH_LOCAL_PATH}
    echo 'eval "$(pyenv virtualenv-init -)"' >> ${ZSH_LOCAL_PATH}
fi
