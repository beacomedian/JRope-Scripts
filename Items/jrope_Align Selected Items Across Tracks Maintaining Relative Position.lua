--[[
 * Name: Align Selected Items Across Tracks Maintaining Relative Position
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
    # From the selected items, aligns the beginning of each track's group while maintaining item spacing along the track
 * Changelog:
    # Initial Release
 * To Do:
    # 


]]



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

-- Load my common functions
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]]) 
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")






-- Function to get all selected items organized by track
function getSelectedItemsByTrack()
    local itemsByTrack = {}
    local itemCount = reaper.CountSelectedMediaItems(0)
    
    if itemCount == 0 then
        reaper.ShowMessageBox("No items selected.", "Error", 0)
        return nil
    end
    
    -- Organize items by track
    for i = 0, itemCount - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local track = reaper.GetMediaItem_Track(item)
        local trackNumber = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
        
        -- Initialize track table if it doesn't exist
        if not itemsByTrack[trackNumber] then
            itemsByTrack[trackNumber] = {}
        end
        
        -- Add item to track's collection
        table.insert(itemsByTrack[trackNumber], item)
    end
    
    return itemsByTrack
end

-- Function to find the earliest start position for each track
function findEarliestPositions(itemsByTrack)
    local earliestPositions = {}
    local globalEarliest = math.huge
    
    for trackNumber, items in pairs(itemsByTrack) do
        local trackEarliest = math.huge
        
        for _, item in ipairs(items) do
            local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            if itemStart < trackEarliest then
                trackEarliest = itemStart
            end
        end
        
        earliestPositions[trackNumber] = trackEarliest
        
        -- Track the global earliest position across all tracks
        if trackEarliest < globalEarliest then
            globalEarliest = trackEarliest
        end
    end
    
    return earliestPositions, globalEarliest
end

-- Function to align items on each track
function alignTrackItems(itemsByTrack, earliestPositions, globalEarliest)
    for trackNumber, items in pairs(itemsByTrack) do
        local trackEarliest = earliestPositions[trackNumber]
        local offset = globalEarliest - trackEarliest
        
        -- Only move items if there's an actual offset needed
        if math.abs(offset) > 0.001 then -- Small tolerance for floating point comparison
            for _, item in ipairs(items) do
                local currentPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local newPos = currentPos + offset
                reaper.SetMediaItemInfo_Value(item, "D_POSITION", newPos)
            end
        end
    end
end





-- Main execution function
function main()
    -- Start undo block
    reaper.Undo_BeginBlock()
    
    -- Get selected items organized by track
    local itemsByTrack = getSelectedItemsByTrack()
    if not itemsByTrack then
        return -- Exit if no items selected
    end
    
    -- Find earliest positions
    local earliestPositions, globalEarliest = findEarliestPositions(itemsByTrack)
    
    -- Align the items
    alignTrackItems(itemsByTrack, earliestPositions, globalEarliest)
    
    -- Update the arrangement view
    reaper.UpdateArrange()
    
    -- End undo block
    reaper.Undo_EndBlock("Align Selected Items by Track Chunks", -1)
    
    -- Optional: Show completion message
    local trackCount = 0
    for _ in pairs(itemsByTrack) do
        trackCount = trackCount + 1
    end
    
    --[[reaper.ShowMessageBox(
        string.format("Aligned items on %d tracks to position %.3f", trackCount, globalEarliest),
        "Alignment Complete",
        0
    )]]
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
-- reaper.UpdateTimeline()
reaper.UpdateArrange()

-- End the undo block with a description
-- reaper.ShowConsoleMsg("-- Script finished\n\n")
-- reaper.ShowMessageBox("Script executed in (s): "..tostring(reaper.time_precise() - time_init), "", 0)
