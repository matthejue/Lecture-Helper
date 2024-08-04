local M = {}

M.opts = {}

M.descs = {
  current_speech = "Get current speech from video",
  update_linenr = "Updates current line to current timetsamp",
  update_timestamp = "Updates timestamp to current timestamp",
  previous_speech = "Get previous speech from video",
  next_speech = "Get next speech from video",
  merge_lines = "Merge newly inserted lines",
  slice_to_line_above = "Paste slice up to cursor position above",
  remove_slice = "Remove slice up to cursor position",
  goto_speech = "Goto position of timestamp in video",
  goto_timestamp = "Goto closest timestamp to video runtime",
  replace_symbols = "Replace math symbols on line by latex",
  remove_words = "Removes unneeded words",
}

M.subtitles_file_path = ""
M.subtitle_file_lines = {}

M.line_nr = 0

return M
