# Setup fzf
# ---------
if [[ ! "$PATH" == *${HOME}/.brew/opt/fzf/bin* ]]; then
  export PATH="$PATH:${HOME}/.brew/opt/fzf/bin"
fi

# Auto-completion
# ---------------
[[ $- == *i* ]] && source "${HOME}/.brew/opt/fzf/shell/completion.zsh" 2> /dev/null

# Key bindings
# ------------
source "${HOME}/.brew/opt/fzf/shell/key-bindings.zsh"
