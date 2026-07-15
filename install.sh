#!/bin/bash

set -Ceuo pipefail

# Speed up Homebrew (no auto-update, no cleanup, no analytics, no hints)
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_ANALYTICS=1

# ============================================================================
# Logging
# ============================================================================
c_blue='\033[00;34m'
c_green='\033[00;32m'
c_yellow='\033[0;33m'
c_red='\033[0;31m'
c_reset='\033[0m'

info() { printf "  [ %b..%b ] %s\n" "$c_blue" "$c_reset" "$*"; }
ok()   { printf "  [ %bOK%b ] %s\n" "$c_green" "$c_reset" "$*"; }
warn() { printf "  [ %b!!%b ] %s\n" "$c_yellow" "$c_reset" "$*"; }
fail() { printf "  [%bFAIL%b] %s\n" "$c_red" "$c_reset" "$*" >&2; exit 1; }

# ============================================================================
# DSL primitives
# ============================================================================
is_macos()  { [ "$(uname -s)" = "Darwin" ]; }
is_ubuntu() { [ "$(uname -s)" = "Linux" ] && [ -f /etc/lsb-release ] && grep -q Ubuntu /etc/lsb-release; }
has()       { command -v "$1" >/dev/null 2>&1; }

link() {
  local src=$1 dst=$2
  if [ ! -e "$src" ] && [ ! -L "$src" ]; then
    fail "link: source not found: $src"
  fi
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  ln -snf "$src" "$dst"
  ok "linked $dst -> $src"
}

directory() {
  [ -d "$1" ] && return 0
  mkdir -p "$1"
  ok "created $1"
}

touch_file() {
  [ -e "$1" ] && return 0
  touch "$1"
  ok "touched $1"
}

apt_install() {
  local pkg=$1
  dpkg -s "$pkg" >/dev/null 2>&1 && return 0
  sudo apt-get install -y "$pkg"
  ok "apt installed: $pkg"
}

git_clone() {
  local url=$1 dst=$2
  [ -d "$dst/.git" ] && return 0
  git clone "$url" "$dst"
  ok "cloned $url -> $dst"
}

cask_install() {
  local cask=$1
  if brew list --cask "$cask" >/dev/null 2>&1; then
    return 0
  fi
  # Skip if any of the cask's app artifacts already exist in /Applications
  local apps
  apps=$(brew info --cask --json=v2 "$cask" 2>/dev/null \
    | jq -r '.casks[0].artifacts[]?.app[]? | if type == "array" then .[0] else . end' 2>/dev/null \
    || echo "")
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    if [ -e "/Applications/$app" ]; then
      ok "cask present (manual): $cask ($app)"
      return 0
    fi
  done <<< "$apps"
  brew install --cask --appdir=/Applications "$cask"
  ok "installed cask: $cask"
}

# ============================================================================
# Config
# ============================================================================
DOTFILES_REPO="https://github.com/corrupt952/dotfiles"
DOTFILES_PATH="$HOME/Workspace/corrupt952/dotfiles"
DOTFILES_HOME="$DOTFILES_PATH/home"

# TODO: load from .zshenv
export XDG_CONFIG_HOME=$HOME/.config
export XDG_CACHE_HOME=$HOME/.cache
export XDG_DATA_HOME=$HOME/.local/share
export XDG_STATE_HOME="$HOME/.local/state"
export ZINIT_HOME="$XDG_DATA_HOME/zinit/zinit.git"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"

# ============================================================================
# Ubuntu prerequisites
# ============================================================================
if is_ubuntu; then
  has sudo || apt-get install -y sudo
  has curl || sudo apt-get install -y curl
  has git  || sudo apt-get install -y git
  has g++  || sudo apt-get install -y build-essential
fi

# ============================================================================
# Homebrew or Linuxbrew bootstrap
# ============================================================================
if is_macos; then
  BREW_PATH=$HOME/.brew
  if [ ! -d "$BREW_PATH" ]; then
    mkdir "$BREW_PATH"
    curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C "$BREW_PATH"
  fi
elif is_ubuntu; then
  BREW_PATH=/home/linuxbrew/.linuxbrew
  if [ ! -d "$BREW_PATH" ]; then
    bash <(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)
  fi
fi

export PATH="$BREW_PATH/bin:$PATH"

# ============================================================================
# Homebrew formulae (single-shot for parallel download)
# ============================================================================
info "installing brew formulae"
brew install \
  automake bat cmake coreutils curl direnv deno fzf grep gpg gnu-sed jq libtool \
  ripgrep tig tmux tree wget wimlib arp-scan gh htop mise ollama \
  corrupt952/tmuxist/tmuxist

# ============================================================================
# Ubuntu packages (apt + Docker)
# ============================================================================
if is_ubuntu; then
  info "updating apt"
  sudo apt-get update

  info "installing apt packages"
  for pkg in locales-all ca-certificates build-essential \
             fonts-ipafont fonts-ipaexfont x11-xkb-utils \
             zsh vim wget; do
    apt_install "$pkg"
  done

  info "setting up Docker repository"
  if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
  fi
  if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    # shellcheck disable=SC1091
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
  fi
  for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
    apt_install "$pkg"
  done

  sudo apt-get autoremove -y
fi

# ============================================================================
# Repos
# ============================================================================
info "cloning repositories"
git_clone "$DOTFILES_REPO" "$DOTFILES_PATH"
git_clone "https://github.com/zdharma-continuum/zinit.git" "$ZINIT_HOME"

# ============================================================================
# XDG directories
# ============================================================================
info "creating XDG directories"
directory "$XDG_CONFIG_HOME"
directory "$XDG_CACHE_HOME"
directory "$XDG_DATA_HOME"
directory "$XDG_STATE_HOME"

# ============================================================================
# Symlinks
# ============================================================================
info "creating symlinks"

# Claude Code
directory "$HOME/.claude"
link "$DOTFILES_HOME/.claude/hooks"         "$HOME/.claude/hooks"
link "$DOTFILES_HOME/.claude/output-styles" "$HOME/.claude/output-styles"
link "$DOTFILES_HOME/.claude/settings.json" "$HOME/.claude/settings.json"

# .local/bin
directory "$HOME/.local/bin"
link "$DOTFILES_HOME/.local/bin/tmux-kubectl" "$HOME/.local/bin/tmux-kubectl"
link "$DOTFILES_HOME/.local/bin/workspace"    "$HOME/.local/bin/workspace"

# Zsh
link "$DOTFILES_HOME/.zshenv"     "$HOME/.zshenv"
link "$DOTFILES_HOME/.config/zsh" "$ZDOTDIR"
touch_file "$ZDOTDIR/.zshrc.local"

# Zeno
link "$DOTFILES_HOME/.config/zeno" "$XDG_CONFIG_HOME/zeno"

# Tmux
link "$DOTFILES_HOME/.tmux.conf"   "$HOME/.tmux.conf"
link "$DOTFILES_HOME/.config/tmux" "$XDG_CONFIG_HOME/tmux"

# WezTerm
link "$DOTFILES_HOME/.config/wezterm" "$XDG_CONFIG_HOME/wezterm"

# OpenCode
directory "$XDG_CONFIG_HOME/opencode/plugins"
link "$DOTFILES_HOME/.config/opencode/plugins/wezterm-notify.ts" \
     "$XDG_CONFIG_HOME/opencode/plugins/wezterm-notify.ts"

# Git
link "$DOTFILES_HOME/.gitconfig"  "$HOME/.gitconfig"
link "$DOTFILES_HOME/.config/git" "$XDG_CONFIG_HOME/git"
touch_file "$XDG_CONFIG_HOME/git/local"

# direnv
link "$DOTFILES_HOME/.direnvrc" "$HOME/.direnvrc"

# Ruby
link "$DOTFILES_HOME/.gemrc" "$HOME/.gemrc"

# ============================================================================
# ~/.claude.json: merge dotfile-managed defaults (existing values win)
# ============================================================================
info "merging ~/.claude.json"
claude_base="$DOTFILES_HOME/.claude.base.json"
claude_target="$HOME/.claude.json"
if [ -f "$claude_target" ]; then
  jq -s '.[0] * .[1]' "$claude_base" "$claude_target" >| "$claude_target.tmp"
  mv "$claude_target.tmp" "$claude_target"
else
  cp "$claude_base" "$claude_target"
fi
ok "merged $claude_target"

# ============================================================================
# macOS
# ============================================================================
if is_macos; then
  info "installing macOS-only brew formulae"
  brew install mas cocoapods

  info "applying macOS defaults"
  # NSGlobalDomain
  defaults write NSGlobalDomain AppleInterfaceStyle Dark
  defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool true
  defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false

  # Menu bar clock
  defaults write com.apple.menuextra.clock Show24Hour -bool true
  defaults write com.apple.menuextra.clock ShowDayOfWeek -bool false
  defaults write com.apple.menuextra.clock ShowSeconds -bool false

  # Control Center
  defaults write com.apple.controlcenter "NSStatusItem Visible FocusModes" -bool false
  defaults write com.apple.controlcenter "NSStatusItem Visible BatteryShowPercentage" -bool false
  defaults write com.apple.controlcenter "NSStatusItem Visible NowPlaying" -bool false
  defaults write com.apple.controlcenter "NSStatusItem Visible Sound" -bool false
  defaults write com.apple.controlcenter "NSStatusItem Visible Bluetooth" -bool false
  defaults write com.apple.controlcenter "NSStatusItem Visible AirDrop" -bool false

  # Trackpad
  defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true

  # Mission Control
  defaults write com.apple.dock mru-spaces -bool false

  # Dock
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.dock show-recents -bool false
  defaults write com.apple.dock magnification -bool false
  defaults write com.apple.dock tilesize -int 64
  defaults write com.apple.dock largesize -int 64
  defaults write com.apple.dock orientation bottom
  defaults write com.apple.dock mineffect scale
  defaults write com.apple.dock launchanim -bool false

  # Finder
  defaults write com.apple.finder AppleShowAllExtensions -bool true
  defaults write com.apple.finder AppleShowAllFiles -bool true
  defaults write com.apple.finder CreateDesktop -bool false
  defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
  defaults write com.apple.finder ShowPathbar -bool true
  defaults write com.apple.finder ShowStatusBar -bool true

  # Apply changes
  killall Dock 2>/dev/null || true
  killall Finder 2>/dev/null || true
  killall SystemUIServer 2>/dev/null || true

  info "installing brew casks"
  # Browsers
  cask_install google-chrome
  cask_install firefox
  # Utilities
  cask_install 1password
  cask_install 1password-cli
  cask_install stats
  cask_install raycast
  cask_install obsidian
  cask_install tailscale
  # Editors & IDEs
  cask_install visual-studio-code
  cask_install cursor
  cask_install codex
  cask_install jetbrains-toolbox
  # Development
  cask_install flutter
  cask_install orbstack
  cask_install wezterm
  # Game Development
  cask_install unity-hub
  cask_install godot
  # Communication
  cask_install discord
  # AI
  cask_install comfyui
  # Entertainment
  cask_install steam

  # App Store
  if [ -t 0 ]; then
    printf 'Do you want to install apps from the App Store? [y/N]: '
    read -r answer
    if [[ "$answer" =~ ^[Yy] ]]; then
      info "installing App Store apps"
      mas install 409183694   # Keynote
      mas install 409201541   # Pages
      mas install 409203825   # Numbers
      mas install 408981434   # iMovie
      mas install 682658836   # GarageBand
      mas install 1246969117  # Steam Link
      mas install 497799835   # Xcode
      mas install 640199958   # Developer
      mas install 1631624924  # Final Cut Pro
      mas install 1615087040  # Logic Pro
      mas install 6746516157  # Compressor
      mas install 6746637089  # MainStage
      mas install 6746637149  # Motion
    fi
  fi
fi

ok "done"
