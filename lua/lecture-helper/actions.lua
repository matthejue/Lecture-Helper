local state = require("lecture-helper.state")

local M = {}

-- ┌────────────────────────┐
-- │ Keybindings and events │
-- └────────────────────────┘

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
	local previous_line
	while line do
		line_nr = line_nr + 1
		local start_time = line:match("%d+:%d+:%d+")
		if start_time then
			if start_time > timestamp then
				return previous_line, line_nr - 1
			end
		end
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
	vim.api.nvim_set_current_line(line)
end

function M.previous_speech()
	if state.line_nr - 1 > 0 then
		state.line_nr = state.line_nr - 1
	end

	vim.api.nvim_set_current_line(state.subtitle_file_lines[state.line_nr])
end

function M.next_speech()
	if state.line_nr + 1 < #state.subtitle_file_lines + 1 then
		state.line_nr = state.line_nr + 1
	end

	vim.api.nvim_set_current_line(state.subtitle_file_lines[state.line_nr])
end

function M.replace_symbols()
	local current_line = vim.api.nvim_get_current_line()
	for i, v in pairs(state.opts.symbols) do
		current_line = string.gsub(current_line, i, v .. " ")
	end
	vim.api.nvim_set_current_line(current_line)
end

return M
