local M = {}

M.opts = {}

M.descs = {
  get_speech = "Get current speech from video",
  previous_speech = "Get previous speech from video",
  next_speech = "Get next speech from video",
  replace_symbols = "Replace math symbols on line by latex",
}

M.subtitles_file_path = ""
M.subtitle_file_lines = {}

M.line_nr = 0

return M
