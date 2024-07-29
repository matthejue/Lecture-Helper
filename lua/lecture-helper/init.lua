local configs = require("lecture-helper.configs")
local state = require("lecture-helper.state")
local actions = require("lecture-helper.actions")

local M = {}

local function set_commands()
	vim.api.nvim_create_user_command("CurrentSpeech", actions.current_speech, { desc = state.descs.current_speech })
	vim.api.nvim_create_user_command("PreviousSpeech", function(arg)
		actions.previous_speech(tonumber(arg.args))
	end, { desc = state.descs.previous_speech, nargs = "?" })
	vim.api.nvim_create_user_command("NextSpeech", function(arg)
		actions.next_speech(tonumber(arg.args))
	end, { desc = state.descs.next_speech, nargs = "?" })
	vim.api.nvim_create_user_command("GotoSpeech", actions.goto_speech, { desc = state.descs.goto_speech })
	vim.api.nvim_create_user_command("ReplaceSymbols", actions.replace_symbols, { desc = state.descs.replace_symbols })
end

local function set_global_keybindings()
	if state.opts.keys.current_speech then
		vim.keymap.set(
			"n",
			state.opts.keys.current_speech,
			actions.current_speech, -- ":GetSpeech<cr>",
			{ silent = true, desc = state.descs.current_speech }
		)
	end
	if state.opts.keys.previous_speech then
		vim.keymap.set(
			"n",
			state.opts.keys.previous_speech,
			function ()
        actions.previous_speech(vim.v.count1)
			end,
			{ silent = true, desc = state.descs.previous_speech }
		)
	end
	if state.opts.keys.next_speech then
		vim.keymap.set(
			"n",
			state.opts.keys.next_speech,
			function ()
        actions.next_speech(vim.v.count1)
			end,
			{ silent = true, desc = state.descs.next_speech }
		)
	end
	if state.opts.keys.goto_speech then
		vim.keymap.set(
			"n",
			state.opts.keys.goto_speech,
			actions.goto_speech,
			{ silent = true, desc = state.descs.goto_speech }
		)
	end
	if state.opts.keys.replace_symbols then
		vim.keymap.set(
			"n",
			state.opts.keys.replace_symbols,
			actions.replace_symbols,
			{ silent = true, desc = state.descs.replace_symbols }
		)
	end
end

function M.setup(opts)
	state.opts = vim.tbl_deep_extend("keep", opts, configs)

	set_commands()
	set_global_keybindings()
end

return M
