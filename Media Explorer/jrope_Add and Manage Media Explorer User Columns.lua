--[[
 * Name: Media Explorer Metadata Column Manager
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
    [main=mediaexplorer] . 
 * Link: https://www.jesserope.com
 * About:
    # Full manager for Media Explorer custom user columns.
    #
    # Shows every user column you've already added (grouped by metadata chunk),
    # whether or not the selected file(s) contain data for them, PLUS any metadata
    # fields discovered in the selected file(s) that aren't columns yet.
    #
    # From one screen you can:
    #   - Add a discovered field   -> check its box
    #   - Remove an existing column -> uncheck its box
    #   - Rename any column         -> edit its name field
    # Then "Apply Changes" rewrites the Media Explorer column list.
    #
    # Selecting files is optional: with no selection you still manage existing
    # columns, you just won't see example values or new fields.
    #
    # Requires the SWS extension, js_ReaScriptAPI, and ReaImGui (all via ReaPack).
 * Changelog:
    # v0.1 - Alpha Release
 * To Do:
    # Option to sort columns breaking out from metadata chunk groups to surface duplicative fields
]]



---------------------------------
---------- USER CONFIG ----------
---------------------------------

-- Must be global (no `local`) so the shared Log() in Common Functions can read it.
ENABLE_DEBUG_LOG = false  -- set to true to print debug output to the REAPER console


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local r = reaper

-- ImGui context (created in MAIN, after we've confirmed ReaImGui is installed).
local ctx = nil

-- Preferred display order for the metadata chunk groups; anything else is
-- appended alphabetically after these.
local CHUNK_ORDER = { "BWF", "IXML", "INFO", "ID3", "CART", "ASWG", "XMP", "ACID", "GENERIC" }

-- Warn when the resulting column count reaches this many user columns.
local MAX_USER_COLUMNS = 32

-- Only scan the first N selected files (metadata union rarely needs more, and it
-- keeps huge selections responsive).
local MAX_SCAN_FILES = 200

-- Shown when hovering a locked SList column name. Edit this to say why they're locked.
local SLIST_LOCK_TOOLTIP =
  "Why is this field locked??\n\n" ..
  "iXML/Steinberg provides these fields dynamically as needed when metadata is written to thie chunk.\n" ..
  "This method makes sense for extensibility, but bad for our purposes because there is no way to \n" ..
  "ensure that each field contains the same category of information across different collections.\n" ..
  "If I add COMMENT and DESCRIPTION, but you add ARTIST and COMMENT, our fields won't match.\n" ..
  "My recommendation is to not sweat this, don't actually look at the contents of these fields,\n" ..
  "but rather just show however many you need in order to produce the search results you are looking for.\n" ..
  "You can still add or remove the column freely."

-- Status text colours (0xRRGGBBAA)
local COL_ADD    = 0x66BB6AFF
local COL_REMOVE = 0xEF5350FF
local COL_RENAME = 0xFFCA28FF
local COL_DIM    = 0x9E9E9EFF


---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Load my common functions
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")


-- Returns is_windows(bool), path_separator(string)
local function get_os()
  if reaper.GetOS():match("Win") then return true, "\\" else return false, "/" end
end
local IS_WIN, SEP = get_os()

-- The Media Explorer stores custom user columns in this .ini section.
local INI_SECTION = IS_WIN and "reaper_explorer" or "reaper_sexplorer"


---------------------------------
------ MEDIA EXPLORER READ ------
---------------------------------

local function get_media_explorer()
  return reaper.JS_Window_Find(reaper.JS_Localize("Media Explorer", "common"), true) or nil
end

local function get_media_explorer_list(hWnd)
  return reaper.JS_Window_FindEx(hWnd, nil, "SysListView32", "") or nil
end

-- Read a window's title/text, tolerating modern and legacy js_ReaScriptAPI signatures.
local function get_window_text(hwnd)
  local ret = reaper.JS_Window_GetTitle(hwnd)
  if type(ret) == "string" then return ret end
  local _, txt = reaper.JS_Window_GetTitle(hwnd, "", 4096)
  return txt or ""
end

-- Resolve the real file on disk for a Media Explorer row. The list view's
-- filename column may hide the extension, so if the direct "dir\name" path
-- doesn't exist we scan the folder for a file whose full name or
-- extension-stripped basename matches.
local function resolve_file_path(dir, fname)
  if dir == "" then return fname end

  local direct = dir .. SEP .. fname
  if reaper.file_exists(direct) then return direct end

  local target = fname:lower()
  local i = 0
  while true do
    local f = reaper.EnumerateFiles(dir, i)
    if not f then break end
    local fl = f:lower()
    local base = fl:match("^(.*)%.[^.]+$")
    if fl == target or base == target then
      Log("Resolved (added extension):", f)
      return dir .. SEP .. f
    end
    i = i + 1
  end

  Log("Could not resolve on disk, using raw name:", direct)
  return direct
end

local function me_item_text(lv, index, col)
  return reaper.JS_ListView_GetItemText(lv, index, col) or ""
end

-- Append the extension from the Media Explorer "Type" column (col 3) when the
-- displayed name doesn't already end with it (REAPER can hide extensions).
local function ensure_ext(name, ext)
  if name == "" or ext == "" then return name end
  if not name:lower():find("%." .. ext:lower() .. "$") then
    return name .. "." .. ext
  end
  return name
end

-- Returns an array of full file paths for the files currently selected in the
-- Media Explorer. Returns an empty table (not an error) when nothing is selected,
-- because the manager can still operate on existing columns without a selection.
--
-- Works for normal folder browsing AND database/collection/search views: files in
-- a database aren't under the current browse folder, so for anything we can't
-- resolve we temporarily enable REAPER's "Browser: Show full path in databases and
-- searches" option (Media Explorer action 42026), which makes column 0 report the
-- full path, then restore the option.
local function get_selected_media_explorer_paths()
  local hWnd = get_media_explorer()
  if not hWnd then return {}, 0 end

  local lv = get_media_explorer_list(hWnd)
  if not lv then return {}, 0 end

  local sel_count, sel_indexes = reaper.JS_ListView_ListAllSelItems(lv)
  if not sel_count or sel_count == 0 then return {}, 0 end

  local combo = reaper.JS_Window_FindChildByID(hWnd, 1002)
  local dir   = (combo and get_window_text(combo) or ""):gsub("[\\/]+$", "")

  local indices, total = {}, 0
  for ndx in string.gmatch(sel_indexes, "[^,]+") do
    total = total + 1
    if #indices < MAX_SCAN_FILES then indices[#indices + 1] = tonumber(ndx) end
  end
  if total > MAX_SCAN_FILES then
    Log("Selection capped:", MAX_SCAN_FILES, "of", total, "selected files scanned")
  end

  local resolved  = {}  -- index -> path
  local unresolved = {} -- indices still needing full-path mode

  -- Pass 1: normal folder resolution (filename, current dir, folder scan).
  for _, index in ipairs(indices) do
    local name  = me_item_text(lv, index, 0)
    local fname = ensure_ext(name, me_item_text(lv, index, 3))
    if fname ~= "" then
      local full = fname
      if not reaper.file_exists(full) and dir ~= "" then full = dir .. SEP .. fname end
      if not reaper.file_exists(full) and dir ~= "" then full = resolve_file_path(dir, name) end
      resolved[index] = full
      if reaper.file_exists(full) then
        Log("Resolved (folder):", full)
      else
        unresolved[#unresolved + 1] = index
      end
    end
  end

  -- Pass 2: database/collection/search — read full paths via option 42026.
  if #unresolved > 0 then
    local show_full = reaper.GetToggleCommandStateEx(32063, 42026) == 1
    local toggled = false
    if not show_full then
      reaper.JS_WindowMessage_Send(hWnd, "WM_COMMAND", 42026, 0, 0, 0)
      toggled = true
    end
    for _, index in ipairs(unresolved) do
      local fp = ensure_ext(me_item_text(lv, index, 0), me_item_text(lv, index, 3))
      if fp ~= "" then
        resolved[index] = fp
        Log("Resolved (full-path mode):", fp, "| exists:", tostring(reaper.file_exists(fp)))
      end
    end
    if toggled then
      reaper.JS_WindowMessage_Send(hWnd, "WM_COMMAND", 42026, 0, 0, 0)  -- restore option
    end
  end

  local paths = {}
  for _, index in ipairs(indices) do
    if resolved[index] then paths[#paths + 1] = resolved[index] end
  end
  return paths, total
end


---------------------------------
------ IDENTIFIER HELPERS -------
---------------------------------

local function fmt_len(sec)
  if not sec or sec <= 0 then return "0:00.000" end
  local m = math.floor(sec / 60)
  return string.format("%d:%06.3f", m, sec - m * 60)
end

-- Chunk name (upper-cased so "iXML" and "IXML" group together for display).
local function chunk_of(identifier)
  return (identifier:match("^([^:]+):") or identifier):upper()
end

local function field_of(identifier)
  return identifier:match("^[^:]+:(.+)$") or identifier
end

-- STEINBERG:ATTR_LIST fields come in NAME / TYPE / VALUE triplets, each with an
-- index suffix (":N"; the un-suffixed one is index 1). We only surface the VALUE
-- fields (the actual data) and suggest a generic "SList<N>" column name.
local function is_steinberg_attr(identifier)
  return identifier:upper():find("STEINBERG:ATTR_LIST", 1, true) ~= nil
end

local function is_steinberg_value(identifier)
  return identifier:upper():find("STEINBERG:ATTR_LIST:ATTR:VALUE", 1, true) ~= nil
end

-- STEINBERG NAME/TYPE fields: an ATTR_LIST field that isn't a VALUE field.
local function is_steinberg_nonvalue(identifier)
  return is_steinberg_attr(identifier) and not is_steinberg_value(identifier)
end

-- The SList index for a STEINBERG VALUE field ("...VALUE" -> 1, "...VALUE:10" -> 10).
local function steinberg_slist_num(identifier)
  return tonumber(identifier:match("[Vv][Aa][Ll][Uu][Ee]:(%d+)$")) or 1
end

-- Sort key that orders embedded numbers naturally (VALUE, VALUE:2, ... VALUE:10)
-- rather than lexically (VALUE:10 before VALUE:2).
local function natural_key(s)
  return (s:gsub("%d+", function(n) return string.format("%020d", tonumber(n)) end)):lower()
end

-- Human-readable names for the fixed-code chunks. Used to suggest a friendly
-- column name; unknown codes fall back to the raw field code.
local FIELD_NAMES = {
  -- RIFF INFO (LIST/INFO) tags
  INFO = {
    IARL = "Archival Location", IART = "Artist",          ICMS = "Commissioned",
    ICMT = "Comment",           ICOP = "Copyright",        ICRD = "Creation Date",
    ICRP = "Cropped",           IDIM = "Dimensions",       IDPI = "Dots Per Inch",
    IDIT = "Digitization Time",  IENG = "Engineer",         IGNR = "Genre",
    IKEY = "Keywords",          ILGT = "Lightness",        IMED = "Medium",
    INAM = "Title",             IPLT = "Palette Setting",  IPRD = "Product",
    IPRT = "Part",              ISBJ = "Subject",          ISFT = "Software",
    ISHP = "Sharpness",         ISRC = "Source",           ISRF = "Source Form",
    ITCH = "Technician",        ITRK = "Track Number",     ISMP = "SMPTE Time Code",
    TAPE = "Tape",
  },
  -- ID3v2 frames (v2.2 3-char, v2.3, v2.4)
  ID3 = {
    TIT1 = "Content Group",     TIT2 = "Title",            TIT3 = "Subtitle",
    TALB = "Album",             TOAL = "Original Album",   TRCK = "Track Number",
    TPOS = "Part of Set",       TSRC = "ISRC",             TPE1 = "Artist",
    TPE2 = "Album Artist",      TPE3 = "Conductor",        TPE4 = "Remixer",
    TOPE = "Original Artist",   TEXT = "Lyricist",         TOLY = "Original Lyricist",
    TCOM = "Composer",          TMCL = "Musician Credits", TIPL = "Involved People",
    TENC = "Encoded By",        TBPM = "BPM",              TLEN = "Length",
    TKEY = "Initial Key",       TLAN = "Language",         TCON = "Genre",
    TFLT = "File Type",         TMED = "Media Type",       TMOO = "Mood",
    TCOP = "Copyright",         TPRO = "Produced Notice",  TPUB = "Publisher",
    TOWN = "File Owner",        TRSN = "Radio Station",    TRSO = "Radio Station Owner",
    TOFN = "Original Filename", TDLY = "Playlist Delay",   TDEN = "Encoding Time",
    TDOR = "Original Release Time", TDRC = "Recording Date", TDRL = "Release Time",
    TDTG = "Tagging Time",      TSSE = "Encoding Settings", TSOA = "Album Sort Order",
    TSOP = "Artist Sort Order", TSOT = "Title Sort Order", TSST = "Set Subtitle",
    TSO2 = "Album Artist Sort", TSOC = "Composer Sort",    COMM = "Comment",
    USLT = "Lyrics",            APIC = "Attached Picture", APIC_TYPE = "Picture Type",
    WXXX = "User URL",          TXXX = "User Text",        PRIV = "Private",
    UFID = "Unique File ID",    POPM = "Popularimeter",    MCDI = "Music CD Identifier",
    -- Older date/time frames
    TYER = "Year",              TDAT = "Date",             TIME = "Time",
    TORY = "Original Release Year", TRDA = "Recording Dates", TSIZ = "Size",
    -- v2.2 three-letter aliases
    TT2 = "Title",              TP1 = "Artist",            TAL = "Album",
    TYE = "Year",               TCO = "Genre",             COM = "Comment",
  },
}

-- Auto-generated default column name. For fixed-code chunks (INFO, ID3) we look up
-- a friendly name; otherwise we use the field without its chunk prefix, e.g.
-- "IXML:BEXT:BWF_DESCRIPTION" -> "BEXT:BWF_DESCRIPTION".
local function default_desc(identifier)
  if is_steinberg_value(identifier) then
    return "SList" .. steinberg_slist_num(identifier)
  end
  local field = field_of(identifier)
  local lut = FIELD_NAMES[chunk_of(identifier)]
  if lut then
    local up = field:upper()
    local name = lut[up] or lut[up:match("^([^:]+)") or up]
    if name then return name end
  end
  return field
end


---------------------------------
------- EXISTING COLUMNS --------
---------------------------------

-- Read the existing user columns from the .ini in index order. Returns:
--   cols     = array of { idx, key, desc, flags }
--   term_idx = index of the first empty slot (extent of the used range)
local function read_existing_columns()
  local ini = reaper.get_ini_file()
  local cols, i = {}, 0
  while true do
    local ret, key = reaper.BR_Win32_GetPrivateProfileString(INI_SECTION, "user" .. i .. "_key", "", ini)
    if key and key ~= "" then
      local _, desc  = reaper.BR_Win32_GetPrivateProfileString(INI_SECTION, "user" .. i .. "_desc",  "",  ini)
      local _, flags = reaper.BR_Win32_GetPrivateProfileString(INI_SECTION, "user" .. i .. "_flags", "1", ini)
      cols[#cols + 1] = { idx = i, key = key, desc = desc or "", flags = (flags ~= "" and flags) or "1" }
    end
    if ret == 0 then break end
    i = i + 1
  end
  Log("Existing user columns:", #cols, "| terminator index:", i)
  return cols, i
end

---------------------------------
--------- METADATA SCAN ---------
---------------------------------

-- REAPER reports non-text blocks (UMID, Soundminer's SMED, embedded art, etc.) as
-- "[Binary data]". Those make useless columns, so we skip them while scanning.
local function is_binary_value(v)
  return (v or ""):match("^%s*%[[Bb]inary [Dd]ata%]%s*$") ~= nil
end

-- Identifiers REAPER already exposes as built-in Media Explorer columns, so there's
-- no point adding them as user columns. Keys are lower-cased identifiers.
local EXCLUDED_FIELDS = {
  ["generic:startoffset"] = true,  -- REAPER's own start offset column
}
local function is_excluded_field(identifier)
  return EXCLUDED_FIELDS[identifier:lower()] == true
end

-- Scan the given files and return the metadata found, without touching any row
-- model. Returns:
--   fields   = map of identifier -> example value (first non-empty wins)
--   scanned  = number of files successfully opened
--   props_str = source properties of the first scanned file
local function scan_files(paths)
  local fields, scanned, props_str = {}, 0, ""

  for _, path in ipairs(paths) do
    local src = reaper.PCM_Source_CreateFromFile(path)
    if src then
      scanned = scanned + 1

      if props_str == "" then
        local sr    = reaper.GetMediaSourceSampleRate(src)
        local chans = reaper.GetMediaSourceNumChannels(src)
        local len   = reaper.GetMediaSourceLength(src)
        local bits  = reaper.APIExists("CF_GetMediaSourceBitDepth") and reaper.CF_GetMediaSourceBitDepth(src) or nil
        props_str = string.format("Length: %s   |   Sample rate: %s   |   Channels: %s%s",
          fmt_len(len), tostring(sr or "?"), tostring(chans or "?"),
          bits and ("   |   Bits/sample: " .. tostring(bits)) or "")
      end

      local retval, id_list = reaper.GetMediaFileMetadata(src, "")
      id_list = id_list or ""
      Log("Scan:", path, "| type:", reaper.GetMediaSourceType(src, ""),
          "| retval:", tostring(retval), "| id_list len:", #id_list)

      for identifier in id_list:gmatch("[^\r\n]+") do
        if fields[identifier] == nil or fields[identifier] == "" then
          if is_steinberg_nonvalue(identifier) then
            -- Only the VALUE fields of STEINBERG:ATTR_LIST are useful; skip NAME/TYPE.
            Log("Skipped STEINBERG NAME/TYPE field:", identifier)
          elseif is_excluded_field(identifier) then
            Log("Skipped excluded field (built-in column):", identifier)
          else
            local _, value = reaper.GetMediaFileMetadata(src, identifier)
            value = value or ""
            if is_binary_value(value) then
              Log("Skipped binary field:", identifier)
            else
              fields[identifier] = value
            end
          end
        end
      end

      reaper.PCM_Source_Destroy(src)
    else
      Log("Could not create source (skipped):", path)
    end
  end

  return fields, scanned, props_str
end

-- Sort rows for display: preferred chunk order first, then alphabetical, then field.
local function sort_rows(rows)
  local rank = {}
  for i, c in ipairs(CHUNK_ORDER) do rank[c] = i end
  table.sort(rows, function(a, b)
    if a.chunk ~= b.chunk then
      local ha, hb = rank[a.chunk], rank[b.chunk]
      if (ha ~= nil) ~= (hb ~= nil) then return ha ~= nil end
      if ha and hb then return ha < hb end
      return a.chunk < b.chunk
    end
    return natural_key(a.field) < natural_key(b.field)
  end)
end

-- Build a fresh row model from the current on-disk columns plus a set of
-- previously-scanned fields (identifier -> example). Existing columns become
-- kept rows; scanned fields that aren't columns become un-added discovery rows.
local function assemble_rows(scanned_fields)
  local existing = read_existing_columns()
  local rows, map = {}, {}
  for _, c in ipairs(existing) do
    -- SList (STEINBERG VALUE) columns have a locked name that is always SList<N>.
    local locked = is_steinberg_value(c.key)
    local name   = locked and default_desc(c.key) or c.desc
    local row = {
      identifier = c.key, chunk = chunk_of(c.key), field = field_of(c.key),
      example = "", name = name, is_column = true, orig_idx = c.idx,
      orig_desc = locked and name or c.desc, flags = c.flags, keep = true,
      name_locked = locked,
    }
    map[c.key:lower()] = row
    rows[#rows + 1] = row
  end
  if scanned_fields then
    for identifier, example in pairs(scanned_fields) do
      local key = identifier:lower()
      local row = map[key]
      if row then
        if row.example == "" then row.example = example end
      else
        local nr = {
          identifier = identifier, chunk = chunk_of(identifier), field = field_of(identifier),
          example = example, name = default_desc(identifier), is_column = false,
          orig_idx = nil, orig_desc = nil, flags = "1", keep = false,
          name_locked = is_steinberg_value(identifier),
        }
        map[key] = nr
        rows[#rows + 1] = nr
      end
    end
  end
  sort_rows(rows)
  return rows
end


---------------------------------
-------- WRITE - REFRESH --------
---------------------------------

local function refresh_media_explorer()
  reaper.Main_OnCommand(50124, 0)
  reaper.Main_OnCommand(50124, 0)
  reaper.OpenMediaExplorer("", false)
end

-- Rebuild the entire user-column list from the desired state:
--   kept existing columns (in their original order) + newly-added fields.
-- Removed columns are dropped and the tail slots are blanked. Returns
-- added, removed, renamed counts.
local function apply_changes(rows)
  local ini = reaper.get_ini_file()
  local _, old_term = read_existing_columns()  -- current extent of used slots

  -- Kept existing columns keep their relative order; new additions are appended.
  local kept, added = {}, {}
  local n_add, n_rem, n_ren = 0, 0, 0
  for _, rrow in ipairs(rows) do
    if rrow.is_column then
      if rrow.keep then
        kept[#kept + 1] = rrow
        if rrow.name ~= rrow.orig_desc then n_ren = n_ren + 1 end
      else
        n_rem = n_rem + 1
      end
    elseif rrow.keep then
      added[#added + 1] = rrow
      n_add = n_add + 1
    end
  end
  table.sort(kept, function(a, b) return a.orig_idx < b.orig_idx end)

  local final = {}
  for _, rrow in ipairs(kept)  do final[#final + 1] = rrow end
  for _, rrow in ipairs(added) do final[#final + 1] = rrow end

  -- Write the final list contiguously from user0.
  for j, rrow in ipairs(final) do
    local idx  = j - 1
    -- SList names are locked; always write SList<N> regardless of any stored/edited value.
    local desc = rrow.name_locked and default_desc(rrow.identifier)
              or ((rrow.name ~= "" and rrow.name) or default_desc(rrow.identifier))
    reaper.BR_Win32_WritePrivateProfileString(INI_SECTION, "user" .. idx .. "_key",   rrow.identifier, ini)
    reaper.BR_Win32_WritePrivateProfileString(INI_SECTION, "user" .. idx .. "_desc",  desc,            ini)
    reaper.BR_Win32_WritePrivateProfileString(INI_SECTION, "user" .. idx .. "_flags", rrow.flags or "1", ini)
    Log("Write column", idx, ":", rrow.identifier, "->", desc)
  end

  -- Blank any slots the old list used beyond the new end.
  for idx = #final, old_term do
    reaper.BR_Win32_WritePrivateProfileString(INI_SECTION, "user" .. idx .. "_key",   "", ini)
    reaper.BR_Win32_WritePrivateProfileString(INI_SECTION, "user" .. idx .. "_desc",  "", ini)
    reaper.BR_Win32_WritePrivateProfileString(INI_SECTION, "user" .. idx .. "_flags", "", ini)
  end

  refresh_media_explorer()
  return n_add, n_rem, n_ren
end


---------------------------------
----------- ImGui GUI -----------
---------------------------------

local G = {
  rows            = {},
  scanned_fields  = {},    -- identifier -> example, accumulated across scans
  props_str       = "",
  scanned_count   = 0,     -- files opened in the last scan
  scan_status     = "Not scanned yet. Select file(s) in the Media Explorer and click 'Scan Files'.",
  has_scanned     = false, -- true once at least one scan has run this session
  hide_empty      = false, -- hide discovered rows with no meaningful example data
  show_only_added = false, -- show only existing/added columns, hide un-added fields
  hide_steinberg  = false, -- hide the STEINBERG SList (ATTR_LIST VALUE) fields
  window_open     = true,
  pending_scan    = false, -- set by the Scan button; handled between frames
  pending_apply   = false, -- set by the Apply button; handled between frames
}

-- Re-baseline the row model from disk (used after applying changes).
local function rebuild_from_disk()
  G.rows = assemble_rows(G.scanned_fields)
end

-- Scan the current Media Explorer selection and merge results into the rows,
-- preserving any in-progress checkbox/name edits.
local function do_scan()
  local paths, total_selected = get_selected_media_explorer_paths()
  if #paths == 0 then
    G.scan_status = "No files selected in the Media Explorer. Select file(s) and click 'Scan Files' again."
    return
  end

  local fields, count, props = scan_files(paths)
  if props ~= "" then G.props_str = props end
  G.scanned_count = count

  -- Accumulate into the persistent field store (first non-empty example wins).
  for identifier, example in pairs(fields) do
    local cur = G.scanned_fields[identifier]
    if cur == nil or cur == "" then G.scanned_fields[identifier] = example end
  end

  -- Merge into the live rows without disturbing existing rows' keep/name edits.
  local map = {}
  for _, row in ipairs(G.rows) do map[row.identifier:lower()] = row end
  for identifier, example in pairs(fields) do
    local key = identifier:lower()
    local row = map[key]
    if row then
      if row.example == "" and example ~= "" then row.example = example end
    else
      local nr = {
        identifier = identifier, chunk = chunk_of(identifier), field = field_of(identifier),
        example = example, name = default_desc(identifier), is_column = false,
        orig_idx = nil, orig_desc = nil, flags = "1", keep = false,
        name_locked = is_steinberg_value(identifier),
      }
      map[key] = nr
      G.rows[#G.rows + 1] = nr
    end
  end
  sort_rows(G.rows)

  G.has_scanned = true

  local nf = 0
  for _ in pairs(G.scanned_fields) do nf = nf + 1 end
  local capped = (total_selected and total_selected > count)
    and string.format(" (capped at %d of %d selected)", count, total_selected) or ""
  G.scan_status = string.format("Scanned %d file(s)%s. %d metadata field(s) known.", count, capped, nf)
end

-- Drop all accumulated scan data and discovered fields, leaving only the existing
-- columns (with their in-progress edits) — a clean slate without relaunching.
local function clear_scan()
  G.scanned_fields = {}
  G.props_str      = ""
  G.scanned_count  = 0
  G.has_scanned    = false

  local kept = {}
  for _, row in ipairs(G.rows) do
    if row.is_column then
      row.example = ""  -- example values only ever came from a scan
      kept[#kept + 1] = row
    end
  end
  G.rows = kept

  G.scan_status = "Scan cleared. Select file(s) in the Media Explorer and click 'Scan Files'."
end

-- An example counts as "blank" when it's empty or just a placeholder dash/period.
local function is_blank_example(ex)
  local t = (ex or ""):match("^%s*(.-)%s*$")
  return t == "" or t == "-" or t == "."
end

-- Whether a row passes the active display filters.
local function should_show(row)
  if G.hide_steinberg and is_steinberg_attr(row.identifier) then return false end
  if G.show_only_added and not (row.is_column or row.keep) then return false end
  if G.hide_empty and (not row.is_column) and (not row.keep) and is_blank_example(row.example) then
    return false
  end
  return true
end

-- Revert every row to its on-disk state.
local function revert_all()
  for _, row in ipairs(G.rows) do
    if row.is_column then
      row.keep = true
      row.name = row.orig_desc
    else
      row.keep = false
      row.name = default_desc(row.identifier)
    end
  end
end

-- Check every currently-visible discovered (not-yet-column) field for adding.
-- Respects the active filters, so hidden fields (e.g. STEINBERG:ATTR_LIST) aren't
-- swept in.
local function add_all_new()
  for _, row in ipairs(G.rows) do
    if not row.is_column and should_show(row) then row.keep = true end
  end
end

-- Pending-change + resulting-column tallies.
local function tally()
  local add, rem, ren, final = 0, 0, 0, 0
  for _, row in ipairs(G.rows) do
    if row.is_column then
      if row.keep then
        final = final + 1
        if row.name ~= row.orig_desc then ren = ren + 1 end
      else
        rem = rem + 1
      end
    elseif row.keep then
      add = add + 1
      final = final + 1
    end
  end
  return add, rem, ren, final
end

-- Status label + colour for a row given its current state.
local function row_status(row)
  if row.is_column then
    if not row.keep then return "REMOVE", COL_REMOVE end
    if row.name ~= row.orig_desc then return "rename", COL_RENAME end
    return "column", COL_DIM
  else
    if row.keep then return "add", COL_ADD end
    return "new", COL_DIM
  end
end

local function draw_row(row, id)
  reaper.ImGui_TableNextRow(ctx)
  reaper.ImGui_PushID(ctx, id)

  -- Col 0: keep/remove checkbox
  reaper.ImGui_TableSetColumnIndex(ctx, 0)
  local _, kv = reaper.ImGui_Checkbox(ctx, "##keep", row.keep)
  row.keep = kv

  -- Col 1: field name
  reaper.ImGui_TableSetColumnIndex(ctx, 1)
  reaper.ImGui_Text(ctx, row.field)

  -- Col 2: example value (truncated, full text on hover)
  reaper.ImGui_TableSetColumnIndex(ctx, 2)
  local ex = row.example
  local disp = (#ex > 80) and (ex:sub(1, 80) .. "…") or ex
  reaper.ImGui_Text(ctx, disp)
  if ex ~= "" and reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, ex)
  end

  -- Col 3: status
  reaper.ImGui_TableSetColumnIndex(ctx, 3)
  local label, color = row_status(row)
  reaper.ImGui_TextColored(ctx, color, label)

  -- Col 4: column name (editable, except SList names which are locked)
  reaper.ImGui_TableSetColumnIndex(ctx, 4)
  reaper.ImGui_SetNextItemWidth(ctx, -1)
  if row.name_locked then
    reaper.ImGui_BeginDisabled(ctx, true)
    reaper.ImGui_InputText(ctx, "##name", row.name)  -- read-only; changes ignored
    reaper.ImGui_EndDisabled(ctx)
    -- Disabled items don't report hover unless we allow it explicitly.
    if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled()) then
      reaper.ImGui_SetTooltip(ctx, SLIST_LOCK_TOOLTIP)
    end
  else
    local changed, newname = reaper.ImGui_InputText(ctx, "##name", row.name)
    if changed then row.name = newname end
  end

  reaper.ImGui_PopID(ctx)
end

-- Collapsible "How this works" section shown at the top of the window.
local INSTRUCTIONS = {
  "SCAN: Select file(s) in the Media Explorer, then click 'Scan Files' to read their metadata. Only the first 200 selected files are scanned, and only the first found entry is shown as an example. Subsequent scans ADD to the collection of displayed fields.",
  "EDIT: A checked box means the column exists. Check a discovered field to ADD it as a column; uncheck an existing column to REMOVE it; edit the name field to RENAME.",
  "CLEAR: 'Clear Scan' drops all scanned data (your existing columns stay). 'Revert changes' undoes pending edits (back to what's on disk).",
  "FILTERS: 'Hide empty' hides discovered fields with no data (blank, '-', '.'); 'Show only added fields' hides fields that aren't added columns.",
  "APPLY: 'Apply Changes' writes the columns to REAPER's .ini. To see the changes you must RESTART REAPER (columns load at startup), then select your files, right-click, and run 'Re-read metadata from media' to populate values. Newly browsed or added files will have all metadata read.",
  "LIMIT: Reaper limits user columns to 32. Remove generic or duplicative fields. Note that many fields like Artist, Description, Comment, etc are read by default Reaper columns.",
}

local function draw_instructions()
  if reaper.ImGui_CollapsingHeader(ctx, "How this works ###help") then
    reaper.ImGui_TextWrapped(ctx,
      "Media Explorer only searches for shown metadata fields. Use this tool to surface and display metadata to improve your search results.\n")
    reaper.ImGui_Spacing(ctx)
    for _, line in ipairs(INSTRUCTIONS) do
      reaper.ImGui_TextWrapped(ctx, "\u{2022}  " .. line)
      reaper.ImGui_Spacing(ctx)
    end
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
  end
end

local function draw_gui()
  reaper.ImGui_SetNextWindowSize(ctx, 820, 660, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, SCRIPT_NAME, true)

  if not open then
    G.window_open = false
    reaper.ImGui_End(ctx)
    return
  end

  if visible then
    draw_instructions()

    reaper.ImGui_Text(ctx, "Check = keep/add, Uncheck = remove. Edit the Column name. Rescan to add more fields to the view. the window stays open.")

    reaper.ImGui_Spacing(ctx)
    local scan_label = G.has_scanned and "Scan Additional Files" or "Scan Files"
    if reaper.ImGui_Button(ctx, scan_label) then G.pending_scan = true end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Clear Scanned") then clear_scan() end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Add all new fields") then add_all_new() end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Revert pending changes") then revert_all() end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, G.scan_status)
    if G.props_str ~= "" then reaper.ImGui_TextWrapped(ctx, G.props_str) end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, "Filters:")
    reaper.ImGui_SameLine(ctx)
    local _, he = reaper.ImGui_Checkbox(ctx, "Hide empty", G.hide_empty)
    G.hide_empty = he
    reaper.ImGui_SameLine(ctx)
    local _, soa = reaper.ImGui_Checkbox(ctx, "Show only added fields", G.show_only_added)
    G.show_only_added = soa

    local n_add, n_rem, n_ren, n_final = tally()

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_BeginChild(ctx, "##scroll", 0, -60) then
      local table_flags = reaper.ImGui_TableFlags_Borders()
                        | reaper.ImGui_TableFlags_RowBg()
                        | reaper.ImGui_TableFlags_Resizable()

      local i, n = 1, #G.rows
      while i <= n do
        local chunk = G.rows[i].chunk
        local group = {}
        local j = i
        while j <= n and G.rows[j].chunk == chunk do
          local rrow = G.rows[j]
          if should_show(rrow) then group[#group + 1] = rrow end
          j = j + 1
        end

        if #group > 0 then
          local header = string.format("%s  (%d)###%s", chunk, #group, chunk)
          if reaper.ImGui_CollapsingHeader(ctx, header, nil, reaper.ImGui_TreeNodeFlags_DefaultOpen()) then
            if reaper.ImGui_BeginTable(ctx, "tbl_" .. chunk, 5, table_flags) then
              reaper.ImGui_TableSetupColumn(ctx, "Keep",        reaper.ImGui_TableColumnFlags_WidthFixed(), 38)
              reaper.ImGui_TableSetupColumn(ctx, "Field",       reaper.ImGui_TableColumnFlags_WidthFixed(), 200)
              reaper.ImGui_TableSetupColumn(ctx, "Example",     reaper.ImGui_TableColumnFlags_WidthStretch())
              reaper.ImGui_TableSetupColumn(ctx, "Status",      reaper.ImGui_TableColumnFlags_WidthFixed(), 70)
              reaper.ImGui_TableSetupColumn(ctx, "Column name", reaper.ImGui_TableColumnFlags_WidthStretch())
              reaper.ImGui_TableHeadersRow(ctx)
              for k, row in ipairs(group) do
                draw_row(row, i * 1000 + k)
              end
              reaper.ImGui_EndTable(ctx)
            end
          end
        end
        i = j
      end
    end
    reaper.ImGui_EndChild(ctx)

    reaper.ImGui_Separator(ctx)

    -- Summary + cap warning
    reaper.ImGui_Text(ctx, string.format("Pending:  +%d add   -%d remove   ~%d rename   =>  %d columns total",
      n_add, n_rem, n_ren, n_final))
    if n_final >= MAX_USER_COLUMNS then
      reaper.ImGui_TextColored(ctx, COL_REMOVE,
        string.format("Warning: %d columns is at/over the Reaper limit of %d. Last added columns will not be shown.", n_final, MAX_USER_COLUMNS))
    end

    local total_changes = n_add + n_rem + n_ren
    if reaper.ImGui_Button(ctx, string.format("Apply Changes (%d)", total_changes)) then
      if total_changes > 0 then G.pending_apply = true end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Close") then
      G.window_open = false
    end
  end

  reaper.ImGui_End(ctx)
end

local function gui_loop()
  if not G.window_open then return end  -- Close/X pressed: end the script

  draw_gui()

  -- Button actions are handled here, between frames, so modal message boxes and
  -- the .ini rewrite never run in the middle of an ImGui frame.
  if G.pending_scan then
    G.pending_scan = false
    do_scan()
  end

  if G.pending_apply then
    G.pending_apply = false
    local a, rem, ren = apply_changes(G.rows)
    reaper.MB(
      string.format("Applied changes:\n  Added:   %d\n  Removed: %d\n  Renamed: %d\n\n" ..
        "To see the result:\n" ..
        "1. RESTART REAPER (user columns are only read at startup).\n" ..
        "2. Select file(s), right-click, and 'Re-read metadata from media'.", a, rem, ren),
      "Media Explorer Column Manager", 0)
    -- Re-baseline the rows from the newly-written .ini so further edits start clean.
    rebuild_from_disk()
  end

  reaper.defer(gui_loop)
end


---------------------------------
-------------- MAIN -------------
---------------------------------

-- Dependency guards ----------------------------------------------------------
if not (reaper.BR_Win32_GetPrivateProfileString and reaper.BR_Win32_WritePrivateProfileString) then
  reaper.MB("This script requires the SWS extension (reaper.BR_Win32_*PrivateProfileString).\n\n" ..
    "Install it from https://www.sws-extension.org, then restart REAPER.", "ERROR: SWS extension missing", 0)
  return
end

if not (reaper.APIExists and reaper.APIExists("JS_Window_Find")) then
  reaper.MB("This script requires the js_ReaScriptAPI extension.\n\n" ..
    "Install it via ReaPack: Extensions > ReaPack > Browse Packages > 'js_ReaScriptAPI'.", "ERROR: js_ReaScriptAPI missing", 0)
  return
end

if not reaper.APIExists("ImGui_CreateContext") then
  reaper.MB("This script requires ReaImGui.\n\n" ..
    "Install it via ReaPack: Extensions > ReaPack > Browse Packages > 'ReaImGui'.", "ERROR: ReaImGui missing", 0)
  return
end

-- Build the initial row model from the existing columns only (no scan yet); the
-- user triggers scanning with the "Scan Files" button once the window is open.
G.rows = assemble_rows(nil)

ctx = reaper.ImGui_CreateContext(SCRIPT_NAME)
reaper.defer(gui_loop)
