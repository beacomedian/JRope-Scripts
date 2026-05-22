--[[
 * Name: Trim and fade selected items (transient + threshold)
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
  [main] . > 
 * Link: https://www.jesserope.com
 * noindex
 * About:Trims left edge to volume threshold, right edge to last transient, with fades
  - Based off of X-Raym Trim left edge of selected items to first transient and MPL Auto Crop
 * Changelog:
  # Initial Release
 * To Do:
  # 


]]



-- USER CONFIG AREA -----------------------------------------------------------

console = false -- true/false: display debug messages in the console
threshold_dB = -45 -- volume threshold in dB for right edge detection
left_fade = 0.001 -- left fade duration in seconds
right_fade = 0.1 -- right fade duration in seconds
left_padding_ms = 10 -- padding before left edge in milliseconds (safety margin)
right_padding_ms = 100 -- padding after right edge in milliseconds (safety margin)
set_snap_offset = false -- true/false: set item snap offset at the detected transient

------------------------------------------------------- END OF USER CONFIG AREA


-- UTILITIES -------------------------------------------------------------

-- Display a message in the console for debugging
function Msg(value)
  if console then
    reaper.ShowConsoleMsg(tostring(value) .. "\n")
  end
end

-- Convert dB to linear value
function WDL_DB2VAL(x) 
  return math.exp((x) * 0.11512925464970228420089957273422) 
end

-- Find the right boundary (last point above threshold)
function FindRightBoundary(item, take, threshold_lin)
  local accessor = reaper.CreateTakeAudioAccessor(take)
  local src = reaper.GetMediaItemTake_Source(take)
  local SR = reaper.GetMediaSourceSampleRate(src)
  local chan = reaper.GetMediaSourceNumChannels(src)
  local it_len = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
  
  local test_dist = 0.01 -- check every 10ms
  local end_offset = 0
  
  -- Scan from end backward until we find audio above threshold
  for pos = it_len - test_dist, 0, -test_dist do
    local samplebuffer = reaper.new_array(chan)
    reaper.GetAudioAccessorSamples(accessor, SR, chan, pos, 1, samplebuffer)
    
    local spl_max = 0
    for i = 1, chan do
      local spl = samplebuffer[i]
      spl_max = math.max(spl_max, math.abs(spl))
    end
    
    if spl_max > threshold_lin then
      end_offset = it_len - pos - test_dist -- how much to trim from end
      break
    end
    
    samplebuffer.clear()
  end
  
  reaper.DestroyAudioAccessor(accessor)
  return end_offset
end

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
-- local time_init = reaper.time_precise()
local r = reaper
local proj = 0

--------------------------------------------------------- END OF UTILITIES


-- Main function
function main()
  local threshold_lin = WDL_DB2VAL(threshold_dB)
  
  -- Convert milliseconds to seconds for padding
  local left_padding = left_padding_ms / 1000
  local right_padding = right_padding_ms / 1000
  
  for i, item in ipairs(init_sel_items) do
    local take = reaper.GetActiveTake(item)
    
    -- Only process audio items (not MIDI)
    if take and not reaper.TakeIsMIDI(take) then
      local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      local original_start = item_pos
      local original_end = item_pos + item_len
      
      -- TRIM LEFT EDGE TO FIRST TRANSIENT
      reaper.SetEditCurPos(item_pos, false, false)
      reaper.Main_OnCommand(40375, 0) -- Item navigation: Move cursor to next transient in items
      local transient_pos = reaper.GetCursorPosition()
      local new_start_pos = transient_pos
      
      -- Make sure we found a valid transient
      if new_start_pos <= item_pos or new_start_pos >= item_pos + item_len then
        new_start_pos = item_pos -- keep original start if transient detection fails
        Msg("Item " .. i .. " - Warning: Could not find valid transient at start, keeping original position")
      end
      
      -- Apply left padding (move start earlier)
      new_start_pos = new_start_pos - left_padding
      -- Don't go before the original item start
      new_start_pos = math.max(new_start_pos, original_start)
      
      -- TRIM RIGHT EDGE TO THRESHOLD
      local right_trim = FindRightBoundary(item, take, threshold_lin)
      local new_end_pos = item_pos + item_len - right_trim
      Msg("Item " .. i .. " - Right trim: " .. right_trim .. " seconds")
      
      -- Apply right padding (move end later)
      new_end_pos = new_end_pos + right_padding
      -- Don't go beyond the original item end
      new_end_pos = math.min(new_end_pos, original_end)
      
      -- Make sure the new end is after the new start
      if new_end_pos <= new_start_pos then
        new_end_pos = item_pos + item_len -- keep original end if something went wrong
        Msg("Item " .. i .. " - Warning: Invalid trim result, keeping original length")
      end
      
      -- Apply the new edges
      reaper.BR_SetItemEdges(item, new_start_pos, new_end_pos)
      
      -- SET SNAP OFFSET AT TRANSIENT (if enabled)
      if set_snap_offset and transient_pos >= new_start_pos and transient_pos <= new_end_pos then
        -- Calculate snap offset relative to new item start
        local snap_offset = transient_pos - new_start_pos
        reaper.SetMediaItemInfo_Value(item, "D_SNAPOFFSET", snap_offset)
        Msg("Item " .. i .. " - Snap offset set at " .. snap_offset .. " seconds from item start")
      end
      
      -- ADD FADES
      reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", left_fade)
      reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", right_fade)
      
      if console then
        local padding_info = ""
        if left_padding > 0 or right_padding > 0 then
          padding_info = " (with padding: L=" .. left_padding_ms .. "ms, R=" .. right_padding_ms .. "ms)"
        end
        Msg("Item " .. i .. " - Processed: Start=" .. new_start_pos .. " End=" .. new_end_pos .. padding_info)
      end
    else
      Msg("Item " .. i .. " - Skipped (MIDI or no active take)")
    end
  end
end


-- INITIALIZATION

function Init()
  -- Check if BR_SetItemEdges is available (from SWS extension)
  if not reaper.APIExists("BR_SetItemEdges") then
    reaper.MB("This script requires the SWS extension.\nPlease install it from www.sws-extension.org", "Missing Extension", 0)
    return false
  end
  
  -- Check for selected items
  local count_sel_items = reaper.CountSelectedMediaItems(0)
  if count_sel_items == 0 then
    Msg("No items selected")
    return false
  end
  
  -- Save current state
  init_sel_items = {}
  for i = 0, count_sel_items - 1 do
    init_sel_items[i + 1] = reaper.GetSelectedMediaItem(0, i)
  end
  
  local cur_pos = reaper.GetCursorPosition()
  local group_state = reaper.GetToggleCommandState(1156)
  
  -- Disable grouping temporarily if enabled
  if group_state == 1 then
    reaper.Main_OnCommand(1156, 0)
  end
  
  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()
  
  -- Run main processing
  main()
  
  -- Restore state
  if group_state == 1 then
    reaper.Main_OnCommand(1156, 0)
  end
  
  reaper.SetEditCurPos(cur_pos, false, false)
  reaper.Undo_EndBlock("Trim and fade selected items", -1)
  reaper.UpdateArrange()
  reaper.PreventUIRefresh(-1)
  
  return true
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

Init()

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
