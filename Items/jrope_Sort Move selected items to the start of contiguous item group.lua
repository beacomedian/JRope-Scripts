--[[
 * Name: Sort - Move selected items to the start of contiguous item group
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
 	[main] . >
 * Link: https://www.jesserope.com
 * About:
 	# Moves the selected items to the start of their contiguous item cluster
 	  (no gaps between items, within a small tolerance) and shifts the other
 	  items in that cluster to follow. Handles selections spanning multiple
 	  tracks, and multiple separate clusters per track.
 * Changelog:
	# Initial Release
	# Support reordering across multiple tracks and multiple clusters per track
 * To Do:
	#

]]


---------------------------------
---------- USER CONFIG ----------
---------------------------------

-- Must be global (no `local`) so the shared Log() in Common Functions can read it.
ENABLE_DEBUG_LOG = false  -- set to true to print debug output to the REAPER console

local GAP_TOLERANCE = 0.001  -- seconds; items closer than this are treated as contiguous


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


-- Build a lookup of which items are currently selected.
local function GetSelectedItemSet()
  local set = {}
  for item in EnumSelectedItems() do
    set[item] = true
  end
  return set
end

-- Collect every item on a track, sorted by position (earliest first).
local function GetSortedTrackItems(track)
  local items = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    items[#items + 1] = {
      item = item,
      position = position,
      length = length,
      end_pos = position + length,
    }
  end
  table.sort(items, function(a, b) return a.position < b.position end)
  return items
end


-- Reorder a single contiguous group so its selected items come first, then the
-- rest, packed with no gaps starting from the group's original start position.
local function ReorderGroup(group_items, selected_set)
  local selected_in_group, other_in_group = {}, {}
  for _, data in ipairs(group_items) do
    if selected_set[data.item] then
      selected_in_group[#selected_in_group + 1] = data
    else
      other_in_group[#other_in_group + 1] = data
    end
  end

  -- Nothing to do if the group has no selected items, or they are already at the front.
  if #selected_in_group == 0 then return end

  local current_pos = group_items[1].position
  for _, data in ipairs(selected_in_group) do
    reaper.SetMediaItemInfo_Value(data.item, "D_POSITION", current_pos)
    current_pos = current_pos + data.length
  end
  for _, data in ipairs(other_in_group) do
    reaper.SetMediaItemInfo_Value(data.item, "D_POSITION", current_pos)
    current_pos = current_pos + data.length
  end
  Log("  Reordered group:", #selected_in_group, "selected,", #other_in_group, "other")
end

-- Split a track's items into contiguous groups and reorder each group that
-- contains at least one selected item.
local function ProcessTrack(track, selected_set)
  local all_items = GetSortedTrackItems(track)
  if #all_items == 0 then return end

  local group = {}
  local function flush()
    if #group > 0 then
      ReorderGroup(group, selected_set)
      group = {}
    end
  end

  for i, data in ipairs(all_items) do
    if i > 1 and data.position - all_items[i - 1].end_pos > GAP_TOLERANCE then
      flush()  -- gap; close the current group before starting a new one
    end
    group[#group + 1] = data
  end
  flush()
end


function main()

  local num_selected = reaper.CountSelectedMediaItems(0)
  Log("Selected items:", num_selected)
  if num_selected == 0 then
    reaper.ShowMessageBox("No items selected", SCRIPT_NAME, 0)
    return
  end

  local selected_set = GetSelectedItemSet()

  -- Collect the distinct tracks that contain selected items (preserve encounter order).
  local tracks, seen = {}, {}
  for item in EnumSelectedItems() do
    local track = reaper.GetMediaItemTrack(item)
    if not seen[track] then
      seen[track] = true
      tracks[#tracks + 1] = track
    end
  end
  Log("Tracks with selected items:", #tracks)

  for _, track in ipairs(tracks) do
    ProcessTrack(track, selected_set)
  end

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
