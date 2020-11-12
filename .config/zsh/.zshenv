setopt combiningchars
setopt no_global_rcs

typeset -gU PATH

###
# Terminal variables
export TERM=xterm-256color

###
# Path variables
export fpath=($HOME/.config/zsh/functions $fpath)
export PATH=$HOME/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

###
# Language variables
export LANG=ja_JP.UTF-8

###
# Editor
export EDITOR=$(where vim)

###
# for Snapd
if [ -d /var/lib/snapd/snap ]; then
    export PATH=/var/lib/snapd/snap/bin:$PATH
fi

###
# for Homebrew
if [ -d $HOME/.brew ]; then
    export PATH=$HOME/.brew/sbin:$HOME/.brew/bin:$PATH
fi

###
# for Linuxbrew
if [ -d /home/linuxbrew/.linuxbrew ]; then
    export PATH=/home/linuxbrew/.linuxbrew/bin:$PATH
fi

###
# for tfenv
if [ -d $HOME/.tfenv ]; then
    export TFENV_ROOT=$HOME/.tfenv
    export PATH=$TFENV_ROOT/bin:$PATH
fi

###
# Local variables
[ -f ${ZDOTDIR}/.zshenv.local ] && source ${ZDOTDIR}/.zshenv.local
