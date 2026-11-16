-- Revert the hunk under the cursor. Unlike unified.hunk_actions (which works
-- against the index), this computes the patch against the *active diff base*
-- (state.get_commit_base), so while reviewing `:Unified main` you can undo a
-- hunk back to that base, not just your uncommitted edits.
local M = {}

function M.revert_hunk_under_cursor()
  local state = require("unified.state")
  local ok_base, base = pcall(state.get_commit_base)
  if not ok_base or not state.is_active() then
    vim.notify("Unified: no active diff", vim.log.levels.WARN)
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local abs = vim.api.nvim_buf_get_name(buf)
  if abs == "" then
    vim.notify("Unified: buffer has no file path", vim.log.levels.WARN)
    return
  end

  local root = vim.trim(vim.fn.system({ "git", "-C", vim.fn.fnamemodify(abs, ":h"), "rev-parse", "--show-toplevel" }))
  if vim.v.shell_error ~= 0 or root == "" then
    vim.notify("Unified: not a git repository", vim.log.levels.WARN)
    return
  end
  if abs:sub(1, #root + 1) ~= root .. "/" then
    vim.notify("Unified: could not compute path relative to repo root", vim.log.levels.WARN)
    return
  end
  local rel = abs:sub(#root + 2)

  local out = vim.fn.system({ "git", "-C", root, "diff", base, "-U3", "--", rel })
  if vim.v.shell_error ~= 0 then
    vim.notify("Unified: git diff failed", vim.log.levels.ERROR)
    return
  end
  local lines = vim.split(out, "\n", { plain = true })
  for _, l in ipairs(lines) do
    if l:match("^Binary files") or l:match("^GIT binary patch") then
      vim.notify("Unified: binary patch not supported", vim.log.levels.WARN)
      return
    end
  end

  -- Walk the unified diff and find the hunk the cursor sits on.
  local headers = {}
  local selected = nil
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local i = 1
  while i <= #lines and not lines[i]:match("^@@") do
    table.insert(headers, lines[i])
    i = i + 1
  end
  while i <= #lines and not selected do
    local header = lines[i]
    local n_start, n_count = header:match("^@@ %-%d+,?%d* %+(%d+),?(%d*) @@")
    i = i + 1
    if n_start then
      n_start = tonumber(n_start)
      n_count = (n_count ~= "" and tonumber(n_count)) or 1
      local hunk_lines = {}
      while i <= #lines and not lines[i]:match("^@@") do
        table.insert(hunk_lines, lines[i])
        i = i + 1
      end
      local on_hunk
      if n_count > 0 then
        on_hunk = cursor_line >= n_start and cursor_line < n_start + n_count
      else
        -- Pure deletion: nothing on the new side; accept the deletion anchor,
        -- the line above it, and the line below it.
        on_hunk = cursor_line == math.max(1, n_start)
          or (n_start >= 1 and cursor_line == n_start - 1)
          or cursor_line == n_start + 1
      end
      if on_hunk then
        selected = { header = header, lines = hunk_lines }
      end
    end
  end
  if not selected then
    vim.notify("Unified: no hunk under the cursor", vim.log.levels.WARN)
    return
  end

  -- Build a single-hunk patch git-apply can reverse, synthesizing ---/+++
  -- headers when the diff didn't include them.
  local patch_lines = {}
  local has_oldnew = false
  for _, l in ipairs(headers) do
    if l:match("^--- ") or l:match("^%+%+%+ ") then
      has_oldnew = true
    end
    table.insert(patch_lines, l)
  end
  if not has_oldnew then
    table.insert(patch_lines, "--- a/" .. rel)
    table.insert(patch_lines, "+++ b/" .. rel)
  end
  table.insert(patch_lines, selected.header)
  for _, l in ipairs(selected.lines) do
    table.insert(patch_lines, l)
  end

  local tmp = vim.fn.tempname()
  local f = io.open(tmp, "wb")
  f:write(table.concat(patch_lines, "\n") .. "\n")
  f:close()
  local result = vim.fn.system({ "git", "-C", root, "apply", "-R", "--unidiff-zero", "--whitespace=nowarn", tmp })
  vim.fn.delete(tmp)
  if vim.v.shell_error ~= 0 then
    vim.notify("Unified: git apply failed: " .. vim.trim(result), vim.log.levels.ERROR)
    return
  end

  -- Reload and repaint: git apply changed the file underneath us.
  pcall(vim.cmd, "checktime")
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("edit!")
    end)
  end
  pcall(require("unified.diff").show_current)
end

return M
