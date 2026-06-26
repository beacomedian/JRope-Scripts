--[[
 * Name: Copy Time Selection Length In Milliseconds
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
   [main] . >
 * Link: https://www.jesserope.com
 * About:
   # Shows the exact length of the current time selection in milliseconds and
   # copies that value to the clipboard (requires the SWS extension for clipboard).
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


function main()
  -- Read the current time selection (start/end in seconds)
  local time_start, time_end = reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)
  Log("time_start:", time_start, "time_end:", time_end)

  if time_end <= time_start then
    reaper.ShowMessageBox("Make a time selection.", "Error", 0)
    return
  end

  -- Convert the length from seconds to milliseconds
  local length_ms = (time_end - time_start) * 1000
  Log("length_ms:", length_ms)

  -- Format the message: exact value plus a rounded-to-3-decimals readout
  local message = string.format("Time selection length:\n%.3f ms\n(%.6f ms exact)", length_ms, length_ms)

  -- Copy to clipboard if SWS' CF_SetClipboard is available
  if reaper.APIExists("CF_SetClipboard") then
    reaper.CF_SetClipboard(string.format("%d", math.floor(length_ms + 0.5)))
    message = message .. "\n\nCopied to clipboard."
  else
    message = message .. "\n\n(Install the SWS extension to enable clipboard copy.)"
  end

  reaper.ShowMessageBox(message, "Time Selection Length", 0)
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
