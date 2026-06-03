-- Copy Selected Tracks Without Children
-- This script copies only top-level selected tracks, excluding both their children AND selected children

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

local num_selected = reaper.CountSelectedTracks(0)

if num_selected == 0 then
  reaper.ShowConsoleMsg("No tracks selected\n")
  reaper.Undo_EndBlock("Copy tracks without children", -1)
  return
end

-- First, collect all selected tracks with their hierarchy info
local all_selected = {}
for i = 0, num_selected - 1 do
  local track = reaper.GetSelectedTrack(0, i)
  local track_idx = reaper.CSurf_TrackToID(track, false) - 1
  local track_depth = reaper.GetTrackDepth(track)
  
  table.insert(all_selected, {
    track = track,
    index = track_idx,
    depth = track_depth,
    is_top_level = true  -- Assume true until proven otherwise
  })
end

-- Sort by track index so we can check parent-child relationships
table.sort(all_selected, function(a, b) return a.index < b.index end)

-- Determine which selected tracks are children of other selected tracks
-- A track is a child if there's a selected track above it with lower depth
for i = 1, #all_selected do
  -- Check all selected tracks that appear before this one
  for j = i - 1, 1, -1 do
    -- If we find a track above with lower depth, this track is its descendant
    if all_selected[j].depth < all_selected[i].depth then
      all_selected[i].is_top_level = false
      break
    end
    -- If we find a track with equal or greater depth, keep checking earlier tracks
  end
end

-- Now collect only the true top-level selected tracks
local top_level_parents = {}
for i = 1, #all_selected do
  if all_selected[i].is_top_level then
    local parent_data = {
      track = all_selected[i].track,
      index = all_selected[i].index,
      depth = all_selected[i].depth,
      was_folder = false
    }
    
    -- Check if this is a folder track
    local folder_depth = reaper.GetMediaTrackInfo_Value(parent_data.track, "I_FOLDERDEPTH")
    if folder_depth == 1 then
      parent_data.was_folder = true
    end
    
    table.insert(top_level_parents, parent_data)
  end
end

-- Unselect all tracks
reaper.Main_OnCommand(40297, 0)

-- Select only the top-level parent tracks
for i = 1, #top_level_parents do
  reaper.SetTrackSelected(top_level_parents[i].track, true)
end

-- Temporarily convert parent folder tracks to normal tracks
for i = 1, #top_level_parents do
  if top_level_parents[i].was_folder then
    reaper.SetMediaTrackInfo_Value(top_level_parents[i].track, "I_FOLDERDEPTH", 0)
  end
end

-- Force Reaper to recalculate track relationships
reaper.TrackList_AdjustWindows(false)

-- Copy the tracks
reaper.Main_OnCommand(40210, 0)

-- Restore the folder relationships
for i = 1, #top_level_parents do
  if top_level_parents[i].was_folder then
    reaper.SetMediaTrackInfo_Value(top_level_parents[i].track, "I_FOLDERDEPTH", 1)
  end
end

-- Force Reaper to recalculate track relationships again
reaper.TrackList_AdjustWindows(false)

-- Restore original selection
reaper.Main_OnCommand(40297, 0)
for i = 1, #all_selected do
  reaper.SetTrackSelected(all_selected[i].track, true)
end

reaper.Undo_EndBlock("Copy tracks without children", -1)
reaper.PreventUIRefresh(-1)

local excluded_count = num_selected - #top_level_parents
reaper.ShowConsoleMsg("Copied " .. #top_level_parents .. " top-level track(s), excluded " .. excluded_count .. " selected children\n")
