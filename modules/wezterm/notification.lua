local wezterm = require 'wezterm'
local act = wezterm.action
local mux = wezterm.mux

local M = {}

-- wezterm-gui does not expose WEZTERM_UNIX_SOCKET to os.getenv at module load,
-- so a child shell reads it instead.
local NOTIFY_ROOT = '/tmp/wezterm-notifications'
local SQLITE = '@sqlite3@'

local function basename(s)
  return (s:gsub('(.*[/\\])(.*)', '%2'))
end

local function detect_socket_path()
  local s = os.getenv('WEZTERM_UNIX_SOCKET')
  if s and s ~= '' then return s end
  local handle = io.popen('printf %s "${WEZTERM_UNIX_SOCKET:-}" 2>/dev/null')
  if not handle then return nil end
  local val = handle:read('*a')
  handle:close()
  if val and val ~= '' then return val end
  return nil
end

local function db_path()
  local s = detect_socket_path()
  local namespace = (s and s ~= '') and basename(s) or '__no_socket__'
  return NOTIFY_ROOT .. '/' .. namespace .. '.db'
end

local STATUS_LABELS = {
  initial = '⚡',
  waiting = '✋',
  done    = '✅',
  error   = '❗',
}

local STATUS_COLORS = {
  initial = '#7aa2f7',
  waiting = '#e0af68',
  done    = '#9ece6a',
  error   = '#f7768e',
}

-- ============================================
-- Storage
-- ============================================
-- One row per pane, and every statement names the pane it belongs to. wezterm
-- runs this module in several lua contexts at once, so nothing may rewrite the
-- whole set.
local SCHEMA = [[
CREATE TABLE IF NOT EXISTS notifications (
  pane_id INTEGER PRIMARY KEY,
  status TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  event_ns INTEGER NOT NULL,
  read_ns INTEGER NOT NULL DEFAULT 0
);
]]

local PRAGMAS = 'PRAGMA busy_timeout=3000;'

local function sqlite_command(sql)
  return string.format(
    "mkdir -p '%s' && '%s' -noheader -separator '|' '%s' '%s' 2>/dev/null",
    NOTIFY_ROOT, SQLITE, db_path(), PRAGMAS .. SCHEMA .. sql
  )
end

local function sqlite_exec(sql)
  local handle = io.popen(sqlite_command(sql))
  if not handle then return end
  handle:read('*a')
  handle:close()
end

local function sqlite_rows(sql)
  local handle = io.popen(sqlite_command(sql))
  if not handle then return {} end

  local rows = {}
  for line in handle:lines() do
    local pane_id, status, updated_at, event_ns, read_ns =
      line:match('^(%-?%d+)|([^|]*)|(%-?%d+)|(%-?%d+)|(%-?%d+)$')
    if pane_id then
      table.insert(rows, {
        pane_id = tonumber(pane_id),
        status = status,
        updated_at = tonumber(updated_at),
        event_ns = tonumber(event_ns),
        read_ns = tonumber(read_ns),
      })
    end
  end
  handle:close()
  return rows
end

-- Refreshed once per update-status tick so tab titles do not each spawn a
-- query. Never written back.
local cache = {}

local function refresh()
  cache = sqlite_rows(
    'SELECT pane_id, status, updated_at, event_ns, read_ns FROM notifications;'
  )
  return cache
end

local function set_status(pane_id, status, event_ns)
  -- read_ns is left alone so a newer event reads as unread again.
  sqlite_exec(string.format([[
INSERT INTO notifications (pane_id, status, updated_at, event_ns, read_ns)
VALUES (%d, '%s', %d, %d, 0)
ON CONFLICT(pane_id) DO UPDATE SET
  status = excluded.status,
  updated_at = excluded.updated_at,
  event_ns = excluded.event_ns
WHERE excluded.event_ns >= notifications.event_ns;
]], pane_id, status, os.time(), event_ns))
end

local function mark_read(pane_id)
  sqlite_exec(string.format(
    'UPDATE notifications SET read_ns = event_ns WHERE pane_id = %d;', pane_id
  ))
end

-- ============================================
-- Views over the snapshot
-- ============================================
local function live_pane_ids()
  local ids = {}
  local ok, windows = pcall(mux.all_windows)
  if not ok or type(windows) ~= 'table' then return ids end

  for _, window in ipairs(windows) do
    local tabs_ok, tabs = pcall(function() return window:tabs() end)
    if tabs_ok and type(tabs) == 'table' then
      for _, tab in ipairs(tabs) do
        local panes_ok, panes = pcall(function() return tab:panes() end)
        if panes_ok and type(panes) == 'table' then
          for _, pane in ipairs(panes) do
            ids[pane:pane_id()] = true
          end
        end
      end
    end
  end
  return ids
end

local function row_for(pane_id)
  for _, row in ipairs(cache) do
    if row.pane_id == pane_id and row.status ~= 'idle' then
      return row
    end
  end
  return nil
end

-- Every live pane that currently has a status, unread first and then newest
-- first, matching how the list has always been ordered.
local function collect_entries()
  local live = live_pane_ids()
  local entries = {}
  for _, row in ipairs(cache) do
    if live[row.pane_id] and row.status ~= 'idle' then
      table.insert(entries, {
        pane_id = row.pane_id,
        status = row.status,
        timestamp = row.updated_at or os.time(),
        read = row.event_ns <= row.read_ns,
      })
    end
  end
  table.sort(entries, function(a, b)
    if a.read ~= b.read then
      return not a.read
    end
    return a.timestamp > b.timestamp
  end)
  return entries
end

-- ============================================
-- Public API (called from appearance.lua)
-- ============================================
function M.get_status_indicator(pane_id)
  local row = row_for(pane_id)
  if row and row.event_ns > row.read_ns then
    return STATUS_LABELS[row.status] or ''
  end
  return ''
end

function M.get_unread_count()
  local count = 0
  for _, entry in ipairs(collect_entries()) do
    if not entry.read then
      count = count + 1
    end
  end
  return count
end

function M.mark_active_pane_read(pane)
  local pane_id = pane:pane_id()
  local row = row_for(pane_id)
  -- Skip the write when there is nothing new to acknowledge, so the common
  -- tick costs one query rather than two.
  if row and row.event_ns > row.read_ns then
    mark_read(pane_id)
  end
end

-- Kept for appearance.lua, which calls this every update-status tick. The hook
-- writes its row directly now, so this only refreshes the snapshot.
function M.ingest()
  refresh()
end

function M.jump_to_pane(window, pane, target_pane_id)
  local ok, target = pcall(mux.get_pane, target_pane_id)
  if not ok or not target then
    window:toast_notification('WezTerm', 'Pane not found', nil, 2000)
    return false
  end

  -- Switch workspace if needed
  local target_window = target:window()
  if target_window then
    local target_workspace = target_window:get_workspace()
    local current_workspace = window:active_workspace()
    if target_workspace ~= current_workspace then
      window:perform_action(
        act.SwitchToWorkspace { name = target_workspace },
        pane
      )
    end
  end

  mark_read(target_pane_id)
  target:activate()
  return true
end

-- ============================================
-- Apply to config
-- ============================================
function M.apply(config)
  config.notification_handling = 'SuppressFromFocusedPane'

  -- Fallback: receive agent status via OSC 1337 user variable (if /dev/tty works)
  wezterm.on('user-var-changed', function(window, pane, name, value)
    if name ~= 'agent_status' then return end

    local pane_id = pane:pane_id()
    if value == 'running' then
      mark_read(pane_id)
      return
    end

    -- This value arrives from the terminal, so only the known statuses reach
    -- the statement above.
    local status = (value == '' or value == 'idle') and 'idle' or value
    if status ~= 'idle' and not STATUS_LABELS[status] then
      return
    end

    -- No nanosecond clock in lua, so use the same epoch in the same unit and
    -- let it order against the hook's events.
    set_status(pane_id, status, math.floor(os.time()) * 1000000000)
    refresh()
  end)

  -- Notification list action (Leader+U)
  M.notification_list_action = wezterm.action_callback(function(window, pane)
    refresh()
    local entries = collect_entries()

    if #entries == 0 then
      window:toast_notification('WezTerm', 'No notifications', nil, 2000)
      return
    end

    local choices = {}
    for _, n in ipairs(entries) do
      local status_text = STATUS_LABELS[n.status] or '???'
      local status_color = STATUS_COLORS[n.status] or '#c6c6c6'
      local age = os.time() - n.timestamp
      local age_str
      if age < 60 then
        age_str = age .. 's'
      elseif age < 3600 then
        age_str = math.floor(age / 60) .. 'm'
      else
        age_str = math.floor(age / 3600) .. 'h'
      end

      -- Resolve workspace and pane title at display time
      local ws = '?'
      local pane_title = ''
      local ok, target = pcall(mux.get_pane, n.pane_id)
      if ok and target then
        local tw = target:window()
        if tw then
          ws = tw:get_workspace()
        end
        pane_title = target:get_title()
      end

      local read_mark = n.read and ' ' or '*'
      local read_color = n.read and '#565f89' or '#c0caf5'

      table.insert(choices, {
        id = tostring(n.pane_id),
        label = wezterm.format {
          { Foreground = { Color = read_color } },
          { Text = read_mark .. ' ' },
          { Foreground = { Color = status_color } },
          { Attribute = { Intensity = 'Bold' } },
          { Text = status_text },
          'ResetAttributes',
          { Foreground = { Color = read_color } },
          { Text = '  ' .. ws },
          { Foreground = { Color = '#565f89' } },
          { Text = '  pane:' .. n.pane_id .. ' ' .. pane_title },
          { Text = '  ' .. age_str .. ' ago' },
        },
      })
    end

    window:perform_action(
      act.InputSelector {
        title = 'Notifications',
        choices = choices,
        fuzzy = true,
        action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
          if id then
            M.jump_to_pane(inner_window, inner_pane, tonumber(id))
          end
        end),
      },
      pane
    )
  end)

  -- Jump to latest unread action (Leader+N)
  M.jump_to_latest_action = wezterm.action_callback(function(window, pane)
    refresh()
    -- collect_entries sorts unread first, so the head is the newest unread
    -- when one exists.
    local entries = collect_entries()
    if #entries == 0 or entries[1].read then
      window:toast_notification('WezTerm', 'No unread notifications', nil, 2000)
      return
    end

    M.jump_to_pane(window, pane, entries[1].pane_id)
  end)
end

return M
