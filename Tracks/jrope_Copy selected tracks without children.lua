--[[
 * Name: Copy selected tracks without children
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
    [main] . >
 * About:
    # Copies only top-level selected tracks, excluding their children even if those children are also selected.
 * Changelog:
    # Initial Release
 * To Do:
    #

]]


---------------------------------
---------- USER CONFIG ----------
---------------------------------

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

local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")

function main()
  local num_selected = reaper.CountSelectedTracks(0)

  if num_selected == 0 then
    Log("No tracks selected")
    reaper.ShowMessageBox("No tracks selected.", SCRIPT_NAME, 0)
    return
  end

  Log("Selected track count:", num_selected)

  -- Collect all selected tracks with hierarchy info
  local all_selected = {}
  for i = 0, num_selected - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local track_idx = reaper.CSurf_TrackToID(track, false) - 1
    local track_depth = reaper.GetTrackDepth(track)
    table.insert(all_selected, {
      track = track,
      index = track_idx,
      depth = track_depth,
      is_top_level = true
    })
    Log("Collected track index:", track_idx, "depth:", track_depth)
  end

  -- Sort by track index so parent-child relationships are checkable
  table.sort(all_selected, function(a, b) return a.index < b.index end)

  -- Mark tracks that are children of other selected tracks
  for i = 1, #all_selected do
    for j = i - 1, 1, -1 do
      if all_selected[j].depth < all_selected[i].depth then
        all_selected[i].is_top_level = false
        Log("Track", all_selected[i].index, "marked as child of track", all_selected[j].index)
        break
      end
    end
  end

  -- Collect only true top-level selected tracks
  local top_level_parents = {}
  for i = 1, #all_selected do
    if all_selected[i].is_top_level then
      local folder_depth = reaper.GetMediaTrackInfo_Value(all_selected[i].track, "I_FOLDERDEPTH")
      table.insert(top_level_parents, {
        track = all_selected[i].track,
        index = all_selected[i].index,
        depth = all_selected[i].depth,
        was_folder = (folder_depth == 1)
      })
      Log("Top-level track:", all_selected[i].index, "was_folder:", (folder_depth == 1))
    end
  end

  Log("Top-level count:", #top_level_parents, "| Excluded children:", num_selected - #top_level_parents)

  -- Select only the top-level tracks
  reaper.Main_OnCommand(40297, 0) -- deselect all tracks
  for i = 1, #top_level_parents do
    reaper.SetTrackSelected(top_level_parents[i].track, true)
  end

  -- Temporarily convert folder tracks to normal so copy doesn't pull children
  for i = 1, #top_level_parents do
    if top_level_parents[i].was_folder then
      reaper.SetMediaTrackInfo_Value(top_level_parents[i].track, "I_FOLDERDEPTH", 0)
      Log("Temporarily de-foldered track:", top_level_parents[i].index)
    end
  end

  reaper.TrackList_AdjustWindows(false)

  reaper.Main_OnCommand(40210, 0) -- copy selected tracks

  -- Restore folder relationships
  for i = 1, #top_level_parents do
    if top_level_parents[i].was_folder then
      reaper.SetMediaTrackInfo_Value(top_level_parents[i].track, "I_FOLDERDEPTH", 1)
      Log("Restored folder depth for track:", top_level_parents[i].index)
    end
  end

  reaper.TrackList_AdjustWindows(false)

  -- Restore original selection
  reaper.Main_OnCommand(40297, 0)
  for i = 1, #all_selected do
    reaper.SetTrackSelected(all_selected[i].track, true)
  end

  Log("Done. Copied", #top_level_parents, "track(s), excluded", num_selected - #top_level_parents, "selected children")
end


---------------------------------
-------------- MAIN -------------
---------------------------------

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

main()

reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, -1)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
