--[[
 * Name: Recursively remove Offline and Bypassed FX from Selected Tracks and their Containers
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.3
 * Provides:
    [main] . >
 * About:
    # Removes every offline or bypassed FX from the selected tracks -- or, when
    # any media items are selected, from every take of those items instead --
    # descending recursively into FX containers (and containers nested inside
    # containers, to any depth). A container that is itself offline/bypassed is
    # removed too. Afterwards, if the cleanup left any online containers empty,
    # the script asks whether to remove those (cascading bottom-up) as well.
 * Changelog:
    # v1.3: Also operate on selected items' take FX (all takes) when any items
    #       are selected; otherwise operate on selected tracks as before. Track
    #       and take FX chains are handled through a shared host adapter.
    # v1.2: Initial working release. Fixed container addressing (last-slot bug)
    #       and added correct depth-aware recursion for nested containers. Added
    #       optional prompt to remove containers left empty by the cleanup.
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

--[[
  A "host" abstracts a single FX chain so the recursion engine below never has to
  know whether it is operating on a track's FX or a take's FX. Each host is a table
  of closures over its target object, wrapping the matching REAPER API
  (TrackFX_* / TakeFX_*). The two APIs share identical signatures and the same
  REAPER-7 container addressing, so the engine is reused unchanged.
]]
local function makeTrackHost(track)
  return {
    label = "track",
    GetCount           = function()           return r.TrackFX_GetCount(track) end,
    GetNamedConfigParm = function(addr, parm)  return r.TrackFX_GetNamedConfigParm(track, addr, parm) end,
    GetOffline         = function(addr)        return r.TrackFX_GetOffline(track, addr) end,
    GetEnabled         = function(addr)        return r.TrackFX_GetEnabled(track, addr) end,
    GetFXName          = function(addr)        return r.TrackFX_GetFXName(track, addr, "") end,
    Delete             = function(addr)        return r.TrackFX_Delete(track, addr) end,
    name               = function()
      local ok, n = r.GetTrackName(track, "")
      return ok and n or "Unnamed Track"
    end,
  }
end

local function makeTakeHost(take)
  return {
    label = "take",
    GetCount           = function()           return r.TakeFX_GetCount(take) end,
    GetNamedConfigParm = function(addr, parm)  return r.TakeFX_GetNamedConfigParm(take, addr, parm) end,
    GetOffline         = function(addr)        return r.TakeFX_GetOffline(take, addr) end,
    GetEnabled         = function(addr)        return r.TakeFX_GetEnabled(take, addr) end,
    GetFXName          = function(addr)        return r.TakeFX_GetFXName(take, addr, "") end,
    Delete             = function(addr)        return r.TakeFX_Delete(take, addr) end,
    name               = function()
      local n = r.GetTakeName(take)
      return (n and n ~= "") and n or "Unnamed Take"
    end,
  }
end

-- Is the FX at this (already-resolved) address a container?
local function isContainer(host, fx_address)
  local ok, fx_type = host.GetNamedConfigParm(fx_address, "fx_type")
  return ok and fx_type == "Container"
end

-- Number of direct child FX inside the container at this address (nil if not a container).
local function getContainerCount(host, fx_address)
  local ok, cnt = host.GetNamedConfigParm(fx_address, "container_count")
  if not ok then return nil end
  return tonumber(cnt) or 0
end

-- Should this FX be removed?
local function shouldRemove(host, fx_address)
  return host.GetOffline(fx_address) or not host.GetEnabled(fx_address)
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
local function removeInContainer(host, container_id, parent_count, parent_diff, depth, indent)
  indent = indent or "  "

  if depth > MAX_DEPTH then
    Log("%sWARNING: max recursion depth (%d) reached\n", indent, MAX_DEPTH)
    return 0
  end

  local removed = 0
  local i = getContainerCount(host, CONTAINER_BASE + container_id)
  if not i or i <= 0 then
    Log("%sEmpty or non-container (count=%s)\n", indent, tostring(i))
    return 0
  end

  Log("%sProcessing container (depth %d) with %d item(s)\n", indent, depth, i)

  while i >= 1 do
    -- Deleting a *direct* child shrinks this container's count; re-read it.
    local count = getContainerCount(host, CONTAINER_BASE + container_id) or 0
    if i > count then i = count end
    if i < 1 then break end

    local diff = (depth == 0) and (parent_count + 1) or (parent_count + 1) * parent_diff
    local fx_id = container_id + diff * i
    local fx_address = CONTAINER_BASE + fx_id

    local ok_name, name = host.GetFXName(fx_address)
    if not ok_name then
      Log("%s  WARNING: cannot access child %d (addr %d)\n", indent, i, fx_address)
      i = i - 1
      goto continue
    end

    -- Descend into nested containers first, passing this container's *current*
    -- child count and diff so the nested addressing resolves correctly.
    if isContainer(host, fx_address) then
      Log("%s  Child %d '%s' is a nested container\n", indent, i, name)
      removed = removed + removeInContainer(host, fx_id, count, diff, depth + 1, indent .. "  ")
    end

    if shouldRemove(host, fx_address) then
      Log("%s  REMOVING child %d '%s'\n", indent, i, name)
      host.Delete(fx_address)
      removed = removed + 1
    else
      Log("%s  Keeping child %d '%s'\n", indent, i, name)
    end

    i = i - 1
    ::continue::
  end

  return removed
end

local function processHost(host)
  Log("\n=== %s: %s ===\n", host.label == "take" and "Take" or "Track", host.name())

  local removed = 0
  -- Walk top-level FX high->low. Re-read the count each step because deleting a
  -- top-level FX also changes the diff used to address container children below.
  local fx = host.GetCount() - 1
  while fx >= 0 do
    local count = host.GetCount()
    if fx > count - 1 then fx = count - 1 end
    if fx < 0 then break end

    local ok_name2, fx_name = host.GetFXName(fx)
    fx_name = ok_name2 and fx_name or "Unknown FX"

    if isContainer(host, fx) then
      -- Top-level container: raw id is the 1-based slot (fx + 1),
      -- parent scope is the host itself (parent_count = chain FX count).
      Log("Top-level container at slot %d ('%s')\n", fx, fx_name)
      removed = removed + removeInContainer(host, fx + 1, count, 0, 0, "  ")
    end

    if shouldRemove(host, fx) then
      Log("REMOVING top-level FX %d ('%s')\n", fx, fx_name)
      host.Delete(fx)
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
local function countEmptyInContainer(host, container_id, parent_count, parent_diff, depth)
  if depth > MAX_DEPTH then return 0, 1 end  -- treat as non-empty; don't recurse further

  local count = getContainerCount(host, CONTAINER_BASE + container_id) or 0
  local pruned, remaining = 0, 0

  for i = 1, count do
    local diff = (depth == 0) and (parent_count + 1) or (parent_count + 1) * parent_diff
    local fx_address = CONTAINER_BASE + container_id + diff * i

    if isContainer(host, fx_address) then
      local child_pruned, child_remaining =
        countEmptyInContainer(host, container_id + diff * i, count, diff, depth + 1)
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

local function countEmptyContainers(host)
  local total = 0
  local count = host.GetCount()
  for fx = 0, count - 1 do
    if isContainer(host, fx) then
      local child_pruned, child_remaining = countEmptyInContainer(host, fx + 1, count, 0, 0)
      total = total + child_pruned
      if child_remaining == 0 then total = total + 1 end
    end
  end
  return total
end

-- Depth-first removal of empty containers. Because children are pruned before
-- the parent is re-checked, a single pass cascades bottom-up.
local function pruneEmptyInContainer(host, container_id, parent_count, parent_diff, depth)
  if depth > MAX_DEPTH then return 0 end

  local removed = 0
  local i = getContainerCount(host, CONTAINER_BASE + container_id) or 0

  while i >= 1 do
    local count = getContainerCount(host, CONTAINER_BASE + container_id) or 0
    if i > count then i = count end
    if i < 1 then break end

    local diff = (depth == 0) and (parent_count + 1) or (parent_count + 1) * parent_diff
    local fx_id = container_id + diff * i
    local fx_address = CONTAINER_BASE + fx_id

    if isContainer(host, fx_address) then
      removed = removed + pruneEmptyInContainer(host, fx_id, count, diff, depth + 1)
      if (getContainerCount(host, fx_address) or 0) == 0 then
        local _, name = host.GetFXName(fx_address)
        Log("%sREMOVING empty container '%s'\n", string.rep("  ", depth + 1), name or "")
        host.Delete(fx_address)
        removed = removed + 1
      end
    end

    i = i - 1
  end

  return removed
end

local function pruneEmptyContainers(host)
  local removed = 0
  local fx = host.GetCount() - 1
  while fx >= 0 do
    local count = host.GetCount()
    if fx > count - 1 then fx = count - 1 end
    if fx < 0 then break end

    if isContainer(host, fx) then
      removed = removed + pruneEmptyInContainer(host, fx + 1, count, 0, 0)
      if (getContainerCount(host, fx) or 0) == 0 then
        local _, name = host.GetFXName(fx)
        Log("REMOVING empty top-level container '%s'\n", name or "")
        host.Delete(fx)
        removed = removed + 1
      end
    end

    fx = fx - 1
  end
  return removed
end

--[[
  Decide what to operate on and build the list of FX hosts:
    * If any media items are selected, process every take of those items.
    * Otherwise, process the selected tracks.
  Returns (hosts, mode) where mode is "item" or "track".
]]
local function gatherHosts()
  local hosts = {}

  local item_count = r.CountSelectedMediaItems(proj)
  if item_count > 0 then
    for i = 0, item_count - 1 do
      local item = r.GetSelectedMediaItem(proj, i)
      for t = 0, r.CountTakes(item) - 1 do          -- every take, not just the active one
        local take = r.GetTake(item, t)
        if take then hosts[#hosts + 1] = makeTakeHost(take) end
      end
    end
    return hosts, "item"
  end

  local track_count = r.CountSelectedTracks(proj)
  for i = 0, track_count - 1 do
    hosts[#hosts + 1] = makeTrackHost(r.GetSelectedTrack(proj, i))
  end
  return hosts, "track"
end

function main()
  if ENABLE_DEBUG_LOG then r.ClearConsole() end
  Log("=== Remove Offline/Bypassed FX (recursive) ===\n")

  local hosts, mode = gatherHosts()
  -- "take(s)" reads better than "item(s)" since multi-take items expand into
  -- several hosts; tracks map one-to-one.
  local unit = (mode == "item") and "take" or "track"

  if #hosts == 0 then
    r.ShowMessageBox("No tracks or items selected. Please select one or more tracks, " ..
                     "or one or more items.", "Remove Offline/Bypassed FX", 0)
    return
  end

  local total_removed = 0
  for _, host in ipairs(hosts) do
    total_removed = total_removed + processHost(host)
  end
  Log("\n=== Offline/bypassed pass: removed %d FX ===\n", total_removed)

  -- Optional follow-up: offer to remove any containers the cleanup emptied out.
  local empty_count = 0
  for _, host in ipairs(hosts) do
    empty_count = empty_count + countEmptyContainers(host)
  end

  local empties_removed = 0
  if empty_count > 0 then
    local prompt = string.format(
      "Removed %d offline and/or bypassed FX.\n\n" ..
      "%d container(s) are now empty. Remove the empty container(s) too?",
      total_removed, empty_count)
    if r.ShowMessageBox(prompt, "Remove Offline/Bypassed FX", 4) == 6 then  -- 4 = Yes/No, 6 = Yes
      for _, host in ipairs(hosts) do
        empties_removed = empties_removed + pruneEmptyContainers(host)
      end
      Log("\n=== Empty-container pass: removed %d container(s) ===\n", empties_removed)
    end
  end

  Log("\n=== SUMMARY: %d FX + %d empty container(s) from %d %s(s) ===\n",
      total_removed, empties_removed, #hosts, unit)

  if total_removed == 0 and empty_count == 0 then
    r.ShowMessageBox(string.format("No offline or bypassed FX found on the selected %s(s).", unit),
                     "Remove Offline/Bypassed FX", 0)
  else
    r.ShowMessageBox(string.format(
      "Removed %d offline/bypassed FX and %d empty container(s) from %d %s(s).",
      total_removed, empties_removed, #hosts, unit), "Remove Offline/Bypassed FX", 0)
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
