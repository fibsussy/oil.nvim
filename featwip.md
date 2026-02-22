# File Conversions Feature WIP

## Overview
Add intuitive file conversions to oil.nvim - rename a file to change its extension and it converts instead of just copying.

## Core Use Cases

### 1. Image Conversions
```
image.jpeg -> image.png     (converts using ffmpeg/imagemagick)
video.mp4 -> video.gif      (converts video to gif)
```

### 2. Archive Extraction  
```
something.zip -> something.unzip   (extracts archive)
something.tar.gz -> something.untar (extracts tarball)
```

### 3. Other Conversions (future)
```
document.md -> document.pdf   (pandoc conversion)
audio.mp3 -> audio.wav        (ffmpeg audio conversion)
```

## Implementation Plan

### Phase 1: Core Infrastructure
- [x] Fork repo and create feature branch
- [x] Add `file_conversions` config option
- [x] Create conversion module (`lua/oil/conversion.lua`)
- [x] Hook into copy action detection in mutator

### Phase 2: Action Handling
- [x] Detect extension changes in copy/move actions
- [x] Create new `convert` action type
- [x] Create new `extract` action type
- [x] Render conversion actions in confirmation popup
- [x] Execute conversions with progress indication

### Phase 3: Archive Handling
- [x] Detect `.unzip` / `.untar` destination patterns
- [x] Create `extract` action type
- [ ] Show archive contents preview in confirmation (optional enhancement)

### Phase 4: Polish
- [ ] Add configuration for custom converters
- [ ] Handle errors gracefully
- [ ] Add documentation
- [ ] Write tests

## Config Structure (Implemented)

```lua
file_conversions = {
  enabled = true,
  converters = {
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
    custom = {},  -- Array of { from = "md", to = "pdf", cmd = "pandoc {src} -o {dst}" }
  },
  extractors = {
    zip = { cmd = "unzip", args = { "-o", "$SRC", "-d", "$DIR" } },
    ["tar.gz"] = { cmd = "tar", args = { "-xzf", "$SRC", "-C", "$DIR" } },
    ["tar.xz"] = { cmd = "tar", args = { "-xJf", "$SRC", "-C", "$DIR" } },
    ["tar.bz2"] = { cmd = "tar", args = { "-xjf", "$SRC", "-C", "$DIR" } },
    ["tar"] = { cmd = "tar", args = { "-xf", "$SRC", "-C", "$DIR" } },
  },
}
```

## Key Files Modified

1. `lua/oil/config.lua` - Added config options and type definitions
2. `lua/oil/mutator/init.lua` - Added convert/extract action types and detection
3. `lua/oil/adapters/files.lua` - Added render and perform handlers
4. `lua/oil/cache.lua` - Added cache handling for new action types
5. NEW `lua/oil/conversion.lua` - Conversion detection and command generation

## Usage Examples

### Image conversion
1. In oil buffer, rename `photo.jpeg` to `photo.png`
2. Save with `:w`
3. Confirmation popup shows: `CONVERT photo.jpeg -> photo.png (jpeg -> png)`
4. Confirm, and imagemagick converts the file

### Video conversion
1. In oil buffer, rename `video.mkv` to `video.mp4`
2. Save with `:w`
3. Confirmation popup shows: `CONVERT video.mkv -> video.mp4 (mkv -> mp4)`
4. Confirm, and ffmpeg converts the file

### Audio conversion
1. In oil buffer, rename `song.flac` to `song.mp3`
2. Save with `:w`
3. Confirmation popup shows: `CONVERT song.flac -> song.mp3 (flac -> mp3)`
4. Confirm, and ffmpeg converts the file

### Video to GIF
1. In oil buffer, rename `clip.mp4` to `clip.gif`
2. Save with `:w`
3. Confirmation popup shows: `CONVERT clip.mp4 -> clip.gif (mp4 -> gif)`
4. Confirm, and ffmpeg converts the video to a GIF

### Archive extraction
1. In oil buffer, copy `archive.zip` to `archive.unzip`
2. Save with `:w`
3. Confirmation popup shows: `EXTRACT archive.zip -> archive/`
4. Confirm, and unzip extracts to a directory

## Known Issues / TODO

- Need to verify `magick` or `ffmpeg` commands are available before conversion
- Archive preview in confirmation window (show file list)
- Handle missing conversion tools gracefully
- Support for custom ffmpeg encoding options (CRF, presets, etc.)
