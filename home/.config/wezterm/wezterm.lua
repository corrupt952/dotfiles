local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Load modules
local appearance = require 'appearance'
local tmux = require 'tmux'
local smart_paste = require 'smart_paste'
local notification = require 'notification'

-- Misc
config.automatically_reload_config = true
config.scrollback_lines = 30000

-- Appearance (loaded from module)
appearance.apply(config)

-- Tmux-like keybinds (loaded from module)
tmux.apply(config)

-- Smart paste: Cmd+V detects clipboard images and pastes file path
smart_paste.apply(config)

-- Notification system (agent status tracking + jump-to-pane)
notification.apply(config)

-- Additional keybinds (non-tmux style)
table.insert(config.keys, {
  key = 'n',
  mods = 'CMD|SHIFT',
  action = wezterm.action_callback(function(window, pane)
    -- Spawn truly independent WezTerm instance (separate mux, separate workspaces)
    wezterm.background_child_process { 'open', '-n', '-a', 'WezTerm', '--args', 'start', '--always-new-process' }
  end),
})

-- Hyperlink rules: keep defaults, but make the catch-all rule stop before ')'
-- so Markdown-style [text](url) links don't include the closing paren
config.hyperlink_rules = wezterm.default_hyperlink_rules()
for _, rule in ipairs(config.hyperlink_rules) do
  if rule.regex == '\\b\\w+://\\S+[)/a-zA-Z0-9-]+' then
    rule.regex = '\\b\\w+://\\S+[/a-zA-Z0-9-]+'
  end
end

-- Audio
config.audible_bell = "Disabled"

return config

