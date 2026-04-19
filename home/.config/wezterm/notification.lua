local wezterm = require 'wezterm'
local act = wezterm.action
local mux = wezterm.mux

local M = {}

local NOTIFY_DIR = '/tmp/wezterm-notifications'

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
-- Local State (survives within process, cleared on restart)
-- ============================================
local notifications = {}

local function load_from_global()
  local json = wezterm.GLOBAL.notifications_json
  if json and json ~= '' then
    local ok, data = pcall(wezterm.json_parse, json)
    if ok and data then
      notifications = data
    end
  end
end

local function save_to_global()
  local ok, json = pcall(wezterm.json_encode, notifications)
  if ok then
    wezterm.GLOBAL.notifications_json = json
  end
end

local function add_notification(pane_id, status)
  for i = #notifications, 1, -1 do
    if notifications[i].pane_id == pane_id then
      table.remove(notifications, i)
    end
  end

  table.insert(notifications, {
    pane_id = pane_id,
    status = status,
    timestamp = os.time(),
    read = false,
  })
  save_to_global()
end

local function mark_read(pane_id)
  for _, n in ipairs(notifications) do
    if n.pane_id == pane_id then
      n.read = true
    end
  end
  save_to_global()
end

local function remove_notification(pane_id)
  for i = #notifications, 1, -1 do
    if notifications[i].pane_id == pane_id then
      table.remove(notifications, i)
    end
  end
  save_to_global()
end

local function prune_stale()
  local live = {}
  for _, n in ipairs(notifications) do
    local ok, pane = pcall(mux.get_pane, n.pane_id)
    if ok and pane then
      table.insert(live, n)
    end
  end
  notifications = live
  save_to_global()
end

-- ============================================
-- File-based Notification Ingestion
-- ============================================
local function ingest_notification_files()
  local handle = io.popen('ls -1 "' .. NOTIFY_DIR .. '"/*.json 2>/dev/null')
  if not handle then return end

  for file in handle:lines() do
    local pane_id_str = file:match('/(%d+)%.json$')
    if pane_id_str then
      local pane_id = tonumber(pane_id_str)
      local f = io.open(file, 'r')
      if f then
        local content = f:read('*a')
        f:close()
        os.remove(file)

        local ok, data = pcall(wezterm.json_parse, content)
        if ok and data then
          if data.status == 'idle' or data.status == '' then
            remove_notification(pane_id)
          else
            add_notification(pane_id, data.status)
          end
        end
      end
    end
  end
  handle:close()
end

-- ============================================
-- Public API (called from appearance.lua)
-- ============================================
function M.get_status_indicator(pane_id)
  for _, n in ipairs(notifications) do
    if n.pane_id == pane_id and not n.read then
      return STATUS_LABELS[n.status] or ''
    end
  end
  return ''
end

function M.get_unread_count()
  local count = 0
  for _, n in ipairs(notifications) do
    if not n.read then
      count = count + 1
    end
  end
  return count
end

function M.mark_active_pane_read(pane)
  mark_read(pane:pane_id())
end

function M.ingest()
  ingest_notification_files()
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
  load_from_global()

  config.notification_handling = 'SuppressFromFocusedPane'

  -- Fallback: receive agent status via OSC 1337 user variable (if /dev/tty works)
  wezterm.on('user-var-changed', function(window, pane, name, value)
    if name == 'agent_status' then
      local pane_id = pane:pane_id()
      if value == '' or value == 'idle' then
        remove_notification(pane_id)
      elseif value == 'running' then
        mark_read(pane_id)
      else
        add_notification(pane_id, value)
      end
    end
  end)

  -- Notification list action (Leader+U)
  M.notification_list_action = wezterm.action_callback(function(window, pane)
    prune_stale()

    if #notifications == 0 then
      window:toast_notification('WezTerm', 'No notifications', nil, 2000)
      return
    end

    -- Sort: unread first, then by timestamp (newest first)
    local sorted = {}
    for _, n in ipairs(notifications) do
      table.insert(sorted, n)
    end
    table.sort(sorted, function(a, b)
      if a.read ~= b.read then
        return not a.read
      end
      return a.timestamp > b.timestamp
    end)

    local choices = {}
    for _, n in ipairs(sorted) do
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
    prune_stale()

    local latest = nil
    for _, n in ipairs(notifications) do
      if not n.read then
        latest = n
      end
    end

    if not latest then
      window:toast_notification('WezTerm', 'No unread notifications', nil, 2000)
      return
    end

    M.jump_to_pane(window, pane, latest.pane_id)
  end)
end

return M
