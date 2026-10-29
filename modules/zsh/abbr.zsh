typeset -gA _abbr_command=(
  bvim     'vim -b'
  c        'code'
  clip     'command::clip'
  dk       'docker'
  dkc      'docker compose'
  g        'git'
  gd       'git fdelete'
  gr       'grep'
  gs       'git fselect'
  k        'kubectl'
  kctx     'kubectx'
  kns      'kubens'
  l        'ls'
  ll       'ls -lh'
  loop     'command::loop'
  reboot   'sudo reboot'
  reload   'exec zsh -l'
  shutdown 'sudo shutdown'
  tf       'terraform'
  tk       'tmuxist'
  vi       'vim'
)

typeset -gA _abbr_global=(
  G     '| grep'
  now   '$(date "+%Y-%m-%dT%H:%M:%S%z")'
  today '$(date "+%Y-%m-%d")'
)

abbr::expand() {
  local word=${LBUFFER##*[[:space:]]}
  local prefix=${LBUFFER%"$word"}
  local head=${prefix%"${prefix##*[![:space:]]}"}

  if (( ${+_abbr_global[$word]} )); then
    LBUFFER=$prefix${_abbr_global[$word]}
  elif (( ${+_abbr_command[$word]} )) && [[ -z $head || $head == *[\|\;\&] ]]; then
    LBUFFER=$prefix${_abbr_command[$word]}
  fi
}

abbr::space() {
  abbr::expand
  zle self-insert
}

abbr::accept-line() {
  abbr::expand
  zle accept-line
}

zle -N abbr::space
zle -N abbr::accept-line
bindkey ' ' abbr::space
bindkey '^M' abbr::accept-line
bindkey -M isearch ' ' self-insert
