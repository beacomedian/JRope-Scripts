--[[
 * Name: Open Global Backups Path
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
   [main] . >
 * Link: https://www.jesserope.com
 * About:
   # Opens the global "Save undo history and backups to" path (REAPER
   # Preferences > General > Paths) in the OS file browser. Reads the
   # autosavedir config variable.
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


-- True if the path is absolute (handles Windows drive letters / UNC and POSIX roots).
local function IsAbsolutePath(path)
  return path:match("^%a:[\\/]") ~= nil   -- C:\... or C:/...
    or path:match("^[\\/][\\/]") ~= nil -- \\server\share UNC
    or path:match("^/") ~= nil          -- /Users/... (macOS/Linux)
end


-- Open a folder in the OS file browser. Prefers SWS's CF_ShellExecute (cross-platform),
-- and falls back to the native shell command so it still works without SWS installed.
local function OpenDirectory(path)
  if r.CF_ShellExecute then
    Log("Opening via CF_ShellExecute:", path)
    r.CF_ShellExecute(path)
    return true
  end

  local isWindows = r.GetOS():match("^Win") ~= nil
  local cmd = isWindows
    and ('explorer "' .. path .. '"')
    or  ('open "' .. path:gsub('"', '\\"') .. '"')  -- macOS Finder (also works on Linux with xdg-open swapped)
  Log("Opening via os.execute:", cmd)
  os.execute(cmd)
  return true
end


-- Read a key from the [REAPER] section of reaper.ini. autosavedir is not exposed
-- through get_config_var_string (that only supports an allowlist of vars), so we
-- parse the ini file directly.
local function ReadIniKey(key)
  local ini = r.get_ini_file()
  Log("Reading ini:", tostring(ini))
  local f = io.open(ini, "r")
  if not f then return nil end
  local value
  for line in f:lines() do
    local k, v = line:match("^([^=]+)=(.*)$")
    if k == key then
      value = v
      break  -- first match is the [REAPER] section entry
    end
  end
  f:close()
  return value
end


function main()
  -- "Auto-save to timestamped file in additional directory" lives in reaper.ini
  -- as autosavedir (the global backups path).
  local path = ReadIniKey("autosavedir")
  Log("autosavedir value:", tostring(path))

  if not path or path == "" then
    r.MB("No global backups path is set.\n\nSet one in Preferences > General > Paths > "
      .. "\"Auto-save to timestamped file in additional directory\".", SCRIPT_NAME, 0)
    return
  end

  if not IsAbsolutePath(path) then
    r.MB("The global backups path is relative (\"" .. path .. "\"), so it resolves "
      .. "per-project rather than to a single global folder.\n\nSet an absolute path in "
      .. "Preferences > General > Paths to use this script.", SCRIPT_NAME, 0)
    return
  end

  OpenDirectory(path)
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
