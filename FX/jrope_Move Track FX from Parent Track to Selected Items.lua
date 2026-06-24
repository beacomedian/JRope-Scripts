--[[
 * Name: Move Track FX from Parent Track to Selected Items
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
 	[main] . >
 * Link: https://www.jesserope.com
 * About:
 	# Moves the FX from each selected item's track down onto the item itself.
 	  The track's FX chain is copied (in order) onto every selected item that
 	  lives on that track, then removed from the track. If several selected
 	  items share a track, they each receive a copy before the track is cleared.
 	  Complementary to "Move Item FX from Selected Items to their Track".
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


-- Copy every track FX on `track` onto `item`'s active take, appended to the end
-- of the take's existing FX chain and preserving the track's FX order.
local function copy_track_fx_to_item(track, item)
	local take = reaper.GetActiveTake(item)
	if not take then return 0 end  -- empty / text items have no take to host FX

	local fx_count = reaper.TrackFX_GetCount(track)
	local copied = 0
	for src_fx = 0, fx_count - 1 do
		local dest_fx = reaper.TakeFX_GetCount(take)  -- append at end
		reaper.TrackFX_CopyToTake(track, src_fx, take, dest_fx, false)  -- false = copy
		copied = copied + 1
	end
	return copied
end


-- Remove all FX from a track. Always deletes index 0 because each delete slides
-- the remaining FX down by one.
local function clear_track_fx(track)
	while reaper.TrackFX_GetCount(track) > 0 do
		reaper.TrackFX_Delete(track, 0)
	end
end


function main()
	local item_count = reaper.CountSelectedMediaItems(proj)
	Log("Selected items:", item_count)
	if item_count == 0 then return end

	-- Group selected items by their track so we copy a track's FX onto every
	-- selected item on it before clearing that track exactly once.
	local order = {}            -- preserves track encounter order
	local items_by_track = {}   -- track -> { item, item, ... }
	for item in EnumSelectedItems() do
		local track = reaper.GetMediaItemTrack(item)
		if not items_by_track[track] then
			items_by_track[track] = {}
			order[#order + 1] = track
		end
		table.insert(items_by_track[track], item)
	end

	local total_copied = 0
	for _, track in ipairs(order) do
		local fx_count = reaper.TrackFX_GetCount(track)
		if fx_count > 0 then
			for _, item in ipairs(items_by_track[track]) do
				local copied = copy_track_fx_to_item(track, item)
				total_copied = total_copied + copied
				Log("Copied", copied, "track FX onto item")
			end
			clear_track_fx(track)  -- complete the "move" once all items have copies
			Log("Cleared", fx_count, "FX from track", reaper.GetTrackGUID(track))
		else
			Log("Track has no FX, skipping:", reaper.GetTrackGUID(track))
		end
	end

	Log("Total FX instances placed on items:", total_copied)
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
