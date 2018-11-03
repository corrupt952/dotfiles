# Setup fzf
# ---------
if [[ ! "$PATH" == */Users/kazuki/.brew/opt/fzf/bin* ]]; then
  export PATH="$PATH:/Users/kazuki/.brew/opt/fzf/bin"
fi

# Auto-completion
# ---------------
[[ $- == *i* ]] && source "/Users/kazuki/.brew/opt/fzf/shell/completion.zsh" 2> /dev/null

# Key bindings
# ------------
source "/Users/kazuki/.brew/opt/fzf/shell/key-bindings.zsh"
