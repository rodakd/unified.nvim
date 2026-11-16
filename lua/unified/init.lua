local M = {}

-- After tree actions that open (or move to) a file, focus lands back in the
-- content window: the tree is for navigation, not for staying in.
local function focus_main_window()
  local win = require("unified.state").get_main_window()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

-- Wrap the tree actions so every caller (the `l` keymap, `<CR>`, ...) returns
-- focus to the content window. Idempotent: re-running setup must not stack
-- wrappers on wrappers.
local wrapped_actions = {}

function M.wrap_tree_actions()
  local actions = require("unified.file_tree.actions")
  for _, name in ipairs({ "toggle_node", "move_cursor_and_open_file" }) do
    local orig = actions[name]
    if orig and not wrapped_actions[name] then
      wrapped_actions[name] = true
      local wrapped = function(...)
        orig(...)
        focus_main_window()
      end
      actions[name] = wrapped
    end
  end
end

function M.setup(opts)
  local config = require("unified.config")
  local colors = require("unified.colors")

  -- Muted highlight groups must exist before config links UnifiedDiff* to them.
  colors.setup()
  config.setup(opts)

  local command = require("unified.command")
  local file_tree = require("unified.file_tree")
  local virt_scroll = require("unified.virt_scroll")
  command.setup()
  file_tree.setup()
  virt_scroll.setup()

  M.wrap_tree_actions()

  if config.values.keymaps then
    require("unified.keymaps").setup()
  end
  require("unified.scrollview_signs").setup()
end

function M.toggle()
  local command = require("unified.command")
  local state = require("unified.state")

  if state.is_active() then
    command.reset()
    return
  end

  -- Reuse the remembered base if there is one; otherwise default to HEAD so the
  -- toggle stays instant. (Bare `:Unified` opens the commit picker instead.)
  local ok, commit_ref = pcall(state.get_commit_base)
  command.run(ok and commit_ref or "HEAD")
end

-- Open a picker to choose the base commit to diff against, then show the diff
-- (the same thing bare `:Unified` does). Exposed so you can map it directly.
function M.pick_commit()
  require("unified.commit_picker").pick()
end

-- Hide the diff paint while keeping the session active (read the file without
-- the noise); a second call re-renders. Exposed so you can map it directly.
function M.toggle_hunks()
  require("unified.diff").toggle_hunks()
end

return M
