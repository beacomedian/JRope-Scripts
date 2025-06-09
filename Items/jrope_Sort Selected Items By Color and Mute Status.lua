-- @description Rearrange Selected Item Position Based on Color and Mute State
-- @author Stephen Schappler (Modified by JRope)
-- @version 1.1
-- @about
--   Original script by Stephen Schappler 'Rearrange Selected Item Position Based on Color'
-- @changelog 
--   8/30/24 v1.0 - Creating the script
--   4/17/25 v1.1 - Modified to handle items on separate tracks independently, and move muted items to the end

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
        local color = reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
        local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 1
        
        if muted then
            -- Handle muted items
            if color == 0 then
                table.insert(uncolored_items_muted, {item=item, position=position})
            else
                if not color_groups_muted[color] then
                    color_groups_muted[color] = {}
                end
                table.insert(color_groups_muted[color], {item=item, position=position})
            end
        else
            -- Handle unmuted items
            if color == 0 then
                table.insert(uncolored_items_unmuted, {item=item, position=position})
            else
                if not color_groups_unmuted[color] then
                    color_groups_unmuted[color] = {}
                end
                table.insert(color_groups_unmuted[color], {item=item, position=position})
            end
        end
    end
    
    -- Create ordered arrays of colors for both unmuted and muted items
    local sorted_unmuted_colors = {}
    for color, _ in pairs(color_groups_unmuted) do
        table.insert(sorted_unmuted_colors, color)
    end
    
    local sorted_muted_colors = {}
    for color, _ in pairs(color_groups_muted) do
        table.insert(sorted_muted_colors, color)
    end
    
    -- Build the final sorted list of items
    local sorted_items = {}
    
    -- 1. First add all colored unmuted items
    for _, color in ipairs(sorted_unmuted_colors) do
        local group = color_groups_unmuted[color]
        -- Sort items within the same color group by their original position
        table.sort(group, function(a, b)
            return a.position < b.position
        end)
        
        -- Add sorted items to the final list
        for _, item_data in ipairs(group) do
            table.insert(sorted_items, item_data.item)
        end
    end
    
    -- 2. Then add all uncolored unmuted items
    table.sort(uncolored_items_unmuted, function(a, b)
        return a.position < b.position
    end)
    
    for _, item_data in ipairs(uncolored_items_unmuted) do
        table.insert(sorted_items, item_data.item)
    end
    
    -- 3. Then add all colored muted items
    for _, color in ipairs(sorted_muted_colors) do
        local group = color_groups_muted[color]
        -- Sort items within the same color group by their original position
        table.sort(group, function(a, b)
            return a.position < b.position
        end)
        
        -- Add sorted items to the final list
        for _, item_data in ipairs(group) do
            table.insert(sorted_items, item_data.item)
        end
    end
    
    -- 4. Finally add all uncolored muted items
    table.sort(uncolored_items_muted, function(a, b)
        return a.position < b.position
    end)
    
    for _, item_data in ipairs(uncolored_items_muted) do
        table.insert(sorted_items, item_data.item)
    end
    
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
