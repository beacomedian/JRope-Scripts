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

-- Prints to the REAPER console only when ENABLE_DEBUG_LOG is true above.
local function Log(msg)
  if ENABLE_DEBUG_LOG then
    r.ShowConsoleMsg(tostring(msg) .. "\n")
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

function CheckIfItemsSelected()
  if sel_item_count_i == 0 then 
    Msg("Select Items: ","") 
    reaper.ShowMessageBox("Select Items!", "", 0)
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
          -- reaper.ShowConsoleMsg("Value " .. tostring(value) .. " already exists in the tbl.\n")
          Msg("Value exists: ",value)
            return true
        else
          -- reaper.ShowConsoleMsg("Value " .. tostring(value) .. " does not exist in the tbl. \n")
          Msg("Value doesn't exist: ",value)
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
  -- if num_regions == 0 then Msg("No Regions","") return end
  Msg("num_markers_and_regions: ",num_markers_and_regions)
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














--|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--
-- ---------------- Shared for Script Groups --------------------- --
--|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--


-------------------------------------------------------
--- USED FOR RIPPLE DELETE MARKER / REGIONS SCRIPTS ---
-------------------------------------------------------

function CountMatchingRegions_j( ... )
  -- local _, _, num_regions = reaper.CountProjectMarkers(0)
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  Msg("Input String: '",... .. "'")  
  Msg("Total Markers:",num_markers)
  Msg("Total Regions:",num_regions) 
  local num_markers_and_regions = num_markers + num_regions

  local count = 0

  -- for i = 0, num_regions - 1 do
  for i = 0, num_markers_and_regions - 1 do
  -- for i = 200, 0, - 1 do -- forcing high loop
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
    
    -- if isrgn and name:find("^x ") then
    -- if isrgn and name:find("^"..search_string) then -- trying out user input search string
    if isrgn and name:find(...) then -- trying out user input search string
      count = count + 1
    end
  end
  
  -- Print the number of regions found with "x " prefix
  reaper.ShowConsoleMsg(count .. " regions matching '".. ... .."'\n")
  return count
end

function CountMatchingMarkers_j( ... )
  -- local _, _, num_regions = reaper.CountProjectMarkers(0)
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  Msg("Total Markers:",num_markers)
  Msg("Total Regions:",num_regions)   
  local num_markers_and_regions = num_markers + num_regions

  local count = 0

  -- for i = 0, num_regions - 1 do
  for i = 0, num_markers_and_regions - 1 do
  -- for i = 200, 0, - 1 do -- forcing high loop
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
    
    -- if isrgn and name:find("^x ") then
    -- if isrgn and name:find("^"..search_string) then -- trying out user input search string
    if not isrgn and name:find(...) then -- trying out user input search string
      count = count + 1
    end
  end
  -- Print the number of regions found with "x " prefix
  reaper.ShowConsoleMsg(count .. " markers matching '".. ... .."'\n")
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
                  Msg("Deleting Region: ",i)
                  reaper.Main_OnCommandEx(40717, 0, 0) -- select all items in time selection
                  reaper.Main_OnCommand(reaper.NamedCommandLookup("_XENAKIOS_TSADEL"), 0) -- adaptive delete time selection
                  reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_CROSSFADE"), 0) -- crossfade adjacent selected items
                  reaper.AddProjectMarker2(0, false, pos, 0, "xAutoCut", -1, 0x1000000) -- add marker at saved pos
                end
            end
        end
    else reaper.ShowConsoleMsg("No X regions found.\n")
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
        Msg("Expected Loop Times: ",num_markers_and_regions)

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
            if isrgn == true then Msg((1+marker_index),": Skipping region") end
            if not isrgn and not name:find(...) then Msg((1+marker_index),": Skipping !match marker") end

            if not isrgn and name:find(...) then -- and not name:find("Auto")
                -- work only in time selection if there is one
                if pos >= init_start_timesel and pos <= init_end_timesel or init_start_timesel == init_end_timesel then
                  -- Create region around marker
                  local region_start = pos - (region_size-(region_size*region_weight))
                  local region_end = pos + (region_size+(region_size*region_weight))
                  reaper.AddProjectMarker2(0, true, region_start, region_end, "xAutoCreatedForGather: "..search_string, -1, 0x1000000)
                  found = true
                  Msg((1+marker_index),": Marker Created")
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


function UnselectAllItems()
  for  i = 0, reaper.CountMediaItems()-1 do
    reaper.SetMediaItemSelected(reaper.GetMediaItem(0, i), 0)
  end
end

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
  if num_regions == 0 then Msg("No Regions","") return end
  Msg("num_markers_and_regions: ",num_markers_and_regions)
  CountMatchingRegions_j(search_string)

  local region_index_t={}

  -- Iterate over all markers and regions
  for i = 0, num_markers_and_regions+1 do
    Msg("Loop: ",i)
      local retval, isrgn, pos, rgnend, name, indx, rgncolor = reaper.EnumProjectMarkers3(0,i)
      
      -- Check if it's a region and the name matches the search string
      if isrgn and string.find(name, search_string) and not ValueExistsInTable(region_index_t, indx) then
          -- Find region start, end, and length
          rgn_start = pos
          rgn_end = rgnend
          local rgn_length = rgn_end - rgn_start
          -- set time selection to region length
          reaper.GetSet_LoopTimeRange(true, false, rgn_start, rgn_end, false)
        Msg("Region Found: ",indx.." '"..name.."'")
        -- Msg("region start: ",rgn_start)
        -- Msg("region end: ",rgn_end)
          -- split items at time selection        
      reaper.Main_OnCommand(40717, 0) -- selects items in time selection
      reaper.Main_OnCommand(40061, 0) -- split items at time selection
      -- reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS2d4f5fa9faff65a9cae14178627cfed7f3e90aea"),0) -- splits items at region
          -- Iterate over all items and split if necessary
          if is_move then
            reaper.ShowConsoleMsg("Moving...\n")
            if reaper.GetToggleCommandState(41990) == 1 then -- if ripple is enabled for 1 track set it for all tracks            
              -- if ripple_per_track == 1 then
            reaper.ShowConsoleMsg("Ripple Editing is enabled per track, changing to all tracks.\n")
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
          reaper.ShowConsoleMsg("Could Not Determine Ripple State.\n")
        end
        
      else
        reaper.ShowConsoleMsg("Copying...\n")
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
        Msg("Added Region Index: ",indx)  
    end 
  end
  Msg("Gathered Regions: ",#region_index_t)
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
local function SaveSelectedItems (table)
  for i = 0, reaper.CountSelectedMediaItems(0)-1 do
    table[i+1] = reaper.GetSelectedMediaItem(0, i)
  end
end

-- RESTORE INITIAL SELECTED ITEMS
local function RestoreSelectedItems (table)
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
local function SaveSelectedTracks (table)
  for i = 0, reaper.CountSelectedTracks(0)-1 do
    table[i+1] = reaper.GetSelectedTrack(0, i)
  end
end

-- RESTORE INITIAL TRACKS SELECTION
local function RestoreSelectedTracks (table)
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


