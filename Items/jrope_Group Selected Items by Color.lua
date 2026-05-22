--[[
 * Name: Group Selected Items by Color
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
  # Create a new group for each unique color, optionally group all default/uncolored items
 * Changelog:
  # Initial Release
 * To Do:
  # 


]]



---------------------------------
---------- USER CONFIG ----------
---------------------------------

local IGNORE_UNCOLORED_ITEMS = true  -- Set to false to include items with no color (color value = 0)

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
  -- Get the number of selected media items
  local item_count = reaper.CountSelectedMediaItems(0)
  
  -- Check if any items are selected
  if item_count == 0 then
    reaper.ShowMessageBox("Please select at least one item", "No Items Selected", 0)
    return
  end
  
  -- Store all originally selected items BEFORE we start changing selection
  local original_items = {}
  for i = 0, item_count - 1 do
    original_items[i + 1] = reaper.GetSelectedMediaItem(0, i)
  end
  
  -- Create a table to store items organized by color
  local color_groups = {}
  
  -- Loop through all selected items and organize by color
  for i = 1, #original_items do
    local item = original_items[i]
    local item_color = reaper.GetDisplayedMediaItemColor(item)
    
    -- Skip uncolored items if user config says so
    if not (IGNORE_UNCOLORED_ITEMS and item_color == 0) then
      -- If this color hasn't been seen yet, create a new table for it
      if not color_groups[item_color] then
        color_groups[item_color] = {}
      end
      
      -- Add this item to the appropriate color group
      table.insert(color_groups[item_color], item)
    end
  end
  
  --[[
  -- Print detected colors to console
  reaper.ShowConsoleMsg("=== Detected Colors ===\n")
  local color_count = 0
  for color, items in pairs(color_groups) do
    color_count = color_count + 1
    reaper.ShowConsoleMsg("Color " .. color_count .. ": " .. color .. " (" .. #items .. " items)\n")
  end
  reaper.ShowConsoleMsg("Total unique colors: " .. color_count .. "\n\n")
  ]]
  
  -- Loop through each color in the table
  for color, items in pairs(color_groups) do
    -- Only create groups if there's more than one item with this color
    if #items > 1 then
      -- Step 1: Deselect all items
      reaper.SelectAllMediaItems(0, false)
      
      -- Step 2: Select items matching this color
      for j = 1, #items do
        reaper.SetMediaItemSelected(items[j], true)
      end
      
      -- Step 3: Group them
      reaper.Main_OnCommand(40032, 0) -- Item grouping: Group items
    end
  end
  
  -- Reselect all originally selected items
  reaper.SelectAllMediaItems(0, false)
  for i = 1, #original_items do
    reaper.SetMediaItemSelected(original_items[i], true)
  end 
  
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
