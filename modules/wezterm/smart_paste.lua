local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

-- ============================================
-- Smart Paste: Cmd+V with clipboard image detection
-- ============================================
-- When the clipboard contains an image, saves it to a temp file
-- and pastes the file path instead. Otherwise, performs normal paste.

local paste_dir = '/tmp/wezterm-clipboard-images'

local function clipboard_has_image()
  local success, stdout, stderr = wezterm.run_child_process {
    'osascript', '-e', 'clipboard info'
  }
  if not success or not stdout then
    return false
  end
  return stdout:find('PNGf') ~= nil
      or stdout:find('TIFF') ~= nil
      or stdout:find('JPEG') ~= nil
end

local function save_clipboard_image()
  os.execute('mkdir -p "' .. paste_dir .. '"')

  local timestamp = os.date('%Y%m%d-%H%M%S')
  local path = paste_dir .. '/paste-' .. timestamp .. '.png'

  local script = string.format([[
    set imgPath to POSIX file "%s"
    set imgData to the clipboard as «class PNGf»
    set fileRef to open for access imgPath with write permission
    write imgData to fileRef
    close access fileRef
  ]], path)

  local success = wezterm.run_child_process { 'osascript', '-e', script }
  if success then
    return path
  end

  return nil
end

-- ============================================
-- Apply to config
-- ============================================
function M.apply(config)
  table.insert(config.keys, {
    key = 'v',
    mods = 'CMD',
    action = wezterm.action_callback(function(window, pane)
      if clipboard_has_image() then
        local path = save_clipboard_image()
        if path then
          pane:send_paste(path)
          window:toast_notification('Smart Paste', 'Image saved: ' .. path, nil, 3000)
        else
          window:toast_notification('Smart Paste', 'Failed to save clipboard image', nil, 3000)
          window:perform_action(act.PasteFrom('Clipboard'), pane)
        end
      else
        window:perform_action(act.PasteFrom('Clipboard'), pane)
      end
    end),
  })
end

return M
