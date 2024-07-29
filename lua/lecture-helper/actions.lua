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

	local total_seconds = math.ceil(position)

	local hours = math.floor(total_seconds / 3600)
	local minutes = math.floor((total_seconds % 3600) / 60)
	local seconds = total_seconds % 60

	local timestamp = string.format("%02d:%02d:%02d", hours, minutes, seconds)

	return timestamp
end

-- function that checks for every line of the subtitles file until it finds one that contains a timestamp that is bigger than the timestamp received from playerctl and return the line and line number
local function find_line(timestamp)
	local line_nr = 1
	local line = state.subtitle_file_lines[line_nr]
	local previous_line = state.subtitle_file_lines[line_nr]
	while line do
		local start_time = line:match("%d+:%d+:%d+")
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

function M.current_speech()
	local timestamp, err = get_playerctl_position()
	if not timestamp then
		print("Error: " .. err)
	end

	set_subtitles_file()
	local line
	line, state.line_nr = find_line(timestamp)
	vim.api.nvim_set_current_line(state.opts.prefix .. line)
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

function M.replace_symbols()
	local current_line = vim.api.nvim_get_current_line()
	for i, v in pairs(state.opts.symbols) do
		current_line = string.gsub(current_line, i, v .. " ")
	end
	vim.api.nvim_set_current_line(current_line)
end

return M
