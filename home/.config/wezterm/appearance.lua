local wezterm = require 'wezterm'

local M = {}

-- ============================================
-- Window
-- ============================================
M.window_decorations = "RESIZE"
M.window_padding = {
  left = '1cell',
  right = '1cell',
  top = '1cell',
  bottom = 0,
}
M.window_frame = {
  inactive_titlebar_bg = "none",
  active_titlebar_bg = "none",
  font_size = 16.0,
}

-- ============================================
-- Tab
-- ============================================
M.show_new_tab_button_in_tab_bar = false
M.tab_max_width = 32
M.use_fancy_tab_bar = false
M.tab_bar_at_bottom = true

-- ============================================
-- Colors
-- ============================================
M.color_scheme = 'Hybrid'
M.colors = {
  tab_bar = {
    background = 'none',
    active_tab = {
      bg_color = 'none',
      fg_color = '#d7af00',
      intensity = 'Bold',
    },
    inactive_tab = {
      bg_color = 'none',
      fg_color = '#c6c6c6',
    },
    inactive_tab_hover = {
      bg_color = '#333333',
      fg_color = '#c6c6c6',
    },
    new_tab = {
      bg_color = 'none',
      fg_color = '#888888',
    },
  }
}

-- ============================================
-- Fonts
-- ============================================
M.font = wezterm.font_with_fallback {
  'JetBrains Mono',
  'Hiragino Sans',
}
M.font_size = 18

-- ============================================
-- Apply to config
-- ============================================
function M.apply(config)
  -- Window
  config.window_decorations = M.window_decorations
  config.window_padding = M.window_padding
  config.window_frame = M.window_frame

  -- Tab
  config.show_new_tab_button_in_tab_bar = M.show_new_tab_button_in_tab_bar
  config.tab_max_width = M.tab_max_width
  config.use_fancy_tab_bar = M.use_fancy_tab_bar
  config.tab_bar_at_bottom = M.tab_bar_at_bottom

  -- Colors
  config.color_scheme = M.color_scheme
  config.colors = M.colors

  -- Fonts
  config.font = M.font
  config.font_size = M.font_size

  -- Tab title format (UTF-8 safe, with notification indicator)
  local notification = require 'notification'
  wezterm.on('format-tab-title', function(tab, tabs, panes, cfg, hover, max_width)
    local index = tab.tab_index + 1
    local title = tab.active_pane.title
    local max_chars = 20
    local char_len = utf8.len(title) or 0
    if char_len > max_chars then
      local byte_pos = utf8.offset(title, max_chars - 1) or #title
      title = title:sub(1, byte_pos - 1) .. '..'
    end

    local indicator = notification.get_status_indicator(tab.active_pane.pane_id)
    if indicator ~= '' then
      return string.format('%s %d:%s ', indicator, index, title)
    end
    return string.format(' %d:%s ', index, title)
  end)

  -- Status bar (single handler: workspace, unread count, datetime)
  local notification_mod = require 'notification'
  wezterm.on('update-status', function(window, pane)
    pcall(notification_mod.ingest)
    pcall(notification_mod.mark_active_pane_read, pane)

    local workspace = window:active_workspace()
    local date = wezterm.strftime('%Y/%m/%d %H:%M:%S')

    window:set_left_status(wezterm.format {
      { Foreground = { Color = '#7aa2f7' } },
      { Background = { Color = '#1a1b26' } },
      { Text = '  ' .. workspace .. ' ' },
    })

    local unread = 0
    ok, unread = pcall(notification_mod.get_unread_count)
    if not ok then unread = 0 end

    local right_items = {}
    local notif_color = unread > 0 and '#f7768e' or '#565f89'
    table.insert(right_items, { Foreground = { Color = notif_color } })
    table.insert(right_items, { Text = ' [' .. unread .. '] ' })
    table.insert(right_items, { Foreground = { Color = '#c6c6c6' } })
    table.insert(right_items, { Text = ' ' .. date .. ' ' })

    window:set_right_status(wezterm.format(right_items))
  end)
end

return M
