-- Optional nvim-scrollview integration: paint +/- marks on the scrollbar for
-- lines changed relative to the active diff base. Silently no-ops when
-- nvim-scrollview is not installed.
local M = {}

local add_group = "unified_add"
local del_group = "unified_del"

function M.setup()
  local ok_sv, scrollview = pcall(require, "scrollview")
  if not ok_sv or type(scrollview.register_sign_group) ~= "function" then
    return
  end

  scrollview.register_sign_group(add_group)
  scrollview.register_sign_group(del_group)

  local add_reg = scrollview.register_sign_spec({ group = add_group, highlight = "UnifiedMutedAdd" })
  local del_reg = scrollview.register_sign_spec({ group = del_group, highlight = "UnifiedMutedDelete" })
  scrollview.set_sign_group_state(add_group, true)
  scrollview.set_sign_group_state(del_group, true)

  -- Cache keyed by buffer/base/changedtick; a single entry per refresh is
  -- enough, the key just dedupes repeated callbacks between edits.
  local cache = {}

  local function update_diff_signs(bufnr)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    if fname == "" then
      return
    end
    local state = require("unified.state")
    local ok, base = pcall(state.get_commit_base)
    local key = tostring(bufnr)
      .. ":"
      .. tostring(ok and base or "inactive")
      .. ":"
      .. tostring(vim.b[bufnr].changedtick or 0)
    if cache[key] then
      return
    end
    cache = { [key] = true }

    local adds, dels = {}, {}
    if ok and state.is_active() then
      -- Parse `git diff <base> -- <file>` and record added/deleted line numbers.
      -- (Buffer-relative; matches what the scrollbar displays.)
      local out = vim.fn.systemlist({ "git", "diff", base, "--", fname })
      if vim.v.shell_error == 0 then
        local line = 0
        for _, l in ipairs(out) do
          if l:sub(1, 3) == "+++" or l:sub(1, 3) == "---" then
            goto continue
          end
          local c = l:sub(1, 1)
          if c == "@" then
            local start = tonumber(l:match("%+(%d+)"))
            if start then
              line = start - 1
            end
          elseif c == "+" then
            line = line + 1
            table.insert(adds, line)
          elseif c == "-" then
            table.insert(dels, math.max(1, line))
          elseif c == " " then
            line = line + 1
          end
          ::continue::
        end
      end
    end
    vim.b[bufnr][add_reg.name] = adds
    vim.b[bufnr][del_reg.name] = dels
  end

  local function refresh_signs()
    if scrollview.is_sign_group_active(add_group) then
      vim.cmd("ScrollViewRefresh")
    end
  end

  scrollview.set_sign_group_callback(add_group, function()
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      update_diff_signs(vim.api.nvim_win_get_buf(winid))
    end
  end)
  scrollview.set_sign_group_callback(del_group, function()
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      update_diff_signs(vim.api.nvim_win_get_buf(winid))
    end
  end)

  local group = vim.api.nvim_create_augroup("UnifiedScrollViewSigns", { clear = true })
  -- The base changed (new :Unified invocation): repaint the marks.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "UnifiedBaseCommitUpdated",
    callback = refresh_signs,
  })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWritePost", "TextChanged" }, {
    group = group,
    callback = function()
      if require("unified.state").is_active() then
        refresh_signs()
      end
    end,
  })
end

return M
