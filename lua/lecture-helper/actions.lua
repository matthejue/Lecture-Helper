local state = require("lecture-helper.state")

local M = {}
local PLAYERCTL_POSITION_WORKAROUND_WAIT_MS = 150
local TIMESTAMP_FRAME_AUTOPREVIEW_GROUP = vim.api.nvim_create_augroup(
  "LectureHelperTimestampFrameAutopreview",
  { clear = false }
)
local TIMESTAMP_FRAME_AUTOPREVIEW_TMP_DIR = "/tmp/lecture_helper"
local TIMESTAMP_FRAME_AUTOPREVIEW_IMG = TIMESTAMP_FRAME_AUTOPREVIEW_TMP_DIR .. "/current.png"
local TIMESTAMP_FRAME_AUTOPREVIEW_LOCK = TIMESTAMP_FRAME_AUTOPREVIEW_TMP_DIR .. "/nsxiv.lock"
local timestamp_frame_autopreview_autocmd_id = nil
local timestamp_frame_autopreview_last_line_by_buf = {}
local timestamp_frame_autopreview_viewer_job_id = nil
local VIDEO_TIMESTAMP_FOLLOW_INTERVAL_SECONDS = 10
local FOLLOW_VIDEO_TIMESTAMP_ONCE_SKIP_PLAYERCTL_WORKAROUND = false
local video_timestamp_follow_timer = nil
local video_timestamp_follow_last_line_by_buf = {}

local function apply_playerctl_position_workaround()
  if not state.opts.playerctl_position_workaround then
    return
  end

  local handle = io.popen("playerctl position 0.000001+")
  if handle then
    handle:close()
  end
  vim.wait(PLAYERCTL_POSITION_WORKAROUND_WAIT_MS)
  handle = io.popen("playerctl position 0.000001-")
  if handle then
    handle:close()
  end
  vim.wait(PLAYERCTL_POSITION_WORKAROUND_WAIT_MS)
end

local function maybe_lowercase(line)
  if state.opts.lowercase_inserted_lines then
    return string.lower(line)
  end
  return line
end

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

local function get_playerctl_position(skip_workaround)
  if not skip_workaround then
    apply_playerctl_position_workaround()
  end
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
    vim.api.nvim_set_current_line(maybe_lowercase(state.opts.prefix .. line))
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
    insert_lines[i + 1] = maybe_lowercase(
      state.opts.prefix .. state.subtitle_file_lines[state.line_nr - (below and n - 1 or 0) + i]
    )
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
  local next_line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]

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

function M.convert_textmode()
  local current_line = vim.api.nvim_get_current_line()
  current_line = current_line:gsub("%$", "")
  -- look for the symbol _ and replace it and the word directly after it by \textsubscript{word}
  current_line = current_line:gsub("_{([^}]+)}", "\\textsubscript{%1}")
  current_line = current_line:gsub("_(%S)", "\\textsubscript{%1}")
  current_line = current_line:gsub("%^{([^}]+)}", "\\textsuperscript{%1}")
  current_line = current_line:gsub("%^(%S)", "\\textsuperscript{%1}")
  current_line = current_line:gsub("\\alert{([^}]*)}", "\\cul{%1}")
  current_line = current_line:gsub("\\ne", "!=")
  current_line = current_line:gsub("\\in", "€")
  current_line = current_line:gsub("\\cup", "U")
  current_line = current_line:gsub("\\cap", "n")
  current_line = current_line:gsub("\\subset", "C")
  current_line = current_line:gsub("\\Phi", "Phi")
  current_line = current_line:gsub("\\phi", "Phi")
  current_line = current_line:gsub("\\not", "!")
  current_line = current_line:gsub("\\emptyset", "\\{\\}")
  current_line = current_line:gsub("\\equiv", "equiv")
  current_line = current_line:gsub("\\Rightarrow", "=>")
  current_line = current_line:gsub("\\rightarrow", "->")
  current_line = current_line:gsub("\\alpha", "alpha")
  current_line = current_line:gsub("α", "alpha")
  current_line = current_line:gsub("\\upnu", "v")
  current_line = current_line:gsub("\\pi", "pi")
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

function M.execute_line()
  local line = vim.api.nvim_get_current_line()

  local original_cwd = vim.fn.getcwd()
  local file_dir = vim.fn.expand("%:p:h")

  vim.cmd("lcd " .. vim.fn.fnameescape(file_dir))
  vim.fn.system(line)
  vim.cmd("lcd " .. vim.fn.fnameescape(original_cwd))
end

function M.open_link()
  local api = vim.api
  local bufnr = api.nvim_get_current_buf()
  local cur_line = api.nvim_win_get_cursor(0)[1]

  for i = cur_line - 1, 1, -1 do
    local line = api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
    local url = line:match("#%s*.-%s*-%s*(https?://%S+)")

    if url then
      vim.fn.jobstart({ "xdg-open", url }, { detach = true })
      return
    end
  end

  print("No lecture URL found above cursor.")
end

function M.open_image_from_img_tag()
  local line = vim.api.nvim_get_current_line()
  local image_path = line:match('<img%s+.-src%s*=%s*"([^"]+)"')
    or line:match("<img%s+.-src%s*=%s*'([^']+)'")

  if not image_path then
    print('No image src path found on current line (expected <img ... src="...">).')
    return
  end

  local expanded_path = vim.fn.expand(image_path)
  if not expanded_path:match("^/") then
    local file_dir = vim.fn.expand("%:p:h")
    expanded_path = file_dir .. "/" .. expanded_path
  end
  expanded_path = vim.fn.fnamemodify(expanded_path, ":p")

  if vim.fn.filereadable(expanded_path) ~= 1 then
    print("Image file not found: " .. expanded_path)
    return
  end

  local viewer = (state.opts.youtube_preview and state.opts.youtube_preview.viewer) or "nsxiv"
  local cmd = vim.split(viewer, "%s+")
  if #cmd == 0 or not cmd[1] or cmd[1] == "" then
    cmd = { "nsxiv" }
  end

  table.insert(cmd, expanded_path)
  local job_id = vim.fn.jobstart(cmd, { detach = true })
  if job_id <= 0 then
    print("Failed to open image with viewer: " .. viewer)
  end
end

local function get_timestamp_from_line(line)
  local h, m, s = line:match("(%d+):(%d+):(%d+)")
  if not h then
    return nil
  end

  return string.format("%02d:%02d:%02d", tonumber(h), tonumber(m), tonumber(s))
end

local function find_youtube_url(bufnr, cur_line)
  for i = cur_line - 1, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
    local url = line:match("xdg%-open%s+(https?://%S+)")
    if url then
      return url
    end
  end

  local total = vim.api.nvim_buf_line_count(bufnr)
  for i = cur_line + 1, total do
    local line = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
    local url = line:match("xdg%-open%s+(https?://%S+)")
    if url then
      return url
    end
  end

  return nil
end

local function get_script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return vim.fn.fnamemodify(src, ":h")
end

local function get_video_timestamp_follow_line(script_path, file_path, current_timestamp)
  local cmd = {
    "python3",
    script_path,
    "--file",
    file_path,
    "--current-time",
    current_timestamp,
  }
  local output = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 or #output == 0 then
    return nil
  end

  return tonumber(output[1])
end

local function get_video_timestamp_follow_interval_ms()
  local seconds = tonumber(state.opts.video_timestamp_follow_interval_seconds)
    or VIDEO_TIMESTAMP_FOLLOW_INTERVAL_SECONDS
  if seconds <= 0 then
    seconds = VIDEO_TIMESTAMP_FOLLOW_INTERVAL_SECONDS
  end

  return math.floor(seconds * 1000)
end

function M.follow_video_timestamp_once()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype ~= "" then
    return
  end

  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" or vim.fn.filereadable(file_path) ~= 1 then
    return
  end

  local current_timestamp = get_playerctl_position(FOLLOW_VIDEO_TIMESTAMP_ONCE_SKIP_PLAYERCTL_WORKAROUND)
  if not current_timestamp then
    return
  end

  local script_path = get_script_dir() .. "/scripts/find_latest_timestamp_line.py"
  if vim.fn.filereadable(script_path) ~= 1 then
    return
  end

  local line_nr = get_video_timestamp_follow_line(script_path, file_path, current_timestamp)
  if not line_nr or line_nr < 1 then
    return
  end

  local max_line = vim.api.nvim_buf_line_count(bufnr)
  line_nr = math.min(line_nr, max_line)
  if video_timestamp_follow_last_line_by_buf[bufnr] == line_nr then
    return
  end
  video_timestamp_follow_last_line_by_buf[bufnr] = line_nr

  local ok = pcall(vim.api.nvim_win_set_cursor, 0, { line_nr, 0 })
  if ok then
    vim.cmd("normal! zz")
  end
end

function M.goto_current_video_timestamp_line()
  M.follow_video_timestamp_once()
end

function M.toggle_video_timestamp_follow()
  if video_timestamp_follow_timer then
    video_timestamp_follow_timer:stop()
    video_timestamp_follow_timer:close()
    video_timestamp_follow_timer = nil
    video_timestamp_follow_last_line_by_buf = {}
    print("Video timestamp follow disabled.")
    return
  end

  local script_path = get_script_dir() .. "/scripts/find_latest_timestamp_line.py"
  if vim.fn.filereadable(script_path) ~= 1 then
    print("Timestamp follow script not found: " .. script_path)
    return
  end

  local interval_ms = get_video_timestamp_follow_interval_ms()
  video_timestamp_follow_timer = vim.loop.new_timer()
  video_timestamp_follow_timer:start(
    0,
    interval_ms,
    vim.schedule_wrap(function()
      if video_timestamp_follow_timer then
        M.follow_video_timestamp_once()
      end
    end)
  )

  print("Video timestamp follow enabled.")
end

local function sanitize_cache_name(name)
  local normalized = name:gsub("%.[^%.]+$", "")
  normalized = normalized:gsub("[^%w%-%._]", "_")
  if normalized == "" then
    return "buffer"
  end
  return normalized
end

local function timestamp_to_filename(timestamp)
  return timestamp:gsub(":", "-") .. ".png"
end

local function get_timestamp_frame_path(bufnr, timestamp)
  local buffer_path = vim.api.nvim_buf_get_name(bufnr)
  if buffer_path == "" then
    return nil
  end

  local file_dir = vim.fn.fnamemodify(buffer_path, ":h")
  local file_name = vim.fn.fnamemodify(buffer_path, ":t")
  local cache_dir = file_dir .. "/.frames/" .. sanitize_cache_name(file_name)
  return cache_dir .. "/" .. timestamp_to_filename(timestamp)
end

local function ensure_timestamp_preview_tmp_dir()
  vim.fn.mkdir(TIMESTAMP_FRAME_AUTOPREVIEW_TMP_DIR, "p")
  return vim.fn.isdirectory(TIMESTAMP_FRAME_AUTOPREVIEW_TMP_DIR) == 1
end

local function remove_autopreview_lock()
  if vim.fn.filereadable(TIMESTAMP_FRAME_AUTOPREVIEW_LOCK) == 1 then
    vim.fn.delete(TIMESTAMP_FRAME_AUTOPREVIEW_LOCK)
  end
end

local function is_pid_running(pid)
  if not pid or pid <= 0 then
    return false
  end

  vim.fn.system({ "kill", "-0", tostring(pid) })
  return vim.v.shell_error == 0
end

local function is_autopreview_viewer_running()
  if timestamp_frame_autopreview_viewer_job_id then
    local status = vim.fn.jobwait({ timestamp_frame_autopreview_viewer_job_id }, 0)[1]
    if status == -1 then
      return true
    end
    timestamp_frame_autopreview_viewer_job_id = nil
  end

  if vim.fn.filereadable(TIMESTAMP_FRAME_AUTOPREVIEW_LOCK) == 1 then
    local lines = vim.fn.readfile(TIMESTAMP_FRAME_AUTOPREVIEW_LOCK)
    local pid = tonumber(lines[1] or "")
    if is_pid_running(pid) then
      return true
    end
    remove_autopreview_lock()
  end

  return false
end

local function maybe_open_autopreview_viewer()
  if is_autopreview_viewer_running() then
    return
  end

  local job_id = vim.fn.jobstart({ "nsxiv", TIMESTAMP_FRAME_AUTOPREVIEW_IMG }, {
    on_exit = function()
      timestamp_frame_autopreview_viewer_job_id = nil
      remove_autopreview_lock()
    end,
  })

  if job_id <= 0 then
    print("Failed to open nsxiv for timestamp autopreview.")
    return
  end

  timestamp_frame_autopreview_viewer_job_id = job_id
  local pid = vim.fn.jobpid(job_id)
  if pid and pid > 0 then
    vim.fn.writefile({ tostring(pid) }, TIMESTAMP_FRAME_AUTOPREVIEW_LOCK)
  end
end

local function update_autopreview_image(bufnr, row)
  if vim.bo[bufnr].buftype ~= "" then
    return
  end

  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  local timestamp = get_timestamp_from_line(line)
  if not timestamp then
    return
  end

  local frame_path = get_timestamp_frame_path(bufnr, timestamp)
  if not frame_path or vim.fn.filereadable(frame_path) ~= 1 then
    return
  end

  if not ensure_timestamp_preview_tmp_dir() then
    print("Failed to create directory: " .. TIMESTAMP_FRAME_AUTOPREVIEW_TMP_DIR)
    return
  end

  if vim.fn.filereadable(TIMESTAMP_FRAME_AUTOPREVIEW_IMG) == 1 then
    vim.fn.delete(TIMESTAMP_FRAME_AUTOPREVIEW_IMG)
  end

  local ok, err = vim.loop.fs_copyfile(frame_path, TIMESTAMP_FRAME_AUTOPREVIEW_IMG)
  if not ok then
    print("Failed to copy image to " .. TIMESTAMP_FRAME_AUTOPREVIEW_IMG .. ": " .. (err or "unknown error"))
    return
  end

  maybe_open_autopreview_viewer()
end

function M.preview_youtube_timestamp_frame()
  local line = vim.api.nvim_get_current_line()
  local timestamp = get_timestamp_from_line(line)
  if not timestamp then
    print("Current line has no timestamp (expected hh:mm:ss).")
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local url = find_youtube_url(bufnr, cur_line)
  if not url then
    print("No youtube URL found in xdg-open lines around cursor.")
    return
  end

  local script_path = get_script_dir() .. "/scripts/youtube_timestamp_preview.py"
  if vim.fn.filereadable(script_path) ~= 1 then
    print("Preview script not found: " .. script_path)
    return
  end

  local preview_opts = state.opts.youtube_preview or {}
  local viewer = preview_opts.viewer or "nsxiv"
  local file_dir = vim.fn.expand("%:p:h")
  local file_name = vim.fn.expand("%:t")
  local cache_dir = file_dir .. "/.frames/" .. sanitize_cache_name(file_name)

  local cmd = {
    "python3",
    script_path,
    "--url",
    url,
    "--timestamp",
    timestamp,
    "--viewer",
    viewer,
    "--cache-dir",
    cache_dir,
  }

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stderr = function(_, data)
      if not data then
        return
      end
      for _, line_text in ipairs(data) do
        if line_text and line_text ~= "" then
          print(line_text)
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        print("Failed to preview timestamp frame.")
      end
    end,
  })
end

function M.toggle_timestamp_frame_autopreview()
  if timestamp_frame_autopreview_autocmd_id then
    vim.api.nvim_del_autocmd(timestamp_frame_autopreview_autocmd_id)
    timestamp_frame_autopreview_autocmd_id = nil
    timestamp_frame_autopreview_last_line_by_buf = {}
    print("Timestamp frame autocheck disabled.")
    return
  end

  timestamp_frame_autopreview_autocmd_id = vim.api.nvim_create_autocmd("CursorMoved", {
    group = TIMESTAMP_FRAME_AUTOPREVIEW_GROUP,
    callback = function(ev)
      local row = vim.api.nvim_win_get_cursor(0)[1]
      if timestamp_frame_autopreview_last_line_by_buf[ev.buf] == row then
        return
      end

      timestamp_frame_autopreview_last_line_by_buf[ev.buf] = row
      update_autopreview_image(ev.buf, row)
    end,
  })

  print("Timestamp frame autocheck enabled.")
end

local current_file_path = nil
local current_output_pdf = nil
local zathura_handle = nil

local function generate_pdf()
    if not current_file_path or not current_output_pdf then
        print("No file is currently being tracked.")
        return false
    end

    local dot_command = string.format("dot -Tpdf %s -o %s", current_file_path, current_output_pdf)
    vim.fn.system(dot_command)

    if vim.v.shell_error ~= 0 then
        print("Failed to generate PDF. Check if 'dot' is installed and the file is valid.")
        return false
    end

    return true
end

function M.generate_pdf_and_open()
    -- Get the current file path
    current_file_path = vim.fn.expand("%:p")
    local file_ext = vim.fn.expand("%:e")
    current_output_pdf = vim.fn.expand("%:p:r") .. ".pdf"

    -- Ensure the file is a .dot file
    if file_ext ~= "dot" then
        print("This function only works with .dot files.")
        return
    end

    -- Generate the PDF
    if not generate_pdf() then
        return
    end

    -- Open the PDF with zathura if not already open
    if not zathura_handle then
        zathura_handle = vim.loop.spawn("zathura", { args = { current_output_pdf } }, function(code, signal)
            -- Reset the handle when zathura exits
            zathura_handle = nil
        end)
        print("PDF opened successfully.")
    else
        print("PDF already open in zathura.")
    end
end

function M.update_pdf()
    if not current_file_path or not current_output_pdf then
        print("No file is currently being tracked. Run generate_pdf_and_open first.")
        return
    end

    -- Regenerate the PDF
    if generate_pdf() then
        print("PDF updated successfully.")
    end
end

function M.convert_line_to_node()
  local line = vim.api.nvim_get_current_line()
  if not line or line == "" then
    print("Invalid input: line is empty or nil.")
    return
    end

    -- Capture leading whitespace for indentation
    local indent = line:match("^(%s*)")
    local content = line:match("^%s*(.*)")

    local new_lines = {
        string.format("%schild {", indent),
        string.format("%s  node {%s}", indent, content),
        string.format("%s}", indent),
    }

  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  vim.api.nvim_buf_set_lines(0, row, row + 1, false, new_lines)
end

function M.convert_lines_to_nodes(start_line, end_line)
  local mode = vim.fn.mode()
  local in_visual = mode == "v" or mode == "V" or mode == ""

  if not start_line or not end_line then
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    start_line = start_pos[2]
    end_line = end_pos[2]
  end

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then
    return
  end

  local new_lines = {}
  for _, line in ipairs(lines) do
    local indent = line:match("^(%s*)") or ""
    local content = line:match("^%s*(.-)%s*$") or ""

    table.insert(new_lines, indent .. "child {")
    table.insert(new_lines, indent .. "  node {" .. content .. "}")
    table.insert(new_lines, indent .. "}")
  end

  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, new_lines)

  if in_visual then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, true, true), "n", true)
  end
  vim.api.nvim_win_set_cursor(0, { start_line, 0 })
end

function M.remove_disturbing_prefix(start_line, end_line)
  local mode = vim.fn.mode()
  local in_visual = mode == "v" or mode == "V" or mode == ""

  if not start_line or not end_line then
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    start_line = start_pos[2]
    end_line = end_pos[2]
  end

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then
    return
  end

  local new_lines = {}
  for _, line in ipairs(lines) do
    local cleaned = line:gsub("^(%s*)[^%w%s]+%s*", "%1")
    table.insert(new_lines, cleaned)
  end

  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, new_lines)

  if in_visual then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, true, true), "n", true)
  end
  vim.api.nvim_win_set_cursor(0, { start_line, 0 })
end

function M.bolden_timestamped_line()
  local line_num = vim.api.nvim_win_get_cursor(0)[1] -- Get current line number
  local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]

  if not line then return end

    -- Check if the line already has bold formatting in the standard format
    if line:match("^%- %d%d:%d%d:%d%d %*%*(.-)%*%*$") then
        -- Remove bold formatting from standard format
        local new_line = line:gsub("(%- %d%d:%d%d:%d%d )%*%*(.-)%*%*", "%1%2")
        vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, { new_line })
    elseif line:match("^%- %d%d:%d%d:%d%d %.%.%. %*%*(.-)%*%*$") then
        -- Remove bold formatting from ellipsis format
        local new_line = line:gsub("(%- %d%d:%d%d:%d%d %.%.%. )%*%*(.-)%*%*", "%1%2")
        vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, { new_line })
    elseif line:match("^%- %d%d:%d%d:%d%d %.%.%. (.+)$") then
        -- Add bold formatting for the ellipsis format
        local new_line = line:gsub("(- %d%d:%d%d:%d%d %.%.%. )(.+)", "%1**%2**")
        vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, { new_line })
    else
        -- Add bold formatting for the standard format
        local new_line = line:gsub("(- %d%d:%d%d:%d%d )(.+)", "%1**%2**")
        vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, { new_line })
    end
end

local function build_box_lines(text, fill_char, is_block, prefix_base)
  local box_opts = state.opts.box or {}
  local indent = prefix_base or ""
  local prefix = indent .. (box_opts.comment or "")

  local max_width = box_opts.width or 79
  local available_width = max_width - #prefix
  if available_width <= 0 then
    print("Box width too small for current indent/comment.")
    return nil, nil
  end

  local effective_padding = (is_block and 0) or (box_opts.padding or 0)
  local text_len = #text
  local padded_len = text_len + effective_padding * 2
  local content = text
  if padded_len > available_width then
    local allow_text = math.max(available_width - effective_padding * 2, 0)
    content = text:sub(1, allow_text)
    text_len = #content
    padded_len = text_len + effective_padding * 2
    print("Box text trimmed to fit width.")
  end

  local content_width = available_width
  local filler = fill_char
  if not filler or filler == "" then
    filler = "-"
  end

  local available = content_width - padded_len
  local left_fill = math.floor(available / 2)
  local right_fill = available - left_fill

  local border = prefix .. filler:rep(content_width)
  local middle
  if is_block then
    middle = prefix
      .. string.rep(" ", left_fill)
      .. string.rep(" ", effective_padding)
      .. content
      .. string.rep(" ", effective_padding)
      .. string.rep(" ", right_fill)
  else
    middle = prefix
      .. filler:rep(left_fill)
      .. string.rep(" ", effective_padding)
      .. content
      .. string.rep(" ", effective_padding)
      .. filler:rep(right_fill)
  end

  local lines
  if is_block then
    lines = { border, middle, border }
  else
    lines = { middle }
  end

  local text_col = #prefix + left_fill + effective_padding

  return lines, text_col
end

local function insert_box(use_secondary, is_block)
  local text = vim.fn.input("Box text: ")
  if not text then
    return
  end
  text = text:gsub("^%s*(.-)%s*$", "%1")
  if text == "" then
    return
  end

  local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
  local current_line = vim.api.nvim_get_current_line()
  local prefix_base = current_line:sub(1, col0)

  local box_opts = state.opts.box or {}
  local chars = box_opts.chars or {}
  local fill_char = use_secondary and chars.secondary or chars.primary

  local lines, text_col = build_box_lines(text, fill_char, is_block, prefix_base)
  if not lines then
    return
  end
  local zero_based_row = row - 1
  if #lines == 1 then
    vim.api.nvim_buf_set_lines(0, zero_based_row, zero_based_row + 1, false, lines)
  else
    vim.api.nvim_buf_set_lines(0, zero_based_row, zero_based_row + 1, false, { lines[1] })
    vim.api.nvim_buf_set_lines(0, zero_based_row + 1, zero_based_row + 1, false, { lines[2], lines[3] })
  end

  local target_row = zero_based_row + (#lines == 1 and 1 or 2)
  vim.api.nvim_win_set_cursor(0, { target_row, text_col })
end

function M.insert_box_line(use_secondary)
  insert_box(use_secondary, false)
end

function M.insert_box_block(use_secondary)
  insert_box(use_secondary, true)
end

function M.set_box_comment()
  local current = state.opts.box and state.opts.box.comment or ""
  local input = vim.fn.input("Box comment prefix: ", current)
  if not input or input == "" then
    return
  end
  state.opts.box = state.opts.box or {}
  state.opts.box.comment = input
end

return M
