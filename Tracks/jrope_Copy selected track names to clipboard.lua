--[[
 * Name: Copy selected track names to clipboard
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.0
 * Version: 1.0
 * Provides:
    [main] . > 
 * Link: https://www.jesserope.com
 * noindex
 * About:
    # Used to paste track names into external editor for modification. Pair with 'Mordi_Paste text from clipboard to selected tracks names (separate by newline)'

 

 * Changelog:
    # Initial Release

]]



---------------------------------
---------- USER CONFIG ----------
---------------------------------


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
-- local time_init = reaper.time_precise()
local r = reaper
local proj = 0

---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- -- Load my common functions
-- local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
-- local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]]) 
-- package.path = parent_path .. "Functions/?.lua;" .. package.path
-- require("jrope__Common Functions")



-- get selected tracks
local function get_selected_tracks()
    local tracks = {}
    local track_count = r.CountSelectedTracks(0)
    
    for i = 0, track_count - 1 do
        local tr = r.GetSelectedTrack(0, i)
        if tr then
            local _, tr_name = r.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', 0)
            table.insert(tracks, tr_name)
        end
    end
    
    return tracks
end

-- Main 
function main()
    local selected_track_names = get_selected_tracks()

    if #selected_track_names > 0 then
        local names_string = table.concat(selected_track_names, '\n')
        r.CF_SetClipboard(names_string)
    end
end








---------------------------------
-------------- MAIN -------------
---------------------------------

-- reaper.APITest()
-- local time_init = reaper.time_precise()
-- reaper.ShowConsoleMsg("-- Script started\n")

-- Begin the undo block
-- reaper.PreventUIRefresh(1)
-- reaper.Undo_BeginBlock()

-- SaveView()
-- SaveCursorPos()
-- SaveLoopTimesel()
-- SaveSelectedItems(init_sel_items)
-- SaveSelectedTracks(init_sel_tracks)

main()

-- RestoreCursorPos()
-- RestoreLoopTimesel()
-- RestoreSelectedItems(init_sel_items)
-- RestoreSelectedTracks(init_sel_tracks)
-- RestoreView()

-- Update the arrangement to reflect the new selection
reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, -1)
-- reaper.PreventUIRefresh(-1)
-- reaper.UpdateTimeline()
-- reaper.UpdateArrange()