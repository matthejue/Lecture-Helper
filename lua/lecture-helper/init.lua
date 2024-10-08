local configs = require("lecture-helper.configs")
local state = require("lecture-helper.state")
local actions = require("lecture-helper.actions")

local M = {}

--  TODO: activate only for .annot file extension, maybe option of lazy.nvim

local function set_commands()
	vim.api.nvim_create_user_command("CurrentSpeech", function()
		actions.current_speech(false)
	end, { desc = state.descs.current_speech })
	vim.api.nvim_create_user_command("UpdateSpeechLineNr", function()
		actions.current_speech(true)
	end, { desc = state.descs.update_linenr })
	vim.api.nvim_create_user_command(
		"UpdateTimestamp",
		actions.update_timestamp,
		{ desc = state.descs.update_timestamp }
	)
	vim.api.nvim_create_user_command("PreviousSpeech", function(arg)
		actions.previous_speech(tonumber(arg.args))
	end, { desc = state.descs.previous_speech, nargs = "?" })
	vim.api.nvim_create_user_command("NextSpeech", function(arg)
		actions.next_speech(tonumber(arg.args))
	end, { desc = state.descs.next_speech, nargs = "?" })
	vim.api.nvim_create_user_command("MergeLines", actions.merge_lines, { desc = state.descs.merge_lines })
	vim.api.nvim_create_user_command(
		"SliceToLineAbove",
		actions.slice_to_line_above,
		{ desc = state.descs.slice_to_line_above }
	)
	vim.api.nvim_create_user_command(
		"SliceToLineBelow",
		actions.slice_to_line_below,
		{ desc = state.descs.slice_to_line_below }
	)
	vim.api.nvim_create_user_command("RemoveSlice", actions.remove_slice, { desc = state.descs.remove_slice })
	vim.api.nvim_create_user_command("GotoSpeech", actions.goto_speech, { desc = state.descs.goto_speech })
	vim.api.nvim_create_user_command("GotoTimestamp", actions.goto_speech, { desc = state.descs.goto_timestamp })
	vim.api.nvim_create_user_command("ReplaceSymbols", actions.replace_symbols, { desc = state.descs.replace_symbols })
	vim.api.nvim_create_user_command(
		"ConvertTextmode",
		actions.convert_textmode,
		{ desc = state.descs.convert_textmode }
	)
	vim.api.nvim_create_user_command("RemoveWords", actions.remove_words, { desc = state.descs.remove_words })
end

local function set_global_keybindings()
	if state.opts.keys.current_speech then
		vim.keymap.set(
			"n",
			state.opts.keys.current_speech,
			function()
				actions.current_speech(false)
			end, -- ":GetSpeech<cr>",
			{ silent = true, desc = state.descs.current_speech }
		)
	end
	if state.opts.keys.update_linenr then
		vim.keymap.set("n", state.opts.keys.update_linenr, function()
			actions.current_speech(true)
		end, { silent = true, desc = state.descs.update_linenr })
	end
	if state.opts.keys.update_timestamp then
		vim.keymap.set(
			"n",
			state.opts.keys.update_timestamp,
			actions.update_timestamp,
			{ silent = true, desc = state.descs.update_timestamp }
		)
	end
	if state.opts.keys.previous_speech then
		vim.keymap.set("n", state.opts.keys.previous_speech, function()
			actions.previous_speech(vim.v.count1)
		end, { silent = true, desc = state.descs.previous_speech })
	end
	if state.opts.keys.next_speech then
		vim.keymap.set("n", state.opts.keys.next_speech, function()
			actions.next_speech(vim.v.count1)
		end, { silent = true, desc = state.descs.next_speech })
	end
	if state.opts.keys.merge_lines then
		vim.keymap.set("v", state.opts.keys.merge_lines, function()
			actions.merge_lines()
		end, {
			silent = true,
			desc = state.descs.merge_lines,
		})
	end
	if state.opts.keys.slice_to_line_above then
		vim.keymap.set(
			"n",
			state.opts.keys.slice_to_line_above,
			actions.slice_to_line_above,
			{ silent = true, desc = state.descs.slice_to_line_above }
		)
	end
	if state.opts.keys.slice_to_line_below then
		vim.keymap.set(
			"n",
			state.opts.keys.slice_to_line_below,
			actions.slice_to_line_below,
			{ silent = true, desc = state.descs.slice_to_line_below }
		)
	end
	if state.opts.keys.remove_slice then
		vim.keymap.set(
			"n",
			state.opts.keys.remove_slice,
			actions.remove_slice,
			{ silent = true, desc = state.descs.remove_slice }
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
	if state.opts.keys.goto_timestamp then
		vim.keymap.set(
			"n",
			state.opts.keys.goto_timestamp,
			actions.goto_timestamp,
			{ silent = true, desc = state.descs.goto_timestamp }
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
	if state.opts.keys.convert_textmode then
		vim.keymap.set(
			"n",
			state.opts.keys.convert_textmode,
			actions.convert_textmode,
			{ silent = true, desc = state.descs.convert_textmode }
		)
	end
	if state.opts.keys.remove_words then
		vim.keymap.set(
			"n",
			state.opts.keys.remove_words,
			actions.remove_words,
			{ silent = true, desc = state.descs.remove_words }
		)
	end
end

function M.setup(opts)
	state.opts = vim.tbl_deep_extend("keep", opts, configs)

	set_commands()
	set_global_keybindings()
end

return M
