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

-- Additional keybinds (non-tmux style)
table.insert(config.keys, {
  key = 'n',
  mods = 'CMD|SHIFT',
  action = wezterm.action_callback(function(window, pane)
    -- Spawn truly independent WezTerm instance (separate mux, separate workspaces)
    wezterm.background_child_process { 'open', '-n', '-a', 'WezTerm', '--args', 'start', '--always-new-process' }
  end),
})

-- Audio
config.audible_bell = "Disabled"

return config

