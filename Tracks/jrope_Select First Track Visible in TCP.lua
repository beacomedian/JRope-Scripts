--[[
 * Name: Select First Track Visible in TCP
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
    # This script finds and selects the first track that is visible in the Track Control Panel

 

 * Changelog:
    # Initial Release

]]


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))

---------------------------------
----------- FUNCTIONS -----------
---------------------------------


function main()
    -- Clear current track selection
    reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
    
    -- Get the number of tracks in the project
    local track_count = reaper.CountTracks(0)
    
    if track_count == 0 then
        reaper.ShowMessageBox("No tracks found in project", "Error", 0)
        return
    end
    
    -- Find the first visible track
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        
        -- Check if track is visible in TCP
        -- I_TCPH returns the track control panel height (0 if collapsed/hidden)
        local tcp_height = reaper.GetMediaTrackInfo_Value(track, "I_TCPH")
        
        if tcp_height > 0 then
            -- Select this track
            reaper.SetTrackSelected(track, true)
            
            -- Optional: Make this track the last touched track
            reaper.SetOnlyTrackSelected(track)
            
            -- Update the arrange view
            reaper.UpdateArrange()
            
            -- Get track name for confirmation
            local retval, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            if track_name == "" then
                track_name = "Track " .. (i + 1)
            end
            
            -- reaper.ShowConsoleMsg("Selected first visible track: " .. track_name .. "\n")
            return
        end
    end
    
    -- If we get here, no visible tracks were found
    reaper.ShowMessageBox("No visible tracks found in TCP", "Info", 0)
end

---------------------------------
-------------- MAIN -------------
---------------------------------


reaper.Undo_BeginBlock()

main()

reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, -1)