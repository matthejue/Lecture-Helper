local M = {}

M.opts = {}

M.descs = {
  current_speech = "Get current speech from video",
  update_linenr = "Updates timestamp to current line",
  previous_speech = "Get previous speech from video",
  next_speech = "Get next speech from video",
  merge_lines = "Merge newly inserted lines",
  goto_speech = "Goto timestamp position in video",
  replace_symbols = "Replace math symbols on line by latex",
}

M.subtitles_file_path = ""
M.subtitle_file_lines = {}

M.line_nr = 0

return M
