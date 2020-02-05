setopt combiningchars
setopt no_global_rcs

typeset -U path PATH

export PATH=${HOME}/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export fpath=(${HOME}/.config/zsh/functions $fpath)

#
# tfenv
#
export TFENV_ROOT=${HOME}/.tfenv
export PATH=${TFENV_ROOT}/bin:${PATH}

if test "$(uname -s)" = "Darwin"; then
    # Homebrew
    export PATH=${HOME}/.brew/lib/ruby/gems/2.6.0/bin:${HOME}/.brew/opt/ruby/bin:${HOME}/.brew/sbin:${HOME}/.brew/bin:$PATH
else
    # Linux Homebrew
    export PATH=/home/linuxbrew/.linuxbrew/bin:${PATH}

    # Snapd
    export PATH=/var/lib/snapd/snap/bin:${PATH}
fi

#
# Local
#
[ -f ${ZDOTDIR}/.zshenv.local ] && source ${ZDOTDIR}/.zshenv.local
