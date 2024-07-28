local state = require("lecture-helper.state")

local M = {}

-- ┌────────────────────────┐
-- │ Keybindings and events │
-- └────────────────────────┘

function M.get_speech() 
end

function M.previous_speech() end

function M.next_speech() end

function M.replace_symbols()
	local current_line = vim.api.nvim_get_current_line()
  for i,v in pairs(state.opts.symbols) do
    current_line = string.gsub(current_line, i, v .. " ")
  end
  vim.api.nvim_set_current_line(current_line)
end

return M
