--[[
 * Name: Import Files to Best Match Track
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
   [main] . > jrope_Import Files to Best Match Track.lua
 * Link: https://www.jesserope.com
 * About:
   # Lets you pick a folder of audio files and imports every file at the
   # edit cursor, each one landing on whichever existing track's name is
   # the closest textual match to that file's name.
   #
   # Files that share the same base name but differ only by a trailing
   # number (e.g. "...xxx 01.wav" and "...xxx 04.wav") are recognized as
   # a set and placed back-to-back on the same track, ordered from the
   # highest number to the lowest.
 * Changelog:
  # Initial Release
 * To Do:
  # Consider an override/mapping file for names the auto-matcher can't resolve
  # Consider fuzzy (typo-tolerant) matching in addition to exact word matching


]]



---------------------------------
---------- USER CONFIG ----------
---------------------------------

-- Logging -------------------------------------------------------------
local ENABLE_DEBUG_LOG     = true   -- true = print step-by-step matching/placement info to the REAPER console. Set false once you trust the results.
local CLEAR_CONSOLE_ON_RUN = true   -- true = wipe the console at the start of every run so old logs don't pile up. Has no effect if ENABLE_DEBUG_LOG is false.

-- File scanning ---------------------------------------------------------
local VALID_EXTENSIONS   = { "wav", "flac", "mp3", "ogg", "aif", "aiff" } -- only files with these extensions will be imported. Not case-sensitive.
local RECURSE_SUBFOLDERS = true     -- true = also search every subfolder of the chosen folder (lets you point this at a parent folder). false = only look directly inside the chosen folder.

-- Matching ----------------------------------------------------------------
-- Words that commonly show up in file names but never describe the
-- destination track (mix-pass labels, placeholders, etc). Add more of
-- your own studio's naming junk here as you run into it.
local IGNORE_WORDS = { "stem", "mix", "recordings", "recording", "xxx" }
local MIN_MATCHED_TOKENS = 1   -- a file must share at least this many words with a track name to be assigned to it. Raise this to be stricter about what counts as a "match".

-- Placement -------------------------------------------------------------
local ITEM_GAP_SECONDS = 2   -- gap (in seconds) left between sequenced items on the same track. 0 = items placed back-to-back with no silence.


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
local r = reaper
local proj = 0

-- Section/key pair used to remember the last folder you searched, via
-- reaper.SetExtState/GetExtState. Keeping this its own unique section
-- name avoids colliding with any other script's saved settings.
local EXT_SECTION = "jrope_ImportFilesToBestMatchTrack"
local EXT_KEY_DIR = "last_search_dir"

-- Turn the IGNORE_WORDS list into a set (a table used purely as a
-- lookup) so checking "is this word ignored?" is an instant table
-- lookup instead of looping the whole list for every single word.
local IGNORE_WORDS_SET = {}
for _, w in ipairs(IGNORE_WORDS) do
  IGNORE_WORDS_SET[w:lower()] = true
end

-- Same trick for the valid file extensions.
local VALID_EXTENSIONS_SET = {}
for _, e in ipairs(VALID_EXTENSIONS) do
  VALID_EXTENSIONS_SET[e:lower()] = true
end

---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Load my common functions
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]]) 
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")


-- Prints to the REAPER console only when ENABLE_DEBUG_LOG is true above.
local function Log(msg)
  if ENABLE_DEBUG_LOG then
    r.ShowConsoleMsg(tostring(msg) .. "\n")
  end
end


-- Splits a string into lowercase word "tokens" on every run of
-- non letter/number characters (spaces, underscores, hyphens,
-- parentheses, etc). This is how both file names and track names get
-- broken down into comparable words.
-- e.g. "SFX_Ability Enemy"  ->  { "sfx", "ability", "enemy" }
local function Tokenize(str)
  local tokens = {}
  for word in str:gmatch("[%a%d]+") do
    table.insert(tokens, word:lower())
  end
  return tokens
end


-- Separates a filename into its name and extension.
-- e.g. "Stem_Weapon_Self.wav"  ->  "Stem_Weapon_Self", "wav"
local function SplitExtension(filename)
  local name, ext = filename:match("^(.*)%.([%a%d]+)$")
  if not name then
    return filename, ""
  end
  return name, ext
end


-- Looks for a trailing number at the end of a name (with a space,
-- underscore or hyphen before it) and splits it off.
-- e.g. "Mix Recordings SFX_Ability Enemy xxx 04" -> "Mix Recordings SFX_Ability Enemy xxx", 4
-- If there's no trailing number, returns the name unchanged and nil.
local function SplitTrailingNumber(name)
  local base, num = name:match("^(.-)[%s_%-]+(%d+)$")
  if base and base ~= "" then
    return base, tonumber(num)
  end
  return name, nil
end


-- Turns a file's base name (its trailing number already removed) into
-- the list of words that are actually allowed to influence track
-- matching: real words only - pure numbers and known filler words
-- (USER CONFIG, IGNORE_WORDS) are stripped out.
local function BuildMatchTokens(base_name)
  local raw_tokens = Tokenize(base_name)
  local tokens = {}
  for _, t in ipairs(raw_tokens) do
    if not t:match("^%d+$") and not IGNORE_WORDS_SET[t] then
      table.insert(tokens, t)
    end
  end
  return tokens
end


-- Compares one file's match-tokens against one track's name-tokens.
-- Returns nil if they share no words at all. Otherwise returns three
-- numbers used to rank how good the match is:
--   matched      - how many words they have in common
--   track_cover  - matched / total words in the TRACK name
--                  (1.0 means every word in the track's name was found in the file)
--   file_cover   - matched / total words remaining in the FILE name
--                  (1.0 means the track name fully explains the file name)
local function ScoreTrackMatch(file_tokens, track_tokens)
  if #track_tokens == 0 or #file_tokens == 0 then return nil end

  local file_set = {}
  for _, t in ipairs(file_tokens) do file_set[t] = true end

  local matched = 0
  for _, t in ipairs(track_tokens) do
    if file_set[t] then matched = matched + 1 end
  end

  if matched == 0 then return nil end

  return matched, matched / #track_tokens, matched / #file_tokens
end


-- Checks the file's tokens against every track and returns whichever
-- track is the "best" match. "Best" means, in order of priority:
--   1) the most shared words wins
--   2) if tied, whichever track name is more FULLY covered by the file wins
--      (this is what makes "SFX_Combat" beat "SFX_Combat_Ambient" for a
--      file literally just called "SFX_Combat")
--   3) if still tied, whichever match explains more of the file name wins
-- Returns: best_track_info (or nil if nothing matched), matched_count, was_a_tie
local function FindBestTrack(file_tokens, track_list)
  local best, best_matched, best_tcov, best_fcov = nil, 0, 0, 0
  local tie = false

  for _, t in ipairs(track_list) do
    local matched, tcov, fcov = ScoreTrackMatch(file_tokens, t.tokens)
    if matched and matched >= MIN_MATCHED_TOKENS then
      local better =
        matched > best_matched
        or (matched == best_matched and tcov > best_tcov)
        or (matched == best_matched and tcov == best_tcov and fcov > best_fcov)

      local equal =
        best ~= nil
        and matched == best_matched
        and tcov == best_tcov
        and fcov == best_fcov

      if better then
        best, best_matched, best_tcov, best_fcov = t, matched, tcov, fcov
        tie = false
      elseif equal then
        tie = true
      end
    end
  end

  return best, best_matched, tie
end


-- Collects every track in the project once, along with its name already
-- broken into tokens, so that work doesn't get repeated for every file
-- we compare against it.
local function GetAllTracks()
  local list = {}
  local count = r.CountTracks(proj)
  for i = 0, count - 1 do
    local track = r.GetTrack(proj, i)
    local _, name = r.GetTrackName(track)
    table.insert(list, { track = track, name = name, tokens = Tokenize(name) })
  end
  return list
end


-- Asks the user to pick a source folder. Uses the JS_ReaScriptAPI native
-- folder browser if that extension is installed, otherwise falls back to
-- a plain text entry box. Either way, the dialog opens pre-filled with
-- whatever folder was used last time (remembered via ExtState), and
-- saves whatever gets picked so the next run starts there too.
-- (reaper.GetUserFileNameForRead can't be used here - it's built for
-- picking a single FILE, it has no folder-picking mode.)
local function GetSourceFolder()
  -- GetExtState returns "" if this key has never been set before, which
  -- is a perfectly valid default to hand to either dialog below.
  local lastDir = r.GetExtState(EXT_SECTION, EXT_KEY_DIR)

  local folder = nil

  if r.JS_Dialog_BrowseForFolder then
    -- Third argument is the starting directory, so the picker opens
    -- wherever the user left off last time.
    local retval, picked = r.JS_Dialog_BrowseForFolder(
      "Select folder to import audio files from", lastDir
    )
    if retval == 1 and picked and picked ~= "" then
      folder = picked
    end
  else
    Log("JS_ReaScriptAPI not found - falling back to manual path entry.")
    local ok, inputDir = r.GetUserInputs(
      "Enter Directory Path to Search", 1,
      "Search Directory (no JS_API installed):,extrawidth=200",
      lastDir
    )
    if ok and inputDir ~= "" then
      folder = inputDir
    end
  end

  -- Remember this folder for next time. The "true" argument tells REAPER
  -- to persist it to disk (reaper-extstate.ini) rather than just keeping
  -- it in memory for the current REAPER session.
  if folder then
    r.SetExtState(EXT_SECTION, EXT_KEY_DIR, folder, true)
  end

  return folder
end


-- Gathers every file directly inside folder whose extension is in
-- VALID_EXTENSIONS, and (if RECURSE_SUBFOLDERS is true) repeats the
-- process for every subfolder too.
local function CollectFiles(folder, results)
  results = results or {}

  local i = 0
  while true do
    local fname = r.EnumerateFiles(folder, i)
    if not fname then break end
    i = i + 1

    local _, ext = SplitExtension(fname)
    if VALID_EXTENSIONS_SET[ext:lower()] then
      table.insert(results, folder .. "/" .. fname)
    end
  end

  if RECURSE_SUBFOLDERS then
    local j = 0
    while true do
      -- reaper.file_exists can't tell folders apart from files, so
      -- subfolders have to be found with EnumerateSubdirectories instead.
      local subdir = r.EnumerateSubdirectories(folder, j)
      if not subdir then break end
      j = j + 1
      CollectFiles(folder .. "/" .. subdir, results)
    end
  end

  return results
end


-- Creates one new audio item on track, starting at position, using
-- filepath as its source and sized to that source's full length.
-- Returns the new item and its length in seconds, or nil, nil if the
-- file couldn't be read as an audio source.
local function InsertAudioItem(track, filepath, position)
  local source = r.PCM_Source_CreateFromFile(filepath)
  if not source then
    return nil, nil
  end

  local length = r.GetMediaSourceLength(source)

  local item = r.AddMediaItemToTrack(track)
  local take = r.AddTakeToMediaItem(item)
  r.SetMediaItemTake_Source(take, source)
  r.SetMediaItemInfo_Value(item, "D_POSITION", position)
  r.SetMediaItemInfo_Value(item, "D_LENGTH", length)

  local fname = filepath:match("([^/\\]+)$")
  r.GetSetMediaItemTakeInfo_String(take, "P_NAME", fname, true)

  return item, length
end


function main()

  if CLEAR_CONSOLE_ON_RUN then r.ClearConsole() end
  Log("---- Import Files to Best Match Track ----")

  local folder = GetSourceFolder()
  if not folder then
    Log("No folder selected - nothing to do.")
    return
  end
  Log("Source folder: " .. folder .. (RECURSE_SUBFOLDERS and " (including subfolders)" or ""))

  local files = CollectFiles(folder)
  Log("Found " .. #files .. " audio file(s).")
  if #files == 0 then
    r.ShowMessageBox("No matching audio files were found in:\n" .. folder, "Import Files to Best Match Track", 0)
    return
  end

  local tracks = GetAllTracks()
  if #tracks == 0 then
    r.ShowMessageBox("This project has no tracks to import onto.", "Import Files to Best Match Track", 0)
    return
  end

  -- ---- Match every file to a track, and work out where it sits in any
  -- ---- numbered sequence (same base name, different trailing number) ----
  local assignments = {}   -- flat list of { file, fname, track_info, base_key, number }
  local skipped = {}

  for _, filepath in ipairs(files) do
    local fname = filepath:match("([^/\\]+)$")
    local name_no_ext = SplitExtension(fname)
    local base, number = SplitTrailingNumber(name_no_ext)
    local match_tokens = BuildMatchTokens(base)

    local best, matched, tie = FindBestTrack(match_tokens, tracks)

    if best then
      Log(string.format("%-45s -> %-30s (%d shared word%s%s)",
        fname, best.name, matched, matched == 1 and "" or "s",
        tie and ", TIE - picked first match" or ""))

      table.insert(assignments, {
        file = filepath,
        fname = fname,
        track_info = best,
        base_key = base:lower(),
        number = number,
      })
    else
      Log(fname .. " -> NO MATCH FOUND, skipping")
      table.insert(skipped, fname)
    end
  end

  -- ---- Group the assignments two levels deep:
  -- ----   1) by source folder, so everything that came from the same
  -- ----      path location can be lined up to one shared start time
  -- ----   2) within that, by track + base name, so files that only
  -- ----      differ by their trailing number end up sequenced together
  local batches = {}       -- folder path -> { groups = {...}, group_order = {...} }
  local batch_order = {}   -- preserves first-seen order (folder scan order)

  for _, a in ipairs(assignments) do
    -- Everything up to (not including) the last slash in the full
    -- file path is that file's source folder - this is the "path
    -- location" used to decide which files get aligned together.
    local folder_key = a.file:match("^(.*)[/\\][^/\\]+$") or ""

    if not batches[folder_key] then
      batches[folder_key] = { groups = {}, group_order = {} }
      table.insert(batch_order, folder_key)
    end
    local batch = batches[folder_key]

    local group_key = tostring(a.track_info.track) .. "|" .. a.base_key
    if not batch.groups[group_key] then
      batch.groups[group_key] = { track_info = a.track_info, entries = {} }
      table.insert(batch.group_order, group_key)
    end
    table.insert(batch.groups[group_key].entries, a)
  end

  -- Within each group, sort by trailing number descending (highest
  -- number first), so e.g. "...04" lands before "...01" on the track.
  -- Files with no trailing number keep alphabetical order.
  for _, folder_key in ipairs(batch_order) do
    local batch = batches[folder_key]
    for _, group_key in ipairs(batch.group_order) do
      table.sort(batch.groups[group_key].entries, function(x, y)
        if x.number and y.number then
          return x.number > y.number
        elseif x.number or y.number then
          return x.number ~= nil
        else
          return x.fname < y.fname
        end
      end)
    end
  end

  -- ---- Place the items, one source folder ("batch") at a time. Every
  -- ---- track remembers its own next-free position, but before placing
  -- ---- a folder's files, every track that folder is about to use gets
  -- ---- pushed up to the LATEST of those positions first. That shared
  -- ---- starting line is what keeps a whole folder's worth of files
  -- ---- aligned vertically, even when some of its tracks already had
  -- ---- earlier folders' items running later on them than others. ----
  local start_pos = r.GetCursorPosition()
  local track_cursor = {} -- MediaTrack -> next free position on that track
  local placed_count = 0

  for _, folder_key in ipairs(batch_order) do
    local batch = batches[folder_key]

    -- Find the latest "next free" position among every track this
    -- folder will use. Tracks not yet touched default to start_pos.
    local batch_start = start_pos
    for _, group_key in ipairs(batch.group_order) do
      local track = batch.groups[group_key].track_info.track
      local existing = track_cursor[track] or start_pos
      if existing > batch_start then batch_start = existing end
    end

    -- Bring every track this folder uses up to that shared start
    -- point before placing anything, so they all begin lined up.
    for _, group_key in ipairs(batch.group_order) do
      local track = batch.groups[group_key].track_info.track
      track_cursor[track] = batch_start
    end

    for _, group_key in ipairs(batch.group_order) do
      local group = batch.groups[group_key]
      local track = group.track_info.track

      for _, entry in ipairs(group.entries) do
        local pos = track_cursor[track]
        local item, length = InsertAudioItem(track, entry.file, pos)

        if item then
          track_cursor[track] = pos + length + ITEM_GAP_SECONDS
          placed_count = placed_count + 1
          Log(string.format("Placed %s on %s at %.3fs (len %.3fs)",
            entry.fname, group.track_info.name, pos, length))
        else
          Log("FAILED to read audio from: " .. entry.file)
          table.insert(skipped, entry.fname)
        end
      end
    end
  end

  Log(string.format("---- Done: %d placed, %d skipped ----", placed_count, #skipped))

  if #skipped > 0 then
    r.ShowMessageBox(
      "Imported " .. placed_count .. " file(s).\n\n" ..
      "Could not match or read " .. #skipped .. " file(s):\n" .. table.concat(skipped, "\n"),
      "Import Files to Best Match Track", 0)
  end

end -- main


---------------------------------
-------------- MAIN -------------
---------------------------------

-- Begin the undo block
reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

main()

-- Update the arrangement to reflect the new items
reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, -1)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
