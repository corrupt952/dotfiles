-- Test suite for notification.lua.
--
-- Stubs only the wezterm API surface. Storage is the real thing: a real
-- sqlite3 binary against a real database, seeded through the real hook script,
-- because the last regression here came precisely from a stub that behaved
-- more conveniently than wezterm does.
--
-- Usage:
--   WEZTERM_UNIX_SOCKET=<path> SQLITE3=<path> HOOK=<path> \
--     lua modules/wezterm/notification.test.lua

local script_dir = arg[0]:match('(.*)/') or '.'
local sqlite3 = os.getenv('SQLITE3') or 'sqlite3'
local hook = assert(os.getenv('HOOK'), 'set HOOK to the substituted hook script')
local socket = assert(os.getenv('WEZTERM_UNIX_SOCKET'), 'set WEZTERM_UNIX_SOCKET')
local db = '/tmp/wezterm-notifications/' .. socket:match('([^/]+)$') .. '.db'

local passed = 0
local failures = {}

local function check(ok, label, detail)
  if ok then
    passed = passed + 1
  else
    table.insert(failures, label .. '\n      ' .. (detail or ''))
  end
end

-- ============================================
-- wezterm stub: API surface only, no storage
-- ============================================
local live_panes = {}

local wt = {
  action = setmetatable({}, {
    __index = function(_, k)
      return function(a) return { kind = k, args = a } end
    end,
  }),
  action_callback = function(fn) return fn end,
  format = function(_) return 'formatted' end,
  on = function() end,
}

wt.mux = {
  all_windows = function()
    local panes = {}
    for _, id in ipairs(live_panes) do
      table.insert(panes, { pane_id = function() return id end })
    end
    local tab = { panes = function() return panes end }
    return { { tabs = function() return { tab } end } }
  end,
  get_pane = function(id)
    for _, l in ipairs(live_panes) do
      if l == id then
        return {
          window = function() return { get_workspace = function() return 'ws' end } end,
          get_title = function() return 'title' end,
          activate = function() end,
        }
      end
    end
    return nil
  end,
}

package.preload['wezterm'] = function() return wt end

-- ============================================
-- Helpers driving the real storage
-- ============================================
local function shell(cmd)
  local handle = assert(io.popen(cmd .. ' 2>&1'))
  local out = handle:read('*a')
  handle:close()
  return out
end

local function reset_db()
  shell('rm -- ' .. db .. ' ' .. db .. '-wal ' .. db .. '-shm 2>/dev/null; true')
end

-- Seed through the hook, so the writer under test is the real one.
local function emit(pane_id, event)
  shell(string.format(
    "printf '%%s' '{\"hook_event_name\":\"%s\"}' | WEZTERM_PANE=%d %s",
    event, pane_id, hook
  ))
end

local function query(sql)
  return shell(string.format("%s '%s' '%s'", sqlite3, db, sql))
end

local function load_module()
  -- Substitute the sqlite3 placeholder the same way the nix build does.
  local src = assert(io.open(script_dir .. '/notification.lua', 'r'))
  local text = src:read('*a')
  src:close()
  text = text:gsub('@sqlite3@', (sqlite3:gsub('%%', '%%%%')))
  return assert(load(text, 'notification.lua'))()
end

local function new_context()
  local mod = load_module()
  mod.apply({})
  return mod
end

local function pane_stub(id)
  return { pane_id = function() return id end }
end

-- ============================================
-- Tests
-- ============================================
print('## the hook writes and lua reads it back')
do
  reset_db()
  live_panes = { 4341, 4612 }
  emit(4341, 'Notification')
  emit(4612, 'Stop')

  local ctx = new_context()
  ctx.ingest()
  check(ctx.get_unread_count() == 2, 'both events visible', 'got ' .. ctx.get_unread_count())
  check(ctx.get_status_indicator(4341) == '✋', 'waiting indicator',
    'got ' .. ctx.get_status_indicator(4341))
  check(ctx.get_status_indicator(4612) == '✅', 'done indicator',
    'got ' .. ctx.get_status_indicator(4612))
end

print('## two contexts writing different panes keep both')
do
  reset_db()
  live_panes = { 1, 2 }
  local ctx_a = new_context()
  local ctx_b = new_context()

  -- Each context acknowledges its own pane. Under the old shared-list design
  -- whichever saved second erased the other's entry.
  emit(1, 'Notification')
  emit(2, 'Notification')
  ctx_a.ingest()
  ctx_b.ingest()

  ctx_a.mark_active_pane_read(pane_stub(1))
  ctx_b.mark_active_pane_read(pane_stub(2))

  ctx_a.ingest()
  check(ctx_a.get_unread_count() == 0, 'both reads survived',
    'got ' .. ctx_a.get_unread_count())
  check(query('SELECT COUNT(*) FROM notifications;'):match('2'), 'both rows still present')
end

print('## a dead pane is not listed')
do
  reset_db()
  live_panes = { 1, 2 }
  emit(1, 'Notification')
  emit(2, 'Notification')

  local ctx = new_context()
  ctx.ingest()
  check(ctx.get_unread_count() == 2, 'both live panes counted')

  live_panes = { 1 }
  check(ctx.get_unread_count() == 1, 'dead pane dropped', 'got ' .. ctx.get_unread_count())
end

print('## SessionEnd hides only its own pane')
do
  reset_db()
  live_panes = { 1, 2 }
  emit(1, 'Notification')
  emit(2, 'Notification')
  emit(1, 'SessionEnd')

  local ctx = new_context()
  ctx.ingest()
  check(ctx.get_unread_count() == 1, 'the other pane is untouched',
    'got ' .. ctx.get_unread_count())
  check(ctx.get_status_indicator(1) == '', 'idle pane shows nothing')
  check(ctx.get_status_indicator(2) ~= '', 'pane 2 still shows')
end

print('## a newer event outranks the read marker')
do
  reset_db()
  live_panes = { 1 }
  emit(1, 'Stop')

  local ctx = new_context()
  ctx.ingest()
  ctx.mark_active_pane_read(pane_stub(1))
  ctx.ingest()
  check(ctx.get_unread_count() == 0, 'no longer unread', 'got ' .. ctx.get_unread_count())

  emit(1, 'Notification')
  ctx.ingest()
  check(ctx.get_unread_count() == 1, 'a newer event reads as unread',
    'got ' .. ctx.get_unread_count())
end

print('## the list action builds a selector')
do
  reset_db()
  live_panes = { 4341, 4612 }
  emit(4341, 'Notification')
  emit(4612, 'Stop')

  local ctx = new_context()
  local shown, kind
  local window = {
    perform_action = function(_, action)
      kind = action and action.kind
      shown = action and action.args and action.args.choices and #action.args.choices
    end,
    toast_notification = function(_, _, msg) kind = 'toast:' .. msg end,
    active_workspace = function() return 'ws' end,
  }

  local ok, err = pcall(ctx.notification_list_action, window, pane_stub(4341))
  check(ok, 'list action does not raise', tostring(err))
  check(kind == 'InputSelector', 'a selector is shown', 'got ' .. tostring(kind))
  check(shown == 2, 'both panes are listed', 'got ' .. tostring(shown))
end

reset_db()

for _, failure in ipairs(failures) do
  print('FAIL  ' .. failure)
end
print(string.format('\npass=%d fail=%d', passed, #failures))
os.exit(#failures == 0 and 0 or 1)
