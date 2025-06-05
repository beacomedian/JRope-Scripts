--[[
 * Name: Add Selected Tracks to Region Render Matrix for Regions Near Edit Cursor or Within Time Selection
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.0
 * Version: 1.0
 * Provides:
  [main] . > 
 * Link: https://www.jesserope.com
 * noindex
 * About:
  #

 

 * Changelog:
  # Initial Release

]]



---------------------------------
---------- USER CONFIG ----------
---------------------------------


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
-- local time_init = reaper.time_precise()
local r = reaper
local proj = 0

---------------------------------
----------- FUNCTIONS -----------
---------------------------------

function main()
  -- Store current project
  local proj = 0 -- 0 represents the current project
  
  -- Get edit cursor position
  local cursor_pos = reaper.GetCursorPosition()
  
  -- Check if there's a time selection
  local time_sel_start, time_sel_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local has_time_selection = time_sel_start ~= time_sel_end
  
  -- Get the count of regions in the project
  local region_count = reaper.CountProjectMarkers(proj, 0)
  
  -- Get selected tracks count
  local sel_tracks_count = reaper.CountSelectedTracks(proj)
  
  -- If no selected tracks, exit with a message
  if sel_tracks_count == 0 then
    reaper.ShowMessageBox("No tracks selected. Please select at least one track.", "Error", 0)
    return
  end
  
  -- Store all selected tracks in a table
  local sel_tracks = {}
  for i = 0, sel_tracks_count - 1 do
    sel_tracks[i] = reaper.GetSelectedTrack(proj, i)
  end
  
  -- Counter for how many regions were processed
  local processed_regions = 0
  
  -- Process regions based on time selection or cursor position
  for i = 0, region_count - 1 do
    local retval, isrgn, region_pos, region_end, name, marker_idx, color = reaper.EnumProjectMarkers3(proj, i)
    
    if retval and isrgn then -- If it's a region
      local should_process = false
      
      if has_time_selection then
        -- Check if region overlaps with time selection
        should_process = (region_pos < time_sel_end and region_end > time_sel_start)
      else
        -- Check if cursor is within region
        should_process = (cursor_pos >= region_pos and cursor_pos <= region_end)
      end
      
      if should_process then
        -- Add all selected tracks to this region's render matrix
        for j = 0, sel_tracks_count - 1 do
          -- Set the render matrix
          -- Flag 1 means "add to render matrix"
          reaper.SetRegionRenderMatrix(proj, marker_idx, sel_tracks[j], 1)
        end
        processed_regions = processed_regions + 1
      end
    end
  end
  
  -- -- Show a message about what happened
  -- if processed_regions == 0 then
  --   if has_time_selection then
  --     reaper.ShowMessageBox("No regions found within the time selection.", "Information", 0)
  --   else
  --     reaper.ShowMessageBox("No regions found at the edit cursor position.", "Information", 0)
  --   end
  -- else
  --   local msg = string.format("%d selected track(s) added to %d region(s) render matrix.", sel_tracks_count, processed_regions)
  --   reaper.ShowMessageBox(msg, "Success", 0)
  -- end
end

---------------------------------
-------------- MAIN -------------
---------------------------------

-- reaper.APITest()
local time_init = reaper.time_precise()
-- reaper.ShowConsoleMsg("-- Script started\n")

-- Begin the undo block
reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

-- SaveView()
-- SaveCursorPos()
-- SaveLoopTimesel()
-- SaveSelectedItems(init_sel_items)
-- SaveSelectedTracks(init_sel_tracks)

main()

-- RestoreCursorPos()
-- RestoreLoopTimesel()
-- RestoreSelectedItems(init_sel_items)
-- RestoreSelectedTracks(init_sel_tracks)
-- RestoreView()

-- Update the arrangement to reflect the new selection
reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, -1)
reaper.PreventUIRefresh(-1)
reaper.UpdateTimeline()
reaper.UpdateArrange()

-- End the undo block with a description
-- reaper.ShowConsoleMsg("-- Script finished\n\n")

-- reaper.ShowMessageBox("Script executed in (s): "..tostring(reaper.time_precise() - time_init), "", 0)