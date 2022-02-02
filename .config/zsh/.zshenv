setopt combiningchars
setopt no_global_rcs

typeset -gU PATH

###
# Terminal variables
export TERM=xterm-256color

###
# Path variables
export fpath=($HOME/.config/zsh/functions $fpath)
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

###
# Language variables
export LANG=ja_JP.UTF-8

###
# for Snapd
if [ -d /var/lib/snapd/snap ]; then
    export PATH=/var/lib/snapd/snap/bin:$PATH
fi

###
# for Homebrew
if [ -d $HOME/.brew ]; then
    export fpath=($HOME/.brew/share/zsh/site-functions $fpath)
    export PATH=$HOME/.brew/sbin:$HOME/.brew/bin:$PATH
fi

###
# for Linuxbrew
if [ -d /home/linuxbrew/.linuxbrew ]; then
    export PATH=/home/linuxbrew/.linuxbrew/sbin:/home/linuxbrew/.linuxbrew/bin:$PATH
fi

##
# VSCode
if [ -d $HOME/.vscode-server ]; then
  for vspath in "$(ls -1d $HOME/.vscode-server/bin/*)"; do
    export PATH=$vspath/bin:$PATH
  done
fi

###
# fzf
export FZF_DEFAULT_OPTS="--exact --cycle --ansi"

###
# Node.js
export N_PREFIX=$HOME/.cache/n
export PATH=$N_PREFIX/bin:$PATH

##
# Home bin path
export PATH=$HOME/bin:$PATH

###
# Local variables
[ -f ${ZDOTDIR}/.zshenv.local ] && source ${ZDOTDIR}/.zshenv.local

###
# Editor
if [[ -n "$(command -v code)" ]]; then
  export EDITOR="$(printf %q "$(command -v code)")"
else
  export EDITOR="$(printf %q "$(command -v vim)")"
fi
