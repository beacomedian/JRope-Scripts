--[[
 * Name: Group Adjacent Selected Items
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
    [main] . > 
 * Link: https://www.jesserope.com
 * noindex
 * About: From selected items, group contiguous chains of items, per track
 * Changelog:
    # Initial Release
 * To Do:
    # 


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

-- Load my common functions
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]]) 
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")









-- Global variable to store original selection
local original_selected_items = {}

function main()
    -- Get the number of selected items
    local num_selected = reaper.CountSelectedMediaItems(0)
    
    if num_selected < 2 then
        reaper.ShowMessageBox("Please select at least 2 items to group.", "Group Adjacent Items", 0)
        return
    end
    
    -- Start undo block
    -- reaper.Undo_BeginBlock()
    
    -- Store original selection in global variable
    for i = 0, num_selected - 1 do
        original_selected_items[i] = reaper.GetSelectedMediaItem(0, i)
    end
    
    -- Create a table to store items by track
    local tracks_items = {}
    
    -- Collect all selected items organized by track
    for i = 0, num_selected - 1 do
        local item = original_selected_items[i]
        local track = reaper.GetMediaItem_Track(item)
        local track_ptr = reaper.GetTrack(0, reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1)
        
        if not tracks_items[track_ptr] then
            tracks_items[track_ptr] = {}
        end
        
        table.insert(tracks_items[track_ptr], item)
    end
    
    -- Process each track
    for track, items in pairs(tracks_items) do
        if #items > 1 then
            -- Sort items by position on the track
            table.sort(items, function(a, b)
                local pos_a = reaper.GetMediaItemInfo_Value(a, "D_POSITION")
                local pos_b = reaper.GetMediaItemInfo_Value(b, "D_POSITION")
                return pos_a < pos_b
            end)
            
            -- Find adjacent groups
            local groups = {}
            local current_group = {items[1]}
            
            for i = 2, #items do
                local prev_item = items[i-1]
                local curr_item = items[i]
                
                -- Get position and length of previous item
                local prev_pos = reaper.GetMediaItemInfo_Value(prev_item, "D_POSITION")
                local prev_len = reaper.GetMediaItemInfo_Value(prev_item, "D_LENGTH")
                local prev_end = prev_pos + prev_len
                
                -- Get position of current item
                local curr_pos = reaper.GetMediaItemInfo_Value(curr_item, "D_POSITION")
                
                -- Check if items are touching (allowing for small floating point errors)
                local gap = curr_pos - prev_end
                local tolerance = 0.001 -- 1ms tolerance for floating point precision
                
                if math.abs(gap) <= tolerance then
                    -- Items are adjacent, add to current group
                    table.insert(current_group, curr_item)
                else
                    -- Items are not adjacent, finish current group and start new one
                    if #current_group > 1 then
                        table.insert(groups, current_group)
                    end
                    current_group = {curr_item}
                end
            end
            
            -- Don't forget the last group
            if #current_group > 1 then
                table.insert(groups, current_group)
            end
            
            -- Create groups for adjacent items
            for _, group in ipairs(groups) do
                if #group > 1 then
                   
                    -- First select only the items in this group
                    reaper.SelectAllMediaItems(0, false) -- Deselect all
                    for _, item in ipairs(group) do
                        reaper.SetMediaItemSelected(item, true)
                    end
                    
                    -- Group the selected items
                    reaper.Main_OnCommand(40032, 0) -- Item grouping: Group items
                end
            end
        end
    end
    
    -- Restore original selection
    reaper.SelectAllMediaItems(0, false)
    for i = 0, #original_selected_items - 1 do
        local item = original_selected_items[i]
        reaper.SetMediaItemSelected(item, true)
    end
    
    -- End undo block
    -- reaper.Undo_EndBlock("Group Adjacent Selected Items", -1)
    
    -- Update the arrange view
    -- reaper.UpdateArrange()
end

---------------------------------
-------------- MAIN -------------
---------------------------------

-- reaper.APITest()
-- local time_init = reaper.time_precise()
-- reaper.ShowConsoleMsg("-- Script started\n")

-- Begin the undo block
-- reaper.PreventUIRefresh(1)
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
-- reaper.PreventUIRefresh(-1)
-- reaper.UpdateTimeline()
reaper.UpdateArrange()

-- End the undo block with a description
-- reaper.ShowConsoleMsg("-- Script finished\n\n")
-- reaper.ShowMessageBox("Script executed in (s): "..tostring(reaper.time_precise() - time_init), "", 0)