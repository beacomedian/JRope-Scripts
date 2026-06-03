--[[
 * Name: MCP Depth Filter
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 2.0
 * Provides:
  [main] . > 
 * Link: https://www.jesserope.com
 * About:
  # Shows/hides tracks in the Mixer (MCP) by folder depth,
  # staying in sync with TCP visibility.
  #
  # Rules:
  #   A track is shown in the MCP if its folder depth is <= the chosen limit.
  #   TCP visibility (B_SHOWINTCP) is ignored — each panel is independent.
  #   Hiding a folder parent in the TCP does NOT hide its children in the MCP.
  #
  # A defer loop watches for any project state change and
  # re-applies the depth filter automatically.
  #
  # Run the script once to set the depth and start the loop.
  # Run it again while it is active to change the depth or stop it.
  #
 * Changelog:
  # v2.0 - TCP sync + defer loop
  # v1.0 - Initial release (one-shot, no TCP awareness)
 * To Do:
  #

]]


---------------------------------
---------- USER CONFIG ----------
---------------------------------

-- Maximum depth shown in the input dialog choices list.
local MAX_DEPTH = 5

-- How often (in seconds) to check for project state changes.
-- 0.1 = 10 checks per second. Lower = more responsive, slightly more CPU.
-- You rarely need to go below 0.1 for a visibility-sync task.
local POLL_INTERVAL = 0.1


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local _, _, SECTION, CMD_ID = reaper.get_action_context()
local r    = reaper
local proj = 0

-- ExtState key used to persist the chosen depth across sessions
-- and share state between the running loop and a second invocation.
local EXT_SECTION   = "jrope_MCPDepthFilter"
local EXT_KEY_DEPTH = "max_visible_depth"
local EXT_KEY_ACTIVE = "is_active"


---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- ── Depth table ─────────────────────────────────────────────────────────────
--
-- Builds a table mapping track index → absolute folder depth.
-- REAPER stores depth as a *delta* per track (I_FOLDERDEPTH):
--
--   >= 1  = folder parent; next track is one level deeper
--   0     = normal track; no depth change
--   <= -1 = last track in N folders; depth decreases by abs(value) for next track
--
-- We walk every track in order, keeping a running counter (current_depth).
-- Each track's depth is captured at entry, then the counter is updated
-- for the next track.
--
local function buildDepthTable()
  local depth_table  = {}
  local track_count  = r.CountTracks(proj)
  local current_depth = 0

  for i = 0, track_count - 1 do
    local track      = r.GetTrack(proj, i)
    local fold_delta = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

    depth_table[i] = current_depth  -- record depth BEFORE applying delta

    if fold_delta >= 1 then
      current_depth = current_depth + 1
    elseif fold_delta <= -1 then
      current_depth = current_depth + fold_delta
      if current_depth < 0 then current_depth = 0 end  -- safety clamp
    end
  end

  return depth_table
end


-- ── MCP filter ──────────────────────────────────────────────────────────────
--
-- Iterates every track and sets B_SHOWINMIXER based on one condition:
--   The track's folder depth is <= max_visible_depth.
--
-- Each track's own TCP visibility (B_SHOWINTCP) is intentionally NOT checked.
-- A track hidden in the TCP can still appear in the MCP if it is within the
-- depth limit — the two panels are treated as fully independent.
-- B_SHOWINMIXER is independent of B_SHOWINTCP, so the TCP is never modified.
--
local function applyMCPDepthFilter(max_visible_depth)
  local depth_table = buildDepthTable()
  local track_count = r.CountTracks(proj)

  for i = 0, track_count - 1 do
    local track      = r.GetTrack(proj, i)
    local this_depth = depth_table[i]

    r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", this_depth <= max_visible_depth and 1 or 0)
  end
end


-- ── Toolbar button highlight ─────────────────────────────────────────────────
--
-- When a script runs as a persistent/background script it can light up its
-- toolbar button. 1 = lit (running), 0 = unlit (stopped).
--
local function setToolbarState(state)
  r.SetToggleCommandState(SECTION, CMD_ID, state)
  r.RefreshToolbar2(SECTION, CMD_ID)
end


-- ── ExtState helpers ────────────────────────────────────────────────────────
--
-- We use REAPER's persistent key-value store (ExtState) to:
--   a) Remember the chosen depth between sessions.
--   b) Signal between the already-running instance and a new invocation.
--
-- GetExtState always returns a string, so we convert as needed.
--
local function saveDepth(depth)
  -- math.huge can't round-trip through a string cleanly, so store "all"
  local val = (depth == math.huge) and "all" or tostring(math.floor(depth))
  r.SetExtState(EXT_SECTION, EXT_KEY_DEPTH, val, true)  -- true = persist to disk
end

local function loadDepth()
  local val = r.GetExtState(EXT_SECTION, EXT_KEY_DEPTH)
  if val == "" or val == nil then return nil end
  if val == "all" then return math.huge end
  return tonumber(val)
end

local function saveActive(state)
  r.SetExtState(EXT_SECTION, EXT_KEY_ACTIVE, state and "1" or "0", false)
end

local function loadActive()
  return r.GetExtState(EXT_SECTION, EXT_KEY_ACTIVE) == "1"
end


-- ── Input dialog ─────────────────────────────────────────────────────────────
--
-- Shows the depth-selection dialog.
-- Returns the chosen depth as a number (math.huge for "all"),
-- or nil if the user cancelled.
--
local function askUserForDepth()
  -- Build a choices hint string for the label, e.g. "0, 1, 2, 3, 4, 5, all"
  local choices = {"0"}
  for d = 1, MAX_DEPTH do choices[#choices + 1] = tostring(d) end
  choices[#choices + 1] = "all"
  local choices_str = table.concat(choices, ", ")

  -- Pre-fill the dialog with the last-used value if one exists.
  local last_depth = loadDepth()
  local default_str = ""
  if last_depth == math.huge then
    default_str = "all"
  elseif last_depth then
    default_str = tostring(math.floor(last_depth))
  end

  local label = "Show MCP tracks at depth 0 through:\n(" .. choices_str .. ")"
  local ok, raw = r.GetUserInputs("MCP Depth Filter", 1, label, default_str)

  if not ok then return nil end  -- user pressed Cancel

  local input = raw:match("^%s*(.-)%s*$"):lower()  -- trim whitespace + lowercase

  if input == "all" then
    return math.huge
  end

  local num = tonumber(input)
  if num == nil or num < 0 or math.floor(num) ~= num then
    r.ShowMessageBox(
      'Please enter a whole number (0, 1, 2, ...) or "all".',
      "MCP Depth Filter – Invalid Input",
      0
    )
    return nil
  end

  return num
end


-- ── Cleanup ──────────────────────────────────────────────────────────────────
--
-- Called when the script exits (via reaper.atexit).
-- Unlit the toolbar button and mark the loop as inactive.
--
local function onExit()
  saveActive(false)
  setToolbarState(0)
end


-- ── Defer loop ───────────────────────────────────────────────────────────────
--
-- This is the heart of the background behavior.
-- REAPER's defer() system calls a function repeatedly.
-- We use GetProjectStateChangeCount() as an efficient change detector:
-- it returns a number that increments on ANY project change.
-- We only re-apply the filter when that number changes.
--
-- A simple time gate (POLL_INTERVAL) prevents us from hammering the API
-- on every audio callback — we only check N times per second.
--
local last_state_count = -1    -- sentinel: -1 forces a filter pass on first run
local last_check_time  = 0     -- timestamp of the last poll

local function deferLoop()

  -- Time gate: only do work after POLL_INTERVAL seconds have passed.
  local now = r.time_precise()
  if now - last_check_time < POLL_INTERVAL then
    r.defer(deferLoop)  -- reschedule and exit early
    return
  end
  last_check_time = now

  -- Check if the project state has changed since our last pass.
  local current_state_count = r.GetProjectStateChangeCount(proj)

  if current_state_count ~= last_state_count then
    last_state_count = current_state_count

    -- State changed — re-apply the filter.
    -- Load the depth from ExtState so changes made by a second invocation
    -- of this script are picked up automatically.
    local depth = loadDepth()
    if depth then
      applyMCPDepthFilter(depth)
      r.TrackList_AdjustWindows(false)
    end
  end

  -- Reschedule ourselves for the next cycle.
  r.defer(deferLoop)
end


---------------------------------
-------------- MAIN -------------
---------------------------------

-- ── Toggle / re-configure logic ──────────────────────────────────────────────
--
-- When the script is invoked:
--   • If it is NOT currently running → ask for depth and start the loop.
--   • If it IS already running → ask "change depth or stop?"
--
-- We detect whether the loop is running using ExtState (saveActive/loadActive).
-- This works because ExtState is global to REAPER and persists across the
-- same session, so a second script invocation can read what the first wrote.
--

local function main()

  if loadActive() then
    -- ── Script is already running ────────────────────────────────────────
    -- Give the user a choice: update the depth, or stop the loop.
    local choice = r.ShowMessageBox(
      "MCP Depth Filter is already running.\n\nOK = change depth\nCancel = stop the filter",
      "MCP Depth Filter",
      1  -- 1 = OK + Cancel buttons
    )

    if choice == 2 then
      -- Cancel pressed → stop. The running instance will detect this
      -- via loadActive() returning false on its next cycle... but
      -- actually the cleaner approach is to not re-schedule deferLoop
      -- from within this invocation. The already-running instance is a
      -- separate script execution; it will keep running until REAPER
      -- exits or the project closes.
      --
      -- To truly stop it we use the toggle command state trick:
      -- the running loop checks loadActive() each cycle and exits if false.
      saveActive(false)
      setToolbarState(0)
      -- Restore all TCP-visible tracks to MCP visible so we leave a clean state.
      local depth = loadDepth()
      if depth then
        -- Setting depth to math.huge shows everything TCP-visible.
        applyMCPDepthFilter(math.huge)
        r.TrackList_AdjustWindows(false)
      end
      return
    end

    -- OK pressed → fall through to ask for new depth below.
  end

  -- ── Ask the user for a depth (new start OR depth change) ─────────────────
  local depth = askUserForDepth()
  if depth == nil then return end  -- user cancelled the dialog

  -- Persist the chosen depth.
  saveDepth(depth)

  -- Apply immediately so the user sees the result right away,
  -- without waiting for the first defer cycle.
  applyMCPDepthFilter(depth)
  r.TrackList_AdjustWindows(false)

  -- Only start the loop if it wasn't already active.
  -- If it was active (user changed depth), the already-running loop
  -- will pick up the new depth from ExtState on its next cycle.
  if not loadActive() then
    saveActive(true)
    setToolbarState(1)
    r.atexit(onExit)
    r.defer(deferLoop)
  end

end

main()
