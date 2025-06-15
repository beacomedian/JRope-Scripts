--[[
 * Name: Randomly color selected items by Group ID
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
    # From selected items, assign a random color to each Item Group
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



function main()
    -- Check if there are any selected items
    local selected_item_count = reaper.CountSelectedMediaItems(0)
    if selected_item_count == 0 then
        reaper.ShowMessageBox("No items selected.", "Random Group Colors", 0)
        return
    end
    
    -- Table to store group IDs and their assigned colors
    local groups = {}
    local processed_groups = {}
    
    -- First pass: collect all group IDs from selected items
    for i = 0, selected_item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local group_id = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
        
        -- Only process items that are actually in a group (group_id > 0)
        if group_id > 0 and not groups[group_id] then
            groups[group_id] = true
        end
    end
    
    -- Check if there are any grouped items
    local group_count = 0
    for _ in pairs(groups) do
        group_count = group_count + 1
    end
    
    if group_count == 0 then
        reaper.ShowMessageBox("No grouped items found in selection.", "Random Group Colors", 0)
        return
    end
    
    -- Save original selection
    local original_selection = {}
    for i = 0, selected_item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        table.insert(original_selection, item)
    end
    
    -- Begin undo block
    -- reaper.Undo_BeginBlock()
    
    -- Process each group
    for group_id, _ in pairs(groups) do
        if not processed_groups[group_id] then
            -- Select all items in this group (from all items in project, not just selected)
            reaper.SelectAllMediaItems(0, false) -- Deselect all first
            
            local items_in_group = 0
            local total_item_count = reaper.CountMediaItems(0)
            for i = 0, total_item_count - 1 do
                local item = reaper.GetMediaItem(0, i)
                local item_group_id = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
                
                if item_group_id == group_id then
                    reaper.SetMediaItemSelected(item, true)
                    items_in_group = items_in_group + 1
                end
            end
            
            -- Apply random color to selected items (group)
            if items_in_group > 0 then
                reaper.Main_OnCommand(40706, 0) -- Set random color for selected items
                processed_groups[group_id] = true
            end
        end
    end
    
    -- Restore original selection
    reaper.SelectAllMediaItems(0, false) -- Deselect all first
    for _, item in ipairs(original_selection) do
        reaper.SetMediaItemSelected(item, true)
    end
    
    -- End undo block
    -- reaper.Undo_EndBlock("Random Colors for Item Groups", -1)
    
    -- Show completion message
    -- reaper.ShowMessageBox("Applied random colors to " .. group_count .. " item groups from selection.", "Random Group Colors", 0)
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
