local wezterm = require 'wezterm'
local act = wezterm.action
local mux = wezterm.mux

local M = {}

-- ============================================
-- Project Workspace System
-- ============================================
local projects_dir = wezterm.home_dir .. '/.config/wezterm-projects'

-- Expand ~ to home directory
local function expand_path(path)
  if path and path:sub(1, 1) == '~' then
    return wezterm.home_dir .. path:sub(2)
  end
  return path
end

local function load_projects()
  local projects = {}
  local handle = io.popen('ls -1 "' .. projects_dir .. '"/*.lua 2>/dev/null')
  if handle then
    for file in handle:lines() do
      local name = file:match('([^/]+)%.lua$')
      if name then
        local ok, project = pcall(dofile, file)
        if ok and project and project.workspace then
          project.cwd = expand_path(project.cwd)
          projects[project.workspace] = project
        end
      end
    end
    handle:close()
  end
  return projects
end

local function get_active_workspaces()
  local active = {}
  for _, win in ipairs(mux.all_windows()) do
    active[win:get_workspace()] = true
  end
  return active
end

local function build_project_choices()
  local projects = load_projects()
  local active = get_active_workspaces()
  local sort_data = {}
  local seen = {}

  for name, project in pairs(projects) do
    seen[name] = true
    local is_active = active[name] and true or false
    local status = is_active and '● ' or '○ '
    table.insert(sort_data, {
      choice = {
        id = 'project:' .. name,
        label = status .. name .. ' (' .. (project.cwd or '?') .. ')',
      },
      is_active = is_active,
    })
  end

  for name, _ in pairs(active) do
    if not seen[name] then
      table.insert(sort_data, {
        choice = {
          id = 'workspace:' .. name,
          label = '● ' .. name .. ' (ad-hoc)',
        },
        is_active = true,
      })
    end
  end

  table.sort(sort_data, function(a, b)
    if a.is_active ~= b.is_active then
      return a.is_active  -- active first
    end
    return a.choice.label < b.choice.label  -- then alphabetical
  end)

  -- Extract choices for InputSelector
  local choices = {}
  for _, item in ipairs(sort_data) do
    table.insert(choices, item.choice)
  end

  return choices, projects
end

local function setup_project_tabs(project)
  wezterm.time.call_after(0.3, function()
    local workspace_windows = {}
    for _, win in ipairs(mux.all_windows()) do
      if win:get_workspace() == project.workspace then
        table.insert(workspace_windows, win)
      end
    end

    if #workspace_windows == 0 then return end
    local mux_win = workspace_windows[1]

    local tabs = project.tabs or {}
    for i, tab_config in ipairs(tabs) do
      local tab, pane
      if i == 1 then
        tab = mux_win:active_tab()
        pane = tab:active_pane()
        if project.cwd then
          pane:send_text('cd ' .. project.cwd .. '\n')
        end
      else
        tab, pane = mux_win:spawn_tab { cwd = project.cwd }
        if project.cwd then
          pane:send_text('cd ' .. project.cwd .. '\n')
        end
      end

      if tab_config.cmd then
        pane:send_text(tab_config.cmd .. '\n')
      end
    end

    local first_tab = mux_win:tabs()[1]
    if first_tab then
      first_tab:activate()
    end
  end)
end

local function switch_or_start_project(window, pane, id)
  local ws_name = id:match('^workspace:(.+)$')
  if ws_name then
    window:perform_action(act.SwitchToWorkspace { name = ws_name }, pane)
    return
  end

  local name = id:match('^project:(.+)$')
  if not name then return end

  local active = get_active_workspaces()
  local projects = load_projects()
  local project = projects[name]

  if active[name] then
    window:perform_action(act.SwitchToWorkspace { name = name }, pane)
  else
    window:perform_action(
      act.SwitchToWorkspace {
        name = name,
        spawn = { cwd = project and project.cwd or wezterm.home_dir },
      },
      pane
    )

    if project and project.tabs then
      setup_project_tabs(project)
    end
  end
end

-- ============================================
-- Keybinds
-- ============================================
M.leader = { key = 'b', mods = 'CTRL', timeout_milliseconds = 1000 }

M.keys = {
  -- Tab operations
  { key = 'c', mods = 'LEADER', action = act.SpawnTab 'CurrentPaneDomain' },          -- new tab
  { key = 'n', mods = 'LEADER', action = act.ActivateTabRelative(1) },                -- next tab
  { key = 'p', mods = 'LEADER', action = act.ActivateTabRelative(-1) },               -- previous tab
  { key = '&', mods = 'LEADER|SHIFT', action = act.CloseCurrentTab { confirm = true } }, -- close tab
  { key = 'w', mods = 'LEADER', action = act.ShowTabNavigator },                      -- list tabs
  { key = ',', mods = 'LEADER', action = act.PromptInputLine {                        -- rename tab
    description = 'Enter new tab name',
    action = wezterm.action_callback(function(window, pane, line)
      if line then
        window:active_tab():set_title(line)
      end
    end),
  }},
  { key = '1', mods = 'LEADER', action = act.ActivateTab(0) },                        -- go to tab 1-9
  { key = '2', mods = 'LEADER', action = act.ActivateTab(1) },
  { key = '3', mods = 'LEADER', action = act.ActivateTab(2) },
  { key = '4', mods = 'LEADER', action = act.ActivateTab(3) },
  { key = '5', mods = 'LEADER', action = act.ActivateTab(4) },
  { key = '6', mods = 'LEADER', action = act.ActivateTab(5) },
  { key = '7', mods = 'LEADER', action = act.ActivateTab(6) },
  { key = '8', mods = 'LEADER', action = act.ActivateTab(7) },
  { key = '9', mods = 'LEADER', action = act.ActivateTab(8) },

  -- Pane operations
  { key = '%', mods = 'LEADER|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } }, -- split horizontal
  { key = '"', mods = 'LEADER|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },   -- split vertical
  { key = 'x', mods = 'LEADER', action = act.CloseCurrentPane { confirm = true } },   -- close pane
  { key = 'z', mods = 'LEADER', action = act.TogglePaneZoomState },                   -- toggle zoom
  { key = 'o', mods = 'LEADER', action = act.ActivatePaneDirection 'Next' },          -- next pane
  { key = ';', mods = 'LEADER', action = act.ActivatePaneDirection 'Prev' },          -- previous pane
  { key = 'LeftArrow', mods = 'LEADER', action = act.ActivatePaneDirection 'Left' },  -- navigate panes (arrow)
  { key = 'RightArrow', mods = 'LEADER', action = act.ActivatePaneDirection 'Right' },
  { key = 'UpArrow', mods = 'LEADER', action = act.ActivatePaneDirection 'Up' },
  { key = 'DownArrow', mods = 'LEADER', action = act.ActivatePaneDirection 'Down' },
  { key = 'h', mods = 'LEADER', action = act.ActivatePaneDirection 'Left' },          -- navigate panes (vim)
  { key = 'j', mods = 'LEADER', action = act.ActivatePaneDirection 'Down' },
  { key = 'k', mods = 'LEADER', action = act.ActivatePaneDirection 'Up' },
  { key = 'l', mods = 'LEADER', action = act.ActivatePaneDirection 'Right' },
  { key = '{', mods = 'LEADER|SHIFT', action = act.RotatePanes 'CounterClockwise' },  -- rotate panes
  { key = '}', mods = 'LEADER|SHIFT', action = act.RotatePanes 'Clockwise' },
  { key = 'Space', mods = 'LEADER', action = act.RotatePanes 'Clockwise' },           -- cycle layout

  -- Resize panes (vim style with Shift)
  { key = 'H', mods = 'LEADER|SHIFT', action = act.AdjustPaneSize { 'Left', 5 } },
  { key = 'J', mods = 'LEADER|SHIFT', action = act.AdjustPaneSize { 'Down', 5 } },
  { key = 'K', mods = 'LEADER|SHIFT', action = act.AdjustPaneSize { 'Up', 5 } },
  { key = 'L', mods = 'LEADER|SHIFT', action = act.AdjustPaneSize { 'Right', 5 } },

  -- Copy mode
  { key = '[', mods = 'LEADER', action = act.ActivateCopyMode },                      -- enter copy mode
  { key = ']', mods = 'LEADER', action = act.PasteFrom 'Clipboard' },                 -- paste

  -- Search & Quick Select
  { key = '/', mods = 'LEADER', action = act.Search 'CurrentSelectionOrEmptyString' }, -- search
  { key = 's', mods = 'LEADER', action = act.QuickSelect },                           -- quick select
  { key = 'u', mods = 'LEADER', action = act.QuickSelectArgs {                        -- open URL
    label = 'open url',
    patterns = { 'https?://\\S+' },
    action = wezterm.action_callback(function(window, pane)
      local url = window:get_selection_text_for_pane(pane)
      wezterm.open_with(url)
    end),
  }},

  -- Workspace / Project
  { key = 'f', mods = 'LEADER', action = wezterm.action_callback(function(window, pane) -- project launcher
    local choices, _ = build_project_choices()

    if #choices == 0 then
      window:toast_notification('WezTerm', 'No projects found in ' .. projects_dir, nil, 3000)
      return
    end

    window:perform_action(
      act.InputSelector {
        title = 'Switch to Project',
        choices = choices,
        fuzzy = true,
        action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
          if id then
            switch_or_start_project(inner_window, inner_pane, id)
          end
        end),
      },
      pane
    )
  end)},

  -- Misc
  { key = 'd', mods = 'LEADER', action = act.QuitApplication },                       -- detach (quit)
  { key = ':', mods = 'LEADER|SHIFT', action = act.ActivateCommandPalette },          -- command palette
  { key = 'r', mods = 'LEADER', action = act.ReloadConfiguration },                   -- reload config
  { key = 'b', mods = 'LEADER|CTRL', action = act.SendKey { key = 'b', mods = 'CTRL' } }, -- send Ctrl+b
}

M.key_tables = {
  copy_mode = {
    -- Movement
    { key = 'h', mods = 'NONE', action = act.CopyMode 'MoveLeft' },
    { key = 'j', mods = 'NONE', action = act.CopyMode 'MoveDown' },
    { key = 'k', mods = 'NONE', action = act.CopyMode 'MoveUp' },
    { key = 'l', mods = 'NONE', action = act.CopyMode 'MoveRight' },
    { key = 'LeftArrow', mods = 'NONE', action = act.CopyMode 'MoveLeft' },
    { key = 'DownArrow', mods = 'NONE', action = act.CopyMode 'MoveDown' },
    { key = 'UpArrow', mods = 'NONE', action = act.CopyMode 'MoveUp' },
    { key = 'RightArrow', mods = 'NONE', action = act.CopyMode 'MoveRight' },

    -- Word movement
    { key = 'w', mods = 'NONE', action = act.CopyMode 'MoveForwardWord' },
    { key = 'b', mods = 'NONE', action = act.CopyMode 'MoveBackwardWord' },
    { key = 'e', mods = 'NONE', action = act.CopyMode 'MoveForwardWordEnd' },

    -- Line movement
    { key = '0', mods = 'NONE', action = act.CopyMode 'MoveToStartOfLine' },
    { key = '$', mods = 'SHIFT', action = act.CopyMode 'MoveToEndOfLineContent' },
    { key = '^', mods = 'SHIFT', action = act.CopyMode 'MoveToStartOfLineContent' },

    -- Page movement
    { key = 'g', mods = 'NONE', action = act.CopyMode 'MoveToScrollbackTop' },
    { key = 'G', mods = 'SHIFT', action = act.CopyMode 'MoveToScrollbackBottom' },
    { key = 'u', mods = 'CTRL', action = act.CopyMode 'PageUp' },
    { key = 'd', mods = 'CTRL', action = act.CopyMode 'PageDown' },

    -- Selection
    { key = 'v', mods = 'NONE', action = act.CopyMode { SetSelectionMode = 'Cell' } },
    { key = 'V', mods = 'SHIFT', action = act.CopyMode { SetSelectionMode = 'Line' } },
    { key = 'v', mods = 'CTRL', action = act.CopyMode { SetSelectionMode = 'Block' } },

    -- Copy and exit
    { key = 'y', mods = 'NONE', action = act.Multiple {
      { CopyTo = 'ClipboardAndPrimarySelection' },
      { CopyMode = 'Close' },
    }},

    -- Exit copy mode
    { key = 'q', mods = 'NONE', action = act.CopyMode 'Close' },
    { key = 'Escape', mods = 'NONE', action = act.CopyMode 'Close' },

    -- Search
    { key = '/', mods = 'NONE', action = act.Search 'CurrentSelectionOrEmptyString' },
    { key = 'n', mods = 'NONE', action = act.CopyMode 'NextMatch' },
    { key = 'N', mods = 'SHIFT', action = act.CopyMode 'PriorMatch' },
  },
}

-- ============================================
-- Apply to config
-- ============================================
function M.apply(config)
  config.leader = M.leader
  config.keys = M.keys
  config.key_tables = M.key_tables
end

return M
