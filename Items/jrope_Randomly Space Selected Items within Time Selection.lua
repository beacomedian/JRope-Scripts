--[[
 * Name: Random Item Spacer and Muter
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
  [main] . > 
 * Link: https://www.jesserope.com
 * noindex
 * About:
  # Randomly scatter selected media items within the time selection.
    Items on the same track will never overlap. Cross-track overlap is
    intentional — useful for layered ambience beds.
    A second section randomly mutes a percentage of items, applied
    per-track so each track independently receives the specified ratio.
 * Changelog:
  # v1.0 - Initial Release
 * To Do:
  #
]]


---------------------------------
---------- USER CONFIG ----------
---------------------------------

-- How many milliseconds to spend per defer frame. Not used for searching
-- here, but kept as a pattern placeholder consistent with other jrope scripts.
local FRAME_BUDGET_MS = 20

-- Set to true to print debug output to the REAPER console.
ENABLE_DEBUG_LOG = true

-- Maximum random placement attempts per item before giving up.
local MAX_ATTEMPTS = 2000


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR  = ({reaper.get_action_context()})[2]:sub(
  1, ({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
local r    = reaper
local proj = 0

local WIN_W = 340   -- fixed window width (height auto-fits via Cond_Always + h=0)


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
-- Persist min-spacing and mute-pct between runs.
-- =============================================================================

local EXT_SECTION      = "jrope_RandomItemSpacer"
local EXT_KEY_SPACING  = "minSpacing"
local EXT_KEY_MUTE_PCT = "mutePct"


---------------------------------
----------- FUNCTIONS -----------
---------------------------------


-- =============================================================================
-- LOGGING
-- =============================================================================

-- Load my common functions (provides the shared Log()). Append to package.path
-- so the ReaImGui path set above is preserved.
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")

-- printf-style convenience around the shared Log() in Common Functions.
-- Log() owns the ENABLE_DEBUG_LOG gate and appends its own newline.
local function log(fmt, ...)
  Log("[RandomSpacer] " .. (select('#', ...) > 0 and fmt:format(...) or fmt))
end


-- =============================================================================
-- HELPERS: random placement
-- =============================================================================

local function rand_range(lo, hi)
  return lo + math.random() * (hi - lo)
end

local function overlaps(as, ae, bs, be)
  local eps = 1e-9
  return as < (be - eps) and ae > (bs + eps)
end

--- Find a random non-overlapping start position for an item of `item_len`
--- seconds within [ts_start, ts_end], keeping at least `gap` seconds of
--- clearance around every already-placed interval.
--- Returns a position number, or nil on failure.
local function find_slot(placed, item_len, gap, ts_start, ts_end)
  if item_len > (ts_end - ts_start) then return nil end
  local lo = ts_start
  local hi = ts_end - item_len
  if hi < lo then return nil end

  for _ = 1, MAX_ATTEMPTS do
    local cs = rand_range(lo, hi)
    local ce = cs + item_len
    local ok = true
    for _, iv in ipairs(placed) do
      if overlaps(cs, ce, iv.s - gap, iv.e + gap) then
        ok = false; break
      end
    end
    if ok then return cs end
  end
  return nil
end


-- =============================================================================
-- HELPER: collect selected items grouped by track
-- Returns track_items (table keyed by track ptr), track_order (array), count
-- =============================================================================

local function collect_by_track()
  local track_items = {}
  local track_order = {}
  local count = reaper.CountSelectedMediaItems(proj)

  for i = 0, count - 1 do
    local item   = reaper.GetSelectedMediaItem(proj, i)
    local track  = reaper.GetMediaItem_Track(item)
    local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if not track_items[track] then
      track_items[track] = {}
      table.insert(track_order, track)
    end
    table.insert(track_items[track], { item = item, length = length })
  end

  return track_items, track_order, count
end


-- =============================================================================
-- HELPER: Fisher-Yates in-place shuffle
-- =============================================================================

local function shuffle(t)
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
end


-- =============================================================================
-- CORE: run_randomize
-- Scatter selected items within the time selection, per-track non-overlapping.
-- Updates state.space_status / state.space_status_ok on completion.
-- =============================================================================

local function run_randomize(state)
  math.randomseed(os.time() + math.floor(reaper.time_precise() * 1e6) % 1000000)
  log("run_randomize() — min_spacing=%.3f", state.min_spacing)

  local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if ts_end <= ts_start then
    state.space_status    = "No time selection found."
    state.space_status_ok = false
    log("WARN: no time selection")
    return
  end

  local item_count = reaper.CountSelectedMediaItems(proj)
  if item_count == 0 then
    state.space_status    = "No items selected."
    state.space_status_ok = false
    log("WARN: no selected items")
    return
  end

  local gap    = math.max(0, state.min_spacing)
  local ts_len = ts_end - ts_start
  log("Time selection %.3f–%.3f (%.3fs), gap=%.2f", ts_start, ts_end, ts_len, gap)

  local track_items, track_order = collect_by_track()

  -- Feasibility: total item length + inter-item gaps must fit
  for _, track in ipairs(track_order) do
    local entries     = track_items[track]
    local total       = 0
    for _, e in ipairs(entries) do total = total + e.length end
    local gaps_needed = gap * (#entries - 1)
    local ti = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    log("Track %d: %d item(s), total=%.3fs, gaps_needed=%.3fs", ti, #entries, total, gaps_needed)
    if (total + gaps_needed) > ts_len then
      state.space_status = string.format(
        "Track %d: items+spacing (%.2fs) exceed selection (%.2fs).",
        ti, total + gaps_needed, ts_len)
      state.space_status_ok = false
      log("FAIL feasibility on track %d", ti)
      return
    end
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local failed = {}

  for _, track in ipairs(track_order) do
    local entries = track_items[track]
    shuffle(entries)
    local placed = {}
    for _, entry in ipairs(entries) do
      local pos = find_slot(placed, entry.length, gap, ts_start, ts_end)
      if pos then
        reaper.SetMediaItemInfo_Value(entry.item, "D_POSITION", pos)
        table.insert(placed, { s = pos, e = pos + entry.length })
        log("  placed at %.3f (len=%.3f)", pos, entry.length)
      else
        local ti = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
        log("FAIL: no slot found on track %d", ti)
        table.insert(failed, ti)
        break
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("jrope: Randomly space selected items", -1)

  if #failed > 0 then
    state.space_status    = "Could not fit all items on track(s): "
                            .. table.concat(failed, ", ")
                            .. ". Try less spacing or undo."
    state.space_status_ok = false
  else
    state.space_status    = string.format(
      "Placed %d item(s)  |  min gap %.2fs.", item_count, gap)
    state.space_status_ok = true
    log("SUCCESS: placed %d items", item_count)
  end
end


-- =============================================================================
-- CORE: run_mute
-- Randomly mute a percentage of selected items, applied independently per track.
-- =============================================================================

local function run_mute(state)
  math.randomseed(os.time() + math.floor(reaper.time_precise() * 1e6) % 1000000)
  log("run_mute() — mute_pct=%d", state.mute_pct)

  local item_count = reaper.CountSelectedMediaItems(proj)
  if item_count == 0 then
    state.mute_status    = "No items selected."
    state.mute_status_ok = false
    log("WARN: no selected items")
    return
  end

  local track_items, track_order = collect_by_track()

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local total_muted   = 0
  local total_unmuted = 0

  for _, track in ipairs(track_order) do
    local entries = track_items[track]
    local n       = #entries
    -- Round to nearest so a 3-item track at 50% → 2 muted, not 1
    local n_mute  = math.floor(n * state.mute_pct / 100 + 0.5)
    local ti      = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    log("Track %d: %d item(s), muting %d (%.0f%%)", ti, n, n_mute, state.mute_pct)

    shuffle(entries)

    for idx, entry in ipairs(entries) do
      local mute = (idx <= n_mute) and 1 or 0
      reaper.SetMediaItemInfo_Value(entry.item, "B_MUTE", mute)
      if mute == 1 then
        total_muted   = total_muted + 1
        log("  muted item on track %d", ti)
      else
        total_unmuted = total_unmuted + 1
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("jrope: Randomly mute selected items by percentage", -1)

  state.mute_status = string.format(
    "Muted %d  |  Active %d  |  %d%% per track.",
    total_muted, total_unmuted, state.mute_pct)
  state.mute_status_ok = true
  log("SUCCESS: muted=%d, active=%d", total_muted, total_unmuted)
end


-- =============================================================================
-- STATE TABLE
-- All persistent GUI state lives here so it survives across defer frames.
-- =============================================================================

local state = {
  ctx         = nil,
  windowOpen  = true,

  -- Spacing section
  min_spacing      = tonumber(reaper.GetExtState(EXT_SECTION, EXT_KEY_SPACING)) or 0.0,
  space_status     = "Select items and set a time selection.",
  space_status_ok  = nil,   -- nil = neutral, true = ok, false = warning/error

  -- Mute section
  mute_pct         = tonumber(reaper.GetExtState(EXT_SECTION, EXT_KEY_MUTE_PCT)) or 50,
  mute_status      = "Mute % applied per track independently.",
  mute_status_ok   = nil,
}


-- =============================================================================
-- DRAW HELPERS
-- =============================================================================

-- Colours as 0xRRGGBBAA
local C = {
  accent      = 0x5AA0FFFF,  -- blue accent (matches jrope blue)
  ok          = 0x50C878FF,  -- green
  warn        = 0xF0A03CFF,  -- amber
  dim         = 0x888888FF,  -- neutral/dim label
  slider_bg   = 0x222228FF,
  slider_fill = 0x5AA0FFFF,
  slider_knob = 0xC8D0F0FF,
  slider_brd  = 0x5AA0FFFF,
  bar_border  = 0x666666FF,
}

--- Draw a coloured status line; col is an 0xRRGGBBAA int.
local function draw_status(ctx, msg, col)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, col)
  ImGui.TextWrapped(ctx, msg)
  ImGui.PopStyleColor(ctx)
end

--- Resolve a status colour from a nil/true/false tri-state.
local function status_col(ok_flag)
  if ok_flag == true  then return C.ok   end
  if ok_flag == false then return C.warn end
  return C.dim
end

--- Draw a styled full-width SliderInt (0–100) using ImGui's native slider
--- widget, coloured to match the jrope palette via PushStyleColor/PushStyleVar.
--- Returns the (possibly changed) integer value.
---
--- WHY NOT DrawList?
--- DrawList paints pixels but registers no interactive widget — ImGui never
--- sees a "hot" item over that area, so the window title bar claims the drag
--- instead. SliderInt IS the widget; it owns hit-testing and drag logic.
local function draw_pct_slider(ctx, id, value)
  -- Style the native slider to match the jrope dark palette:
  --   FrameBg        → track background (unselected portion)
  --   FrameBgHovered → track hovered
  --   FrameBgActive  → track while dragging
  --   SliderGrab     → the knob fill
  --   SliderGrabActive → knob while dragging
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg,        0x2A2A38FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x35354AFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive,  0x35354AFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab,     0x5AA0FFFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive, 0x80BAFFFF)

  -- Taller grab and rounded edges to look closer to the old gfx knob
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabMinSize,    14)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabRounding,   3)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding,  3)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding,   4, 4)

  -- Full-width: SetNextItemWidth(-1) fills remaining horizontal space
  ImGui.SetNextItemWidth(ctx, -1)
  local rv, new_val = ImGui.SliderInt(ctx, id, value, 0, 100, "%d%%")

  ImGui.PopStyleVar(ctx, 4)
  ImGui.PopStyleColor(ctx, 5)

  return rv and new_val or value
end


-- =============================================================================
-- IMGUI LOOP
-- Called every frame via reaper.defer(). Draws the window and handles input.
-- =============================================================================

local function loop()
  -- Pin width; let height auto-fit vertically
  ImGui.SetNextWindowSize(state.ctx, WIN_W, 0, ImGui.Cond_Always)

  local win_flags = ImGui.WindowFlags_NoCollapse
                  | ImGui.WindowFlags_NoResize
                  | ImGui.WindowFlags_NoSavedSettings

  local visible, open = ImGui.Begin(state.ctx, "Random Item Spacer", true, win_flags)
  state.windowOpen = open

  if visible then

    -- =========================================================================
    -- SECTION: SPACING
    -- =========================================================================
    ImGui.SeparatorText(state.ctx, "SPACING")
    ImGui.Spacing(state.ctx)

    -- Min spacing input
    ImGui.SetNextItemWidth(state.ctx, 120)
    local rv, new_spacing = ImGui.InputDouble(
      state.ctx, "Min gap (sec)##spacing",
      state.min_spacing, 0.1, 1.0, "%.2f")
    if rv then
      state.min_spacing = math.max(0, new_spacing)
      reaper.SetExtState(EXT_SECTION, EXT_KEY_SPACING,
        tostring(state.min_spacing), true)
    end

    ImGui.Spacing(state.ctx)

    -- Randomize Spacing button (full width)
    local bw = ImGui.GetContentRegionAvail(state.ctx)
    if ImGui.Button(state.ctx, "Randomize Spacing##space_btn", bw, 0) then
      run_randomize(state)
    end

    ImGui.Spacing(state.ctx)
    draw_status(state.ctx, state.space_status, status_col(state.space_status_ok))

    ImGui.Spacing(state.ctx)
    ImGui.Spacing(state.ctx)

    -- =========================================================================
    -- SECTION: MUTE
    -- =========================================================================
    ImGui.SeparatorText(state.ctx, "MUTE")
    ImGui.Spacing(state.ctx)

    -- Percentage label above the slider
    ImGui.TextColored(state.ctx, C.dim,
      string.format("Mute chance per track:  %d%%", state.mute_pct))

    ImGui.Spacing(state.ctx)

    -- Native SliderInt styled to match jrope palette. Ctrl+click to type a value.
    local new_pct = draw_pct_slider(state.ctx, "##muteslider", state.mute_pct)
    if new_pct ~= state.mute_pct then
      state.mute_pct = new_pct
      reaper.SetExtState(EXT_SECTION, EXT_KEY_MUTE_PCT,
        tostring(state.mute_pct), true)
    end

    -- 0% / 100% end labels
    ImGui.PushStyleColor(state.ctx, ImGui.Col_Text, C.dim)
    ImGui.Text(state.ctx, "0%")
    ImGui.SameLine(state.ctx, 0, 0)
    local lbl100    = "100%"
    local lbl100_w  = ImGui.CalcTextSize(state.ctx, lbl100)
    ImGui.SetCursorPosX(state.ctx,
      ImGui.GetWindowWidth(state.ctx)
      - lbl100_w
      - ImGui.GetStyleVar(state.ctx, ImGui.StyleVar_WindowPadding))
    ImGui.Text(state.ctx, lbl100)
    ImGui.PopStyleColor(state.ctx)

    ImGui.Spacing(state.ctx)

    -- Randomize Mute button (full width)
    local bw2 = ImGui.GetContentRegionAvail(state.ctx)
    if ImGui.Button(state.ctx, "Randomize Mute##mute_btn", bw2, 0) then
      run_mute(state)
    end

    ImGui.Spacing(state.ctx)
    draw_status(state.ctx, state.mute_status, status_col(state.mute_status_ok))

    ImGui.Spacing(state.ctx)

  end -- visible

  ImGui.End(state.ctx)

  -- Continue or stop
  if state.windowOpen then
    reaper.defer(loop)
  end
end


---------------------------------
-------------- MAIN -------------
---------------------------------

state.ctx = ImGui.CreateContext(SCRIPT_NAME)

reaper.defer(loop)
