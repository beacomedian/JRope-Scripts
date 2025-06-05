--[[
   * ReaScript Name: Snap selected items to each other (Multi-track)
   * Lua script for Cockos REAPER
   * Author: MPL (Modified by JRope)
   * Author URI: http://forum.cockos.com/member.php?u=70694
   * Licence: GPL v3
   * Version: 1.2
   * About: modification of "mpl_Snap selected items to each other to work across multiple tracks" to work across multiple tracks of selected items
  ]]
  
script_title = "Snap selected items to each other (Multi-track)"
reaper.Undo_BeginBlock()

-- Get count of selected items
item_count = reaper.CountSelectedMediaItems(0)

if item_count > 0 then
  -- Create a table to store items grouped by track
  local tracks = {}
  
  -- Collect all selected items and organize by track
  for i = 0, item_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
      local track = reaper.GetMediaItem_Track(item)
      local track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
      
      -- Initialize track table if it doesn't exist
      if not tracks[track_idx] then
        tracks[track_idx] = {}
      end
      
      -- Store item position and item itself
      table.insert(tracks[track_idx], {
        item = item,
        position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      })
    end
  end
  
  -- Process each track separately
  for track_idx, track_items in pairs(tracks) do
    -- Sort items by position
    table.sort(track_items, function(a, b) return a.position < b.position end)
    
    -- Snap items within each track
    for i = 2, #track_items do
      local prev_item = track_items[i-1].item
      local curr_item = track_items[i].item
      
      local prev_item_pos = reaper.GetMediaItemInfo_Value(prev_item, "D_POSITION")
      local prev_item_len = reaper.GetMediaItemInfo_Value(prev_item, "D_LENGTH")
      local new_pos = prev_item_pos + prev_item_len
      
      reaper.SetMediaItemInfo_Value(curr_item, "D_POSITION", new_pos)
    end
  end
end

reaper.UpdateArrange()
reaper.Undo_EndBlock(script_title, 0)
