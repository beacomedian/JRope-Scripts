--[[
 * Name: Organize Items By Variation
 * Author: Jesse Rope
 * AI: Claude Opus 4.8 Medium
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
 	[main] . >
 * Link: https://www.jesserope.com
 * About:
 	# Organizes selected items onto new tracks grouped by "variation".
 	# A variation group is the source file name up to (but not including) the
 	# first standalone numbered segment, e.g.
 	#   VO_E15_BanterGeneric_Team_07            -> VO_E15_BanterGeneric_Team
 	#   VO_E15_BanterGeneric_Team_01_face5      -> VO_E15_BanterGeneric_Team
 	#   VO_E15_Transform_Enemies_01_face02      -> VO_E15_Transform_Enemies
 	# One new named track is created per group (inserted after the last track
 	# holding a selected item) and every item in that group is moved onto it.
 	# Item timeline positions are preserved. Original tracks are left as-is.
 * Changelog:
	# Initial Release
 * To Do:
	#

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
local SCRIPT_DIR = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
local r = reaper
local proj = 0

---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Load my common functions
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")


-- Strip directory and extension from a full source path, returning the bare file name.
local function BaseName(path)
  local name = path:match("[^/\\]+$") or path  -- drop directory
  name = name:gsub("%.[^.]+$", "")             -- drop extension
  return name
end

-- Derive the variation group key from a file base name.
-- The group key is every underscore-delimited segment BEFORE the first segment
-- that is purely numeric (the numbered variation suffix). Segments containing
-- digits mixed with letters (E15, Weap1) are NOT treated as the suffix.
-- Returns nil when there is no numeric segment (caller decides how to handle).
local function GroupKeyFromName(name)
  local segments = {}
  for seg in name:gmatch("[^_]+") do
    segments[#segments + 1] = seg
  end
  local cut = nil
  for i, seg in ipairs(segments) do
    if seg:match("^%d+$") then
      cut = i
      break
    end
  end
  if not cut or cut == 1 then
    return nil  -- no numbered suffix, or the name starts with a number
  end
  local head = {}
  for i = 1, cut - 1 do
    head[i] = segments[i]
  end
  return table.concat(head, "_")
end


function main()
  local item_count = reaper.CountSelectedMediaItems(proj)
  Log("Selected items:", item_count)

  if item_count == 0 then
    reaper.MB("No media items are selected.", "jrope_"..SCRIPT_NAME, 0)
    return
  end

  -- Pass 1: gather items, resolve each to a variation group key, and record the
  -- highest track number among the selected items (our insertion anchor).
  local groups = {}          -- group_key -> { items = {item, ...} }
  local group_order = {}     -- list of unique group_keys (for stable/sorted iteration)
  local max_track_num = 0    -- 1-based IP_TRACKNUMBER of the lowest track we insert after
  local skipped = 0

  for i = 0, item_count - 1 do
    local item = reaper.GetSelectedMediaItem(proj, i)
    local take = reaper.GetActiveTake(item)

    if not take or reaper.TakeIsMIDI(take) then
      skipped = skipped + 1
      Log("  Skipped item", i, "- no audio take")
    else
      local source = reaper.GetMediaItemTake_Source(take)
      local path = reaper.GetMediaSourceFileName(source, "")
      local base = BaseName(path)
      local key = GroupKeyFromName(base)

      if not key then
        skipped = skipped + 1
        Log("  Skipped item", i, "- no variation suffix in name:", base)
      else
        if not groups[key] then
          groups[key] = { items = {} }
          group_order[#group_order + 1] = key
        end
        local g = groups[key]
        g.items[#g.items + 1] = item

        local track = reaper.GetMediaItem_Track(item)
        local tnum = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
        if tnum > max_track_num then max_track_num = tnum end
      end
    end
  end

  local group_count = #group_order
  Log("Variation groups found:", group_count, "| items skipped:", skipped)

  if group_count == 0 then
    reaper.MB("No selected items could be grouped by variation.", "jrope_"..SCRIPT_NAME, 0)
    return
  end

  -- Sort group keys alphabetically for tidy, predictable output.
  table.sort(group_order)

  -- Pass 2: insert one named track per group, right after the last selected track.
  -- IP_TRACKNUMBER is 1-based, so a track at number N sits at 0-based index N-1;
  -- inserting "after" it means index N. Successive groups go at N, N+1, N+2, ...
  local insert_index = math.floor(max_track_num)  -- 0-based index just past the anchor track

  for i, key in ipairs(group_order) do
    local idx = insert_index + (i - 1)
    reaper.InsertTrackAtIndex(idx, true)
    local track = reaper.GetTrack(proj, idx)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", key, true)
    groups[key].track = track
    Log("  Track", idx, "=>", key, "(" .. #groups[key].items .. " items)")
  end

  -- Pass 3: move every item onto its group's track (positions preserved).
  for _, key in ipairs(group_order) do
    local g = groups[key]
    for _, item in ipairs(g.items) do
      reaper.MoveMediaItemToTrack(item, g.track)
    end
  end

  Log("Done. Created", group_count, "tracks.")
end -- main


---------------------------------
-------------- MAIN -------------
---------------------------------

-- Begin the undo block
reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

main()

reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, -1)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
