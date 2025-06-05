--[[
 * Name: Create Region from selected items and mark tracks in render matrix
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.0
 * Version: 1.1
 * Provides:
  [main] . > 
 * Link: https://www.jesserope.com
 * noindex
 * About:
  # Modification of Mordi's "Create single region from selected items (get name and color from folder track) and mark it in region render matrix"
  # Creates one region spanning all selected items and adds each unique track to the region render matrix 

 * Changelog:
  # v1.0 - Initial Release

]]

-- @noindex

SCRIPT_NAME = "Create single region from selected items (get name and color from folder track) and mark all item tracks in region render matrix"

reaper.ClearConsole()

function Msg(variable)
  reaper.ShowConsoleMsg(tostring(variable).."\n")
end

selectedItemNum = reaper.CountSelectedMediaItems()

-- Abort if no items are selected
if selectedItemNum == 0 then
  return
end

-- Begin undo-block
reaper.Undo_BeginBlock2(0)

-- Get total span of items and collect unique tracks
regionPos = 0
regionEnd = 0
topTrackIndex = 0
itemTracks = {} -- Table to store unique tracks containing selected items

for i = 0, selectedItemNum-1 do
  -- Get item
  item = reaper.GetSelectedMediaItem(0, i)
  
  -- Get item position
  itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  
  -- Get item length
  itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  
  -- Get track from item
  itemTrack = reaper.GetMediaItem_Track(item)
  
  -- Get track index from item track
  itemTrackIndex = reaper.GetMediaTrackInfo_Value(itemTrack, "IP_TRACKNUMBER")
  
  -- Add track to our collection (avoiding duplicates)
  local trackExists = false
  for j = 1, #itemTracks do
    if itemTracks[j] == itemTrack then
      trackExists = true
      break
    end
  end
  if not trackExists then
    itemTracks[#itemTracks + 1] = itemTrack
  end
  
  -- Use first item as initial start and end
  if i == 0 then
    regionPos = itemPos
    regionEnd = itemPos + itemLength
    topTrackIndex = itemTrackIndex
  end
  
  -- Check start
  if regionPos > itemPos then
    regionPos = itemPos
  end
  
  -- Check end
  if regionEnd < itemPos + itemLength then
    regionEnd = itemPos + itemLength
  end
  
  -- Check track index
  if itemTrackIndex < topTrackIndex then
    topTrackIndex = itemTrackIndex
  end
  
end

-- Get track from track index (topmost track for naming purposes)
track = reaper.GetTrack(0, topTrackIndex-1)

-- Init parent variable
parent = track

-- Loop: Get topmost parent
repeat

  -- Get potential parent
  potParent = reaper.GetParentTrack(parent)

  -- Check if potential parent exists
  if potParent == nil then
    break;
  else
    -- Check if potential parent's name starts with "#FX"
    retval, name = reaper.GetTrackName(potParent, "")
    if string.sub(name, 1, 3) == "#FX" then
      break
    end
  end

  parent = potParent
  
until(reaper.GetParentTrack(parent) == nil)

-- Get color of track
color = reaper.GetTrackColor(parent)

-- Get name of track
retval, name = reaper.GetTrackName(parent, "")

-- Create region and store index
rgnIndex = reaper.AddProjectMarker2(0, true, regionPos, regionEnd, name, -1, color)

-- JROPE MODIFICATION - Add all tracks containing selected items to region render matrix
for i = 1, #itemTracks do
  reaper.SetRegionRenderMatrix(0, rgnIndex, itemTracks[i], 1)
end

-- End undo-block
reaper.Undo_EndBlock2(0,SCRIPT_NAME,-1)
