--[[
 * Name: Select First N Items Per Track
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
    [main] . > 
 * Link: https://www.jesserope.com
 * noindex
 * About:
    #
 * Changelog:
    # Initial Release
 * To Do:
    # 


]]



---------------------------------
---------- USER CONFIG ----------
---------------------------------
-- Configuration: Change this number to select different amounts
local ITEMS_TO_KEEP = 5

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


    -- Get the number of selected items in the project
    local num_selected_items = reaper.CountSelectedMediaItems(0)

    -- Exit early if no items are selected
    if num_selected_items == 0 then
        reaper.ShowMessageBox("No items selected!", "Error", 0)
        return
    end

    -- Table to store items grouped by track
    local tracks_with_items = {}

    -- Loop through all selected items and group them by track
    for i = 0, num_selected_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local track = reaper.GetMediaItem_Track(item)
        local item_position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        
        -- If this is the first time we see this track, create a new table for it
        if not tracks_with_items[track] then
            tracks_with_items[track] = {}
        end
        
        -- Add item info to the track's table
        table.insert(tracks_with_items[track], {
            item = item,
            position = item_position
        })
    end

    -- Process each track: sort items by position and keep only first N
    for track, items in pairs(tracks_with_items) do
        -- Sort items by their timeline position (earliest first)
        table.sort(items, function(a, b)
            return a.position < b.position
        end)
        
        -- Deselect items beyond the first N
        for i = ITEMS_TO_KEEP + 1, #items do
            reaper.SetMediaItemSelected(items[i].item, false)
        end
    end


end -- main


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
-- reaper.UpdateTimeline()
reaper.UpdateArrange()

-- End the undo block with a description
-- reaper.ShowConsoleMsg("-- Script finished\n\n")
-- reaper.ShowMessageBox("Script executed in (s): "..tostring(reaper.time_precise() - time_init), "", 0)
