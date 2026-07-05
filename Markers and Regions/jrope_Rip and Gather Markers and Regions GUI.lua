--[[
 * Name: Rip and Gather Markers and Regions GUI
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 0.5
 * Provides:
    [main] . >
 * Link: https://www.jesserope.com
 * noindex
 * About:
    # ReaImGui tool that unifies two operations on markers/regions whose
    # name matches a search string:
    #   GATHER — copy or move the media-item contents under each match,
    #            stacking them contiguously at the edit cursor.
    #   DELETE — remove each match and its contents, optionally rippling
    #            the timeline closed.
    # Works on both markers and regions (per-type toggles). Markers are
    # points, so a buffer window (size + weighting) defines their content
    # range; regions use their own start/end. If a time selection is
    # active, only matches inside it are processed. All settings persist
    # between runs via ExtState. Self-contained — no third-party scripts.
 * Changelog:
    # v0.5 - Public Alpha
 * To Do:
    #
]]


---------------------------------
---------- USER CONFIG ----------
---------------------------------

-- Must be global (no `local`) so the shared Log() in Common Functions can
-- read it. The GUI's "Console logging" checkbox writes to this at runtime.
ENABLE_DEBUG_LOG = false


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR  = ({reaper.get_action_context()})[2]:sub(
  1, ({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
local r    = reaper
local proj = 0

local WIN_W = 380   -- fixed window width (height auto-fits)
local EPS   = 1e-9


-- =============================================================================
-- REIMGUI SETUP
-- =============================================================================

if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox(
    "This script requires the ReaImGui extension.\nPlease install it via ReaPack.",
    "Missing Dependency", 0)
  return
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'


-- =============================================================================
-- EXTSTATE CONSTANTS
-- =============================================================================

local EXT = "jrope_RipAndGatherMarkersRegions"


---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Load my common functions (provides Log, UnselectAllItems,
-- set_tr_with_top_item_in_ts_as_last_touched). Append to package.path so the
-- ReaImGui path set above is preserved.
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")

-- printf-style convenience around the shared Log() in Common Functions.
-- Log() owns the ENABLE_DEBUG_LOG gate and appends its own newline.
local function log(fmt, ...)
  local s = select('#', ...) > 0 and fmt:format(...) or fmt
  s = s:gsub("\n$", "")
  Log("[RipGather] " .. s)
end


-- =============================================================================
-- EXTSTATE HELPERS
-- =============================================================================

local function ext_get_bool(key, default)
  local v = reaper.GetExtState(EXT, key)
  if v == "" then return default end
  return v == "true" or v == "1"
end

local function ext_get_num(key, default)
  local v = tonumber(reaper.GetExtState(EXT, key))
  if v == nil then return default end
  return v
end

local function ext_get_str(key, default)
  local v = reaper.GetExtState(EXT, key)
  if v == "" then return default end
  return v
end

local function ext_set(key, value)
  reaper.SetExtState(EXT, key, tostring(value), true)
end


-- =============================================================================
-- RIPPLE STATE SAVE / RESTORE
-- 0 = off, 1 = per-track, 2 = all-tracks. Toggle command states:
--   41990 = ripple per-track, 41991 = ripple all-tracks.
-- Set actions: 40309 off, 40310 per-track, 40311 all-tracks.
-- =============================================================================

local function get_ripple_state()
  if reaper.GetToggleCommandState(41991) == 1 then return 2 end
  if reaper.GetToggleCommandState(41990) == 1 then return 1 end
  return 0
end

local function set_ripple_state(s)
  if     s == 2 then reaper.Main_OnCommandEx(40311, 0, 0)
  elseif s == 1 then reaper.Main_OnCommandEx(40310, 0, 0)
  else               reaper.Main_OnCommandEx(40309, 0, 0) end
end


-- =============================================================================
-- CROSSFADES AT RIPPLE JOINS
-- After a ripple removal the material either side of the origin butts together
-- at a single point. Optionally blend that seam with a crossfade of up to the
-- requested length, centred on the join. Fades are built by extending each
-- item's edge into the other using only available source handle (and never
-- past the partner item), so nothing else on the timeline shifts. Where the
-- handles or item lengths are too short, the fade is shortened or skipped.
-- =============================================================================

local XF_TOL = 1e-5

-- Seconds of source material available AFTER an item's right edge (item-time).
local function handle_after(item)
  if reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC") == 1 then return math.huge end
  local take = reaper.GetActiveTake(item)
  if not take then return 0 end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return 0 end
  local srclen, isQN = reaper.GetMediaSourceLength(src)
  if isQN then return math.huge end  -- beat-based source; assume material is available
  local rate      = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local startoffs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local ilen      = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  if rate <= 0 then rate = 1 end
  local avail = srclen - (startoffs + ilen * rate)
  if avail < 0 then avail = 0 end
  return avail / rate
end

-- Seconds of source material available BEFORE an item's left edge (item-time).
local function handle_before(item)
  if reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC") == 1 then return math.huge end
  local take = reaper.GetActiveTake(item)
  if not take then return 0 end
  local rate      = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local startoffs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  if rate <= 0 then rate = 1 end
  if startoffs < 0 then startoffs = 0 end
  return startoffs / rate
end

-- Build a crossfade centred at time P across every track that has an item
-- ending at P and an item starting at P. `want` is the requested total fade
-- length. `left_bound` (optional) caps how far the right item may extend
-- leftward, so a fade never reaches into a window still queued for removal.
-- Returns (faded_count, shortened_count) across tracks.
local function crossfade_at(P, want, left_bound)
  if want <= XF_TOL then return 0, 0 end
  local half = want / 2
  local left_cap = left_bound and (P - left_bound) or math.huge
  if left_cap < 0 then left_cap = 0 end
  local faded, shortened = 0, 0

  for ti = 0, reaper.CountTracks(proj) - 1 do
    local track = reaper.GetTrack(proj, ti)
    local L, R
    for ii = 0, reaper.CountTrackMediaItems(track) - 1 do
      local it  = reaper.GetTrackMediaItem(track, ii)
      local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if math.abs((pos + len) - P) <= XF_TOL then L = it end
      if math.abs(pos - P)         <= XF_TOL then R = it end
    end

    if L and R and L ~= R then
      local L_len = reaper.GetMediaItemInfo_Value(L, "D_LENGTH")
      local R_len = reaper.GetMediaItemInfo_Value(R, "D_LENGTH")
      -- Extend L rightwards into R; extend R leftwards into L. Each side is
      -- limited by its own source handle and by the partner item's length
      -- (so the fade never runs past the partner).
      local hL = math.min(half, handle_after(L),  R_len)
      local hR = math.min(half, handle_before(R), L_len, left_cap)
      if hL < 0 then hL = 0 end
      if hR < 0 then hR = 0 end
      local overlap = hL + hR

      if overlap > XF_TOL then
        if hL > XF_TOL then
          reaper.SetMediaItemInfo_Value(L, "D_LENGTH", L_len + hL)
        end
        if hR > XF_TOL then
          local take = reaper.GetActiveTake(R)
          local rate = take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
          if rate <= 0 then rate = 1 end
          reaper.SetMediaItemInfo_Value(R, "D_POSITION", P - hR)
          reaper.SetMediaItemInfo_Value(R, "D_LENGTH", R_len + hR)
          if take then
            local so = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") - hR * rate
            if so < 0 then so = 0 end
            reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", so)
          end
        end
        reaper.SetMediaItemInfo_Value(L, "D_FADEOUTLEN", overlap)
        reaper.SetMediaItemInfo_Value(R, "D_FADEINLEN",  overlap)
        faded = faded + 1
        if overlap < want - XF_TOL then shortened = shortened + 1 end
      end
    end
  end

  return faded, shortened
end


-- =============================================================================
-- MATCHING + TARGET COLLECTION
-- =============================================================================

-- Case-insensitive plain-text substring match (no Lua pattern parsing, so
-- prefixes like "x ", "!", ":", "_", "$" match literally).
local function name_matches(name, query)
  if query == nil or query == "" then return false end
  return string.find(name:lower(), query:lower(), 1, true) ~= nil
end

-- Content window for a marker point given the buffer size (total seconds)
-- and weight (-1..1 shifts the window's centre off the marker).
local function marker_window(pos, buffer_size, weight)
  local half  = buffer_size / 2
  local left  = half * (1 - weight)
  local right = half * (1 + weight)
  return pos - left, pos + right
end

-- Returns the active time selection as (start, end, active_bool).
local function get_time_selection()
  local s, e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  return s, e, (e - s) > EPS
end

-- Build the sorted list of targets matching `query`, honouring include
-- toggles, marker buffer window, and (if present) the active time selection.
-- Each target: {is_region, pos, rgnend, name, idx, color, win_s, win_e}
local function collect_targets(query, include_markers, include_regions, buffer_size, weight)
  local targets = {}
  local ts_s, ts_e, ts_active = get_time_selection()

  local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
  local total = num_markers + num_regions

  for i = 0, total - 1 do
    local retval, isrgn, pos, rgnend, name, idx, color = reaper.EnumProjectMarkers3(proj, i)
    if retval ~= 0 then
      local wanted = (isrgn and include_regions) or (not isrgn and include_markers)
      if wanted and name_matches(name, query) then
        local win_s, win_e
        if isrgn then
          win_s, win_e = pos, rgnend
        else
          win_s, win_e = marker_window(pos, buffer_size, weight)
        end
        -- Time-selection test: regions must fall within the selection by their
        -- own bounds; markers are tested by their point position (NOT the buffer
        -- window, which may spill past the selection), inclusive of the edges.
        local in_ts
        if not ts_active then
          in_ts = true
        elseif isrgn then
          in_ts = win_s >= ts_s - EPS and win_e <= ts_e + EPS
        else
          in_ts = pos >= ts_s - EPS and pos <= ts_e + EPS
        end
        if in_ts and win_e > win_s + EPS then
          targets[#targets + 1] = {
            is_region = isrgn, pos = pos, rgnend = rgnend, name = name,
            idx = idx, color = color, win_s = win_s, win_e = win_e,
          }
        end
      end
    end
  end

  table.sort(targets, function(a, b) return a.win_s < b.win_s end)
  return targets, ts_active
end


-- =============================================================================
-- CORE: GATHER (copy or move to the edit cursor)
-- =============================================================================

local function do_gather(state)
  local targets = collect_targets(
    state.gather_search, state.include_markers, state.include_regions,
    state.gather_buffer_size, state.gather_buffer_weight)

  if #targets == 0 then
    state.gather_status    = "No matching markers/regions found."
    state.gather_status_ok = false
    log("gather: no targets")
    return
  end

  local saved_ripple = get_ripple_state()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local ripple = state.ripple_edit

  -- Total content length to be gathered.
  local total_len = 0
  for _, t in ipairs(targets) do total_len = total_len + (t.win_e - t.win_s) end

  local dest = reaper.GetCursorPosition()

  -- RIPPLE ON: make room at the destination by inserting empty space there,
  -- pushing all later items/markers down the timeline. Any source window that
  -- sat at/after the insert point moves with it, so adjust its cached coords.
  if ripple then
    set_ripple_state(0)
    reaper.GetSet_LoopTimeRange(true, false, dest, dest + total_len, false)
    reaper.Main_OnCommand(40200, 0)  -- insert empty space at TS (moving later items)
    for _, t in ipairs(targets) do
      if t.win_s >= dest - EPS then
        t.win_s = t.win_s + total_len
        t.win_e = t.win_e + total_len
      end
    end
    log("gather: inserted %.3fs of room at %.3f", total_len, dest)
  end

  -- Fill the destination with ripple OFF so items land in the cleared space
  -- without shifting anything further.
  set_ripple_state(0)

  -- When moving with ripple, origin markers are placed AFTER the 40201 pass
  -- collapses each window, or that same pass would delete them.
  local defer_origin_markers = state.gather_is_move and ripple

  local paste_pos = dest
  log("gather: %d target(s), mode=%s, ripple=%s, dest=%.3f",
    #targets, state.gather_is_move and "MOVE" or "COPY", tostring(ripple), dest)

  for _, t in ipairs(targets) do
    local len = t.win_e - t.win_s

    -- Select + split the content window, then set the topmost involved track
    -- as last-touched so paste reproduces the multi-track layout.
    reaper.GetSet_LoopTimeRange(true, false, t.win_s, t.win_e, false)
    reaper.Main_OnCommand(40717, 0)  -- select all items in time selection
    reaper.Main_OnCommand(40061, 0)  -- split items at time selection
    reaper.Main_OnCommand(40717, 0)  -- re-select items in TS after the split

    -- Only touch the clipboard/tracks when items actually exist in the window;
    -- an empty window still gets its label recreated at the destination below.
    if reaper.CountSelectedMediaItems(proj) > 0 then
      set_tr_with_top_item_in_ts_as_last_touched()  -- re-selects items in TS + sets track

      if state.gather_is_move then
        reaper.Main_OnCommand(40699, 0)  -- cut items
      else
        reaper.Main_OnCommand(40698, 0)  -- copy items
      end

      reaper.SetEditCurPos(paste_pos, false, false)
      reaper.Main_OnCommand(42398, 0)  -- paste items
    end

    -- Recreate the marker/region label at the destination.
    if t.is_region then
      reaper.AddProjectMarker2(proj, true, paste_pos, paste_pos + len, t.name, -1, t.color)
    else
      reaper.AddProjectMarker2(proj, false, paste_pos, 0, t.name, -1, t.color)
    end

    -- Move: remove the original marker/region metadata.
    if state.gather_is_move then
      reaper.DeleteProjectMarker(proj, t.idx, t.is_region)
    end

    -- Optional origin marker (deferred to the ripple pass when moving+rippling,
    -- otherwise the 40201 pass below would delete it).
    if state.leave_marker and not defer_origin_markers then
      reaper.AddProjectMarker2(proj, false, t.win_s, 0, state.leave_marker_label, -1, 0x1000000)
    end

    paste_pos = paste_pos + len
  end

  -- Move + ripple: close the vacated source windows right-to-left, dropping
  -- each origin marker only after its window has collapsed, and optionally
  -- crossfading the newly-formed seam.
  local xf_faded, xf_short = 0, 0
  if state.gather_is_move and ripple then
    set_ripple_state(2)
    for i = #targets, 1, -1 do
      local t = targets[i]
      reaper.GetSet_LoopTimeRange(true, false, t.win_s, t.win_e, false)
      reaper.Main_OnCommand(40201, 0)  -- remove contents of TS (moving later items)
      local left_bound = (i > 1) and targets[i - 1].win_e or nil
      local f, sh = crossfade_at(t.win_s, state.xfade_sec, left_bound)
      xf_faded, xf_short = xf_faded + f, xf_short + sh
      if state.leave_marker then
        reaper.AddProjectMarker2(proj, false, t.win_s, 0, state.leave_marker_label, -1, 0x1000000)
      end
    end
    log("gather: closed %d source gap(s), crossfaded %d seam(s)", #targets, xf_faded)
  end

  set_ripple_state(saved_ripple)
  reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)  -- clear TS

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock("jrope_" .. SCRIPT_NAME .. " (gather)", -1)

  local xf_msg = ""
  if state.gather_is_move and ripple and state.xfade_sec > XF_TOL then
    xf_msg = string.format("  Crossfaded %d seam(s)", xf_faded)
    xf_msg = xf_msg .. (xf_short > 0
      and string.format(" (%d shorter than %.2fs - not enough item/handle).", xf_short, state.xfade_sec)
      or ".")
  end
  state.gather_status    = string.format("%s %d match(es) to cursor%s.%s",
    state.gather_is_move and "Moved" or "Copied", #targets,
    ripple and " (ripple)" or "", xf_msg)
  state.gather_status_ok = (xf_short == 0) or false  -- amber warning if any fade shortened
  log("gather: done")
end


-- =============================================================================
-- CORE: DELETE (remove matches + contents, optionally ripple closed)
-- =============================================================================

local function do_delete(state)
  local targets = collect_targets(
    state.delete_search, state.include_markers, state.include_regions,
    state.delete_buffer_size, state.delete_buffer_weight)

  if #targets == 0 then
    state.delete_status    = "No matching markers/regions found."
    state.delete_status_ok = false
    log("delete: no targets")
    return
  end

  local saved_ripple = get_ripple_state()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  if state.ripple_edit then set_ripple_state(2) else set_ripple_state(0) end
  log("delete: %d target(s), ripple=%s", #targets, tostring(state.ripple_edit))

  -- Right-to-left so ripple shifts only already-processed (rightward) material.
  local xf_faded, xf_short = 0, 0
  for i = #targets, 1, -1 do
    local t = targets[i]
    reaper.GetSet_LoopTimeRange(true, false, t.win_s, t.win_e, false)

    if state.ripple_edit then
      reaper.Main_OnCommand(40201, 0)  -- remove contents of TS (moving later items)
      -- The material either side of the origin now butts at t.win_s; blend it.
      local left_bound = (i > 1) and targets[i - 1].win_e or nil
      local f, sh = crossfade_at(t.win_s, state.xfade_sec, left_bound)
      xf_faded, xf_short = xf_faded + f, xf_short + sh
    else
      -- Split at the window edges first so only the portion inside the window
      -- is removed; without the split, 40717 selects items that merely touch
      -- the window and 40006 would delete them whole.
      reaper.Main_OnCommand(40717, 0)  -- select all items in time selection
      reaper.Main_OnCommand(40061, 0)  -- split items at time selection
      reaper.Main_OnCommand(40717, 0)  -- re-select items now bounded by the window
      reaper.Main_OnCommand(40006, 0)  -- remove selected items
    end

    -- Remove the matched marker/region metadata itself.
    reaper.DeleteProjectMarker(proj, t.idx, t.is_region)

    -- Optional marker at the (post-ripple) collapse point.
    if state.leave_marker then
      reaper.AddProjectMarker2(proj, false, t.win_s, 0, state.leave_marker_label, -1, 0x1000000)
    end
  end

  set_ripple_state(saved_ripple)
  reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)  -- clear TS

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock("jrope_" .. SCRIPT_NAME .. " (delete)", -1)

  local xf_msg = ""
  if state.ripple_edit and state.xfade_sec > XF_TOL then
    xf_msg = string.format("  Crossfaded %d seam(s)", xf_faded)
    xf_msg = xf_msg .. (xf_short > 0
      and string.format(" (%d shorter than %.2fs - not enough item/handle).", xf_short, state.xfade_sec)
      or ".")
  end
  state.delete_status    = string.format("Deleted %d match(es).%s", #targets, xf_msg)
  state.delete_status_ok = (xf_short == 0) or false  -- amber warning if any fade shortened
  log("delete: done")
end


-- =============================================================================
-- STATE TABLE (seeded from ExtState)
-- =============================================================================

local state = {
  ctx        = nil,
  windowOpen = true,

  -- Shared options
  include_markers    = ext_get_bool("include_markers", true),
  include_regions    = ext_get_bool("include_regions", true),
  ripple_edit        = ext_get_bool("ripple_edit", false),
  xfade_sec          = ext_get_num("xfade_sec", 0.0),
  leave_marker       = ext_get_bool("leave_marker", false),
  leave_marker_label = ext_get_str("leave_marker_label", "xRipGather"),
  enable_log         = ext_get_bool("enable_log", false),

  -- Gather
  gather_search        = ext_get_str("gather_search", ""),
  gather_is_move       = ext_get_bool("gather_is_move", false),
  gather_buffer_size   = ext_get_num("gather_buffer_size", 1.0),
  gather_buffer_weight = ext_get_num("gather_buffer_weight", 0.0),
  gather_status        = "Set a search string, place the cursor, and Gather.",
  gather_status_ok     = nil,

  -- Delete
  delete_search        = ext_get_str("delete_search", ""),
  delete_buffer_size   = ext_get_num("delete_buffer_size", 1.0),
  delete_buffer_weight = ext_get_num("delete_buffer_weight", 0.0),
  delete_status        = "Set a search string and Delete.",
  delete_status_ok     = nil,
}

ENABLE_DEBUG_LOG = state.enable_log


-- =============================================================================
-- DRAW HELPERS
-- =============================================================================

local C = {
  accent = 0x5AA0FFFF,
  ok     = 0x50C878FF,
  warn   = 0xF0A03CFF,
  dim    = 0x888888FF,
}

local function draw_status(ctx, msg, col)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, col)
  ImGui.TextWrapped(ctx, msg)
  ImGui.PopStyleColor(ctx)
end

local function status_col(ok_flag)
  if ok_flag == true  then return C.ok   end
  if ok_flag == false then return C.warn end
  return C.dim
end

-- Live count of current matches for a section (cheap: one marker enum pass).
local function preview_count(state, search, buffer_size, weight)
  local targets = collect_targets(
    search, state.include_markers, state.include_regions, buffer_size, weight)
  return #targets
end


-- =============================================================================
-- IMGUI LOOP
-- =============================================================================

local function loop()
  ImGui.SetNextWindowSize(state.ctx, WIN_W, 0, ImGui.Cond_FirstUseEver)

  local win_flags = ImGui.WindowFlags_NoCollapse
  local visible, open = ImGui.Begin(state.ctx, "Rip and Gather Markers and Regions", true, win_flags)
  state.windowOpen = open

  if visible then
    local ctx = state.ctx
    local _, _, ts_active = get_time_selection()

    -- =========================================================================
    -- OPTIONS
    -- =========================================================================
    ImGui.SeparatorText(ctx, "OPTIONS")

    local rv
    rv, state.include_markers = ImGui.Checkbox(ctx, "Include markers", state.include_markers)
    if rv then ext_set("include_markers", state.include_markers) end
    ImGui.SameLine(ctx)
    rv, state.include_regions = ImGui.Checkbox(ctx, "Include regions", state.include_regions)
    if rv then ext_set("include_regions", state.include_regions) end

    rv, state.ripple_edit = ImGui.Checkbox(ctx, "Ripple Edit (insert at dest / close source gaps)", state.ripple_edit)
    if rv then ext_set("ripple_edit", state.ripple_edit) end

    -- Crossfade at the ripple origin (only meaningful when Ripple Edit is on).
    ImGui.BeginDisabled(ctx, not state.ripple_edit)
    ImGui.SetNextItemWidth(ctx, -1)
    rv, state.xfade_sec = ImGui.SliderDouble(
      ctx, "Crossfade at origin (sec)##xfade", state.xfade_sec, 0.0, 3.0, "%.2f")
    if rv then
      state.xfade_sec = math.max(0, math.min(3, state.xfade_sec))
      ext_set("xfade_sec", state.xfade_sec)
    end
    ImGui.EndDisabled(ctx)

    rv, state.leave_marker = ImGui.Checkbox(ctx, "Leave marker at origin", state.leave_marker)
    if rv then ext_set("leave_marker", state.leave_marker) end
    if state.leave_marker then
      ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 130)
      rv, state.leave_marker_label = ImGui.InputText(ctx, "##leavelabel", state.leave_marker_label)
      if rv then ext_set("leave_marker_label", state.leave_marker_label) end
    end

    rv, state.enable_log = ImGui.Checkbox(ctx, "Console logging", state.enable_log)
    if rv then
      ext_set("enable_log", state.enable_log)
      ENABLE_DEBUG_LOG = state.enable_log
    end

    -- Time-selection status line
    if ts_active then
      ImGui.TextColored(ctx, C.accent, "Time selection active - restricting to it.")
    else
      ImGui.TextColored(ctx, C.dim, "No time selection - whole project.")
    end

    ImGui.Spacing(ctx)
    ImGui.Spacing(ctx)

    -- =========================================================================
    -- GATHER
    -- =========================================================================
    ImGui.SeparatorText(ctx, "GATHER")
    ImGui.TextColored(ctx, C.dim, "Copy/move matched contents to the edit cursor.")

    ImGui.SetNextItemWidth(ctx, -1)
    rv, state.gather_search = ImGui.InputText(ctx, "##gathersearch", state.gather_search)
    if rv then ext_set("gather_search", state.gather_search) end
    ImGui.TextColored(ctx, C.dim, "Search string (name contains, case-insensitive)")

    ImGui.Spacing(ctx)
    if ImGui.RadioButton(ctx, "Copy", not state.gather_is_move) then
      state.gather_is_move = false; ext_set("gather_is_move", false)
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Move", state.gather_is_move) then
      state.gather_is_move = true; ext_set("gather_is_move", true)
    end

    ImGui.SetNextItemWidth(ctx, 120)
    rv, state.gather_buffer_size = ImGui.InputDouble(
      ctx, "Buffer sec (markers)##gbuf", state.gather_buffer_size, 0.1, 1.0, "%.3f")
    if rv then
      state.gather_buffer_size = math.max(0, state.gather_buffer_size)
      ext_set("gather_buffer_size", state.gather_buffer_size)
    end

    ImGui.SetNextItemWidth(ctx, 200)
    rv, state.gather_buffer_weight = ImGui.SliderDouble(
      ctx, "Weight##gwt", state.gather_buffer_weight, -1.0, 1.0, "%.2f")
    if rv then
      state.gather_buffer_weight = math.max(-1, math.min(1, state.gather_buffer_weight))
      ext_set("gather_buffer_weight", state.gather_buffer_weight)
    end

    ImGui.TextColored(ctx, C.dim, string.format("matches: %d",
      preview_count(state, state.gather_search, state.gather_buffer_size, state.gather_buffer_weight)))

    local bw = ImGui.GetContentRegionAvail(ctx)
    if ImGui.Button(ctx, "Gather##gatherbtn", bw, 0) then
      do_gather(state)
    end
    draw_status(ctx, state.gather_status, status_col(state.gather_status_ok))

    ImGui.Spacing(ctx)
    ImGui.Spacing(ctx)

    -- =========================================================================
    -- DELETE
    -- =========================================================================
    ImGui.SeparatorText(ctx, "DELETE")
    ImGui.TextColored(ctx, C.dim, "Remove matched markers/regions and their contents.")

    ImGui.SetNextItemWidth(ctx, -1)
    rv, state.delete_search = ImGui.InputText(ctx, "##deletesearch", state.delete_search)
    if rv then ext_set("delete_search", state.delete_search) end
    ImGui.TextColored(ctx, C.dim, "Search string (name contains, case-insensitive)")

    ImGui.Spacing(ctx)
    ImGui.SetNextItemWidth(ctx, 120)
    rv, state.delete_buffer_size = ImGui.InputDouble(
      ctx, "Buffer sec (markers)##dbuf", state.delete_buffer_size, 0.1, 1.0, "%.3f")
    if rv then
      state.delete_buffer_size = math.max(0, state.delete_buffer_size)
      ext_set("delete_buffer_size", state.delete_buffer_size)
    end

    ImGui.SetNextItemWidth(ctx, 200)
    rv, state.delete_buffer_weight = ImGui.SliderDouble(
      ctx, "Weight##dwt", state.delete_buffer_weight, -1.0, 1.0, "%.2f")
    if rv then
      state.delete_buffer_weight = math.max(-1, math.min(1, state.delete_buffer_weight))
      ext_set("delete_buffer_weight", state.delete_buffer_weight)
    end

    ImGui.TextColored(ctx, C.dim, string.format("matches: %d",
      preview_count(state, state.delete_search, state.delete_buffer_size, state.delete_buffer_weight)))

    local bw2 = ImGui.GetContentRegionAvail(ctx)
    if ImGui.Button(ctx, "Delete##deletebtn", bw2, 0) then
      do_delete(state)
    end
    draw_status(ctx, state.delete_status, status_col(state.delete_status_ok))

    ImGui.Spacing(ctx)
  end -- visible

  ImGui.End(state.ctx)

  if state.windowOpen then
    reaper.defer(loop)
  end
end


---------------------------------
-------------- MAIN -------------
---------------------------------

state.ctx = ImGui.CreateContext(SCRIPT_NAME)
reaper.defer(loop)
