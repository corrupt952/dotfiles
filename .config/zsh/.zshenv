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
export EDITOR=$(which vim)

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
# fzf
export FZF_DEFAULT_OPTS="--exact --cycle --ansi"

###
# Local variables
[ -f ${ZDOTDIR}/.zshenv.local ] && source ${ZDOTDIR}/.zshenv.local
