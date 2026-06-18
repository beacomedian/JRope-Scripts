-- @description Basehead iXML Metadata Columns
-- @author Aaron Cendan, modified by Jesse Rope
-- @version 1.6
-- @metapackage
-- @provides
--   [main=mediaexplorer] .
-- @link https://aaroncendan.me
-- @changelog
--   #1.5 Update LuaUtils path with case sensitivity for Linux
--   #1.6 Modified iXML colums to pull in Basehead-generated fields
--   #1.6 Pulled in ascenden utilities functions so the script runs standalone

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- ~~~~~~~~~~~ GLOBAL VARS ~~~~~~~~~~
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-- Standalone utility replacements
acendan = {}

function acendan.version()
  return 4.4
end

function acendan.msg(msg, title)
  reaper.MB(tostring(msg), title or "ACendan Info", 0)
end

function acendan.getOS()
  local os = reaper.GetOS()

  if os:match("Win") then
    return true, "\\"
  else
    return false, "/"
  end
end

-- Table of iXML Columns
local iXML = {}
iXML["INFO:IARL"]                 = "Location"
iXML["INFO:IART"]                 = "Artist"
iXML["INFO:ICMT"]                 = "Comment"
iXML["INFO:ICOP"]                 = "Copyright"
iXML["INFO:ICRD"]                 = "Created Date"
iXML["INFO:IENG"]                 = "Designer"
iXML["INFO:IGNR"]                 = "Genre"
iXML["INFO:IKEY"]                 = "Keywords"
iXML["INFO:IMED"]                 = "Subcategory"
iXML["INFO:INAM"]                 = "Track Title"
iXML["INFO:IPRD"]                 = "CD Title"
iXML["INFO:ISBJ"]                 = "Category"
iXML["INFO:ISFT"]                 = "Software"
iXML["INFO:ISRC"]                 = "Library"
iXML["INFO:ISRF"]                 = "Notes"
iXML["INFO:ITCH"]                 = "Recordist"
iXML["ID3:COMM"]                  = "Comment"
iXML["ID3:TKEY"]                  = "Initial Key"
iXML["ID3:TORY"]                  = "Year"
iXML["ID3:TPUB"]                  = "Publisher"
iXML["ID3:TYER"]                  = "Year"
iXML["IXML:BEXT:BWF_DESCRIPTION"] = "Description"
iXML["IXML:PROJECT"]              = "Project"
iXML["IXML:SCENE"]                = "Scene"
iXML["IXML:TAKE"]                 = "Take"
iXML["IXML:TAPE"]                 = "Tape"

-- Other globals
local script_name = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local script_directory = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
local win, sep = acendan.getOS()
local ini_section = win and "reaper_explorer" or "reaper_sexplorer" -- For some reason, it's 'sexplorer' on Mac
local ENABLE_DEBUG_LOG = true

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- ~~~~~~~~~~~~ FUNCTIONS ~~~~~~~~~~~
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function main()
  local reaper_version = tonumber(reaper.GetAppVersion():sub(1,4))
  if reaper_version >= 6.29 then
    AddIXML()
  else
    -- ~~~~~~~~~ PRE-RELEASE BUILDS ONLY
    if ENABLE_DEBUG_LOG then AddIXML() else
    -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    reaper.MB("This script requires Reaper v6.29 or greater! Please update Reaper.","ERROR: Update Reaper!",0) end
  end
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- ~~~~~~~~~~~~ UTILITIES ~~~~~~~~~~~
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Adds the IXML columns to the Media Explorer
function AddIXML()
  local ini_file = reaper.get_ini_file()
  local i = 0
  repeat 
    -- Check .ini file for custom user columns
    local ret,val = reaper.BR_Win32_GetPrivateProfileString(ini_section,"user" .. tostring(i) .. "_key","",ini_file)
    -- Check if custom user column is already in table
    if tableContainsKey(iXML,val) then
      if ENABLE_DEBUG_LOG then reaper.ShowConsoleMsg("Found existing entry for: " .. iXML[val] .. "\n") end
      iXML[val] = nil
    end
    i = i+1
  until ret == 0
  
  i = i-1
  
  -- Loop through iXML metadata table  
  if tableLength(iXML) > 0 then 
    for k, v in pairs(iXML) do
      -- Set metadata scheme/key
      local ret = reaper.BR_Win32_WritePrivateProfileString(ini_section,"user" .. tostring(i) .. "_key",k,ini_file)
      -- Set column description
      local ret2 = reaper.BR_Win32_WritePrivateProfileString(ini_section,"user" .. tostring(i) .. "_desc",v,ini_file)
      -- Set custom entry flag
      local ret3 = reaper.BR_Win32_WritePrivateProfileString(ini_section,"user" .. tostring(i) .. "_flags","1",ini_file)
      if ret and ret2 then 
        if ENABLE_DEBUG_LOG then reaper.ShowConsoleMsg("Succesfully added entry: " .. k .. " - " .. v .. "\n") end
      else
        if ENABLE_DEBUG_LOG then reaper.ShowConsoleMsg("ERROR: Failed to add entry: " .. k .. " - " .. v .. "\n") end
      end
      i = i + 1
    end
    
    -- Force refresh the media explorer
    reaper.Main_OnCommand(50124,0) -- Show/hide media explorer
    reaper.Main_OnCommand(50124,0) -- Show/hide media explorer
    reaper.OpenMediaExplorer("",false)
    
    reaper.MB("Succesfully updated Media Explorer metadata columns!\n\nRESTART Reaper, then select your file(s), right click, and run 'Re-read metadata from media'.","Media Explorer Metadata",0)
  else
    -- Force refresh the media explorer
    reaper.Main_OnCommand(50124,0) -- Show/hide media explorer
    reaper.Main_OnCommand(50124,0) -- Show/hide media explorer
    reaper.OpenMediaExplorer("",false)
    
    reaper.MB("All metadata columns are already set up!\n\nDid you RESTART Reaper? If you don't see them, try right clicking on a Media Explorer column and checking whether your User Columns at the bottom of the menu are enabled/visible.","Media Explorer Metadata",0)
  end
end

-- Check if a table contains a key // returns Boolean
function tableContainsKey(table, key)
    return table[key] ~= nil
end

-- Get table length for non numeric keys (unlike # or table.getn function)
function tableLength(table)
  local i = 0
  for _ in pairs(table) do i = i + 1 end
  return i
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- ~~~~~~~~~~~~~~ MAIN ~~~~~~~~~~~~~~
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
reaper.PreventUIRefresh(1)

reaper.Undo_BeginBlock()

main()

reaper.Undo_EndBlock(script_name,-1)

reaper.PreventUIRefresh(-1)

reaper.UpdateArrange()


