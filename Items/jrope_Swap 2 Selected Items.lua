--[[
 * Name: Swap 2 Selected Items
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
   # Swaps the positions of exactly 2 selected items, on the same track or across
   # tracks (vertically, horizontally or diagonally). Works purely through the
   # REAPER API - no temporary track, no clipboard, no edit cursor movement - so
   # the arrange view never scrolls or flickers.
   #
   # When the two items sit on the same track and are contiguous (or overlapping),
   # PRESERVE_CONTIGUITY keeps them butted together after the swap instead of
   # leaving a gap/overlap when their lengths differ.
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

-- Same-track swaps: when the two items butt up against each other (or overlap),
-- keep that relationship after the swap rather than swapping raw start positions.
-- Only matters when the two items have different lengths.
local PRESERVE_CONTIGUITY = true

-- Cross-track swaps on fixed-lane tracks: also swap which lane each item lands in.
local SWAP_FIXED_LANES = true


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match([[([^/\_]+)%.lua$]])
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


-- I_FREEMODE == 2 means the track is in fixed item lanes mode.
local FREEMODE_FIXED_LANES = 2

local function LanesEnabled(track)
  return r.GetMediaTrackInfo_Value(track, "I_FREEMODE") == FREEMODE_FIXED_LANES
end


-- Snapshot of everything we need to reposition an item.
local function GetItemState(item)
  local track = r.GetMediaItemTrack(item)
  return {
    item     = item,
    track    = track,
    pos      = r.GetMediaItemInfo_Value(item, "D_POSITION"),
    len      = r.GetMediaItemInfo_Value(item, "D_LENGTH"),
    lane     = r.GetMediaItemInfo_Value(item, "I_FIXEDLANE"),
    freemode = r.GetMediaTrackInfo_Value(track, "I_FREEMODE"),
  }
end


-- Set when the backstop below had to undo a lanes-mode change; drives UpdateTimeline().
local lanes_restored = false


function main()

  local itm_cnt = r.CountSelectedMediaItems(proj)
  Log("selected items:", itm_cnt)

  if itm_cnt ~= 2 then
    r.MB(itm_cnt == 0 and "No items selected."
      or "Exactly 2 items must be selected.", "ERROR", 0)
    return
  end

  local a = GetItemState(r.GetSelectedMediaItem(proj, 0))
  local b = GetItemState(r.GetSelectedMediaItem(proj, 1))

  -- GetSelectedMediaItem() ordering isn't guaranteed to be left-to-right, so
  -- normalise: `a` is always the earlier item.
  if b.pos < a.pos then a, b = b, a end

  Log(("A: track %d pos %.6f len %.6f lane %d")
    :format(r.GetMediaTrackInfo_Value(a.track, "IP_TRACKNUMBER"), a.pos, a.len, a.lane))
  Log(("B: track %d pos %.6f len %.6f lane %d")
    :format(r.GetMediaTrackInfo_Value(b.track, "IP_TRACKNUMBER"), b.pos, b.len, b.lane))

  local a_new_pos, b_new_pos = b.pos, a.pos

  -- Same track and touching/overlapping: anchor the pair's outer edges and let the
  -- shared boundary move, so the items stay butted together when lengths differ.
  local same_track = a.track == b.track
  local contiguous = b.pos <= a.pos + a.len + 0.0000001
  if PRESERVE_CONTIGUITY and same_track and contiguous then
    local overlap = (a.pos + a.len) - b.pos   -- 0 when exactly adjacent
    b_new_pos = a.pos                          -- B takes over the left slot
    a_new_pos = a.pos + b.len - overlap        -- A follows, same gap/overlap as before
    Log(("contiguous same-track swap, overlap %.6f"):format(overlap))
  end

  -- Position first, then track: MoveMediaItemToTrack() doesn't touch D_POSITION,
  -- so the order is only about keeping the intermediate state tidy.
  r.SetMediaItemInfo_Value(a.item, "D_POSITION", a_new_pos)
  r.SetMediaItemInfo_Value(b.item, "D_POSITION", b_new_pos)

  if not same_track then
    r.MoveMediaItemToTrack(a.item, b.track)
    r.MoveMediaItemToTrack(b.item, a.track)

    -- Only touch I_FIXEDLANE on a destination track that is already in fixed
    -- lanes mode. Writing that property to a normal track switches the track
    -- INTO lanes mode, which is the unwanted side effect we're avoiding.
    if SWAP_FIXED_LANES then
      if LanesEnabled(b.track) then
        r.SetMediaItemInfo_Value(a.item, "I_FIXEDLANE", b.lane)
      else
        Log("dest track for A has no fixed lanes - leaving I_FIXEDLANE alone")
      end
      if LanesEnabled(a.track) then
        r.SetMediaItemInfo_Value(b.item, "I_FIXEDLANE", a.lane)
      else
        Log("dest track for B has no fixed lanes - leaving I_FIXEDLANE alone")
      end
    end

    -- Backstop: if the move itself still flipped a track into lanes mode, put
    -- the track back the way we found it.
    for _, t in ipairs({a, b}) do
      local now = r.GetMediaTrackInfo_Value(t.track, "I_FREEMODE")
      if now ~= t.freemode then
        r.SetMediaTrackInfo_Value(t.track, "I_FREEMODE", t.freemode)
        lanes_restored = true
        Log(("restored I_FREEMODE %d -> %d on track %d"):format(now, t.freemode,
          r.GetMediaTrackInfo_Value(t.track, "IP_TRACKNUMBER")))
      end
    end

    Log("moved items across tracks")
  end

  Log(("new positions: A %.6f  B %.6f"):format(a_new_pos, b_new_pos))

end -- main


---------------------------------
-------------- MAIN -------------
---------------------------------

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

main()

reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, -1)
reaper.PreventUIRefresh(-1)
if lanes_restored then reaper.UpdateTimeline() end  -- I_FREEMODE changes need this
reaper.UpdateArrange()
