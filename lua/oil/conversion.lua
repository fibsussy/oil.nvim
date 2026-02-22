local config = require("oil.config")
local fs = require("oil.fs")
local log = require("oil.log")
local util = require("oil.util")
local M = {}

local default_converters = {
  image = {
    extensions = { png = true, jpg = true, jpeg = true, gif = true, webp = true, bmp = true, tiff = true, ico = true, heic = true, heif = true, avif = true },
    get_command = function(src, dst, src_ext, dst_ext)
      return { "magick", src, dst }
    end,
  },
  video = {
    extensions = { mp4 = true, mkv = true, avi = true, mov = true, webm = true, flv = true, wmv = true, m4v = true },
    get_command = function(src, dst, src_ext, dst_ext)
      return { "ffmpeg", "-y", "-i", src, dst }
    end,
  },
  audio = {
    extensions = { mp3 = true, wav = true, flac = true, aac = true, ogg = true, m4a = true, wma = true, opus = true },
    get_command = function(src, dst, src_ext, dst_ext)
      return { "ffmpeg", "-y", "-i", src, dst }
    end,
  },
}

local video_to_gif_extensions = { gif = true }

local default_extractors = {
  zip = { cmd = "unzip", args = { "-o", "$SRC", "-d", "$DIR" }, list_cmd = { "unzip", "-l", "$SRC" } },
  ["tar.gz"] = { cmd = "tar", args = { "-xzf", "$SRC", "-C", "$DIR" }, list_cmd = { "tar", "-tzf", "$SRC" } },
  ["tar.xz"] = { cmd = "tar", args = { "-xJf", "$SRC", "-C", "$DIR" }, list_cmd = { "tar", "-tJf", "$SRC" } },
  ["tar.bz2"] = { cmd = "tar", args = { "-xjf", "$SRC", "-C", "$DIR" }, list_cmd = { "tar", "-tjf", "$SRC" } },
  ["tar"] = { cmd = "tar", args = { "-xf", "$SRC", "-C", "$DIR" }, list_cmd = { "tar", "-tf", "$SRC" } },
  gz = { cmd = "gunzip", args = { "-k", "$SRC" }, single_file = true },
  bz2 = { cmd = "bunzip2", args = { "-k", "$SRC" }, single_file = true },
  xz = { cmd = "unxz", args = { "-k", "$SRC" }, single_file = true },
  ["7z"] = { cmd = "7z", args = { "x", "$SRC", "-o$DIR", "-y" }, list_cmd = { "7z", "l", "$SRC" } },
  rar = { cmd = "unrar", args = { "x", "-y", "$SRC", "$DIR/" }, list_cmd = { "unrar", "l", "$SRC" } },
}

local archive_extensions = {}
for ext, _ in pairs(default_extractors) do
  archive_extensions[ext] = true
end

M.get_file_extension = function(filename)
  local basename = vim.fs.basename(filename)
  if not basename then return nil end
  
  if basename:match("%.tar%.[^.]+$") then
    local ext = basename:match("%.tar%.[^.]+$")
    return ext:sub(2)
  end
  
  local ext = basename:match("%.[^.]+$")
  if ext then
    return ext:sub(2):lower()
  end
  return nil
end

M.is_archive = function(url)
  local ext = M.get_file_extension(url)
  if not ext then return false end
  
  local extractors = config.file_conversions and config.file_conversions.extractors or default_extractors
  local user_archive_exts = config.file_conversions and config.file_conversions.archive_extensions
  
  if user_archive_exts then
    return user_archive_exts[ext] == true
  end
  
  return extractors[ext] ~= nil
end

M.get_archive_type = function(url)
  local ext = M.get_file_extension(url)
  if not ext then return nil end
  
  local extractors = config.file_conversions and config.file_conversions.extractors or default_extractors
  if extractors[ext] then
    return ext
  end
  
  return nil
end

M.is_conversion = function(src_url, dest_url)
  local conversion_config = config.file_conversions
  if not conversion_config or not conversion_config.enabled then
    return false
  end
  
  local src_ext = M.get_file_extension(src_url)
  local dst_ext = M.get_file_extension(dest_url)
  
  if not src_ext or not dst_ext then
    return false
  end
  
  if src_ext == dst_ext then
    return false
  end
  
  local converters = conversion_config.converters or {}
  
  for conv_type, default_conv in pairs(default_converters) do
    local conv_config = converters[conv_type] or default_conv
    local exts = conv_config.extensions or default_conv.extensions
    
    if exts[src_ext] and exts[dst_ext] then
      return true, conv_type, src_ext, dst_ext
    end
  end
  
  if converters.video and converters.video.extensions then
    local video_exts = converters.video.extensions
    if video_exts[src_ext] and video_to_gif_extensions[dst_ext] then
      return true, "video", src_ext, dst_ext
    end
  elseif default_converters.video.extensions[src_ext] and video_to_gif_extensions[dst_ext] then
    return true, "video", src_ext, dst_ext
  end
  
  for _, custom in ipairs(converters.custom or {}) do
    if custom.from:lower() == src_ext and custom.to:lower() == dst_ext then
      return true, "custom", src_ext, dst_ext, custom
    end
  end
  
  return false
end

M.is_extraction_trigger = function(dest_url)
  local conversion_config = config.file_conversions
  if not conversion_config or not conversion_config.enabled then
    return false
  end
  
  local _, dst_path = util.parse_url(dest_url)
  if not dst_path then return false end
  
  local dst_ext = M.get_file_extension(dst_path)
  if not dst_ext then return false end
  
  local extract_patterns = { "unzip", "untar", "extract", "unpack" }
  for _, pattern in ipairs(extract_patterns) do
    if dst_ext == pattern then
      local basename = vim.fs.basename(dst_path)
      local dest_name = basename:match("^(.+)%." .. pattern .. "$")
      if dest_name then
        return true, dest_name
      end
    end
  end
  
  return false
end

M.get_extraction_dest_dir = function(src_url, trigger_name)
  local scheme, src_path = util.parse_url(src_url)
  if not src_path then return nil end
  
  local parent = vim.fn.fnamemodify(src_path, ":h")
  local dest_path = parent .. "/" .. trigger_name .. "/"
  
  return (scheme or "oil://") .. dest_path
end

M.get_extract_command = function(src_path, dest_dir, ext)
  local extractors = config.file_conversions and config.file_conversions.extractors or default_extractors
  local extractor = extractors[ext]
  if not extractor then return nil end
  
  local args = {}
  for _, arg in ipairs(extractor.args) do
    arg = arg:gsub("$SRC", src_path)
    arg = arg:gsub("$DIR", dest_dir)
    table.insert(args, arg)
  end
  
  return extractor.cmd, args, extractor.single_file
end

M.get_conversion_command = function(src_path, dest_path, conv_type, src_ext, dst_ext, custom)
  local converters = config.file_conversions and config.file_conversions.converters or {}
  
  if conv_type == "custom" and custom then
    if type(custom.cmd) == "table" then
      local cmd = {}
      for _, part in ipairs(custom.cmd) do
        part = part:gsub("{src}", src_path)
        part = part:gsub("{dst}", dest_path)
        table.insert(cmd, part)
      end
      return cmd
    else
      local cmd = custom.cmd:gsub("{src}", src_path)
      cmd = cmd:gsub("{dst}", dest_path)
      return vim.split(cmd, " ")
    end
  end
  
  local conv_config = converters[conv_type] or default_converters[conv_type]
  if conv_config and conv_config.get_command then
    return conv_config.get_command(src_path, dest_path, src_ext, dst_ext)
  end
  
  if conv_type == "video" or conv_type == "audio" then
    return { "ffmpeg", "-y", "-i", src_path, dest_path }
  end
  
  return { "magick", src_path, dest_path }
end

M.list_archive_contents = function(src_path, ext, cb)
  local extractors = config.file_conversions and config.file_conversions.extractors or default_extractors
  local extractor = extractors[ext] or default_extractors[ext]
  
  if not extractor or not extractor.list_cmd then
    return cb(nil, {})
  end
  
  local list_cmd = {}
  for _, part in ipairs(extractor.list_cmd) do
    part = part:gsub("$SRC", src_path)
    table.insert(list_cmd, part)
  end
  
  local contents = {}
  local jid = vim.fn.jobstart(list_cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line and line ~= "" and not line:match("^%s*$") then
          if ext == "zip" then
            local name = line:match("%s+(.+)%s*$")
            if name and not name:match("^%s*$") and not name:match("/$") then
              table.insert(contents, name)
            end
          elseif ext == "7z" then
            local name = line:match("^.-:%s*(.+)$") or line:match("^%S+%s+(.+)$")
            if name and not name:match("^%s*$") then
              table.insert(contents, vim.trim(name))
            end
          else
            local name = line:gsub("^%./", "")
            if name and name ~= "" and not name:match("/$") then
              table.insert(contents, name)
            end
          end
        end
      end
    end,
    on_exit = function(_, code)
      if code == 0 then
        cb(nil, contents)
      else
        cb("Failed to list archive contents", nil)
      end
    end,
  })
  
  if jid <= 0 then
    cb("Failed to start archive list command", nil)
  end
end

M.check_tool_available = function(tool)
  return vim.fn.executable(tool) == 1
end

M.get_converter_tool = function(conv_type)
  if conv_type == "image" then
    return "magick"
  elseif conv_type == "video" or conv_type == "audio" then
    return "ffmpeg"
  end
  return nil
end

return M
