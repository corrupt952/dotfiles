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

define :install_apt_packages, packages: [] do
  packages = params[:packages]
  execute "Install #{packages.join(',')}" do
    command "sudo apt install -y --no-install-recommends #{packages.join(' ')}"
  end
end

define :install_brew_packages, packages: [], options: [] do
  packages = params[:packages]
  options = params[:options]
  execute "Install #{packages.join(',')}" do
    command "brew install #{options.join(' ')} #{packages.join(' ')}"
  end
end

define :link, source: nil, destination: nil do
  source_path = File.expand_path(params[:source])
  destination_path = File.expand_path(params[:destination])
  execute "link #{source_path} to #{destination_path}" do
    command "ln -s #{source_path} #{destination_path}"
  end
end

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

  install_apt_packages 'apt install' do
    packages %w(
      locales-all ca-certificates build-essential
      fonts-ipafont fonts-ipaexfont x11-xkb-utils
      zsh vim wget
    )
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
  install_apt_packages 'apt install docker' do
    packages %w(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
  end

  execute 'apt autoremove' do
    command 'sudo apt autoremove'
  end
end

# Homebrew
execute 'brew update' do
  command 'brew update'
end

install_brew_packages 'brew install' do
  packages %w(
    automake
    bat
    cmake
    coreutils
    curl
    direnv
    deno
    fzf
    grep
    gpg
    gnu-sed
    jq
    libtool
    ripgrep
    tig
    tmux
    tree
    wget
    wimlib
    arp-scan
    asdf
    aquaproj/aqua/aqua
    corrupt952/tmuxist/tmuxist
  )
end

# Configure dotfiles
git 'corrupt952/dotfiles' do
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

directory File.join(HOME_PATH, '.local', 'bin') do
  action :create
end

# Zsh
link '$HOME/.zshenv' do
  not_if { File.exist?(File.join(HOME_PATH, '.zshenv'))}

  source File.join(DOTFILES_CONFIG_PATH, '.zshenv')
  destination File.join(HOME_PATH, '.zshenv')
end
link '$ZDOTDIR' do
  not_if { File.exist?(ZDOTDIR) }

  source File.join(DOTFILES_CONFIG_PATH, '.config', 'zsh')
  destination ZDOTDIR
end
touch '.zshrc.local' do
  path File.join(ZDOTDIR, '.zshrc.local')
end
git 'zinit' do
  not_if { File.exist?(ZINIT_HOME) }

  repository 'https://github.com/zdharma-continuum/zinit.git'
  destination ZINIT_HOME
end
link '$XDG_CONFIG_HOME/zeno' do
  not_if { File.exist?(File.join(XDG_CONFIG_HOME, 'zeno')) }

  source File.join(DOTFILES_CONFIG_PATH, '.config', 'zeno')
  destination File.join(XDG_CONFIG_HOME, 'zeno')
end

# Tmux
link '$HOME/.tmux.conf' do
  not_if { File.exist?(File.join(HOME_PATH, '.tmux.conf')) }

  source File.join(DOTFILES_CONFIG_PATH, '.tmux.conf')
  destination File.join(HOME_PATH, '.tmux.conf')
end
link '$XDG_CONFIG_HOME/tmux' do
  not_if { File.exist?(File.join(XDG_CONFIG_HOME, 'tmux')) }

  source File.join(DOTFILES_CONFIG_PATH, '.config', 'tmux')
  destination File.join(XDG_CONFIG_HOME, 'tmux')
end

# Git
link '$HOME/.gitconfig' do
  not_if { File.exist?(File.join(HOME_PATH, '.gitconfig')) }

  source File.join(DOTFILES_CONFIG_PATH, '.gitconfig')
  destination File.join(HOME_PATH, '.gitconfig')
end
link "$XDG_CONFIG_HOME/git" do
  not_if { File.exist?(File.join(XDG_CONFIG_HOME, 'git')) }

  source File.join(DOTFILES_CONFIG_PATH, '.config', 'git')
  destination File.join(XDG_CONFIG_HOME, 'git')
end
touch '$XDG_CONFIG_HOME/git/local' do
  path File.join(XDG_CONFIG_HOME, 'git', 'local')
end

# direnv
link '$HOME/.direnvrc' do
  not_if { File.exist?(File.join(HOME_PATH, '.direnvrc')) }

  source File.join(DOTFILES_CONFIG_PATH, '.direnvrc')
  destination File.join(HOME_PATH, '.direnvrc')
end

# Ruby
link '$HOME/.gemrc' do
  not_if { File.exist?(File.join(HOME_PATH, '.gemrc')) }

  source File.join(DOTFILES_CONFIG_PATH, '.gemrc')
  destination File.join(HOME_PATH, '.gemrc')
end

# Darwin
# TODO:

# WSL
# TODO: 

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
