--[[
 * Name: Group items horizontally by track
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.0
 * Version: 1.1
 * Provides:
    [main] . > 
 * Link: https://www.jesserope.com
 * noindex
 * About:
    # Groups selected items horizontally by track; A new group for each track.

 

 * Changelog:
    # Initial Release
    # Renamed to add 'horizontally' because that's what I kept searching for

]]


---------------------------------
---------- USER CONFIG ----------
---------------------------------


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
time_init = reaper.time_precise()
r = reaper
proj = 0


---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Save initally selected items
local init_sel_items = {}
function SaveSelectedItems (table)
  for i = 0, reaper.CountSelectedMediaItems(0)-1 do
    table[i+1] = reaper.GetSelectedMediaItem(0, i)
  end
end

-- Restore initially selected items
function RestoreSelectedItems (table)
  reaper.Main_OnCommand(40289, 0) -- Unselect all items
  for _, item in ipairs(table) do
    reaper.SetMediaItemSelected(item, true)
  end
end

function main( ... )
    -- Get the number of selected items
    num_items = reaper.CountSelectedMediaItems(0)

    if num_items > 0 then
        -- Table to store track-specific items
        track_items = {}

        -- Iterate through selected items
        for i = 0, num_items - 1 do
            -- Get the media item
            item = reaper.GetSelectedMediaItem(0, i)
            -- Get the track of the media item
            track = reaper.GetMediaItemTrack(item)

            -- Check if the track is already in the table
            if track_items[track] == nil then
                track_items[track] = {}
            end
            
            -- Add the item to the track's group
            table.insert(track_items[track], item)
        end

        -- Iterate through the track_items table and create groups
        for _, items in pairs(track_items) do
            -- Clear any existing grouping
            for _, item in ipairs(items) do
                reaper.SetMediaItemInfo_Value(item, "I_GROUPID", 0)
            end

            -- Select the items on this track
            reaper.Main_OnCommand(40289, 0) -- Unselect all items
            for _, item in ipairs(items) do
                reaper.SetMediaItemSelected(item, true)
            end

            -- Create a new group for the selected items
            reaper.Main_OnCommand(40032, 0) -- Group selected items
        end
    end
end

---------------------------------
-------------- MAIN -------------
---------------------------------

-- reaper.APITest()
-- reaper.ShowConsoleMsg("-- Script started\n")

-- Begin the undo block
reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock() -- Begining of the undo block. Leave it at the top of your main function.

--SaveView()
--SaveCursorPos()
--SaveLoopTimesel()
SaveSelectedItems(init_sel_items)
--SaveSelectedTracks(init_sel_tracks)

main()

--RestoreCursorPos()
--RestoreLoopTimesel()
RestoreSelectedItems(init_sel_items)
--RestoreSelectedTracks(init_sel_tracks)
--RestoreView()

-- Update the arrangement to reflect the new selection
reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, -1)
reaper.PreventUIRefresh(-1)
reaper.UpdateTimeline()
reaper.UpdateArrange()

-- End the undo block with a description
-- reaper.ShowConsoleMsg("-- Script finished\n\n")

-- reaper.ShowMessageBox("Script executed in (s): "..tostring(reaper.time_precise() - time_init), "", 0)