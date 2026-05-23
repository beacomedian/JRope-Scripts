--[[
 * Name: Hide Muted Tracks and their children in Selected Tracks
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
    #   Hides any muted tracks in the currently selected tracks
        If a muted track is a folder, it also hides all child tracks
 * Changelog:
    # Initial Release
 * To Do:
    # 


]]


-- Function to hide a track and all its children
local function HideTrackAndChildren(track)
    local hidden_count = 0
    
    -- Hide the parent track
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
    hidden_count = hidden_count + 1
    
    -- Check if this track is a folder (folder depth > 0 means it's a parent)
    local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    
    if folder_depth == 1 then
        -- This is a folder track, so we need to find and hide its children
        local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
        local total_tracks = reaper.CountTracks(0)
        local current_depth = 1  -- Start at depth 1 since we're inside the folder
        
        -- Loop through tracks after this one to find children
        for i = track_index + 1, total_tracks - 1 do
            local child_track = reaper.GetTrack(0, i)
            local child_folder_depth = reaper.GetMediaTrackInfo_Value(child_track, "I_FOLDERDEPTH")
            
            -- Update our depth tracking
            current_depth = current_depth + child_folder_depth
            
            -- Hide this child track
            reaper.SetMediaTrackInfo_Value(child_track, "B_SHOWINTCP", 0)
            reaper.SetMediaTrackInfo_Value(child_track, "B_SHOWINMIXER", 0)
            hidden_count = hidden_count + 1
            
            -- If we've exited the folder (depth back to 0), stop
            if current_depth <= 0 then
                break
            end
        end
    end
    
    return hidden_count
end

    -- Get the number of selected tracks
    local selected_track_count = reaper.CountSelectedTracks(0)

    -- Check if any tracks are selected
    if selected_track_count == 0 then
        reaper.ShowMessageBox("No tracks selected. Please select tracks first.", "Error", 0)
        return
    end

-- Counter for how many tracks we hide
local total_hidden = 0

-- Loop through all selected tracks
for i = 0, selected_track_count - 1 do
    -- Get the selected track (index 0-based)
    local track = reaper.GetSelectedTrack(0, i)
    
    -- Check if track is muted (returns 1 if muted, 0 if not)
    local is_muted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
    
    -- If the track is muted, hide it (and children if it's a folder)
    if is_muted == 1 then
        local hidden_count = HideTrackAndChildren(track)
        total_hidden = total_hidden + hidden_count
    end
end

-- Update the arrange view to reflect changes
reaper.TrackList_AdjustWindows(false)

--[[-- Show completion message
if total_hidden > 0 then
    reaper.ShowMessageBox(total_hidden .. " track(s) have been hidden.", "Complete", 0)
else
    reaper.ShowMessageBox("No muted tracks found in selection.", "Complete", 0)
end
]]