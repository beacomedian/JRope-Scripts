--[[
 * Name: Create New Named FOlder Track for Each Selected Track
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
    # Quickly creates parent folders for each selected track and gives them the same name

 

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
-- local r = reaper
-- local proj = 0

---------------------------------
----------- FUNCTIONS -----------
---------------------------------

function create_parent_tracks()
    -- Store track colors before manipulation
    local track_colors = {}
    local num_tracks = reaper.CountTracks(0)
    
    -- First, store colors for all tracks
    for i = 0, num_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        track_colors[i + 1] = reaper.GetTrackColor(track)
    end
    
    -- Store the number of selected tracks
    local num_selected_tracks = reaper.CountSelectedTracks(0)
    
    -- Iterate through all selected tracks in reverse order
    for i = num_selected_tracks - 1, 0, -1 do
        -- Get the current selected track
        local cur_track = reaper.GetSelectedTrack(0, i)
        
        -- Get the name of the current track
        local _, track_name = reaper.GetTrackName(cur_track, "")
        
        -- Get the current track's index
        local cur_track_index = reaper.GetMediaTrackInfo_Value(cur_track, "IP_TRACKNUMBER")
        
        -- Insert a new track above the current track to be the parent
        reaper.InsertTrackAtIndex(cur_track_index - 1, true)
        
        -- Get the newly created parent track
        local parent_track = reaper.GetTrack(0, cur_track_index - 1)
        
        -- Set the track name to match the original track
        reaper.GetSetMediaTrackInfo_String(parent_track, "P_NAME", track_name, true)
        
        -- Copy track color from child to parent
        local track_color = reaper.GetTrackColor(cur_track)
        reaper.SetTrackColor(parent_track, track_color)
        
        -- Set the folder depth to create a proper folder structure
        reaper.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1)  -- Open folder
        reaper.SetMediaTrackInfo_Value(cur_track, "I_FOLDERDEPTH", -1)   -- Make this track a child
    end
    
    -- Restore colors for all tracks
    for i = 0, num_tracks do
        local track = reaper.GetTrack(0, i)
        if track and track_colors[i + 1] then
            reaper.SetTrackColor(track, track_colors[i + 1])
        end
    end
    
    -- Refresh the track list
    reaper.TrackList_AdjustWindows(false)
end



---------------------------------
-------------- MAIN -------------
---------------------------------

-- reaper.APITest()
-- local time_init = reaper.time_precise()
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