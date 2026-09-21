--[[
 * Name: Solo In Place Exclusive Selected Tracks
 * Author: Jesse Rope
 * AI: Claude Opus 5
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
   [main] . >
 * Link: https://www.jesserope.com
 * About:
   # Solo-in-place the selected tracks and unsolo every other track.
   # Faster rewrite of X-Raym's "Solo in place exclusive selected tracks":
   # only tracks whose solo state actually changes are written, and the
   # undo point stores track config only instead of the full project state.
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


-- Read-only pass: collect only the tracks whose solo state must change.
-- Writing I_SOLO triggers a solo/routing recalc, so skipping no-op writes is the main speedup.
local function GetSoloChanges()
  local changes = {}
  local track_count = r.CountTracks(proj)
  for i = 0, track_count - 1 do
    local track = r.GetTrack(proj, i)
    local want = r.IsTrackSelected(track) and SOLO_IN_PLACE or SOLO_OFF
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

local changes = GetSoloChanges()

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
