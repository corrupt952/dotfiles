local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Load modules
local appearance = require 'appearance'
local tmux = require 'tmux'

-- Misc
config.automatically_reload_config = true
config.scrollback_lines = 30000

-- Appearance (loaded from module)
appearance.apply(config)

-- Tmux-like keybinds (loaded from module)
tmux.apply(config)

-- Audio
config.audible_bell = "Disabled"

return config

