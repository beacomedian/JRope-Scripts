-- @description Toggle visibility of empty non-folder tracks (selected only)
-- @version 1.0
-- @author cfillion (modified by Jesse Rope)
-- * Changelog:
--  # Version 1.0 created this version to only run on selected tracks


local UNDO_STATE_TRACKCFG = 1
local script_name = ({reaper.get_action_context()})[2]:match("([^/\\_]+).lua$")
local empty_tracks, setVisible = {}, 0
local match = script_name:match("matching '([^']+)'")

-- CHANGED: CountSelectedTracks(0) instead of CountTracks()-1
-- CountSelectedTracks returns how many tracks the user has selected.
-- We subtract 1 because the loop below counts from 0.
for ti = 0, reaper.CountSelectedTracks(0) - 1 do

  -- CHANGED: GetSelectedTrack(0, ti) instead of GetTrack(0, ti)
  -- GetSelectedTrack retrieves only from the pool of selected tracks,
  -- so the index ti now walks only selected tracks, not all tracks.
  local track = reaper.GetSelectedTrack(0, ti)

  local fx_count   = reaper.TrackFX_GetCount(track)
  local item_count = reaper.CountTrackMediaItems(track)
  local env_count  = reaper.CountTrackEnvelopes(track)
  local depth      = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
  local is_armed   = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")
  local name       = ({reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)})[2]
  local matches    = (function()
    if not match or name:find(match) then
      return 0
    else
      return 1
    end
  end)()

  if fx_count + item_count + env_count + math.max(depth, 0) + is_armed + matches == 0 then
    local mcpVis = reaper.GetMediaTrackInfo_Value(track, 'B_SHOWINMIXER')
    local tcpVis = reaper.GetMediaTrackInfo_Value(track, 'B_SHOWINTCP') -- BUGFIX (see below)

    if mcpVis + tcpVis == 0 then
      setVisible = 1
    end

    table.insert(empty_tracks, track)
  end
end

if #empty_tracks == 0 then return reaper.defer(function() end) end

reaper.Undo_BeginBlock()

for i, track in ipairs(empty_tracks) do
  reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINMIXER', setVisible)
  reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINTCP', setVisible)
end

reaper.Undo_EndBlock(script_name, UNDO_STATE_TRACKCFG)

reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
