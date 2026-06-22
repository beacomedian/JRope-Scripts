--[[
 * Name: Recursively remove Offline and Bypassed FX from Selected Tracks and their Containers
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.2
 * Provides:
    [main] . >
 * About:
    # Removes every offline or bypassed FX from the selected tracks, descending
    # recursively into FX containers (and containers nested inside containers,
    # to any depth). A container that is itself offline/bypassed is removed too.
    # Afterwards, if the cleanup left any online containers empty, the script
    # asks whether to remove those (cascading bottom-up) as well.
 * Changelog:
    # Initial working release. Fixed container addressing (last-slot bug) and
    # added correct depth-aware recursion for nested containers. Added optional
    # prompt to remove containers left empty by the cleanup.
 * To Do:
    #
]]

---------------------------------
---------- USER CONFIG ----------
---------------------------------

ENABLE_DEBUG_LOG = false  -- set to true to print debug output to the REAPER console

local MAX_DEPTH = 20      -- safety limit against runaway recursion

---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
local r = reaper
local proj = 0

local CONTAINER_BASE = 0x2000000  -- REAPER 7 container-FX address offset

---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Load my common functions
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")

-- Is the FX at this (already-resolved) address a container?
local function isContainer(track, fx_address)
  local ok, fx_type = r.TrackFX_GetNamedConfigParm(track, fx_address, "fx_type")
  return ok and fx_type == "Container"
end

-- Number of direct child FX inside the container at this address (nil if not a container).
local function getContainerCount(track, fx_address)
  local ok, cnt = r.TrackFX_GetNamedConfigParm(track, fx_address, "container_count")
  if not ok then return nil end
  return tonumber(cnt) or 0
end

-- Should this FX be removed?
local function shouldRemove(track, fx_address)
  return r.TrackFX_GetOffline(track, fx_address) or not r.TrackFX_GetEnabled(track, fx_address)
end

--[[
  Recursively remove offline/bypassed FX from inside a container.

  REAPER 7 container addressing (see Sexan ParanormalFX / cfillion):
      child_address = CONTAINER_BASE + container_id + diff * i      (i is 1-based)
      diff = (depth == 0) and (parent_count + 1)
                          or  (parent_count + 1) * parent_diff

  where `container_id` is the container's *raw* id (the 1-based track slot at
  the top level, or the raw child id when nested), `parent_count` is the number
  of FX in the enclosing scope (track FX count at depth 0, else the parent
  container's child count), and `parent_diff` is the enclosing container's diff.

  We iterate children high->low so deleting one never shifts the index of a
  not-yet-visited (lower) child, and we re-read the live counts every step so
  the addressing stays correct as items disappear.
]]
local function removeInContainer(track, container_id, parent_count, parent_diff, depth, indent)
  indent = indent or "  "

  if depth > MAX_DEPTH then
    Log("%sWARNING: max recursion depth (%d) reached\n", indent, MAX_DEPTH)
    return 0
  end

  local removed = 0
  local i = getContainerCount(track, CONTAINER_BASE + container_id)
  if not i or i <= 0 then
    Log("%sEmpty or non-container (count=%s)\n", indent, tostring(i))
    return 0
  end

  Log("%sProcessing container (depth %d) with %d item(s)\n", indent, depth, i)

  while i >= 1 do
    -- Deleting a *direct* child shrinks this container's count; re-read it.
    local count = getContainerCount(track, CONTAINER_BASE + container_id) or 0
    if i > count then i = count end
    if i < 1 then break end

    local diff = (depth == 0) and (parent_count + 1) or (parent_count + 1) * parent_diff
    local fx_id = container_id + diff * i
    local fx_address = CONTAINER_BASE + fx_id

    local ok_name, name = r.TrackFX_GetFXName(track, fx_address, "")
    if not ok_name then
      Log("%s  WARNING: cannot access child %d (addr %d)\n", indent, i, fx_address)
      i = i - 1
      goto continue
    end

    -- Descend into nested containers first, passing this container's *current*
    -- child count and diff so the nested addressing resolves correctly.
    if isContainer(track, fx_address) then
      Log("%s  Child %d '%s' is a nested container\n", indent, i, name)
      removed = removed + removeInContainer(track, fx_id, count, diff, depth + 1, indent .. "  ")
    end

    if shouldRemove(track, fx_address) then
      Log("%s  REMOVING child %d '%s'\n", indent, i, name)
      r.TrackFX_Delete(track, fx_address)
      removed = removed + 1
    else
      Log("%s  Keeping child %d '%s'\n", indent, i, name)
    end

    i = i - 1
    ::continue::
  end

  return removed
end

local function processTrack(track)
  local ok_name, track_name = r.GetTrackName(track, "")
  Log("\n=== Track: %s ===\n", ok_name and track_name or "Unnamed Track")

  local removed = 0
  -- Walk top-level FX high->low. Re-read the count each step because deleting a
  -- top-level FX also changes the diff used to address container children below.
  local fx = r.TrackFX_GetCount(track) - 1
  while fx >= 0 do
    local count = r.TrackFX_GetCount(track)
    if fx > count - 1 then fx = count - 1 end
    if fx < 0 then break end

    local ok_name2, fx_name = r.TrackFX_GetFXName(track, fx, "")
    fx_name = ok_name2 and fx_name or "Unknown FX"

    if isContainer(track, fx) then
      -- Top-level container: raw id is the 1-based slot (fx + 1),
      -- parent scope is the track itself (parent_count = track FX count).
      Log("Top-level container at slot %d ('%s')\n", fx, fx_name)
      removed = removed + removeInContainer(track, fx + 1, count, 0, 0, "  ")
    end

    if shouldRemove(track, fx) then
      Log("REMOVING top-level FX %d ('%s')\n", fx, fx_name)
      r.TrackFX_Delete(track, fx)
      removed = removed + 1
    end

    fx = fx - 1
  end

  return removed
end

--[[
  Read-only count of empty containers that the cleanup left behind, accounting
  for cascades: a container whose only remaining children are themselves
  empty containers will also become empty once they are pruned.

  Returns (pruned, remaining) for the given container:
    pruned    = how many containers at or below it would be removed,
    remaining = how many real (non-removed) children it would be left with.
  No deletions happen here, so the live addressing stays stable and we can
  iterate low->high.
]]
local function countEmptyInContainer(track, container_id, parent_count, parent_diff, depth)
  if depth > MAX_DEPTH then return 0, 1 end  -- treat as non-empty; don't recurse further

  local count = getContainerCount(track, CONTAINER_BASE + container_id) or 0
  local pruned, remaining = 0, 0

  for i = 1, count do
    local diff = (depth == 0) and (parent_count + 1) or (parent_count + 1) * parent_diff
    local fx_address = CONTAINER_BASE + container_id + diff * i

    if isContainer(track, fx_address) then
      local child_pruned, child_remaining =
        countEmptyInContainer(track, container_id + diff * i, count, diff, depth + 1)
      pruned = pruned + child_pruned
      if child_remaining == 0 then
        pruned = pruned + 1   -- this child container would itself become empty
      else
        remaining = remaining + 1
      end
    else
      remaining = remaining + 1
    end
  end

  return pruned, remaining
end

local function countEmptyContainers(track)
  local total = 0
  local count = r.TrackFX_GetCount(track)
  for fx = 0, count - 1 do
    if isContainer(track, fx) then
      local child_pruned, child_remaining = countEmptyInContainer(track, fx + 1, count, 0, 0)
      total = total + child_pruned
      if child_remaining == 0 then total = total + 1 end
    end
  end
  return total
end

-- Depth-first removal of empty containers. Because children are pruned before
-- the parent is re-checked, a single pass cascades bottom-up.
local function pruneEmptyInContainer(track, container_id, parent_count, parent_diff, depth)
  if depth > MAX_DEPTH then return 0 end

  local removed = 0
  local i = getContainerCount(track, CONTAINER_BASE + container_id) or 0

  while i >= 1 do
    local count = getContainerCount(track, CONTAINER_BASE + container_id) or 0
    if i > count then i = count end
    if i < 1 then break end

    local diff = (depth == 0) and (parent_count + 1) or (parent_count + 1) * parent_diff
    local fx_id = container_id + diff * i
    local fx_address = CONTAINER_BASE + fx_id

    if isContainer(track, fx_address) then
      removed = removed + pruneEmptyInContainer(track, fx_id, count, diff, depth + 1)
      if (getContainerCount(track, fx_address) or 0) == 0 then
        local _, name = r.TrackFX_GetFXName(track, fx_address, "")
        Log("%sREMOVING empty container '%s'\n", string.rep("  ", depth + 1), name or "")
        r.TrackFX_Delete(track, fx_address)
        removed = removed + 1
      end
    end

    i = i - 1
  end

  return removed
end

local function pruneEmptyContainers(track)
  local removed = 0
  local fx = r.TrackFX_GetCount(track) - 1
  while fx >= 0 do
    local count = r.TrackFX_GetCount(track)
    if fx > count - 1 then fx = count - 1 end
    if fx < 0 then break end

    if isContainer(track, fx) then
      removed = removed + pruneEmptyInContainer(track, fx + 1, count, 0, 0)
      if (getContainerCount(track, fx) or 0) == 0 then
        local _, name = r.TrackFX_GetFXName(track, fx, "")
        Log("REMOVING empty top-level container '%s'\n", name or "")
        r.TrackFX_Delete(track, fx)
        removed = removed + 1
      end
    end

    fx = fx - 1
  end
  return removed
end

function main()
  if ENABLE_DEBUG_LOG then r.ClearConsole() end
  Log("=== Remove Offline/Bypassed FX (recursive) ===\n")

  local selected_track_count = r.CountSelectedTracks(proj)
  if selected_track_count == 0 then
    r.ShowMessageBox("No tracks selected. Please select one or more tracks.",
                     "Remove Offline/Bypassed FX", 0)
    return
  end

  local total_removed = 0
  for i = 0, selected_track_count - 1 do
    total_removed = total_removed + processTrack(r.GetSelectedTrack(proj, i))
  end
  Log("\n=== Offline/bypassed pass: removed %d FX ===\n", total_removed)

  -- Optional follow-up: offer to remove any containers the cleanup emptied out.
  local empty_count = 0
  for i = 0, selected_track_count - 1 do
    empty_count = empty_count + countEmptyContainers(r.GetSelectedTrack(proj, i))
  end

  local empties_removed = 0
  if empty_count > 0 then
    local prompt = string.format(
      "Removed %d offline and/or bypassed FX.\n\n" ..
      "%d container(s) are now empty. Remove the empty container(s) too?",
      total_removed, empty_count)
    if r.ShowMessageBox(prompt, "Remove Offline/Bypassed FX", 4) == 6 then  -- 4 = Yes/No, 6 = Yes
      for i = 0, selected_track_count - 1 do
        empties_removed = empties_removed + pruneEmptyContainers(r.GetSelectedTrack(proj, i))
      end
      Log("\n=== Empty-container pass: removed %d container(s) ===\n", empties_removed)
    end
  end

  Log("\n=== SUMMARY: %d FX + %d empty container(s) from %d track(s) ===\n",
      total_removed, empties_removed, selected_track_count)

  if total_removed == 0 and empty_count == 0 then
    r.ShowMessageBox("No offline or bypassed FX found on the selected tracks.",
                     "Remove Offline/Bypassed FX", 0)
  else
    r.ShowMessageBox(string.format(
      "Removed %d offline/bypassed FX and %d empty container(s) from %d selected track(s).",
      total_removed, empties_removed, selected_track_count), "Remove Offline/Bypassed FX", 0)
  end
end

---------------------------------
-------------- MAIN -------------
---------------------------------

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

main()

reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, -1)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
