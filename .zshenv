setopt combiningchars
setopt no_global_rcs

export PATH=${HOME}/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export ZDOTDIR=${HOME}/.zsh

#######################################
# Homebrew
#######################################
export PATH=${HOME}/.brew/sbin:${HOME}/.brew/bin:$PATH

#######################################
# rbenv
#######################################
export RBENV_ROOT=${HOME}/.rbenv
export PATH=${RBENV_ROOT}/bin:${RBENV_ROOT}/shims:$PATH

#######################################
# pyenv
#######################################
export PYENV_ROOT=${HOME}/.pyenv
export PATH=${PYENV_ROOT}/bin:${PYENV_ROOT}/shims:${PATH}

#######################################
# go & goenv
#######################################
export GOENV_ROOT=${HOME}/.goenv
export PATH=${GOENV_ROOT}/bin:${HOME}/go/bin:${PATH}

#######################################
# tfenv
#######################################
export TFENV_ROOT=${HOME}/.tfenv
export PATH=${TFENV_ROOT}/bin:${PATH}

#######################################
# Local
#######################################
[ -f ${HOME}/.zsh/.zshenv.local ] && source ${HOME}/.zsh/.zshenv.local
