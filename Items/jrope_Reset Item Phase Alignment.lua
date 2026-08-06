--[[
 * Name: Reset Item Phase Alignment
 * Author: Jesse Rope
 * AI: Claude Opus 4.8 Medium
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
 	[main] . >
 * Link: https://www.jesserope.com
 * About:
 	# Reset Item Phase Alignment
 	Undoes manual phase-alignment nudges on the selected items.

	Requires reference item (top item in selection) to match start offset.

 	The selection is split into vertical columns (groups of items whose time
 	extents overlap), exactly like jrope_Batch Phase Alignment. Within each
 	column the reference item is the one on the TOPMOST track. Every other item
 	in the column has its active take's "Start in source" offset (D_STARTOFFS)
 	set to match that reference item, realigning the column against its top item.

 	Independently, the invert-phase (polarity) flag is cleared on every selected
 	item.
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

-- Items are grouped into a column when their time extents overlap. This tolerance
-- (seconds) is added to the overlap test: 0 = touching/overlapping items group;
-- a small positive value bridges tiny gaps; a small negative value requires real overlap.
-- Matches the grouping used by jrope_Batch Phase Alignment.
local OVERLAP_TOLERANCE = -0.1


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


-- Split the selected items into time-overlapping columns.
-- Mirrors jrope_Batch Phase Alignment: sort by start, then cluster any item whose
-- start falls within (running column end + OVERLAP_TOLERANCE) into that column.
local function build_columns()
	local items = {}
	for i = 0, r.CountSelectedMediaItems(proj) - 1 do
		local it  = r.GetSelectedMediaItem(proj, i)
		local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
		local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
		items[#items + 1] = { item = it, s = pos, e = pos + len }
	end
	table.sort(items, function(a, b) return a.s < b.s end)

	local columns, cur = {}, nil
	for _, it in ipairs(items) do
		if cur and it.s <= (cur.max_e + OVERLAP_TOLERANCE) then
			cur.items[#cur.items + 1] = it.item
			if it.e > cur.max_e then cur.max_e = it.e end
		else
			cur = { items = { it.item }, min_s = it.s, max_e = it.e }
			columns[#columns + 1] = cur
		end
	end
	return columns
end


-- The reference item of a column is the one on the topmost track (lowest track
-- number); ties (same track) are broken by earliest position.
local function reference_item(col_items)
	local ref, ref_tracknum, ref_pos
	for _, item in ipairs(col_items) do
		local track = r.GetMediaItem_Track(item)
		local tracknum = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
		local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
		if not ref
			or tracknum < ref_tracknum
			or (tracknum == ref_tracknum and pos < ref_pos) then
			ref, ref_tracknum, ref_pos = item, tracknum, pos
		end
	end
	return ref
end


-- Clears an item's invert-phase (polarity) flag via its state chunk.
-- Polarity is stored as a leading "-" on the 3rd value of the item's VOLPAN line.
-- Returns true only when the flag was set and had to be cleared.
local function ClearItemPhaseInvert(item)
	local ok, chunk = r.GetItemStateChunk(item, "", false)
	if not ok or not chunk then return false end

	local line = chunk:match("VOLPAN[^\r\n]*")
	if not line then return false end

	local head, sign, tail = line:match("^(VOLPAN%s+[%-%d%.]+%s+[%-%d%.]+%s*)(%-?)(.*)$")
	if not head then return false end
	if sign ~= "-" then return false end -- already non-inverted, nothing to do

	local new_line = head .. (tail or "")
	local start_pos = chunk:find(line, 1, true)
	if not start_pos then return false end

	local newchunk = chunk:sub(1, start_pos - 1) .. new_line .. chunk:sub(start_pos + #line)
	r.SetItemStateChunk(item, newchunk, false)
	return true
end


function main()
	local count = r.CountSelectedMediaItems(proj)
	Log("Selected items:", count)

	if count == 0 then
		r.ShowMessageBox("No items selected. Select one or more items first.", SCRIPT_NAME, 0)
		return
	end

	local columns = build_columns()
	Log("Columns:", #columns)

	local offset_resets = 0
	local phase_resets = 0

	for ci, col in ipairs(columns) do
		-- Reference item's "Start in source" is the target for the whole column.
		local ref = reference_item(col.items)
		local ref_take = ref and r.GetActiveTake(ref)
		local target_offs = ref_take and r.GetMediaItemTakeInfo_Value(ref_take, "D_STARTOFFS") or 0

		Log(string.format("[column %d/%d] %d items, %.3f..%.3f s, ref start-in-source = %.6f",
			ci, #columns, #col.items, col.min_s, col.max_e, target_offs))

		for _, item in ipairs(col.items) do
			-- Align "Start in source" to the reference item (skip the reference itself).
			if item ~= ref then
				local take = r.GetActiveTake(item)
				if take then
					local offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
					if offs ~= target_offs then
						r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", target_offs)
						offset_resets = offset_resets + 1
						Log(string.format("    reset D_STARTOFFS %.6f -> %.6f", offs, target_offs))
					end
				end
			end

			-- Clear the invert-phase (polarity) flag on every item.
			if ClearItemPhaseInvert(item) then
				phase_resets = phase_resets + 1
				Log("    cleared invert-phase flag")
			end
		end
	end

	Log("Done. Offsets aligned:", offset_resets, "| Phase flags cleared:", phase_resets)
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
