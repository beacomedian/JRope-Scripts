-- @description Rearrange Selected Item Position Based on Color and Mute State, maintaining original spacing/positions
-- @author Stephen Schappler (Modified by JRope)
-- @version 1.1
-- @about
--   Original script by Stephen Schappler 'Rearrange Selected Item Position Based on Color'
-- @changelog 
--   8/30/24 v1.0 - Creating the script
--   4/17/25 v1.1 - Modified to handle items on separate tracks independently, preserve original item spacing, move muted items to the end

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
    -- First, collect all items with their original positions
    local item_data = {}
    local positions = {}
    
    for _, item in ipairs(items) do
        local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local color = reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
        local muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 1
        
        table.insert(item_data, {
            item = item,
            position = position,
            color = color,
            muted = muted
        })
        
        table.insert(positions, position)
    end
    
    -- Sort positions to get original timeline positions
    table.sort(positions)
    
    -- Separate items into four groups:
    -- 1. Colored unmuted items
    -- 2. Uncolored unmuted items
    -- 3. Colored muted items
    -- 4. Uncolored muted items
    local colored_unmuted = {}
    local uncolored_unmuted = {}
    local colored_muted = {}
    local uncolored_muted = {}
    
    for _, data in ipairs(item_data) do
        if data.muted then
            -- Muted items
            if data.color == 0 then
                table.insert(uncolored_muted, data)
            else
                if not colored_muted[data.color] then
                    colored_muted[data.color] = {}
                end
                table.insert(colored_muted[data.color], data)
            end
        else
            -- Unmuted items
            if data.color == 0 then
                table.insert(uncolored_unmuted, data)
            else
                if not colored_unmuted[data.color] then
                    colored_unmuted[data.color] = {}
                end
                table.insert(colored_unmuted[data.color], data)
            end
        end
    end
    
    -- Create ordered arrays of colors for both unmuted and muted colored items
    local sorted_unmuted_colors = {}
    for color, _ in pairs(colored_unmuted) do
        table.insert(sorted_unmuted_colors, color)
    end
    
    local sorted_muted_colors = {}
    for color, _ in pairs(colored_muted) do
        table.insert(sorted_muted_colors, color)
    end
    
    -- Build the final sorted list of items
    local sorted_items = {}
    
    -- 1. First add all colored unmuted items
    for _, color in ipairs(sorted_unmuted_colors) do
        local group = colored_unmuted[color]
        -- Sort items within the same color group by their original position
        table.sort(group, function(a, b)
            return a.position < b.position
        end)
        
        -- Add sorted items to the final list
        for _, data in ipairs(group) do
            table.insert(sorted_items, data)
        end
    end
    
    -- 2. Then add all uncolored unmuted items
    table.sort(uncolored_unmuted, function(a, b)
        return a.position < b.position
    end)
    
    for _, data in ipairs(uncolored_unmuted) do
        table.insert(sorted_items, data)
    end
    
    -- 3. Then add all colored muted items
    for _, color in ipairs(sorted_muted_colors) do
        local group = colored_muted[color]
        -- Sort items within the same color group by their original position
        table.sort(group, function(a, b)
            return a.position < b.position
        end)
        
        -- Add sorted items to the final list
        for _, data in ipairs(group) do
            table.insert(sorted_items, data)
        end
    end
    
    -- 4. Finally add all uncolored muted items
    table.sort(uncolored_muted, function(a, b)
        return a.position < b.position
    end)
    
    for _, data in ipairs(uncolored_muted) do
        table.insert(sorted_items, data)
    end
    
    -- If no items to rearrange, exit
    if #sorted_items == 0 then return end
    
    -- Assign each item to its corresponding position from the original timeline
    for i = 1, #sorted_items do
        local position_to_use = positions[i]
        reaper.SetMediaItemPosition(sorted_items[i].item, position_to_use, false)
    end
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Rearrange items by color and mute state", -1)
