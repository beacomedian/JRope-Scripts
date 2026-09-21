--[[
 * Name: Pro Tools X-Or Solo
 * Author: Jesse Rope
 * AI: Claude Opus 5
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.8
 * Version: 1.0
 * Provides:
   [main] . >
 * Link: https://www.jesserope.com
 * About:
   # Pro Tools style X-OR (exclusive) solo toggle.
   # If all selected tracks are soloed, unsolo all tracks.
   # Otherwise, solo-in-place the selected tracks and unsolo every other track
 * Changelog:
  # Initial Release
 * To Do:
  #

]]



---------------------------------
---------- USER CONFIG ----------
---------------------------------

-- Must be global (no `local`) so the shared Log() in Common Functions can read it.
ENABLE_DEBUG_LOG = false  -- set to true to print debug output to the REAPER console


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
local time_init = reaper.time_precise()
local r = reaper
local proj = 0

local SOLO_OFF = 0
local SOLO_IN_PLACE = 2

---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Load my common functions
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")


-- True if every selected track has some solo state (solo, solo-in-place, etc.).
-- No selection also returns true, so the script falls through to "unsolo all".
local function AreAllSelectedTracksSoloed()
  for i = 0, r.CountSelectedTracks(proj) - 1 do
    if r.GetMediaTrackInfo_Value(r.GetSelectedTrack(proj, i), "I_SOLO") == SOLO_OFF then
      return false
    end
  end
  return true
end


-- Read-only pass: collect only the tracks whose solo state must change.
-- Writing I_SOLO triggers a solo/routing recalc, so skipping no-op writes is the main speedup.
-- unsolo_all: true = every track goes to SOLO_OFF; false = selected -> SOLO_IN_PLACE, others -> SOLO_OFF
local function GetSoloChanges(unsolo_all)
  local changes = {}
  local track_count = r.CountTracks(proj)
  for i = 0, track_count - 1 do
    local track = r.GetTrack(proj, i)
    local want = (not unsolo_all and r.IsTrackSelected(track)) and SOLO_IN_PLACE or SOLO_OFF
    if r.GetMediaTrackInfo_Value(track, "I_SOLO") ~= want then
      changes[#changes + 1] = {track = track, solo = want}
    end
  end
  Log("Tracks:", track_count, "| Selected:", r.CountSelectedTracks(proj), "| To change:", #changes)
  return changes
end


function main(changes)
  for _, c in ipairs(changes) do
    r.SetMediaTrackInfo_Value(c.track, "I_SOLO", c.solo)
  end
end -- main


---------------------------------
-------------- MAIN -------------
---------------------------------

local unsolo_all = AreAllSelectedTracksSoloed()
Log("Mode:", unsolo_all and "unsolo all" or "solo in place exclusive")

local changes = GetSoloChanges(unsolo_all)

-- Nothing to do: skip the undo point entirely
if #changes == 0 then
  Log("No solo changes needed")
  return
end

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

main(changes)

-- 1 = UNDO_STATE_TRACKCFG: solo is track config, so avoid snapshotting the whole project (-1)
reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, 1)
reaper.PreventUIRefresh(-1)

Log(string.format("Done in %.4f s", reaper.time_precise() - time_init))
