--[[
 * Name: Rename markers/regions from clipboard
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.2
 * Provides:
  [main] . >
 * Link: https://www.jesserope.com
 * noindex
 * About:
  # Combined Acenden and Cfillion scripts
 * Changelog:
  # v1.2 - Added "Copy to clipboard" button so names can be exported, edited, then pasted back
  # v1.1 - Replaced USER CONFIG section with ImGui settings window
  # v1.0 - Initial Release
 * To Do:
  #


]]



---------------------------------
---------- USER CONFIG ----------
---------------------------------

ENABLE_DEBUG_LOG = false  -- set to true to print debug output to the REAPER console


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local UNDO_STATE_MARKERS = 4

-- ImGui context
local ctx = reaper.ImGui_CreateContext(SCRIPT_NAME)


---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Load my common functions
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")


-- -------------------------------------------------------
-- Check if a given marker/region should be processed
-- based on the user's chosen type and time selection options
-- -------------------------------------------------------
local function should_process(isrgn, pos, settings, time_sel_start, time_sel_end)

  -- Check if the type (marker vs region) matches the user's choice
  local type_matches = false

  if settings.process_type == 0 and not isrgn then
    -- "Markers" selected, and this item is a marker (not a region)
    type_matches = true
  elseif settings.process_type == 1 and isrgn then
    -- "Regions" selected, and this item is a region
    type_matches = true
  elseif settings.process_type == 2 then
    -- "Both" selected
    type_matches = true
  end

  if not type_matches then return false end

  -- Check if within time selection (if that option is enabled)
  if settings.only_in_time_selection then
    return pos >= time_sel_start and pos <= time_sel_end
  end

  return true
end


-- -------------------------------------------------------
-- Resolve the time selection bounds, if that option is on.
-- Returns start, end, ok — ok is false (and a message box is shown)
-- when the option is enabled but there is no time selection.
-- -------------------------------------------------------
local function get_time_selection(settings)

  if not settings.only_in_time_selection then return 0, 0, true end

  local time_sel_start, time_sel_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

  if time_sel_end <= time_sel_start then
    reaper.ShowMessageBox("No time selection found!", "Error", 0)
    return 0, 0, false
  end

  Log("Time selection:", time_sel_start, "to", time_sel_end)
  return time_sel_start, time_sel_end, true
end


-- -------------------------------------------------------
-- Copy the names of the matching markers/regions to the
-- clipboard, one per line, in project (timeline) order.
-- Runs when the user clicks "Copy names to clipboard".
-- Returns a short status string for the GUI.
-- -------------------------------------------------------
local function run_copy(settings)

  local retval, num_markers, num_regions = reaper.CountProjectMarkers(0)
  Log("Copy: found", num_markers, "markers and", num_regions, "regions")

  if retval < 1 then
    reaper.ShowMessageBox("No markers or regions found in the project.", "Nothing to do", 0)
    return "Nothing to copy."
  end

  local time_sel_start, time_sel_end, ok = get_time_selection(settings)
  if not ok then return "No time selection." end

  -- Collect the names of everything that passes the filter
  local names = {}

  for i = 0, retval - 1 do
    local retval2, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)

    if should_process(isrgn, pos, settings, time_sel_start, time_sel_end) then
      names[#names + 1] = name
      Log("Copy: including", isrgn and "region" or "marker", markrgnindexnumber, "->", name)
    end
  end

  if #names < 1 then
    reaper.ShowMessageBox("No markers or regions matched the current settings.", "Nothing to do", 0)
    return "Nothing matched."
  end

  reaper.CF_SetClipboard(table.concat(names, "\n"))
  Log("Copy: wrote", #names, "names to the clipboard")

  return ("Copied %d name%s to the clipboard."):format(#names, #names == 1 and "" or "s")
end


-- -------------------------------------------------------
-- Core rename logic — runs after the user clicks "Run"
-- -------------------------------------------------------
local function run_rename(settings)

  local clipboard = reaper.CF_GetClipboard('')

  -- Guard: clipboard must have content
  if clipboard:len() < 1 then
    reaper.ShowMessageBox("Clipboard is empty! Copy your list of names first.", "Nothing to do", 0)
    return
  end

  -- Guard: project must have markers or regions
  local retval, num_markers, num_regions = reaper.CountProjectMarkers(0)
  if retval < 1 then
    reaper.ShowMessageBox("No markers or regions found in the project.", "Nothing to do", 0)
    return
  end

  -- Handle time selection requirement
  local time_sel_start, time_sel_end, ok = get_time_selection(settings)
  if not ok then return end

  -- Begin undo block here, just before making changes
  --reaper.Undo_BeginBlock()

  local index = 0

  -- Loop through each line in the clipboard
  for line in clipboard:gmatch("([^\r\n]*)[\r\n]*") do

    -- Find the next marker/region that matches our criteria
    local found = false

    for i = index, retval - 1 do
      local retval2, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)

      if should_process(isrgn, pos, settings, time_sel_start, time_sel_end) then

        -- Rename the marker or region
        if isrgn then
          reaper.SetProjectMarker(markrgnindexnumber, true, pos, rgnend, line)
        else
          reaper.SetProjectMarker(markrgnindexnumber, false, pos, 0, line)
        end

        Log("Rename:", isrgn and "region" or "marker", markrgnindexnumber, "->", line)

        index = i + 1
        found = true
        break
      end
    end

    -- Stop if we've run out of matching markers/regions
    if not found then break end
  end

  --reaper.Undo_EndBlock(SCRIPT_NAME, UNDO_STATE_MARKERS)
end


-- -------------------------------------------------------
-- ImGui settings window
-- Draws the GUI each frame until the user clicks Run or Cancel
-- -------------------------------------------------------

-- State table — holds the user's current selections
-- process_type: 0=markers, 1=regions, 2=both
local settings = {
  process_type            = 0,
  only_in_time_selection  = true,
}

-- Tracks whether the window should stay open
local window_open = true

-- Tracks whether the user clicked Run (so we execute after the GUI closes)
local should_run = false

-- Last action feedback, shown at the bottom of the window
local status_message = ""


local function draw_gui()

  -- Set a fixed window size so it doesn't collapse weirdly
  reaper.ImGui_SetNextWindowSize(ctx, 340, 250, reaper.ImGui_Cond_FirstUseEver())

  -- Begin the window; rv is false if the window is collapsed
  local rv, open = reaper.ImGui_Begin(ctx, "Rename from Clipboard - Settings", true)

  -- The user clicked the X button to close
  if not open then
    window_open = false
    reaper.ImGui_End(ctx)
    return
  end

  if rv then

    -- ---- Section: Process Type ----
    reaper.ImGui_Text(ctx, "What to rename:")
    reaper.ImGui_Spacing(ctx)

    -- RadioButtonEx(ctx, label, current_value, button_value)
    -- Returns the (possibly updated) current_value
    local changed
    changed, settings.process_type = reaper.ImGui_RadioButtonEx(ctx, "Markers only",  settings.process_type, 0)
    changed, settings.process_type = reaper.ImGui_RadioButtonEx(ctx, "Regions only",  settings.process_type, 1)
    changed, settings.process_type = reaper.ImGui_RadioButtonEx(ctx, "Both",          settings.process_type, 2)

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- ---- Section: Time Selection ----
    -- Checkbox returns (changed, new_value)
    local _, new_val = reaper.ImGui_Checkbox(
      ctx,
      "Only within time selection",
      settings.only_in_time_selection
    )
    settings.only_in_time_selection = new_val

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- ---- Buttons ----
    -- Copy runs immediately and leaves the window open, so the user can
    -- copy, edit the list in a text editor, then come back and hit Run.
    if reaper.ImGui_Button(ctx, "Copy names to clipboard") then
      status_message = run_copy(settings)
    end

    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_Button(ctx, "Run") then
      should_run   = true
      window_open  = false  -- close the GUI after clicking Run
    end

    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, "Cancel") then
      window_open = false
    end

    -- ---- Status line ----
    if status_message ~= "" then
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Text(ctx, status_message)
    end

  end -- if rv

  reaper.ImGui_End(ctx)
end


-- -------------------------------------------------------
-- Main deferred loop — keeps the GUI alive across frames
-- -------------------------------------------------------
local function gui_loop()

  if window_open then
    draw_gui()
    reaper.defer(gui_loop)   -- keep looping until the window closes

  else
    -- Window has been closed — run the rename logic if the user clicked "Run"
    if should_run then

      reaper.Undo_BeginBlock()
      run_rename(settings)
      reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, -1)
      reaper.UpdateArrange()
    end
  end

end


---------------------------------
-------------- MAIN -------------
---------------------------------

-- Kick off the deferred GUI loop
-- Note: with an ImGui-driven script, we do NOT wrap everything in
-- Undo_BeginBlock/EndBlock here at the top level. Instead, the undo
-- block is opened and closed inside run_rename(), only when work is
-- actually performed.
reaper.defer(gui_loop)