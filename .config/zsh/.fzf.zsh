if isDarwin; then
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
else
    # Setup fzf
    # ---------
    if [[ ! "$PATH" == */home/kajiku/.fzf/bin* ]]; then
      export PATH="${PATH:+${PATH}:}/home/kajiku/.fzf/bin"
    fi

    # Auto-completion
    # ---------------
    [[ $- == *i* ]] && source "/home/kajiku/.fzf/shell/completion.zsh" 2> /dev/null

    # Key bindings
    # ------------
    source "/home/kajiku/.fzf/shell/key-bindings.zsh"
fi
