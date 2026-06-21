--[[
 * Name: Hide Muted Tracks in Selected Tracks
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
    # Hides any muted tracks in currently selected tracks
 * Changelog:
    # Initial Release
 * To Do:
    # 


]]


-- Load my common functions
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")

-- Check if any tracks are selected
local selected_track_count = RequireSelectedTracks("No tracks selected. Please select tracks first.")
if not selected_track_count then return end

-- Counter for how many tracks we hide
local hidden_count = 0

-- Loop through all selected tracks
for i = 0, selected_track_count - 1 do
    -- Get the selected track (index 0-based)
    local track = reaper.GetSelectedTrack(0, i)
    
    -- Check if track is muted (returns 1 if muted, 0 if not)
    local is_muted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
    
    -- If the track is muted, hide it
    if is_muted == 1 then
        -- Hide the track by setting B_SHOWINTCP to 0 (0 = hidden, 1 = visible)
        reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
        reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
        hidden_count = hidden_count + 1
    end
end

-- Update the arrange view to reflect changes
reaper.TrackList_AdjustWindows(false)

-- Show completion message
if hidden_count > 0 then
    reaper.ShowMessageBox(hidden_count .. " muted track(s) have been hidden.", "Complete", 0)
else
    reaper.ShowMessageBox("No muted tracks found in selection.", "Complete", 0)
end
