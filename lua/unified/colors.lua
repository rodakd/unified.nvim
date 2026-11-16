-- Muted diff colors for this fork: quiet Nord-toned backgrounds instead of
-- the screaming built-in Diff* highlights. Applied on setup and re-applied
-- after every colorscheme switch, since most colorschemes wipe custom groups.
local M = {}

M.groups = {
  UnifiedMutedAdd = { bg = "#2F4034", fg = "#A3BE8C" },
  UnifiedMutedDelete = { bg = "#3F343A", fg = "#BF616A" },
  UnifiedMutedChange = { bg = "#3E4A5E", fg = "#81A1C1" },
}

-- Also mute the built-in DiffChange so non-unified diff views (folds,
-- :diffthis, quickfix previews, ...) match the muted palette.
M.extra = {
  DiffChange = { bg = "#3E4A5E", fg = "#81A1C1" },
}

function M.apply()
  for name, attrs in pairs(M.groups) do
    vim.api.nvim_set_hl(0, name, attrs)
  end
  for name, attrs in pairs(M.extra) do
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

function M.setup()
  M.apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("UnifiedMutedColors", { clear = true }),
    callback = M.apply,
  })
end

return M
