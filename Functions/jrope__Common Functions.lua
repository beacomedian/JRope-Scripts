--[[
 * Name: Jrope Common Functions
 * Author: Jesse Rope
 * Repository: GitHub > beacomedian
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
 * Link: https://www.jesserope.com
 * About:
  # Collection of my shared functions
  # Constantly tweaked and CLs will not be kept up to date

 

 * Changelog:
  # Initial Release

]]



--||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--
-- ---------------- General Functions --------------------- --
--||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--

-- Prints to the REAPER console only when the calling script sets ENABLE_DEBUG_LOG = true.
function Log(...)
  if ENABLE_DEBUG_LOG then
    local t = {}
    for _, v in ipairs({...}) do t[#t + 1] = tostring(v) end
    reaper.ShowConsoleMsg(table.concat(t, " ") .. "\n")
  end
end


function Msg(x,y)
    reaper.ShowConsoleMsg(tostring(x)..tostring(y).."\n")
end 

function Print( ... )
  local t ={}
  for i,v in ipairs({...}) do
    t[i] = tostring(v)
  end
  reaper.ShowConsoleMsg( table.concat( t, " ") .."\n" )
end

function print( ... )
  local t ={}
  for i,v in ipairs({...}) do
    t[i] = tostring(v)
  end
  reaper.ShowConsoleMsg( table.concat( t, " ") .."\n" )
end


function GetTrack()
  local ud_sel_trk = reaper.GetSelectedTrack(0,0)
  if not ud_sel_trk then
    reaper.ShowMessageBox("Please select a Track", "Error", 0)
  end
end

function GetEnv()
  local ud_sel_env = reaper.GetSelectedEnvelope(0)
  if not ud_sel_env then
    reaper.ShowMessageBox("Please select an Envelope", "Error", 0)
  end
end

function GetSelItem(x)
  local sel_item_u = reaper.GetSelectedMediaItem(0,x)
  -- Msg(sel_item_u)
  if not sel_item_u then
    reaper.ShowMessageBox("Please select an Item", "Error", 0)
  end
end

function PrintItemProperties(x)
  Msg("- ITEM PROPERTIES","" )
  -- local sel_item = reaper.GetSelectedMediaItem(0, 0)
  Msg("ID: " ,(x))
  -- local item_position = reaper.GetMediaItemInfo_Value(x, "D_POSITION")
  -- Msg("Pos: " , item_position)
  -- local fadeo_len = reaper.GetMediaItemInfo_Value(x, "D_FADEOUTLEN")
  -- Msg("FadeO: " , fadeo_len)
  -- Msg("-","")
end

function GetTimeSelection()
  local time_start,time_end = reaper.GetSet_LoopTimeRange2(0, 0, 0, 0, 0, 0)
  if time_end == time_start
    then reaper.ShowMessageBox("Make a time selection.", "Error", 0)
    return
  end
end

--- Return dbval in linear value. 0 = -inf, 1 = 0dB, 2 = +6dB, etc...
function dBToLinear(dbval)
    return 10^(dbval/20) 
end

--- Return value in db. 0 = -inf, 1 = 0dB, 2 = +6dB, etc...
function LinearTodB(value)
    return 20 * math.log(value,10)    
end

function EnumSelectedTracks()
    local i = -1 
    return function ()
        i = i + 1
      return reaper.GetSelectedTrack(0, i)
    end
end

function EnumSelectedItems()
  local i = -1 -- sets initial i to -1 so the first loop of our next function will be 0
  return function () -- using an unnamed function to do multiple things
    i = i+1 -- increases the count each time the loop is run
    return reaper.GetSelectedMediaItem(0, i) -- returns the next item each time the loop is run
  end -- when i tries to get an item beyond the number selected, the reaper action will return nil, which will close the loop
end

--[[
function CheckTableContents(...)
  -- local t = {}
  -- for key, value in pairs(...) do 
  --  t[i] = tostring(v)
  -- end
  -- reaper.ShowConsoleMsg(table.concat(t, " ").."\n")
  reaper.ShowConsoleMsg(table.concat(..., " ").."\n") -- should this work by itself if we're just putting a table in here?
end
]]

function SelectSelectedItemsTracks()
  -- reaper.Main_OnCommand(40297s, 0) -- deselect all tracks
  local num_selected_items = reaper.CountSelectedMediaItems(0)
  -- Loop through each selected item
  for i = 0, num_selected_items - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      if item then
          -- Get the track of the current item
          local track = reaper.GetMediaItemTrack(item)
          if track then
              -- Select the track
              reaper.SetTrackSelected(track, true)
          end
      end
  end
end

function PrintTable(tbl, indent) -- Function to print a table's contents recursively
    -- Msg("Printing Table: ",tbl)
    indent = indent or 0
    local indentString = string.rep("  ", indent)

    for key, value in pairs(tbl) do
        if type(value) == "table" then
            reaper.ShowConsoleMsg(indentString .. tostring(key) .. ":\n")
            PrintTable(value, indent + 1)
        else
            reaper.ShowConsoleMsg(string.format("%s%s: %s\n", indentString, tostring(key), tostring(value)))
        end
    end
end

function Msg2(...)
  -- via Claudiobsantos
  local indent = 0

  local function printTable(table,tableName)
    if tableName then reaper.ShowConsoleMsg(string.rep("    ",indent)..tostring(tableName)..": \n") end
    indent = indent + 1
    for key,tableValue in pairs(table) do
      if type(tableValue) == "table" then
        printTable(tableValue,key)
      else
        reaper.ShowConsoleMsg(string.rep("    ",indent)..tostring(key).." = "..tostring(tableValue).."\n")
      end
    end
    indent = indent - 1
  end

  printTable({...})
end


function ValueExistsInTable(tbl, value) -- check if a value exists in an table
    for i = 1, #tbl do
        if tbl[i] == value then
          Log("Value exists: ", value)
            return true
        else
          Log("Value doesn't exist: ", value)
        end
    end
    return false
end

function AddRegionIndexesToTable()
  -- body
  local tbl = {}
  -- add to table
  num_markers_and_regions = CountMarkersAndRegions()
  for i = 0,num_markers_and_regions-1 do
    local _, isRegion, startPos, endPos, name, indx, color = reaper.EnumProjectMarkers3(0,i)
    if isRegion then
      table.insert(tbl,indx)
    end
  end
  return tbl
end


function CountMarkersAndRegions()
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local num_markers_and_regions = num_markers + num_regions
  Log("num_markers_and_regions: ", num_markers_and_regions)
  return num_markers_and_regions
end

function MapRange(value,min1,max1,min2,max2)
    return (value - min1) / (max1 - min1) * (max2 - min2) + min2
end

function RandomNumberFloat(min,max,is_include_max)
    local sub = (is_include_max and 0) or 1 --  -1 because it cant never be the max value. Lets say we want to choose random between a and b a have 2/3 chance and b 1/3. If the random value is from 0 - 2(not includded) it is a, if the value is from 2 - 3(not includded) it is b.
    local big_val = 1000000 -- the bigger the number the bigger the resolution. Using 1M right now
    local random = math.random(0,big_val-sub) -- Generating a very big value to be Scaled to the sum of the chances, for enabling floats.
    random = MapRange(random,0,big_val,min,max) -- Scale the random value to the sum of the chances

    return random
end


-- Returns the selected media item count. If zero, shows a message box and returns nil.
-- Usage: if not RequireSelectedItems() then return end
function RequireSelectedItems(msg)
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then
    reaper.ShowMessageBox(msg or "No items selected!", "Error", 0)
    return nil
  end
  return count
end

-- Returns the selected track count. If zero, shows a message box and returns nil.
-- Usage: if not RequireSelectedTracks() then return end
function RequireSelectedTracks(msg)
  local count = reaper.CountSelectedTracks(0)
  if count == 0 then
    reaper.ShowMessageBox(msg or "No tracks selected!", "Error", 0)
    return nil
  end
  return count
end

-- Returns a table keyed by track (MediaTrack*) -> ordered list of that track's
-- currently selected items, in selection order.
function GetSelectedItemsByTrack()
  local tracks_items = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)
    if not tracks_items[track] then tracks_items[track] = {} end
    table.insert(tracks_items[track], item)
  end
  return tracks_items
end

-- Sorts an array of media items in place by timeline position (ascending). Returns the table.
function SortItemsByPosition(items)
  table.sort(items, function(a, b)
    return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
  end)
  return items
end

-- Absolute folder nesting depth of a track: the running sum of I_FOLDERDEPTH deltas
-- of all tracks before it. Top-level tracks return 0. Clamped to >= 0.
function GetTrackDepth(track)
  local track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
  local depth = 0
  for i = 0, track_idx - 1 do
    depth = depth + reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, i), "I_FOLDERDEPTH")
  end
  if depth < 0 then depth = 0 end
  return depth
end

-- Deletes a track without breaking the folder structure of the tracks around it.
-- A deleted track that closed one or more folders (negative I_FOLDERDEPTH) hands
-- that closing depth to the track above it.
-- If the track is a folder parent: with include_children, the whole folder
-- (parent + all descendants) is deleted; otherwise nothing is deleted.
-- Returns the number of tracks deleted.
function DeleteTrackPreservingHierarchy(track, include_children)
  if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return 0 end
  local first = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
  local last = first
  local depth_sum = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

  if depth_sum > 0 then
    if not include_children then return 0 end
    -- Walk down until the folder is closed; depth_sum ends as the net closing depth (<= 0)
    local track_count = reaper.CountTracks(0)
    while depth_sum > 0 and last < track_count - 1 do
      last = last + 1
      depth_sum = depth_sum + reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, last), "I_FOLDERDEPTH")
    end
    if depth_sum > 0 then depth_sum = 0 end -- unterminated folder at end of project
  end

  for i = last, first, -1 do
    reaper.DeleteTrack(reaper.GetTrack(0, i))
  end

  if depth_sum < 0 and first > 0 then
    local prev = reaper.GetTrack(0, first - 1)
    local prev_depth = reaper.GetMediaTrackInfo_Value(prev, "I_FOLDERDEPTH")
    reaper.SetMediaTrackInfo_Value(prev, "I_FOLDERDEPTH", prev_depth + depth_sum)
  end

  return last - first + 1
end

-- Item color as displayed (falls back to track/default color if the item has none).
function GetItemDisplayedColor(item)
  return reaper.GetDisplayedMediaItemColor(item)
end

-- Item's explicitly-set custom color (raw int incl. the 0x1000000 "set" flag; 0 if none).
function GetItemCustomColor(item)
  return reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
end














--|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--
-- ---------------- Shared for Script Groups --------------------- --
--|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--


-------------------------------------------------------
--- USED FOR RIPPLE DELETE MARKER / REGIONS SCRIPTS ---
-------------------------------------------------------

function CountMatchingRegions_j( ... )
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  Log("Input String: '", ... .. "'")
  Log("Total Markers:", num_markers)
  Log("Total Regions:", num_regions)
  local num_markers_and_regions = num_markers + num_regions

  local count = 0

  for i = 0, num_markers_and_regions - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
    if isrgn and name:find(...) then
      count = count + 1
    end
  end

  Log(count .. " regions matching '" .. ... .. "'")
  return count
end

function CountMatchingMarkers_j( ... )
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  Log("Total Markers:", num_markers)
  Log("Total Regions:", num_regions)
  local num_markers_and_regions = num_markers + num_regions

  local count = 0

  for i = 0, num_markers_and_regions - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
    if not isrgn and name:find(...) then
      count = count + 1
    end
  end

  Log(count .. " markers matching '" .. ... .. "'")
  return count
end

function RippleDeleteMatchingRegions( ... )
  -- function main()
    -- Get time selection
    SaveLoopTimesel() -- init_start_timesel, init_end_timesel
    -- Verify the number of matching regions before proceeding
    local matching_regions_count = CountMatchingRegions_j(...)
    if matching_regions_count > 0 then
        reaper.Main_OnCommandEx(40311, 0, 0) -- enable ripple editing
        local _, num_markers, num_regions = reaper.CountProjectMarkers(0)       
        local num_markers_and_regions = num_markers + num_regions
        -- for i = num_regions, 0, -1 do    -- this command leaves some regions behind in large sessions
        -- for i = num_markers_and_regions, 0, -1 do   -- this command leaves some regions behind in large sessions
        for i = 200, 0, - 1 do -- forcing it to loop an arbitrarily high number takes care of all the regions, so something about the loop counts above need to be reconsidered
        -- probably should do something like putting loop ID into a table then running a while loop and strike off the ID as it's processed
            local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)            
            -- if isrgn and name:find("^x ") then
            -- if isrgn and name:find("^"..search_string) then -- trying out user input search string
            if isrgn and name:find(...) then -- trying out user input search string
              -- ensure region is inside original time selection if there was one
              if pos >= init_start_timesel and rgnend <= init_end_timesel or init_start_timesel == init_end_timesel then
                  -- Set time selection to the region
                  reaper.GetSet_LoopTimeRange(true, false, pos, rgnend, false)
                  reaper.Main_OnCommandEx(40630, 0, 0) -- move cursor to start of time selection
                  local pos = reaper.GetCursorPositionEx(0)
                  Log("Deleting Region: ", i)
                  reaper.Main_OnCommandEx(40717, 0, 0) -- select all items in time selection
                  reaper.Main_OnCommand(reaper.NamedCommandLookup("_XENAKIOS_TSADEL"), 0) -- adaptive delete time selection
                  reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_CROSSFADE"), 0) -- crossfade adjacent selected items
                  reaper.AddProjectMarker2(0, false, pos, 0, "xAutoCut", -1, 0x1000000) -- add marker at saved pos
                end
            end
        end
    else Log("No X regions found.")
    end
    -- Clear time selection after operation
    -- reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
-- end
end


function CreateRegionsAroundMarkers( ... )
  -- SaveLoopTimesel() -- init_start_timesel, init_end_timesel
  local search_string = ...
  local marker_index = 0
  local found = false
  local matching_markers_count = CountMatchingMarkers_j(search_string)

    if matching_markers_count > 0 then -- make sure there are markers matching the string
        -- reaper.Main_OnCommandEx(40311, 0, 0) -- enable ripple editing
        local _, num_markers, num_regions = reaper.CountProjectMarkers(0) 
        local num_markers_and_regions = CountMarkersAndRegions()
        Log("Expected Loop Times: ", num_markers_and_regions)

        while true do -- WHILE loops may be dangerous when creating new markers
          -- [] how to refactor this loop so that it only runs on the original matching markers and stops when they are processed

          -- Recount the total number of markers on each iteration
          local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
          local num_markers_and_regions = num_markers + num_regions
          -- Exit the loop if we've checked all markers
          if marker_index >= num_markers_and_regions then break end

            -- Msg("Loop: ",(1+marker_index))
            -- marker_index is based on timeline position - this breaks if we add a region that starts before an unprocessed marker
            local retval, isrgn, pos, rgnend, name, marker_idx = reaper.EnumProjectMarkers(marker_index) 
            if not retval then break end
            if isrgn == true then Log((1+marker_index), ": Skipping region") end
            if not isrgn and not name:find(...) then Log((1+marker_index), ": Skipping !match marker") end

            if not isrgn and name:find(...) then -- and not name:find("Auto")
                -- work only in time selection if there is one
                if pos >= init_start_timesel and pos <= init_end_timesel or init_start_timesel == init_end_timesel then
                  -- Create region around marker
                  local region_start = pos - (region_size-(region_size*region_weight))
                  local region_end = pos + (region_size+(region_size*region_weight))
                  reaper.AddProjectMarker2(0, true, region_start, region_end, "xAutoCreatedForGather: "..search_string, -1, 0x1000000)
                  found = true
                  Log((1+marker_index), ": Marker Created")
                end
              -- Msg((1+marker_index),": Outside Time Selection") -- not the right spot
            end

          marker_index = marker_index + 1
      end
    end

    if not found then
        reaper.ShowMessageBox("Marker not found.", "Error", 0)
    end
end



------------------------------------------------
--- USED FOR GATHER MARKER / REGIONS SCRIPTS ---
------------------------------------------------


function set_tr_with_top_item_in_ts_as_last_touched() -- needed to ensure pasted items end up on the same track
    --W: items selection changes!
    --N: UnselectAllItems()
    UnselectAllItems()
    reaper.Main_OnCommand(40717,0) -- select all items in current time selection
  
    local items = reaper.CountSelectedMediaItems()
  
    local min = 1000
  
    for i = 0, items-1 do
      local item = reaper.GetSelectedMediaItem(0,i)
      local tr = reaper.GetMediaItem_Track(item)
      local num = reaper.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER')
      min = math.min(min,num)
    end
  
    local tr = reaper.GetTrack(0,min-1)
    reaper.SetOnlyTrackSelected(tr,1)
    reaper.Main_OnCommand(40914,0) -- Track: Set first selected track as last touched track
end

function GatherRegionsContentsMatchingString(is_move,search_string,paste_pos)
  -- Save the current cursor position as the paste destination
  local paste_pos = reaper.GetCursorPosition()
  local init_paste_pos = paste_pos
  --[] add check to ensure the paste position is at the end of the project until I can make sure the moved markers don't get cycled

  --[] Only run  on current time selection
  -- SaveLoopTimesel() --init_start_timesel, init_end_timesel

  -- Get the number of regions/markers in the project
  local retval, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local num_markers_and_regions = num_markers + num_regions
  if num_regions == 0 then Log("No Regions") return end
  Log("num_markers_and_regions: ", num_markers_and_regions)
  CountMatchingRegions_j(search_string)

  local region_index_t={}

  -- Iterate over all markers and regions
  for i = 0, num_markers_and_regions+1 do
    Log("Loop: ", i)
      local retval, isrgn, pos, rgnend, name, indx, rgncolor = reaper.EnumProjectMarkers3(0,i)
      
      -- Check if it's a region and the name matches the search string
      if isrgn and string.find(name, search_string) and not ValueExistsInTable(region_index_t, indx) then
          -- Find region start, end, and length
          rgn_start = pos
          rgn_end = rgnend
          local rgn_length = rgn_end - rgn_start
          -- set time selection to region length
          reaper.GetSet_LoopTimeRange(true, false, rgn_start, rgn_end, false)
        Log("Region Found: ", indx .. " '" .. name .. "'")
        -- Msg("region start: ",rgn_start)
        -- Msg("region end: ",rgn_end)
          -- split items at time selection        
      reaper.Main_OnCommand(40717, 0) -- selects items in time selection
      reaper.Main_OnCommand(40061, 0) -- split items at time selection
      -- reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS2d4f5fa9faff65a9cae14178627cfed7f3e90aea"),0) -- splits items at region
          -- Iterate over all items and split if necessary
          if is_move then
            Log("Moving...")
            if reaper.GetToggleCommandState(41990) == 1 then -- if ripple is enabled for 1 track set it for all tracks            
              -- if ripple_per_track == 1 then
            Log("Ripple Editing is enabled per track, changing to all tracks.")
          -- reaper.SetToggleCommandState(0, 41991, 1) -- enable ripple editing
          reaper.Main_OnCommandEx(40311, 0, 0) -- enable ripple editing
          -- ripple_per_track = 0
          -- ripple_all_tracks = 1
        end
        if reaper.GetToggleCommandState(41991) == 1 then -- move if ripple_all_tracks is on -- FUNCTIONAL
            -- reaper.ShowConsoleMsg("Ripple Editing is enabled for all tracks.\n")
            -- moves region position to paste position
          -- reaper.SetProjectMarkerByIndex(0, i, true, rgn_start, paste_pos, indx, "", 0) -- move the back of the region
              set_tr_with_top_item_in_ts_as_last_touched()
              reaper.Main_OnCommand(40699, 0) -- cut items
              reaper.SetEditCurPos(init_paste_pos - rgn_length, false, false)
              reaper.Main_OnCommand(42398, 0) -- paste items
              -- reaper.SetProjectMarkerByIndex(0, i, true, paste_pos- rgn_length, paste_pos, indx, "", 0) -- move the front of the region
              -- alt create new region
              reaper.AddProjectMarker2(0, true, init_paste_pos - rgn_length, paste_pos, name, indx, rgncolor) -- add new region
              local num_markers_and_regions = num_markers_and_regions-1
        elseif reaper.GetToggleCommandState(41991) == 0 and reaper.GetToggleCommandState(41990) == 0 then -- move if ripple is off - FUNCTIONAL
            -- reaper.ShowConsoleMsg("Ripple Editing is turned off.\n")
              -- moves region position to paste position
          reaper.SetProjectMarkerByIndex(0, i, true, paste_pos, paste_pos + rgn_length, indx, "", 0)
              -- reaper.Main_OnCommand(40297s, 0) -- deselect all tracks
              -- reaper.Main_OnCommandEx(40311, 0, 0) -- enable ripple editing
              -- reaper.Main_OnCommandEx(40309, 0, 0) -- disable ripple editing
              -- SelectSelectedItemsTracks()
              set_tr_with_top_item_in_ts_as_last_touched()
              reaper.Main_OnCommand(40699, 0) -- cut items
              -- reaper.SetEditCurPos(paste_pos - rgn_length, false, false)
              reaper.Main_OnCommand(42398, 0) -- paste items
              -- paste_pos = paste_pos - rgn_length
              -- reaper.Main_OnCommand(41748, 0) -- insert time and paste items
              paste_pos = paste_pos + rgn_length

        -- marker manipulation ref
              -- reaper.AddProjectMarker(proj, isrgn, pos, rgnend, name, wantidx)     
              -- reaper.AddProjectMarker2(0, true, paste_pos, paste_pos + rgn_length, name, indx, rgncolor)
              -- reaper.SetProjectMarkerByIndex(ReaProject proj, integer markrgnidx, boolean isrgn, number pos, number rgnend, integer IDnumber, string name, integer color)
              -- reaper.SetProjectMarkerByIndex2(ReaProject proj, integer markrgnidx, boolean isrgn, number pos, number rgnend, integer IDnumber, string name, integer color, integer flags)
              -- retval, isrgn, pos, rgnend, stringname, markrgnindexnumber = reaper.EnumProjectMarkers(idx)
              -- retval, isrgn, pos, rgnend, stringname, markrgnindexnumber = reaper.EnumProjectMarkers2(ReaProject proj, integer idx)
              -- retval, isrgn, pos, rgnend, stringname, markrgnindexnumber, color = reaper.EnumProjectMarkers3(ReaProject proj, integer idx)

        else
          Log("Could Not Determine Ripple State.")
        end
        
      else
        Log("Copying...")
        -- reaper.SetProjectMarkerByIndex(0, i, true, paste_pos, paste_pos + rgn_length, indx, "", 0)
            -- reaper.Main_OnCommand(40297s, 0) -- deselect all tracks
            -- reaper.Main_OnCommandEx(40311, 0, 0) -- enable ripple editing
            -- reaper.Main_OnCommandEx(40309, 0, 0) -- disable ripple editing
            -- SelectSelectedItemsTracks()
            set_tr_with_top_item_in_ts_as_last_touched()
            reaper.Main_OnCommand(40698, 0) -- copy items
            -- reaper.SetEditCurPos(paste_pos - rgn_length, false, false)
            reaper.Main_OnCommand(42398, 0) -- paste items
          -- paste_pos = paste_pos - rgn_length
            -- reaper.Main_OnCommand(41748, 0) -- insert time and paste items
            reaper.AddProjectMarker2(0, true, paste_pos, paste_pos + rgn_length, name, indx, rgncolor) -- add new region
          paste_pos = paste_pos + rgn_length -- set subsequent paste position
          local num_markers_and_regions = num_markers_and_regions+1

            
        
        end
          -- Add a marker at the original location
          local marker_name = "xAuto Region " .. (is_move and "Moved" or "Copied")
          reaper.AddProjectMarker2(0, false, rgn_start, 0, marker_name, -1, 0x1000000)
          --add region index to table
          table.insert(region_index_t,indx)
        Log("Added Region Index: ", indx)
    end
  end
  Log("Gathered Regions: ", #region_index_t)
end





--|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--
-- ---------------- Collected from Others' --------------------- --
--|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--



------------------------------------------------
--- X-RAYM TEMPLATE ---
------------------------------------------------

-- The following functions may be passed as global if needed
-- ----- INITIAL SAVE AND RESTORE ====> 

-- ITEMS
-- UNSELECT ALL ITEMS
function UnselectAllItems()
  for  i = 0, reaper.CountMediaItems(0)-1 do
    reaper.SetMediaItemSelected(reaper.GetMediaItem(0, i), false)
  end
end

-- SAVE INITIAL SELECTED ITEMS
init_sel_items = {}
function SaveSelectedItems (table)
  for i = 0, reaper.CountSelectedMediaItems(0)-1 do
    table[i+1] = reaper.GetSelectedMediaItem(0, i)
  end
end

-- RESTORE INITIAL SELECTED ITEMS
function RestoreSelectedItems (table)
  UnselectAllItems() -- Unselect all items
  for _, item in ipairs(table) do
    reaper.SetMediaItemSelected(item, true)
  end
end

-- TRACKS
-- UNSELECT ALL TRACKS
function UnselectAllTracks()
  first_track = reaper.GetTrack(0, 0)
  reaper.SetOnlyTrackSelected(first_track)
  reaper.SetTrackSelected(first_track, false)
end

-- SAVE INITIAL TRACKS SELECTION
init_sel_tracks = {}
function SaveSelectedTracks (table)
  for i = 0, reaper.CountSelectedTracks(0)-1 do
    table[i+1] = reaper.GetSelectedTrack(0, i)
  end
end

-- RESTORE INITIAL TRACKS SELECTION
function RestoreSelectedTracks (table)
  UnselectAllTracks()
  for _, track in ipairs(table) do
    reaper.SetTrackSelected(track, true)
  end
end

-- LOOP AND TIME SELECTION
-- SAVE INITIAL LOOP AND TIME SELECTION
function SaveLoopTimesel()
  init_start_timesel, init_end_timesel = reaper.GetSet_LoopTimeRange(0, 0, 0, 0, 0)
  init_start_loop, init_end_loop = reaper.GetSet_LoopTimeRange(0, 1, 0, 0, 0)
end

-- RESTORE INITIAL LOOP AND TIME SELECTION
function RestoreLoopTimesel()
  reaper.GetSet_LoopTimeRange(1, 0, init_start_timesel, init_end_timesel, 0)
  reaper.GetSet_LoopTimeRange(1, 1, init_start_loop, init_end_loop, 0)
end

-- CURSOR
-- SAVE INITIAL CURSOR POS
function SaveCursorPos()
  init_cursor_pos = reaper.GetCursorPosition()
end

-- RESTORE INITIAL CURSOR POS
function RestoreCursorPos()
  reaper.SetEditCurPos(init_cursor_pos, false, false)
end

-- VIEW
-- SAVE INITIAL VIEW
function SaveView()
  start_time_view, end_time_view = reaper.BR_GetArrangeView(0)
end


-- RESTORE INITIAL VIEW
function RestoreView()
  reaper.BR_SetArrangeView(0, start_time_view, end_time_view)
end

-- <==== INITIAL SAVE AND RESTORE -----



--||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--
-- --------------- Pitch Detection (aubio) ---------------- --
--||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--
-- Requires the aubio command line tools, installed via X-Raym's ReaPack repo:
--   https://github.com/X-Raym/Aubio-for-REAPER-Reapack
-- We shell out to aubiopitch, which prints one "time_seconds midi_note" pair per
-- analysis frame to stdout (0.000000 for unvoiced frames).

-- Shared with X-Raym's "Define aubio path in ExtState" setup script so the two stay in sync.
AUBIO_EXT_STATE_SECTION = "XRaym_AubioPath"
AUBIO_EXT_STATE_KEY     = "aubio_exe_path"

local AUBIO_IS_WIN = (reaper.GetOS() or ""):match("Win") ~= nil
local AUBIO_SEP    = AUBIO_IS_WIN and "\\" or "/"

-- Default aubiopitch invocation settings. Override per script by passing an options
-- table to RunAubioPitch / GetItemPitch (see the USER CONFIG block of the sort scripts).
AUBIO_DEFAULT_OPTS = {
  method    = "yinfft",  -- -p  pitch algorithm: default|yinfft|yinfast|yin|mcomb|fcomb|schmitt
  bufsize   = 2048,      -- -B  FFT window size in frames
  hopsize   = 256,       -- -H  frames between analyses (smaller = finer time resolution)
  silence   = -60,       -- -s  silence threshold in dB; frames below this are not analysed
  tolerance = 0.3,       -- -l  yin/yinfft pitch tolerance, 0.1 to 0.7
  trim_pct  = 0.10,      -- fraction dropped from each end before taking the median
}

local NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}

-- Converts a floating point MIDI note number to a readable name.
-- 60 -> "C4", 60.14 -> "C4 (+14 cents)". MIDI 60 is C4, hence the -1 on the octave.
function MidiToNoteName(midi_float)
  if not midi_float then return "n/a" end
  local nearest = math.floor(midi_float + 0.5)
  local cents   = math.floor((midi_float - nearest) * 100 + 0.5)
  local octave  = math.floor(nearest / 12) - 1
  local note    = NOTE_NAMES[(nearest % 12) + 1] or "?"
  local result  = note .. octave
  if cents ~= 0 then
    result = result .. " (" .. (cents > 0 and "+" or "") .. cents .. " cents)"
  end
  return result
end

-- Median of a numeric array after discarding trim_pct (default 0.10) from each end.
-- The trim is what makes pitch tracking usable for sorting: it throws away the octave
-- errors and attack transients that would otherwise drag a plain mean off the real note.
function TrimmedMedian(values, trim_pct)
  local n = #values
  if n == 0 then return nil end

  local v = {}
  for i = 1, n do v[i] = values[i] end
  table.sort(v)

  local cut = math.floor(n * (trim_pct or 0.10))
  local lo, hi = 1 + cut, n - cut
  if lo > hi then lo, hi = 1, n end  -- too few values to trim; use them all

  local count = hi - lo + 1
  local mid   = lo + math.floor(count / 2)
  if count % 2 == 1 then
    return v[mid]
  else
    return (v[mid - 1] + v[mid]) / 2
  end
end

-- Looks for aubiopitch inside REAPER's UserPlugins folder, walking the version
-- subfolders so a ReaPack update doesn't invalidate a stored path.
-- Layout installed by ReaPack: UserPlugins/aubio/<version>/<platform>/aubiopitch[.exe]
local function ProbeAubioExePath()
  local root = reaper.GetResourcePath() .. AUBIO_SEP .. "UserPlugins" .. AUBIO_SEP .. "aubio"
  local platforms = {"win64", "win32", "macos", "linux"}
  local exe_names = {"aubiopitch.exe", "aubiopitch"}

  local i = 0
  while true do
    local version = reaper.EnumerateSubdirectories(root, i)
    if not version then break end
    for _, platform in ipairs(platforms) do
      for _, exe_name in ipairs(exe_names) do
        local candidate = root .. AUBIO_SEP .. version .. AUBIO_SEP .. platform .. AUBIO_SEP .. exe_name
        if reaper.file_exists(candidate) then return candidate end
      end
    end
    i = i + 1
  end
  return nil
end

-- Resolves the aubiopitch executable: stored ExtState first, then an auto-probe of
-- UserPlugins, then a file dialog as a last resort. Whatever resolves is persisted.
-- Pass prompt_if_missing = false to skip the dialog (returns nil instead).
function GetAubioExePath(prompt_if_missing)
  local saved = reaper.GetExtState(AUBIO_EXT_STATE_SECTION, AUBIO_EXT_STATE_KEY)
  if saved ~= "" and reaper.file_exists(saved) then
    Log("aubio exe (ExtState):", saved)
    return saved
  end

  local probed = ProbeAubioExePath()
  if probed then
    Log("aubio exe (auto-probed):", probed)
    reaper.SetExtState(AUBIO_EXT_STATE_SECTION, AUBIO_EXT_STATE_KEY, probed, true)
    return probed
  end

  if prompt_if_missing == false then return nil end

  reaper.ShowMessageBox(
    "aubio could not be found automatically.\n\n" ..
    "Install it via ReaPack (X-Raym's Aubio-for-REAPER repository), or locate\n" ..
    "aubiopitch yourself on the next screen. The path will be remembered.",
    "Locate aubiopitch", 0)

  local retval, path = reaper.GetUserFileNameForRead("", "Locate aubiopitch executable", "")
  if not retval or not path or path == "" then return nil end

  Log("aubio exe (user selected):", path)
  reaper.SetExtState(AUBIO_EXT_STATE_SECTION, AUBIO_EXT_STATE_KEY, path, true)
  return path
end

-- Pulls the "time midi" pairs out of whatever aubiopitch printed.
-- A data line is exactly two numbers; ExecProcess prefixes its output with a lone
-- exit code line, which fails that test and is skipped without special handling.
-- Stored as two parallel flat arrays rather than a table per frame: a ten minute
-- file at these settings is over 200,000 frames, where per-frame tables would cost
-- well over 10 MB against roughly 2 MB this way.
local function ParseAubioOutput(raw)
  local d = { n = 0, t = {}, midi = {} }
  if not raw then return d end
  local n, ts, ms = 0, d.t, d.midi
  for line in raw:gmatch("[^\r\n]+") do
    local t, midi = line:match("^%s*(%-?[%d%.]+[eE]?[%-%+]?%d*)%s+(%-?[%d%.]+[eE]?[%-%+]?%d*)%s*$")
    t, midi = tonumber(t), tonumber(midi)
    if t and midi and midi > 0 then
      n = n + 1
      ts[n], ms[n] = t, midi
    end
  end
  d.n = n
  return d
end

-- Analysis results for source files already examined during this script run.
-- aubiopitch always analyses the whole file, so every item cut from the same source
-- shares one result set and only differs in which frames it windows out. Keyed by
-- source path. This lives and dies with the Lua state REAPER creates per script run,
-- so there is nothing to invalidate: a re-rendered file is re-analysed next time.
local aubio_cache = {}

-- Runs aubiopitch over an audio file and returns its per-frame pitch detections.
-- Returns: detections, err (string or nil), raw_output (string).
-- detections is { n = frame_count, t = {seconds...}, midi = {note_numbers...} },
-- covering the whole source file -- see GetItemPitch for windowing it to one item.
function RunAubioPitch(source_path, opts)
  local o = opts or AUBIO_DEFAULT_OPTS

  local cached = aubio_cache[source_path]
  if cached then
    Log(string.format("aubio cache hit (%d frames): %s", cached.n, source_path))
    return cached, nil, ""
  end

  local exe = GetAubioExePath()
  if not exe then
    return nil, "No aubio executable available.", ""
  end
  if not reaper.file_exists(source_path) then
    return nil, "Source file not found on disk:\n" .. tostring(source_path), ""
  end

  local args = string.format('-i "%s" -u midi -p %s -B %s -H %s -s %s -l %s',
    source_path,
    o.method    or AUBIO_DEFAULT_OPTS.method,
    o.bufsize   or AUBIO_DEFAULT_OPTS.bufsize,
    o.hopsize   or AUBIO_DEFAULT_OPTS.hopsize,
    o.silence   or AUBIO_DEFAULT_OPTS.silence,
    o.tolerance or AUBIO_DEFAULT_OPTS.tolerance)

  local cmd = string.format('"%s" %s', exe, args)
  Log("aubio command:", cmd)

  -- ExecProcess timeout semantics: 0 = run to completion and capture output.
  -- -1 means "no wait, then terminate", which returns Windows exit code 259
  -- (STILL_ACTIVE) and no data at all -- a very easy trap to fall into.
  local raw = reaper.ExecProcess(cmd, 0)
  local detections = ParseAubioOutput(raw)

  -- Fallback: some REAPER/OS combinations return only the exit code from ExecProcess.
  -- Redirect stdout to a temp file through the shell and read it back ourselves.
  if detections.n == 0 then
    Log("aubio direct call returned no data lines. Raw output:", tostring(raw))
    Log("Retrying via temp file redirection...")

    local temp_path = reaper.GetResourcePath() .. AUBIO_SEP .. "jrope_aubio_out.txt"
    local shell_cmd
    if AUBIO_IS_WIN then
      -- cmd.exe strips the outermost quote pair, so the whole line is wrapped again.
      shell_cmd = string.format('cmd.exe /C ""%s" %s > "%s" 2>&1"', exe, args, temp_path)
    else
      shell_cmd = string.format('/bin/sh -c \'"%s" %s > "%s" 2>&1\'', exe, args, temp_path)
    end
    Log("aubio fallback command:", shell_cmd)
    reaper.ExecProcess(shell_cmd, 0)

    local file = io.open(temp_path, "r")
    if file then
      raw = file:read("*all")
      file:close()
      os.remove(temp_path)
      detections = ParseAubioOutput(raw)
    else
      return nil, "aubio produced no output and the fallback temp file could not be read.", tostring(raw)
    end
  end

  if detections.n == 0 then
    return nil, "aubio returned no pitch data. Raw output:\n" .. tostring(raw), tostring(raw)
  end

  aubio_cache[source_path] = detections
  Log(string.format("aubio analysed %d voiced frames, cached for this run: %s",
    detections.n, source_path))

  return detections, nil, raw
end

-- Detects the representative pitch of a single media item, in MIDI note numbers.
-- aubio analyses the whole source file, but an item is usually a trimmed slice of it,
-- so the detections are windowed to the part of the source the item actually plays.
-- The take's own pitch shift (D_PITCH) is added, so a transposed item sorts where it sounds.
-- Returns: midi_float, frame_count -- or nil, 0 when nothing pitched was found.
function GetItemPitch(item, opts)
  local o = opts or AUBIO_DEFAULT_OPTS

  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return nil, 0 end

  local source = reaper.GetMediaItemTake_Source(take)
  if not source then return nil, 0 end

  local source_path = reaper.GetMediaSourceFileName(source, "")
  if not source_path or source_path == "" then return nil, 0 end

  local detections, err = RunAubioPitch(source_path, o)
  if err then
    Log("aubio error for", source_path, "->", err)
    return nil, 0
  end

  -- Window of the source file this item plays, in source seconds.
  local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  if rate <= 0 then rate = 1 end
  local win_start, win_end = offs, offs + len * rate

  local pitches, count = {}, 0
  local ts, ms = detections.t, detections.midi
  for i = 1, detections.n do
    local t = ts[i]
    if t >= win_start and t <= win_end then
      count = count + 1
      pitches[count] = ms[i]
    end
  end

  Log(string.format("  window %.3f-%.3f s of source, %d voiced frames (of %d in file)",
    win_start, win_end, count, detections.n))

  if #pitches == 0 then return nil, 0 end

  local median = TrimmedMedian(pitches, o.trim_pct or AUBIO_DEFAULT_OPTS.trim_pct)
  if not median then return nil, 0 end

  local take_pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")
  if take_pitch ~= 0 then
    Log(string.format("  applying take pitch offset of %+.2f semitones", take_pitch))
    median = median + take_pitch
  end

  return median, #pitches
end

-- Analyses an array of media items and returns them as entries sorted by detected pitch.
-- Entries: { item, position, length, pitch (nil if undetected), frames, name }
-- Items with no detectable pitch always sort to the end, ordered by original position,
-- regardless of the ascending flag -- they have no pitch to reverse.
-- Returns: entries, pitched_count.
function AnalyzeAndSortItemsByPitch(items, opts, ascending)
  if ascending == nil then ascending = true end

  local entries, pitched_count = {}, 0

  for _, item in ipairs(items) do
    local name = "(no source)"
    local take = reaper.GetActiveTake(item)
    if take then
      local source = reaper.GetMediaItemTake_Source(take)
      if source then
        local path = reaper.GetMediaSourceFileName(source, "")
        name = path:match("([^/\\]+)$") or path
      end
    end
    Log("Analysing:", name)

    local pitch, frames = GetItemPitch(item, opts)
    if pitch then
      pitched_count = pitched_count + 1
      Log(string.format("  -> %s (MIDI %.2f) from %d frames", MidiToNoteName(pitch), pitch, frames))
    else
      Log("  -> no pitch detected")
    end

    entries[#entries + 1] = {
      item     = item,
      position = reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
      length   = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
      pitch    = pitch,
      frames   = frames,
      name     = name,
    }
  end

  table.sort(entries, function(a, b)
    if a.pitch and b.pitch then
      if a.pitch == b.pitch then return a.position < b.position end
      if ascending then return a.pitch < b.pitch else return a.pitch > b.pitch end
    end
    if a.pitch then return true end   -- pitched items always come before unpitched ones
    if b.pitch then return false end
    return a.position < b.position
  end)

  return entries, pitched_count
end


