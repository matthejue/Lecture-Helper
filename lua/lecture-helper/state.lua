local M = {}

M.opts = {}

M.descs = {
  current_speech = "Get current speech from video",
  update_linenr = "Updates current line to current timetsamp",
  update_timestamp = "Updates timestamp to current timestamp",
  insert_playerctl_timestamp_line = "Insert '- hh:mm:ss' using current playerctl position",
  previous_speech = "Get previous speech from video",
  next_speech = "Get next speech from video",
  merge_lines = "Merge newly inserted lines",
  slice_to_line_above = "Paste slice up to cursor position above",
  slice_to_line_below = "Paste slice from cursor position below",
  remove_slice = "Remove slice up to cursor position",
  goto_speech = "Goto position of timestamp in video",
  goto_timestamp = "Goto closest timestamp to video runtime",
  replace_symbols = "Replace math symbols on line by latex",
  convert_textmode = "Convert mathmode to textmode",
  remove_words = "Removes unneeded words",
  execute_line = "Execute line",
  open_link = "Open link",
  open_image_from_img_tag = "Open image from <img src=\"...\"> on current line",
  preview_youtube_timestamp_frame = "Preview youtube frame at timestamp",
  toggle_timestamp_frame_autopreview = "Toggle auto-copy/open cached timestamp frame on line move",
  toggle_video_timestamp_follow = "Toggle following the video timestamp in the current file",
  goto_current_video_timestamp_line = "Jump to current video timestamp line once",
  generate_pdf_and_open = "Generate PDF and open",
  update_pdf = "Update PDF",
  convert_line_to_node = "Convert line to mindmap node",
  convert_lines_to_nodes = "Convert selected lines to mindmap children",
  remove_disturbing_prefix = "Remove leading bullet-like character from selected lines",
  bolden_timestamped_line = "Bolden timestamped line",
  box_line_primary = "Insert single-line comment box (primary char)",
  box_block_primary = "Insert 3-line comment box (primary char)",
  box_line_secondary = "Insert single-line comment box (secondary char)",
  box_block_secondary = "Insert 3-line comment box (secondary char)",
  box_set_comment = "Set box comment prefix",
}

M.subtitles_file_path = ""
M.subtitle_file_lines = {}

M.line_nr = 0

return M
