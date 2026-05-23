--[[
 * Name: Relink missing WAV Source with FLAC
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.1
 * Provides:
  [main] . > 
 * Link: https://www.jesserope.com
 * noindex
 * About:
  # Converted a library to Flac? 
    This script relinks unavailable WAV media files to FLAC files with the same name.
    If replacements aren't found in the same location, it will prompt for a directory to search.
    Updates take names and rebuilds peaks for relinked files.
 * Changelog:
  # v1.1 - Animated ReaImGui progress window during recursive file search
  # v1.0 - Initial Release
 * To Do:
  # 
]]


---------------------------------
---------- USER CONFIG ----------
---------------------------------

-- FRAME_BUDGET_MS: how many milliseconds of search work to do per frame.
-- At 30fps a frame is ~33ms, so 20ms leaves ~13ms for ImGui drawing.
-- Raise this if you want faster searches and don't mind slightly choppier
-- animation; lower it for smoother animation at the cost of search speed.
--

local FRAME_BUDGET_MS = 100





---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
-- local time_init = reaper.time_precise()
local r = reaper
local proj = 0



-- =============================================================================
-- REIMGUI SETUP
-- ReaImGui is REAPER's Dear ImGui extension. We load it here before anything
-- else. The package.path line tells Lua where to find the imgui module.
-- =============================================================================

if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox(
    "This script requires the ReaImGui extension.\nPlease install it via ReaPack.",
    "Missing Dependency", 0
  )
  return
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'


-- =============================================================================
-- EXTSTATE CONSTANTS
-- ExtState is REAPER's persistent key-value store — it survives between script
-- runs and even between REAPER restarts. We give it a unique "section" name
-- (the first argument) so it doesn't clash with other scripts.
-- =============================================================================

local EXT_SECTION = "jrope_WavToFlac"
local EXT_KEY_DIR = "lastSearchDir"


-- =============================================================================
-- STATE TABLE
-- All shared state lives here so it persists across defer frames. Local
-- variables inside functions disappear when the function returns — state in
-- this table does not.
--
-- PHASE FLOW:
--   "scan"  → examine every item/take; relink easy wins; queue the rest
--   "ask_search" → prompt user whether to do a recursive search
--   "searching"  → coroutine-driven directory walk, one yield per subdir
--   "finalize"   → select items, rebuild peaks, show results dialog
--   "done"       → script is finished; loop() will not re-defer
-- =============================================================================

local state = {
  phase = "scan",

  -- Project scan counters
  project          = 0,
  itemCount        = 0,
  relinkedCount    = 0,
  unavailableCount = 0,
  takeNamesUpdated = 0,
  notFoundCount    = 0,

  -- Collections built during scan
  missingFiles  = {},  -- {take, name, path, item} for each WAV not found nearby
  relinkedItems = {},  -- item handles for successfully relinked takes

  -- Search phase state
  searchDir        = nil,
  searchQueue      = {},  -- {targetName, fileInfo} one entry per missing file
  searchQueueIndex = 1,   -- which queue entry we are currently working on
  foundInSearch    = 0,

  -- Coroutine handle for the active file search.
  -- A coroutine is a function that can pause itself mid-execution and hand
  -- control back to the caller, then be resumed exactly where it left off.
  -- We use this so the directory walk can yield between subdirectories,
  -- giving the ImGui window a chance to repaint on every frame.
  searchCoroutine = nil,

  -- ImGui state
  ctx         = nil,
  windowOpen  = true,
  statusLabel = "Scanning project...",
  currentFile = "",

  -- Progress bar value.
  -- During scan/indeterminate phases: negative (drives the animated bounce bar).
  -- During searching phase: 0.0–1.0 (drives a real percentage fill bar).
  progressValue = -1.0,
}





---------------------------------
----------- FUNCTIONS -----------
---------------------------------



-- =============================================================================
-- HELPER: relinkTake
-- Swaps a take's source file to a new path and renames the take if it ends
-- with .wav. Extracted into one function so both the "found nearby" and
-- "found by search" code paths behave identically.
-- =============================================================================

local function relinkTake(take, newFilename, item)
  local takeName = reaper.GetTakeName(take)

  reaper.BR_SetTakeSourceFromFile(take, newFilename, false)
  state.relinkedCount = state.relinkedCount + 1
  table.insert(state.relinkedItems, item)

  if takeName:lower():match("%.wav$") then
    local newTakeName = takeName:sub(1, -5) .. ".flac"
    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", newTakeName, true)
    state.takeNamesUpdated = state.takeNamesUpdated + 1
  end
end


-- =============================================================================
-- HELPER: scanProject
-- Walks every item/take once. WAVs with a FLAC right beside them are relinked
-- immediately. WAVs that need a broader search go into state.missingFiles.
-- This runs synchronously — it's only file_exists() calls, so very fast.
-- =============================================================================

local function scanProject()
  state.itemCount = reaper.CountMediaItems(state.project)

  for i = 0, state.itemCount - 1 do
    local item      = reaper.GetMediaItem(state.project, i)
    local takeCount = reaper.CountTakes(item)

    for j = 0, takeCount - 1 do
      local take = reaper.GetTake(item, j)
      if take then
        local pcm_source  = reaper.GetMediaItemTake_Source(take)
        local source_type = reaper.GetMediaSourceType(pcm_source, "")

        if source_type == "WAVE" or source_type == "WAVPACK" or source_type == "wave" then
          local filename = reaper.GetMediaSourceFileName(pcm_source, "")

          if not reaper.file_exists(filename) and filename:lower():sub(-4) == ".wav" then
            state.unavailableCount = state.unavailableCount + 1

            local newFilename = filename:sub(1, -5) .. ".flac"

            if reaper.file_exists(newFilename) then
              relinkTake(take, newFilename, item)
            else
              local filenameBase = filename:match("([^/\\]+)%.wav$")
              if filenameBase then
                table.insert(state.missingFiles, {
                  take = take,
                  name = filenameBase,
                  path = filename,
                  item = item,
                })
                state.notFoundCount = state.notFoundCount + 1
              end
            end
          end
        end
      end
    end
  end
end


-- =============================================================================
-- HELPER: getSearchDirectory
-- Asks the user to pick a directory. Uses the native OS folder picker from
-- JS_ReaScriptAPI if it is installed, otherwise falls back to a text input box.
-- Also pre-fills with the last directory used (loaded from ExtState).
--
-- Returns the chosen path string, or nil if the user cancelled.
-- =============================================================================

local function getSearchDirectory()
  -- Load the last-used directory from persistent storage.
  -- GetExtState returns an empty string if the key has never been set.
  local lastDir = reaper.GetExtState(EXT_SECTION, EXT_KEY_DIR)

  -- JS_Dialog_BrowseForFolder is part of the optional js_ReaScriptAPI extension.
  -- We check for it at runtime rather than requiring it, so the script still
  -- works without it — just with a less polished UI.
  if reaper.JS_Dialog_BrowseForFolder then
    -- Third argument is the starting directory — pass lastDir so the picker
    -- opens in the same place the user chose last time.
    local retval, folder = reaper.JS_Dialog_BrowseForFolder(
      "Select directory to search for FLAC files", lastDir
    )
    if retval == 1 and folder and folder ~= "" then
      return folder
    else
      return nil  -- User cancelled the native picker
    end
  else
    -- Fallback: text input dialog with lastDir as the default value.
    local ok, inputDir = reaper.GetUserInputs(
      "Enter Directory Path to Search", 1,
      "Search Directory (no JS_API installed):,extrawidth=200",
      lastDir
    )
    if ok and inputDir ~= "" then
      return inputDir
    else
      return nil
    end
  end
end


-- =============================================================================
-- HELPER: makeSearchCoroutine
-- Returns a new coroutine that performs a recursive directory search for ONE
-- specific file (targetName) under baseDir.
--
-- WHY A COROUTINE?
-- A normal recursive function runs to completion without any way to pause.
-- A coroutine can call coroutine.yield() to suspend itself, returning control
-- to whoever called coroutine.resume(). The coroutine remembers exactly where
-- it was — all local variables, the call stack, everything — and picks up
-- from there on the next resume().
--
-- In our loop(), we resume the coroutine once per defer frame. Each time it
-- either yields (more directories to check) or returns (search is done). This
-- gives ImGui a repaint opportunity between every subdirectory visited, making
-- the progress bar animate smoothly even during a deep search.
--
-- HOW THE COROUTINE COMMUNICATES RESULTS:
-- coroutine.yield() and the final return both pass values back to the caller
-- via coroutine.resume(). We use a simple convention:
--   yield(false)  → "still searching, no result yet"
--   return path   → "found it at this path" (path may be nil = not found)
-- =============================================================================

local function makeSearchCoroutine(baseDir, targetName)
  return coroutine.create(function()

    -- Inner recursive function. This can call itself for subdirectories.
    -- It lives inside the coroutine so it shares the coroutine's execution
    -- context and can yield from any depth in the call stack.
    local function searchDir(dir)
      -- Normalise the path separator
      if dir:sub(-1) ~= "/" and dir:sub(-1) ~= "\\" then
        dir = dir .. "/"
      end

      -- Check every file in this directory first
      local i = 0
      while true do
        local fileName = reaper.EnumerateFiles(dir, i)
        if not fileName then break end

        if fileName:lower() == targetName:lower() then
          return dir .. fileName  -- found — return the full path
        end
        i = i + 1
      end

      -- Recurse into subdirectories.
      -- After finishing each subdirectory we yield so the caller gets a
      -- repaint frame before we move on to the next one.
      local j = 0
      while true do
        local subDirName = reaper.EnumerateSubdirectories(dir, j)
        if not subDirName then break end

        local found = searchDir(dir .. subDirName)
        if found then return found end

        -- Yield after each subdirectory — this is the key pause point.
        -- false signals "still searching, haven't found it yet".
        coroutine.yield(false)

        j = j + 1
      end

      return nil  -- not found in this directory or any of its children
    end

    -- Start the search and return the result (found path or nil)
    local result = searchDir(baseDir)
    return result

  end)
end


-- =============================================================================
-- HELPER: buildSearchQueue
-- Converts state.missingFiles into state.searchQueue (one entry per file)
-- and resets the queue index and running counters.
-- =============================================================================

local function buildSearchQueue()
  state.searchQueue      = {}
  state.searchQueueIndex = 1
  state.foundInSearch    = 0

  for _, fileInfo in ipairs(state.missingFiles) do
    table.insert(state.searchQueue, {
      targetName = fileInfo.name .. ".flac",
      fileInfo   = fileInfo,
    })
  end
end


-- =============================================================================
-- HELPER: advanceSearch
-- Called once per defer frame during the "searching" phase.
-- Runs as many coroutine steps as possible within a time budget, then returns
-- so the UI can repaint. This keeps search speed close to the non-coroutine
-- original while still allowing animation frames between bursts.
--
-- Uses FRAME_BUDGET_MS to balance ImGui smoothness and search speed.
--
-- Returns true if there is still more work to do, false when all files done.
-- =============================================================================



local function advanceSearch()
  local totalFiles  = #state.searchQueue
  local deadline    = reaper.time_precise() + FRAME_BUDGET_MS / 1000.0

  -- Run as many coroutine steps as we can before the deadline
  repeat

    -- If there's no active coroutine, start one for the current queue entry
    if not state.searchCoroutine then
      local entry = state.searchQueue[state.searchQueueIndex]
      if not entry then
        -- Queue exhausted
        state.notFoundCount = state.notFoundCount - state.foundInSearch
        state.progressValue = 1.0
        return false
      end

      state.currentFile     = entry.targetName
      state.searchCoroutine = makeSearchCoroutine(state.searchDir, entry.targetName)
    end

    -- Resume the coroutine for one step (one subdirectory visited).
    -- coroutine.resume() returns:
    --   ok    = true if the coroutine yielded or returned normally
    --   value = what the coroutine passed to yield(), or its return value
    local ok, value = coroutine.resume(state.searchCoroutine)

    if not ok then
      -- Coroutine hit a Lua error — log it and move to the next file
      reaper.ShowConsoleMsg("Search coroutine error: " .. tostring(value) .. "\n")
      state.searchCoroutine  = nil
      state.searchQueueIndex = state.searchQueueIndex + 1

    elseif coroutine.status(state.searchCoroutine) == "dead" then
      -- Coroutine returned — search for this file is complete.
      -- 'value' is the found path, or nil if not found anywhere.
      local entry = state.searchQueue[state.searchQueueIndex]
      if value and entry then
        relinkTake(entry.fileInfo.take, value, entry.fileInfo.item)
        state.foundInSearch = state.foundInSearch + 1
      end

      state.searchCoroutine  = nil
      state.searchQueueIndex = state.searchQueueIndex + 1
    end
    -- else: coroutine yielded — still searching this file, loop again

  until reaper.time_precise() >= deadline

  -- Update the progress bar fraction based on how far through the queue we are
  if totalFiles > 0 then
    state.progressValue = math.min(1.0, (state.searchQueueIndex - 1) / totalFiles)
  else
    state.progressValue = 1.0
  end

  return state.searchQueueIndex <= totalFiles
end


-- =============================================================================
-- HELPER: finalizeResults
-- Selects all relinked items, rebuilds peaks, shows the summary dialog, and
-- saves the search directory to ExtState for next time.
-- =============================================================================

local function finalizeResults()
  for _, item in ipairs(state.relinkedItems) do
    reaper.SetMediaItemSelected(item, true)
  end

  if #state.relinkedItems > 0 then
    reaper.Main_OnCommand(40047, 0) -- Peaks: Rebuild peaks for selected items
  end

  reaper.UpdateArrange()

  -- Save the search directory for next time, but only if we actually used one.
  if state.searchDir then
    reaper.SetExtState(EXT_SECTION, EXT_KEY_DIR, state.searchDir, true)
    -- The third argument `true` means "persist to disk" — it survives REAPER restarts.
  end

  local message = state.unavailableCount .. " offline WAV file(s).\n"
               .. state.relinkedCount    .. " file(s) successfully linked to FLAC.\n"
               .. state.notFoundCount    .. " file(s) could not be found."

  reaper.ShowMessageBox(message, "WAV to FLAC Media Relinker - Results", 0)
  reaper.Main_OnCommand(40289, 0) -- Unselect all items
end


-- =============================================================================
-- IMGUI LOOP
-- Called once per REAPER frame via reaper.defer(). Draws the progress window
-- and advances the script state machine by one step.
--
-- PROGRESS BAR BEHAVIOUR:
--   "scan" phase         → indeterminate bounce (negative time value)
--   "searching" phase    → real 0.0–1.0 fill, updates as each file completes
--   "finalize" phase     → bar stays at 1.0 briefly before window closes
-- =============================================================================

local function loop()
  -- NoResize prevents the user from dragging the window smaller than our
  -- intended width. We drop AlwaysAutoResize because it caused a feedback
  -- loop: the bar width is derived from GetContentRegionAvail(), so as the
  -- window auto-shrunk toward the longest text string, the bar shrank with
  -- it, which made the window shrink further.
  --
  -- Instead we pin the WIDTH to a fixed value on every frame using
  -- Cond_Always, while leaving the HEIGHT as 0 so ImGui still auto-fits
  -- it vertically to match however many lines of text are visible.
  local windowFlags = ImGui.WindowFlags_NoCollapse
                    | ImGui.WindowFlags_NoResize
                    | ImGui.WindowFlags_NoSavedSettings

  ImGui.SetNextWindowSize(state.ctx, 400, 0, ImGui.Cond_Always)

  local visible, open = ImGui.Begin(state.ctx, "WAV → FLAC Relinker", true, windowFlags)
  state.windowOpen = open

  if visible then
    ImGui.Text(state.ctx, state.statusLabel)

    -- ── Custom progress bar drawn via DrawList API ────────────────────────────
    --
    -- WHY NOT ImGui.ProgressBar()?
    -- The standard ProgressBar widget takes (fraction, width, height). Passing
    -- -1 as width tells Dear ImGui to fill available width — BUT when we also
    -- pass a negative fraction (for the indeterminate/bounce mode), Dear ImGui
    -- in this version of ReaImGui conflates the negative width with the negative
    -- fraction and grows the bar off-screen. Drawing manually avoids this entirely
    -- and also lets us render the exact two-zone look you described:
    --   LEFT  → solid filled colour (real progress)
    --   RIGHT → animated diagonal stripes (work still in progress)
    --
    -- HOW DRAWLIST WORKS:
    -- ImGui.GetWindowDrawList() returns a drawing canvas attached to the current
    -- window. Anything we add to it (rectangles, lines, etc.) renders behind the
    -- window's widgets but inside its border. Coordinates are in screen pixels.
    -- ImGui.GetCursorScreenPos() tells us where the next widget would appear,
    -- so we use that as the top-left corner of our bar.
    -- After drawing we call ImGui.Dummy() to advance the layout cursor by the
    -- bar's height, so the next widget (the filename text) appears below it
    -- rather than overlapping.

    local BAR_HEIGHT  = 20          -- pixel height of the whole bar
    local BAR_PADDING = 4           -- gap between bar and window edge (each side)
    local STRIPE_W    = 12          -- width of each diagonal stripe cell
    local STRIPE_SPEED = 40         -- pixels per second the stripes scroll

    -- Colours as 0xRRGGBBAA integers (ImGui DrawList uses this format)
    local COL_BG      = 0x333333ff  -- dark grey background / empty track
    local COL_FILL    = 0x4da6ffff  -- solid blue fill (completed portion)
    local COL_STRIPE1 = 0x555555ff  -- darker stripe band
    local COL_STRIPE2 = 0x3d3d3dff  -- lighter stripe band
    local COL_BORDER  = 0x888888ff  -- thin border around the whole bar

    local draw_list = ImGui.GetWindowDrawList(state.ctx)

    -- Get the pixel coordinates where the bar should start
    local bx, by    = ImGui.GetCursorScreenPos(state.ctx)
    -- Get the full content width of the window so the bar stretches edge-to-edge
    local avail_w   = ImGui.GetContentRegionAvail(state.ctx)
    local bar_w     = avail_w - BAR_PADDING * 2
    local x0        = bx + BAR_PADDING
    local y0        = by
    local x1        = x0 + bar_w
    local y1        = y0 + BAR_HEIGHT

    -- 1. Draw the background track
    ImGui.DrawList_AddRectFilled(draw_list, x0, y0, x1, y1, COL_BG)

    -- 2. Determine the split point between solid fill and stripes.
    --    During scan phase progressValue is negative (indeterminate) so we
    --    treat the whole bar as the stripe zone.
    local fill_frac = math.max(0.0, math.min(1.0, state.progressValue))
    local fill_x    = x0 + bar_w * fill_frac   -- pixel x where stripes begin

    -- 3. Draw solid fill on the left
    if fill_x > x0 then
      ImGui.DrawList_AddRectFilled(draw_list, x0, y0, fill_x, y1, COL_FILL)
    end

    -- 4. Draw animated diagonal stripes on the right (the "still working" zone).
    --    We clip the stripe drawing to the right portion of the bar so they never
    --    bleed over the solid fill.
    --
    --    TECHNIQUE: draw a series of parallelograms (pairs of triangles) that
    --    scroll leftward over time. The scroll offset is derived from wall-clock
    --    time so the animation runs at a constant speed regardless of frame rate.
    --    ImGui.DrawList_PushClipRect() restricts all drawing to a rectangle,
    --    then we pop it afterward to restore normal clipping.
    if fill_x < x1 then
      -- Push a clip rect so stripes can't draw outside the right zone
      ImGui.DrawList_PushClipRect(draw_list, fill_x, y0, x1, y1, true)

      local t      = ImGui.GetTime(state.ctx)
      local offset = (t * STRIPE_SPEED) % (STRIPE_W * 2)  -- scroll offset in px

      -- Draw enough stripe columns to cover the full bar width plus overflow
      -- so there are no gaps at the edges when scrolling
      local stripe_x = x0 - offset - STRIPE_W * 2
      while stripe_x < x1 + STRIPE_W * 2 do
        -- Each "cell" is a parallelogram: top-left corner offset by BAR_HEIGHT
        -- to the right compared to bottom-left, giving the diagonal effect.
        local slant = BAR_HEIGHT   -- horizontal slant amount (= height → 45°)
        -- Four corners of the filled stripe band:
        --   top-left, top-right, bottom-right, bottom-left
        ImGui.DrawList_AddQuadFilled(draw_list,
          stripe_x + slant,        y0,           -- top-left
          stripe_x + STRIPE_W + slant, y0,        -- top-right
          stripe_x + STRIPE_W,     y1,            -- bottom-right
          stripe_x,                y1,            -- bottom-left
          COL_STRIPE1
        )
        -- The gap between stripes is left as COL_STRIPE2 — draw it explicitly
        ImGui.DrawList_AddQuadFilled(draw_list,
          stripe_x + STRIPE_W + slant, y0,
          stripe_x + STRIPE_W * 2 + slant, y0,
          stripe_x + STRIPE_W * 2, y1,
          stripe_x + STRIPE_W,    y1,
          COL_STRIPE2
        )
        stripe_x = stripe_x + STRIPE_W * 2
      end

      ImGui.DrawList_PopClipRect(draw_list)
    end

    -- 5. Draw border over everything
    ImGui.DrawList_AddRect(draw_list, x0, y0, x1, y1, COL_BORDER)

    -- 6. Advance the layout cursor past the bar so the next Text() goes below it
    ImGui.Dummy(state.ctx, bar_w, BAR_HEIGHT)

    -- 7. Percentage label (only meaningful once we are in real 0-100% mode)
    if state.progressValue >= 0.0 then
      local pct = math.floor(fill_frac * 100)
      ImGui.Text(state.ctx, pct .. "% complete ("
        .. math.max(0, state.searchQueueIndex - 1)
        .. " of " .. #state.searchQueue .. " files)")
    end

    -- Show the current filename being searched
    if state.currentFile ~= "" then
      ImGui.Text(state.ctx, "Looking for: " .. state.currentFile)
    end

    ImGui.End(state.ctx)
  end

  -- ── State machine: advance one step per frame ────────────────────────────

  if state.phase == "scan" then
    -- Keep progressValue negative during scan so the drawing code renders
    -- the full-width stripe zone (fill_frac clamps to 0.0, no solid fill).
    state.progressValue = -1.0
    scanProject()

    if #state.missingFiles > 0 then
      state.phase = "ask_search"
    else
      state.phase       = "finalize"
      state.windowOpen  = false
    end

  elseif state.phase == "ask_search" then
    -- Close the progress window before showing blocking dialogs.
    -- We set windowOpen = false here, then defer the dialogs so the window
    -- actually closes before we block the UI thread.
    state.windowOpen = false

    reaper.defer(function()
      local searchMsg = state.notFoundCount
        .. " file(s) could not be linked in their original locations.\n"
        .. "Would you like to search a directory?"
      local searchConfirm = reaper.ShowMessageBox(searchMsg, "Search for Missing Files", 4)

      if searchConfirm == 6 then  -- user clicked Yes
        local chosenDir = getSearchDirectory()

        if chosenDir then
          state.searchDir   = chosenDir
          state.statusLabel = "Searching for "
                            .. #state.missingFiles .. " file(s)..."
          buildSearchQueue()

          -- Open a fresh ImGui context and re-enter the loop
          state.ctx           = ImGui.CreateContext("WAV→FLAC Progress")
          state.windowOpen    = true
          state.progressValue = 0.0  -- start the real bar at 0%
          state.phase         = "searching"
          reaper.defer(loop)
          return
        end
      end

      -- User said No, or cancelled the folder picker
      state.phase = "finalize"
      finalizeResults()
      reaper.Undo_EndBlock("Relink WAV to FLAC and Update Take Names", -1)
    end)
    return  -- Stop this iteration; the deferred function takes over

  elseif state.phase == "searching" then
    state.statusLabel = "Searching for FLAC replacements..."

    local moreWork = advanceSearch()

    if not moreWork then
      -- Search is done. Move to "complete" — a single frame whose only job
      -- is to let ImGui render the bar at 100% before anything else happens.
      -- We do NOT close the window or call finalizeResults() here.
      state.phase         = "complete"
      state.progressValue = 1.0
      state.currentFile   = ""
      state.statusLabel   = "Complete!"
    end

  elseif state.phase == "complete" then
    -- The bar has now been drawn at 100% for one full frame.
    -- Move to "finalize" so the next frame closes the window.
    state.phase = "finalize"

  elseif state.phase == "finalize" then
    state.windowOpen = false

  end

  -- ── Continue or stop ────────────────────────────────────────────────────

  if state.windowOpen then
    reaper.defer(loop)
  else
    if state.phase == "finalize" then
      state.phase = "done"
      finalizeResults()
      reaper.Undo_EndBlock("Relink WAV to FLAC and Update Take Names", -1)
    end
  end
end


-- =============================================================================
-- ENTRY POINT
-- The initial confirmation dialog is shown synchronously (before the ImGui
-- window opens), so blocking here is fine — there's nothing yet to animate.
-- After confirmation we set up state and kick off the defer loop.
-- =============================================================================

reaper.Undo_BeginBlock()

local confirm = reaper.ShowMessageBox(
  "This script will relink all missing WAV media to FLAC files.\n"
  .. "Take names will also be updated to reflect the new extension.\nContinue?",
  "WAV to FLAC Media Relinker", 4
)

if confirm ~= 6 then
  reaper.Undo_EndBlock("Relink WAV to FLAC and Update Take Names", -1)
  return
end

reaper.Main_OnCommand(40289, 0)  -- Unselect all items before scanning

state.ctx   = ImGui.CreateContext("WAV→FLAC Progress")
state.phase = "scan"

reaper.defer(loop)
