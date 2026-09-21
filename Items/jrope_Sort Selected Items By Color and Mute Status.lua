-- @description Rearrange Selected Item Position Based on Color and Mute State
-- @author Stephen Schappler (Modified by JRope)
-- @version 1.2
-- @about
--   Original script by Stephen Schappler 'Rearrange Selected Item Position Based on Color'
--   Order: colored unmuted -> uncolored unmuted -> colored muted -> uncolored muted
-- @changelog 
--   8/30/24 v1.0 - Creating the script
--   4/17/25 v1.1 - Modified to handle items on separate tracks independently, and move muted items to the end
--   9/9/26  v1.2 - Fixed colored items landing behind default-colored items: I_CUSTOMCOLOR is now
--                  tested against REAPER's 0x1000000 "custom color set" flag instead of ~= 0, and
--                  color groups are ordered deterministically by their earliest item position

-- True only when the item actually has a custom color assigned.
-- REAPER ORs 0x1000000 into I_CUSTOMCOLOR when a custom color is set; the raw
-- value can be non-zero without that flag (e.g. a color that was later cleared),
-- which made default-colored items sort as if they were colored.
local function HasCustomColor(item)
    local color = reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
    return (math.floor(color) & 0x1000000) ~= 0, math.floor(color)
end

function main()
    local item_count = reaper.CountSelectedMediaItems(0)
    if item_count == 0 then return end
    
    -- Group items by track first
    local track_items = {}
    
    -- Collect all items and organize them by track
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local track = reaper.GetMediaItem_Track(item)
        local track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
        
        if not track_items[track_idx] then
            track_items[track_idx] = {}
        end
        
        table.insert(track_items[track_idx], item)
    end
    
    -- Process each track separately
    for track_idx, items in pairs(track_items) do
        process_track_items(items)
    end
    
    reaper.UpdateArrange()
end

-- Appends every item of a color-keyed group table to sorted_items.
-- Color groups run in order of their earliest item, and items inside a group
-- run in their original position order, so the result is stable run to run.
local function append_color_groups(color_groups, sorted_items)
    local ordered_colors = {}
    for color, group in pairs(color_groups) do
        table.sort(group, function(a, b) return a.position < b.position end)
        table.insert(ordered_colors, {color = color, position = group[1].position})
    end
    
    table.sort(ordered_colors, function(a, b)
        if a.position == b.position then return a.color < b.color end
        return a.position < b.position
    end)
    
    for _, entry in ipairs(ordered_colors) do
        for _, item_data in ipairs(color_groups[entry.color]) do
            table.insert(sorted_items, item_data.item)
        end
    end
end

local function append_items(list, sorted_items)
    table.sort(list, function(a, b) return a.position < b.position end)
    for _, item_data in ipairs(list) do
        table.insert(sorted_items, item_data.item)
    end
end

function process_track_items(items)
    -- Find the earliest item position on this track
    local first_position = nil
    for _, item in ipairs(items) do
        local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        if first_position == nil or position < first_position then
            first_position = position
        end
    end
    
    local color_groups_unmuted = {}
    local uncolored_items_unmuted = {}
    local color_groups_muted = {}
    local uncolored_items_muted = {}
    
    -- Group items by color and mute state
    for _, item in ipairs(items) do
        local colored, color = HasCustomColor(item)
        local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 1
        
        local color_groups = muted and color_groups_muted or color_groups_unmuted
        local uncolored_items = muted and uncolored_items_muted or uncolored_items_unmuted
        
        if colored then
            if not color_groups[color] then
                color_groups[color] = {}
            end
            table.insert(color_groups[color], {item=item, position=position})
        else
            table.insert(uncolored_items, {item=item, position=position})
        end
    end
    
    -- Build the final sorted list of items:
    -- 1. colored unmuted  2. uncolored unmuted  3. colored muted  4. uncolored muted
    local sorted_items = {}
    append_color_groups(color_groups_unmuted, sorted_items)
    append_items(uncolored_items_unmuted, sorted_items)
    append_color_groups(color_groups_muted, sorted_items)
    append_items(uncolored_items_muted, sorted_items)
    
    -- If no items to rearrange, exit
    if #sorted_items == 0 then return end
    
    -- Start repositioning from the first position on this track
    local current_position = first_position
    
    for _, item in ipairs(sorted_items) do
        reaper.SetMediaItemPosition(item, current_position, false)
        current_position = current_position + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    end
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Rearrange items by color and mute state", -1)
