--[[
 * Name: Detect and Remove Duplicate Items
 * Author: Jesse Rope
 * AI: Claude Opus 4.8 Medium
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 0.1
 * Provides:
 	[main] . >
 * Link: https://www.jesserope.com
 * About:
 	# Detect and Remove Duplicate Items
 	Scans the project for duplicate media items and offers to remove the extra copies.
 	A duplicate is any item that shares the same source file, the same duration, AND the
 	same take start offset as another item -- i.e. it references the exact same region of
 	the same file. Useful for cleaning up source content accidentally imported multiple
 	times during a design session.

 	The script reports how many duplicates were found and asks for permission before
 	removing anything. When removing, it keeps the "first" copy in each group -- the
 	item on the lowest-numbered track, and earliest in the timeline on ties -- and
 	deletes the rest.

 	Scan scope can be narrowed with the current project selections, which combine (AND):
 	a time selection limits the scan to items overlapping it, selected items limit the
 	scan to those items, and selected tracks limit it to items on those tracks. Any
 	active filters are reported in the confirmation dialog.
 * Changelog:
	# Initial WIP
 * To Do:
	# Add tools to help choose which duplicate to keep (e.g. by take volume, color, folder)

]]



---------------------------------
---------- USER CONFIG ----------
---------------------------------

-- Must be global (no `local`) so the shared Log() in Common Functions can read it.
ENABLE_DEBUG_LOG = false  -- set to true to print debug output to the REAPER console

-- Rounding (in seconds) used when comparing item durations, to avoid float precision
-- mismatches between otherwise-identical items.
local LENGTH_TOLERANCE = 0.0001


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


-- Returns the underlying source filename for an item's active take, following through
-- SECTION/reverse wrappers to the parent file. Returns nil if the item has no take or
-- no file-backed source (e.g. empty or MIDI items).
local function GetItemSourceFile(item)
	local take = r.GetActiveTake(item)
	if not take then return nil end
	if r.TakeIsMIDI(take) then return nil end

	local source = r.GetMediaItemTake_Source(take)
	if not source then return nil end

	-- Follow section/reverse wrappers down to the real parent source.
	local parent = r.GetMediaSourceParent(source)
	while parent do
		source = parent
		parent = r.GetMediaSourceParent(source)
	end

	local filename = r.GetMediaSourceFileName(source, "")
	if filename == "" then return nil end
	return filename
end


-- Inspects the current project selections and returns a filters table describing which
-- scope filters are active. Filters combine with AND: an item must satisfy every active
-- filter to be scanned. `descriptions` lists human-readable labels for the dialog.
local function GetActiveFilters()
	local filters = { descriptions = {} }

	-- Time selection: active when the loop/time range has a non-zero span.
	local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
	if ts_end > ts_start then
		filters.time_start = ts_start
		filters.time_end = ts_end
		table.insert(filters.descriptions, "within the time selection")
	end

	-- Selected items.
	if r.CountSelectedMediaItems(proj) > 0 then
		filters.selected_items = true
		table.insert(filters.descriptions, "among selected items")
	end

	-- Selected tracks.
	if r.CountSelectedTracks(proj) > 0 then
		filters.selected_tracks = true
		table.insert(filters.descriptions, "on selected tracks")
	end

	return filters
end


-- Returns true if the item passes every active scope filter.
local function ItemPassesFilters(item, filters)
	if filters.time_start then
		local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
		local item_end = pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")
		-- Overlap test: any part of the item falls inside the time selection.
		if item_end <= filters.time_start or pos >= filters.time_end then
			return false
		end
	end

	if filters.selected_items and not r.IsMediaItemSelected(item) then
		return false
	end

	if filters.selected_tracks then
		local track = r.GetMediaItemTrack(item)
		if not (track and r.IsTrackSelected(track)) then
			return false
		end
	end

	return true
end


-- Builds a stable sort key so we can pick the "first" item in a duplicate group:
-- lowest track number first, then earliest timeline position.
local function CompareItemsFirst(a, b)
	if a.track_num ~= b.track_num then
		return a.track_num < b.track_num
	end
	if a.position ~= b.position then
		return a.position < b.position
	end
	-- Final tiebreak keeps ordering deterministic.
	return tostring(a.item) < tostring(b.item)
end


function main()
	local item_count = r.CountMediaItems(proj)
	Log("Scanning", item_count, "items")

	if item_count == 0 then
		r.ShowMessageBox("There are no items in the project to scan.", SCRIPT_NAME, 0)
		return
	end

	local filters = GetActiveFilters()
	if #filters.descriptions > 0 then
		Log("Active filters:", table.concat(filters.descriptions, ", "))
	end

	-- Group items by source file + rounded duration.
	local groups = {}
	local scanned, skipped, filtered = 0, 0, 0
	for i = 0, item_count - 1 do
		local item = r.GetMediaItem(proj, i)

		if not ItemPassesFilters(item, filters) then
			filtered = filtered + 1
			goto continue
		end

		local source_file = GetItemSourceFile(item)

		if source_file then
			local length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
			-- Quantise length to the tolerance so near-identical durations collide.
			local length_key = math.floor(length / LENGTH_TOLERANCE + 0.5)

			-- Take start offset, so only items pointing at the same region of the
			-- source (not just the same file + duration) are treated as duplicates.
			local take = r.GetActiveTake(item)
			local start_offset = take and r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
			local offset_key = math.floor(start_offset / LENGTH_TOLERANCE + 0.5)

			local key = source_file .. "|" .. length_key .. "|" .. offset_key

			local track = r.GetMediaItemTrack(item)
			local entry = {
				item = item,
				track_num = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"),
				position = r.GetMediaItemInfo_Value(item, "D_POSITION"),
			}

			groups[key] = groups[key] or {}
			table.insert(groups[key], entry)
			scanned = scanned + 1
		else
			skipped = skipped + 1
		end

		::continue::
	end
	Log("Scanned", scanned, "file-backed items;",
		"skipped", skipped, "(empty/MIDI/no source);",
		"excluded by filters", filtered)

	-- Collect the extra copies to remove (everything but the first item in each group).
	local to_remove = {}
	local group_count = 0
	for _, entries in pairs(groups) do
		if #entries > 1 then
			group_count = group_count + 1
			table.sort(entries, CompareItemsFirst)
			Log("Duplicate group of", #entries, "-> keeping track", entries[1].track_num, "pos", entries[1].position)
			for i = 2, #entries do
				table.insert(to_remove, entries[i].item)
			end
		end
	end

	-- Note describing which scope filters narrowed the scan, shown in the dialogs.
	local filter_note = ""
	if #filters.descriptions > 0 then
		filter_note = "\n\nScan was limited to items " .. table.concat(filters.descriptions, " and ") .. "."
	end

	local dup_count = #to_remove
	if dup_count == 0 then
		r.ShowMessageBox("No duplicate items were found." .. filter_note, SCRIPT_NAME, 0)
		return
	end

	local msg = string.format(
		"Found %d duplicate item%s across %d group%s (same source, duration, and start offset).%s\n\n" ..
		"Remove the extra cop%s? The first item in each group (lowest track number, " ..
		"earliest position) will be kept.",
		dup_count, dup_count == 1 and "" or "s",
		group_count, group_count == 1 and "" or "s",
		filter_note,
		dup_count == 1 and "y" or "ies")

	-- Type 4 = Yes/No. 6 = Yes, 7 = No.
	local answer = r.ShowMessageBox(msg, SCRIPT_NAME, 4)
	if answer ~= 6 then
		Log("User declined removal")
		return
	end

	local removed = 0
	for _, item in ipairs(to_remove) do
		local track = r.GetMediaItemTrack(item)
		if track and r.DeleteTrackMediaItem(track, item) then
			removed = removed + 1
		end
	end
	Log("Removed", removed, "duplicate items")

	r.ShowMessageBox(
		string.format("Removed %d duplicate item%s.", removed, removed == 1 and "" or "s"),
		SCRIPT_NAME, 0)
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
