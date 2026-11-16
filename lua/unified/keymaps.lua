-- Default keymaps for this fork, consolidated from the old init.lua setup.
-- Disable with `require('unified').setup({ keymaps = false })`.
local M = {}

function M.setup()
  -- Revert the hunk under the cursor (against the active diff base).
  vim.keymap.set("n", "<leader>hr", function()
    require("unified.hunk_revert").revert_hunk_under_cursor()
  end, { desc = "Unified: revert hunk under cursor" })

  -- Hide/show the diff paint while the diff session stays active.
  vim.keymap.set("n", "<leader>ht", function()
    require("unified").toggle_hunks()
  end, { desc = "Unified: toggle hunk visibility" })

  -- Toggle: active diff -> reset; otherwise diff against a branch (empty
  -- input = HEAD), using merge-base so you see everything since the branches
  -- diverged.
  vim.keymap.set("n", "<leader>d", function()
    local state = require("unified.state")

    if state.is_active() then
      require("unified.command").reset()
      pcall(vim.cmd, "ScrollViewRefresh")
      return
    end

    local branch = vim.trim(vim.fn.input("Diff against branch (empty = working copy): "))

    if branch == "" then
      require("unified.command").run("HEAD")
    else
      local merge_base = vim.trim(vim.fn.system({ "git", "merge-base", branch, "HEAD" }))
      if vim.v.shell_error ~= 0 or merge_base == "" then
        vim.notify("merge-base failed for " .. branch, vim.log.levels.ERROR)
        return
      end
      require("unified.command").run(merge_base)
    end
  end, { desc = "Unified: toggle diff / diff against branch" })
end

return M
