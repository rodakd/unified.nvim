local utils = require("test.test_utils")

local M = {}

local function assert_eq(a, b, msg)
  assert(a == b, msg or string.format("Expected %s, got %s", tostring(a), tostring(b)))
end

local function setup_diffed_buffer()
  local repo = utils.create_git_repo()
  if not repo then
    return nil
  end

  -- Keep the tree out of the way; we only care about the inline diff lifecycle.
  require("unified").setup({ file_tree = { enabled = false } })

  local test_path = utils.create_and_commit_file(repo, "test.txt", { "line 1", "line 2", "line 3" }, "Initial commit")

  vim.cmd("edit " .. test_path)
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { "modified line 1" })

  require("unified.command").run("HEAD")

  local diff = require("unified.diff")
  assert(
    vim.wait(1000, function()
      return diff.is_diff_displayed(buffer)
    end),
    "diff should render before toggling"
  )

  return buffer
end

function M.test_toggle_hides_and_restores_paint()
  local buffer = setup_diffed_buffer()
  if not buffer then
    return true
  end
  local diff = require("unified.diff")

  assert_eq(diff.toggle_hunks(buffer), true, "first toggle should hide the paint")
  assert(not diff.is_diff_displayed(buffer), "extmarks must be gone after hiding")
  assert_eq(#require("unified.hunk_store").get(buffer), 0, "hunk store must be cleared while hidden")
  assert(vim.b[buffer].unified_hunks_hidden, "buffer must carry the hidden flag")

  assert_eq(diff.toggle_hunks(buffer), true, "second toggle should re-render")
  assert(diff.is_diff_displayed(buffer), "extmarks must be back after re-showing")
  assert(not vim.b[buffer].unified_hunks_hidden, "hidden flag must be cleared on re-show")

  require("unified.command").reset()
  return true
end

-- Regression: an auto-refresh already in flight when the user hides the paint
-- must not silently repaint the diff behind their back.
function M.test_hidden_suppresses_auto_refresh()
  local buffer = setup_diffed_buffer()
  if not buffer then
    return true
  end
  local diff = require("unified.diff")
  local git = require("unified.git")

  diff.toggle_hunks(buffer)
  assert(not diff.is_diff_displayed(buffer), "precondition: paint hidden")

  -- Simulate a debounced refresh firing after the hide (both the plugin's and
  -- the user-overridden auto-refresh funnel through this call directly).
  local rendered = git.show_git_diff_against_commit("HEAD", buffer)
  vim.wait(200, function()
    return false
  end)
  assert(not rendered, "refresh must be refused while hidden")
  assert(not diff.is_diff_displayed(buffer), "refresh must not repaint while hidden")

  -- An explicit show is user intent and must lift the suppression.
  assert(diff.show("HEAD", buffer), "explicit show must succeed while hidden")
  assert(diff.is_diff_displayed(buffer), "explicit show must repaint")
  assert(not vim.b[buffer].unified_hunks_hidden, "explicit show must clear the hidden flag")

  require("unified.command").reset()
  return true
end

function M.test_toggle_without_diff_is_a_noop()
  vim.api.nvim_command("enew!")
  local buffer = vim.api.nvim_get_current_buf()

  assert_eq(require("unified.diff").toggle_hunks(buffer), false, "no diff displayed -> refuse")
  assert(not vim.b[buffer].unified_hunks_hidden, "refusal must not set the hidden flag")
  return true
end

-- A stale hidden flag from before a reset would silently suppress the next
-- :Unified for the buffer; reset must clear it.
function M.test_reset_clears_hidden_flag()
  local buffer = setup_diffed_buffer()
  if not buffer then
    return true
  end
  local diff = require("unified.diff")

  diff.toggle_hunks(buffer)
  require("unified.command").reset()
  assert(not vim.b[buffer].unified_hunks_hidden, "reset must clear the hidden flag")

  -- The next :Unified must render again instead of being suppressed.
  require("unified.command").run("HEAD")
  assert(
    vim.wait(1000, function()
      return diff.is_diff_displayed(buffer)
    end),
    "diff must render after a reset that cleared the hidden flag"
  )

  require("unified.command").reset()
  return true
end

return M
