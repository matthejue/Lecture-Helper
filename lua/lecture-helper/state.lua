local M = {}

M.opts = {}

M.descs = {
  current_speech = "Get current speech from video",
  update_linenr = "Updates timestamp to current line",
  previous_speech = "Get previous speech from video",
  next_speech = "Get next speech from video",
  merge_lines = "Merge newly inserted lines",
  slice_to_line_above = "Paste slice up to cursor position above",
  goto_speech = "Goto position of timestamp in video",
  goto_timestamp = "Goto closest timestamp to video runtime",
  replace_symbols = "Replace math symbols on line by latex",
}

M.subtitles_file_path = ""
M.subtitle_file_lines = {}

M.line_nr = 0

return M
