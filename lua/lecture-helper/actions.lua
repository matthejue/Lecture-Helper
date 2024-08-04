local state = require("lecture-helper.state")

local M = {}

local function set_subtitles_file()
	local basepath = vim.fn.expand("%:p:r")
	local subtitles_file_path = basepath .. ".subtitles"

	if subtitles_file_path == state.subtitles_file_path then
		return
	end

	state.subtitles_file_path = subtitles_file_path
	local subtitle_file = io.open(state.subtitles_file_path, "r")
	if not subtitle_file then
		print("Error: Failed to open subtitles file " .. subtitles_file_path)
	end
	for line in subtitle_file:lines() do
		table.insert(state.subtitle_file_lines, line)
	end
	subtitle_file:close()
end

local function get_playerctl_position()
	local handle = io.popen("playerctl position")
	if not handle then
		return nil, "Failed to get playerctl position"
	end
	local result = handle:read("*a")
	handle:close()

	local position = tonumber(result:match("%d+%.?%d*"))

	if not position then
		return nil, "Failed to get position from playerctl"
	end

	local total_seconds = math.floor(position)

	local hours = math.floor(total_seconds / 3600)
	local minutes = math.floor((total_seconds % 3600) / 60)
	local seconds = total_seconds % 60

	local timestamp = string.format("%02d:%02d:%02d", hours, minutes, seconds)

	return timestamp
end

-- function that checks for every line of the subtitles file until it finds one that contains a timestamp that is bigger than the timestamp received from playerctl and return the line and line number
local function find_line(timestamp)
	local start_time
	local line_nr = 1
	local line = state.subtitle_file_lines[line_nr]
	local previous_line = state.subtitle_file_lines[line_nr]
	while line do
		start_time = line:match("%d+:%d+:%d+")
		if start_time then
			if start_time > timestamp then
				return previous_line, math.max(line_nr - 1, 1)
			end
		end
		line_nr = line_nr + 1
		previous_line = line
		line = state.subtitle_file_lines[line_nr]
	end
	return previous_line, line_nr - 1
end

function M.current_speech(update_linenr)
	local timestamp, err
	if update_linenr then
		local line = vim.api.nvim_get_current_line()
		timestamp = line:match("%d+:%d+:%d+")
		if not timestamp then
			print("Error: Line does not contain timestamp")
		end
	else
		timestamp, err = get_playerctl_position()
		if not timestamp then
			print("Error: " .. err)
		end
	end

	set_subtitles_file()
	local line
	line, state.line_nr = find_line(timestamp)
	if not update_linenr then
		vim.api.nvim_set_current_line(state.opts.prefix .. line)
	end
end

function M.update_timestamp()
	local current_timestamp = get_playerctl_position()
	set_subtitles_file()
	local line_with_timestamp, _ = find_line(current_timestamp)
	local line_timestamp = line_with_timestamp:match("%d+:%d+:%d+")

	local line = vim.api.nvim_get_current_line()
	line = line:gsub("%d+:%d+:%d+", line_timestamp)
	vim.api.nvim_set_current_line(line)
end

local function insert_lines(n, below)
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local cline = cursor_pos[1] - 1

	local insert_lines = {}
	for i = 0, n - 1, 1 do
		insert_lines[i + 1] = state.opts.prefix .. state.subtitle_file_lines[state.line_nr - (below and n - 1 or 0) + i]
	end

	vim.api.nvim_buf_set_lines(bufnr, cline + (below and 1 or 0), cline + (below and 1 or 0), false, insert_lines)
end

local function move_cursor(count)
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local new_line
	if count > 0 then
		local buf = vim.api.nvim_get_current_buf()
		new_line = math.min(vim.api.nvim_buf_line_count(buf), current_line + count)
	elseif count < 0 then
		new_line = math.max(1, current_line + count)
	end
	vim.api.nvim_win_set_cursor(0, { new_line, 0 })
end

function M.previous_speech(count)
	count = count or 1

	count = state.line_nr - math.max(state.line_nr - count, 1)
	state.line_nr = state.line_nr - count
	insert_lines(count, false)
	move_cursor(-count)
end

function M.next_speech(count)
	count = count or 1

	count = math.min(state.line_nr + count, #state.subtitle_file_lines) - state.line_nr
	state.line_nr = state.line_nr + count
	insert_lines(count, true)
	move_cursor(count)
end

function M.merge_lines()
	local _, start_line, _, _ = unpack(vim.fn.getpos("v"))
	local _, end_line, _, _ = unpack(vim.fn.getpos("."))
	if start_line > end_line then
		start_line, end_line = end_line, start_line
	end
	local lines = vim.fn.getline(start_line, end_line)

	for i = 2, #lines do
		lines[i] = string.sub(lines[i], 12)
	end
	local merged_line = table.concat(lines, " ")
	vim.fn.setline(start_line, merged_line)
	if end_line > start_line then
		vim.fn.deletebufline(vim.fn.bufnr(), start_line + 1, end_line)
	end
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, true, true), "n", true)
	vim.api.nvim_win_set_cursor(0, { start_line, 0 })
end

function M.slice_to_line_above()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	if row == 1 then
		return
	end

	local current_line = vim.api.nvim_get_current_line()
	local previous_line = vim.api.nvim_buf_get_lines(0, row - 2, row - 1, false)[1]

	local text_to_move = current_line:sub(12, col + 1)

	previous_line = previous_line .. " " .. text_to_move
	vim.api.nvim_buf_set_lines(0, row - 2, row - 1, false, { previous_line })

	current_line = current_line:sub(1, 11) .. current_line:sub(col + 3)
	vim.api.nvim_buf_set_lines(0, row - 1, row, false, { current_line })

	vim.api.nvim_win_set_cursor(0, { row, 11 })
end

function M.slice_to_line_below()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	if row == 1 then
		return
	end

	local current_line = vim.api.nvim_get_current_line()
	local next_line = vim.api.nvim_buf_get_lines(0, row, row+1, false)[1]

	local text_to_move = current_line:sub(col + 3)

	next_line = next_line:sub(1, 10) .. " " .. text_to_move .. " " .. next_line:sub(12)
	vim.api.nvim_buf_set_lines(0, row, row + 1, false, { next_line })

	current_line = current_line:sub(1, col + 1)
	vim.api.nvim_set_current_line(current_line)
end

function M.remove_slice()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local line = vim.api.nvim_get_current_line()

	local start_idx = 11
	if col < start_idx then
		return
	end

	local new_line = line:sub(1, start_idx) .. line:sub(col + 3)
	vim.api.nvim_set_current_line(new_line)
	vim.api.nvim_win_set_cursor(0, { row, 11 })
end

-- function that converts timestampt of the format "hh:mm:ss" to seconds
local function timestamp_to_seconds(hours, minutes, seconds)
	return tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds)
end

function M.goto_speech()
	local line = vim.api.nvim_get_current_line()
	local hours, minutes, seconds = line:match("(%d+):(%d+):(%d+)")
	seconds = timestamp_to_seconds(hours, minutes, seconds)
	local handle = io.popen("playerctl position " .. seconds)
	if not handle then
		return nil, "Failed to set playerctl position"
	end
	handle:close()
end

-- function looks up current timestamp with playerctl and finds the closest timestamp in the current buffer
function M.goto_timestamp()
	local timestamp = get_playerctl_position()
	local start_time

	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	local line_nr = 1
	local line = lines[line_nr]
	while line do
		start_time = line:match("%d+:%d+:%d+")
		if not start_time then
			goto continue
		end
		if start_time then
			if start_time > timestamp then
				break
			end
		end
		::continue::
		line_nr = line_nr + 1
		line = lines[line_nr]
	end

	vim.api.nvim_win_set_cursor(0, { line_nr - 1, 0 })
end

function M.replace_symbols()
	local current_line = vim.api.nvim_get_current_line()
	for i, v in pairs(state.opts.replace_symbols) do
		current_line = string.gsub(current_line, i, v .. " ")
	end
	vim.api.nvim_set_current_line(current_line)
end

local function remove_duplicates(line)
	local no_duplicate = {}
	local result_line = {}

	for word in string.gmatch(line, "%S+") do
		if no_duplicate[word] == nil then
			no_duplicate[word] = true
		elseif no_duplicate[word] then
			no_duplicate[word] = false
		end
		table.insert(result_line, word)
	end

	local final_result = {}
	for _, word in ipairs(result_line) do
		if no_duplicate[word] then
			table.insert(final_result, word)
		else
			no_duplicate[word] = true
		end
	end

	local new_line = table.concat(final_result, " ")

	return new_line
end

function M.remove_words()
	local line = vim.api.nvim_get_current_line()
	line = remove_duplicates(line)
	for _, v in ipairs(state.opts.unneeded_words) do
		line = line:gsub(" " .. v, "")
	end
	vim.api.nvim_set_current_line(line)
end

return M
