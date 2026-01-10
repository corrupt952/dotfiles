# Definitions
HOME_PATH = File.expand_path('~')
CURRENT_PATH = Dir.pwd
DOTFILES_REPO = 'https://github.com/corrupt952/dotfiles'
DOTFILES_PATH = File.join(HOME_PATH, 'Workspace', 'corrupt952', 'dotfiles')
DOTFILES_CONFIG_PATH = File.join(DOTFILES_PATH, 'config')
XDG_CONFIG_HOME = ENV.fetch('XDG_CONFIG_HOME', File.join(HOME_PATH, '.config'))
XDG_CACHE_HOME = ENV.fetch('XDG_CACHE_HOME', File.join(HOME_PATH, '.cache'))
XDG_DATA_HOME = ENV.fetch('XDG_DATA_HOME', File.join(HOME_PATH, '.local', 'share'))
XDG_STATE_HOME = ENV.fetch('XDG_STATE_HOME', File.join(HOME_PATH, '.local', 'state'))
ZDOTDIR = ENV.fetch('ZDOTDIR', File.join(HOME_PATH, '.config', 'zsh'))
ZINIT_HOME = ENV.fetch('ZINIT_HOME', File.join(HOME_PATH, '.zinit'))

define :touch, path: nil do
  path = File.expand_path(params[:path])
  execute "touch #{path}" do
    command "touch #{path}"
  end
end

# Ubuntu
result = run_command('[ "$(uname -s)" = "Linux" ] && [ -f /etc/lsb-release ] && grep -q Ubuntu /etc/lsb-release', error: false)
if result.success?
  execute 'apt update' do
    command 'sudo apt update'
  end

  %w(
    locales-all ca-certificates build-essential
    fonts-ipafont fonts-ipaexfont x11-xkb-utils
    zsh vim wget
  ).each do |package|
    package package do
      user 'root'
      action :install
    end
  end

  # Docker
  execute 'install keyrings' do
    command 'sudo install -m 0755 -d /etc/apt/keyrings'
  end
  execute 'curl docker.asc' do
    command 'sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc'
  end
  execute 'chmod docker.asc' do
    command 'sudo chmod a+r /etc/apt/keyrings/docker.asc'
  end
  execute 'Make docker.list' do
    command  <<~COMMAND
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    COMMAND
  end
  execute 'apt update' do
    command 'sudo apt update'
  end
  %w(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin).each do |package|
    package package do
      user 'root'
      action :install
    end
  end

  execute 'apt autoremove' do
    command 'sudo apt autoremove'
  end
end

# Homebrew
execute 'brew update' do
  command 'brew update'
end

%w(
  automake bat cmake coreutils curl direnv deno fzf grep gpg gnu-sed jq libtool
  ripgrep tig tmux tree wget wimlib arp-scan asdf aquaproj/aqua/aqua corrupt952/tmuxist/tmuxist
).each do |package|
  brew package do
    action :install
  end
end

# Configure dotfiles
git 'corrupt952/dotfiles' do
  not_if { File.exist?(DOTFILES_PATH) }

  repository DOTFILES_REPO
  destination DOTFILES_PATH
end

# Configure XDGs
directory XDG_CONFIG_HOME do
  action :create
end
directory XDG_CACHE_HOME do
  action :create
end
directory XDG_DATA_HOME do
  action :create
end
directory XDG_STATE_HOME do
  action :create
end

# Claude Code
directory File.join(HOME_PATH, '.claude') do
  action :create
end
symlink File.join(HOME_PATH, '.claude', 'commands') do
  source File.join(DOTFILES_CONFIG_PATH, '.claude', 'commands')
  force true
end

# .local/bin
directory File.join(HOME_PATH, '.local') do
  action :create
end
symlink File.join(HOME_PATH, '.local', 'bin') do
  source File.join(DOTFILES_CONFIG_PATH, '.local', 'bin')
  force true
end

# # Zsh
symlink File.join(HOME_PATH, '.zshenv') do
  source File.join(DOTFILES_CONFIG_PATH, '.zshenv')
  force true
end
symlink ZDOTDIR do
  source File.join(DOTFILES_CONFIG_PATH, '.config', 'zsh')
  force true
end
touch '.zshrc.local' do
  path File.join(ZDOTDIR, '.zshrc.local')
end
git 'zinit' do
  not_if { File.exist?(ZINIT_HOME) }

  repository 'https://github.com/zdharma-continuum/zinit.git'
  destination ZINIT_HOME
end
symlink File.join(XDG_CONFIG_HOME, 'zeno') do
  source File.join(DOTFILES_CONFIG_PATH, '.config', 'zeno')
  force true
end

# # Tmux
symlink File.join(HOME_PATH, '.tmux.conf') do
  source File.join(DOTFILES_CONFIG_PATH, '.tmux.conf')
  force true
end
symlink File.join(XDG_CONFIG_HOME, 'tmux') do
  source File.join(DOTFILES_CONFIG_PATH, '.config', 'tmux')
  force true
end

# # WezTerm
symlink File.join(XDG_CONFIG_HOME, 'wezterm') do
  source File.join(DOTFILES_CONFIG_PATH, '.config', 'wezterm')
  force true
end

# # Git
symlink File.join(HOME_PATH, '.gitconfig') do
  source File.join(DOTFILES_CONFIG_PATH, '.gitconfig')
  force true
end
symlink File.join(XDG_CONFIG_HOME, 'git') do
  source File.join(DOTFILES_CONFIG_PATH, '.config', 'git')
  force true
end
touch '$XDG_CONFIG_HOME/git/local' do
  path File.join(XDG_CONFIG_HOME, 'git', 'local')
end

# # direnv
symlink File.join(HOME_PATH, '.direnvrc') do
  source File.join(DOTFILES_CONFIG_PATH, '.direnvrc')
  force true
end

# # Ruby
symlink File.join(HOME_PATH, '.gemrc') do
  source File.join(DOTFILES_CONFIG_PATH, '.gemrc')
  force true
end

# # Darwin
result = run_command('[ "$(uname -s)" = "Darwin" ]', error: false)
if result.success?
  %w(mas cocoapods).each do |package|
    brew package do
      action :install
    end
  end

  # macOS defaults settings
  # NSGlobalDomain
  execute 'Set dark mode' do
    command 'defaults write NSGlobalDomain AppleInterfaceStyle Dark'
  end
  execute 'Enable swipe navigation' do
    command 'defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool true'
  end
  execute 'Set natural scrolling' do
    command 'defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false'
  end

  # Menu bar clock
  execute 'Set 24-hour time format' do
    command 'defaults write com.apple.menuextra.clock Show24Hour -bool true'
  end
  execute 'Hide day of week in clock' do
    command 'defaults write com.apple.menuextra.clock ShowDayOfWeek -bool false'
  end
  execute 'Hide seconds in clock' do
    command 'defaults write com.apple.menuextra.clock ShowSeconds -bool false'
  end

  # Control Center
  execute 'Hide Focus Modes in Control Center' do
    command 'defaults write com.apple.controlcenter "NSStatusItem Visible FocusModes" -bool false'
  end
  execute 'Hide Battery percentage in Control Center' do
    command 'defaults write com.apple.controlcenter "NSStatusItem Visible BatteryShowPercentage" -bool false'
  end
  execute 'Hide Now Playing in Control Center' do
    command 'defaults write com.apple.controlcenter "NSStatusItem Visible NowPlaying" -bool false'
  end
  execute 'Hide Sound in Control Center' do
    command 'defaults write com.apple.controlcenter "NSStatusItem Visible Sound" -bool false'
  end
  execute 'Hide Bluetooth in Control Center' do
    command 'defaults write com.apple.controlcenter "NSStatusItem Visible Bluetooth" -bool false'
  end
  execute 'Hide AirDrop in Control Center' do
    command 'defaults write com.apple.controlcenter "NSStatusItem Visible AirDrop" -bool false'
  end

  # Trackpad
  execute 'Enable tap to click' do
    command 'defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true'
  end

  # Mission Control
  execute 'Disable automatic space rearrangement' do
    command 'defaults write com.apple.dock mru-spaces -bool false'
  end

  # Dock
  execute 'Auto-hide Dock' do
    command 'defaults write com.apple.dock autohide -bool true'
  end
  execute 'Hide recent apps in Dock' do
    command 'defaults write com.apple.dock show-recents -bool false'
  end
  execute 'Disable Dock magnification' do
    command 'defaults write com.apple.dock magnification -bool false'
  end
  execute 'Set Dock icon size' do
    command 'defaults write com.apple.dock tilesize -int 64'
  end
  execute 'Set Dock large size' do
    command 'defaults write com.apple.dock largesize -int 64'
  end
  execute 'Set Dock position' do
    command 'defaults write com.apple.dock orientation bottom'
  end
  execute 'Set minimize effect' do
    command 'defaults write com.apple.dock mineffect scale'
  end
  execute 'Disable launch animation' do
    command 'defaults write com.apple.dock launchanim -bool false'
  end

  # Finder
  execute 'Show all file extensions' do
    command 'defaults write com.apple.finder AppleShowAllExtensions -bool true'
  end
  execute 'Show hidden files' do
    command 'defaults write com.apple.finder AppleShowAllFiles -bool true'
  end
  execute 'Hide desktop icons' do
    command 'defaults write com.apple.finder CreateDesktop -bool false'
  end
  execute 'Disable extension change warning' do
    command 'defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false'
  end
  execute 'Show path bar in Finder' do
    command 'defaults write com.apple.finder ShowPathbar -bool true'
  end
  execute 'Show status bar in Finder' do
    command 'defaults write com.apple.finder ShowStatusBar -bool true'
  end

  # Keyboard remapping (CapsLock to Control)
  execute 'Remap CapsLock to Control' do
    command 'hidutil property --set \'{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E0}]}\''
  end

  # Apply changes
  execute 'Restart Dock' do
    command 'killall Dock'
  end
  execute 'Restart Finder' do
    command 'killall Finder'
  end
  execute 'Restart SystemUIServer' do
    command 'killall SystemUIServer'
  end

  [
    # Browsers
    'google-chrome', 'firefox',
    # Utilities
    '1password', 'stats', 'raycast',
    # Development
    'visual-studio-code', 'cursor', 'flutter', 'orbstack', 'unity-hub', 'jetbrains-toolbox', 'wezterm',
    # Communication
    "discord",
    # Entertainment
    'steam',
  ].each do |package|
    brew package do
      action :install
      options ['--cask', '--appdir=/Applications']
    end
  end

  print 'Do you want to install apps from the App Store? [y/N]: '
  if $stdin.tty? && $stdin.gets.chomp.start_with?('y')
    [
      409183694, # Keynote
      409201541, # Pages
      409203825, # Numbers
      408981434, # iMovie
      682658836, # GarageBand
      1295203466, # Microsoft Remote Desktop
      1246969117, # Steam Link
    ].each do |id|
      execute "mas install #{id}" do
        command "mas install #{id}"
      end
    end
  end
end


# asdf
execute 'asdf plugin add ruby' do
  command 'asdf plugin add ruby'
end
execute 'asdf plugin add nodejs' do
  command 'asdf plugin add nodejs'
end
execute 'asdf plugin add python' do
  command 'asdf plugin add python'
end
execute 'asdf plugin add golang' do
  command 'asdf plugin add golang'
end
execute 'asdf plugin add rust' do
  command 'asdf plugin add rust'
end
