--[[
 * Name: Move Item FX from Selected Items to their Track
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.1
 * Provides:
   [main] . >
 * Link: https://www.jesserope.com
 * About:
   # Moves the take FX from each selected item up onto the item's track.
     When several selected items on the same track carry the same FX with
     identical settings, only one instance is moved to the track and the
     duplicate item FX are discarded. The first instance of each unique FX
     (by name + parameter values) is appended to the track in order; the rest
     are deleted. Complementary to
     "Move Track FX from Parent Track to Selected Items".
    # While an attempt is made to deduce unique FX settings, the logic is only
      examining the FX parameters, not the entire hunk. Some FX with complex
      data structures may mistakenly be labeled as duplicates.
 * Changelog:
  # Initial Release
  # v1.1 - Deduplicate: only FX with unique settings are moved to the track,
  #        duplicate item FX are discarded.
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
local r = reaper
local proj = 0

---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Load my common functions
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")


-- Build a signature that identifies an FX by what it *is* and how it is *set*,
-- so two instances of the same plugin with identical settings collide. We use
-- the FX name plus every parameter value (normalized 0..1), rounded to tame
-- floating-point noise from the param read-back.
local PARAM_PRECISION = 1e6  -- ~6 significant digits is plenty to tell presets apart
local function take_fx_signature(take, fx)
  local _, name = reaper.TakeFX_GetFXName(take, fx, "")
  local parts = { name }
  local num_params = reaper.TakeFX_GetNumParams(take, fx)
  for p = 0, num_params - 1 do
    local val = reaper.TakeFX_GetParam(take, fx, p)
    parts[#parts + 1] = math.floor(val * PARAM_PRECISION + 0.5)
  end
  return table.concat(parts, "|")
end


-- Process every take FX on `item`. The first time a given signature is seen
-- (tracked in `seen`), the FX is moved up onto `track`; every later duplicate is
-- deleted from the take. Always operate on index 0 because both a move and a
-- delete remove that FX, sliding the next one down to 0 — and appending each
-- kept FX to the track's current end preserves order.
local function consolidate_item_fx(item, track, seen)
  local take = reaper.GetActiveTake(item)
  if not take then return 0, 0 end  -- empty / MIDI-less text items have no take

  local moved, discarded = 0, 0
  while reaper.TakeFX_GetCount(take) > 0 do
    local sig = take_fx_signature(take, 0)
    if seen[sig] then
      reaper.TakeFX_Delete(take, 0)  -- duplicate settings: discard
      discarded = discarded + 1
    else
      seen[sig] = true
      local dest_fx = reaper.TrackFX_GetCount(track)  -- append at end
      reaper.TakeFX_CopyToTrack(take, 0, track, dest_fx, true)  -- true = move
      moved = moved + 1
    end
  end
  return moved, discarded
end


function main()
  local item_count = reaper.CountSelectedMediaItems(proj)
  Log("Selected items:", item_count)
  if item_count == 0 then return end

  -- Dedup is scoped per track: each track keeps its own set of seen FX
  -- signatures so a unique FX lands on every track it appears on, while
  -- duplicates among that track's items collapse to a single instance.
  local seen_by_track = {}

  local total_moved, total_discarded = 0, 0
  for item in EnumSelectedItems() do
    local track = reaper.GetMediaItemTrack(item)
    local seen = seen_by_track[track]
    if not seen then
      seen = {}
      seen_by_track[track] = seen
    end
    local moved, discarded = consolidate_item_fx(item, track, seen)
    total_moved = total_moved + moved
    total_discarded = total_discarded + discarded
    Log("Item on track", reaper.GetTrackGUID(track), "- moved", moved, "discarded", discarded)
  end

  Log("Total FX moved to tracks:", total_moved, "| duplicates discarded:", total_discarded)
end -- main


---------------------------------
-------------- MAIN -------------
---------------------------------

-- Begin the undo block
reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

main()

reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, -1)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
