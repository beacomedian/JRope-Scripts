--[[
 * Name: Delete Empty Tracks Among Selected (Respecting Folder Hierarchy)
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * About:
    Removes selected tracks that are empty (no items, no automation, no enabled FX, not folder)
    while maintaining proper folder hierarchy. Empty folder tracks (after children removed) are also removed.
 * Changelog:
    # Initial Release
]]

----------- CONSTANTS -----------
local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local r = reaper
local proj = 0

----------- FUNCTIONS -----------
-- Check if track is a folder with children
function IsFolderWithChildren(track)
    if not track then return false end
    local depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if depth ~= 1 then return false end -- Not a folder start

    local track_idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    local track_count = r.CountTracks(0)

    -- If this is the last track, it can't have children
    if track_idx >= track_count - 1 then
        return false
end

-- If there's a next track, this folder has at least one child
return true
end
-- Check if track is empty according to our criteria
function IsTrackEmpty(track)
    if not track then return true end
    -- Folder tracks with children are not empty
    if IsFolderWithChildren(track) then
        return false
end

-- Check for media items
local item_count = r.CountTrackMediaItems(track)
if item_count > 0 then
    return false
end

-- Check for automation envelope points
local env_count = r.CountTrackEnvelopes(track)
for i = 0, env_count - 1 do
    local env = r.GetTrackEnvelope(track, i)
    local point_count = r.CountEnvelopePoints(env)
    if point_count > 0 then
        return false
    end
end

-- Check for enabled FX
local fx_count = r.TrackFX_GetCount(track)
for i = 0, fx_count - 1 do
    local fx_enabled = r.TrackFX_GetEnabled(track, i)
    if fx_enabled then
        return false
    end
end

-- Track is empty
return true
end
-- Get the current folder nesting level at a track index
function GetNestingLevelAtIndex(track_idx)
    local level = 0
    for i = 0, track_idx - 1 do
        local t = r.GetTrack(0, i)
        if t then
        local depth = r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
        level = level + depth
        end
    end
    return level
end
-- Fix folder hierarchy after deleting a track
function FixFolderDepthAfterDelete(track_idx, original_depth)
-- Only need to fix if the deleted track had a negative depth (was closing folder(s))
    if original_depth >= 0 then
    return
    end
-- The track that was deleted had depth of original_depth (negative number)
-- We need to transfer this closing depth to the track before it
    if track_idx > 0 then
        local prev_track = r.GetTrack(0, track_idx - 1)
        if prev_track then
            local prev_depth = r.GetMediaTrackInfo_Value(prev_track, "I_FOLDERDEPTH")
            -- Add the negative depth to the previous track
            r.SetMediaTrackInfo_Value(prev_track, "I_FOLDERDEPTH", prev_depth + original_depth)
        end
    end
end

function main()
    -- Get selected tracks
    local sel_track_count = r.CountSelectedTracks(0)
        if sel_track_count == 0 then
        r.ShowMessageBox("No tracks selected.", "Error", 0)
        return
        end
    -- Store selected tracks with their info
    local selected_tracks = {}
    for i = 0, sel_track_count - 1 do
        local track = r.GetSelectedTrack(0, i)
        local track_idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
        local depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        table.insert(selected_tracks, {
            track = track,
            index = track_idx,
            depth = depth
        })
    end

    -- Sort by track index (highest to lowest) so we delete from bottom to top
    table.sort(selected_tracks, function(a, b) return a.index > b.index end)

    -- Multiple passes to handle folders that become empty after children are removed
    local made_changes = true
    local iteration = 0
    local max_iterations = 10

    while made_changes and iteration < max_iterations do
        made_changes = false
        iteration = iteration + 1
        
        -- Mark tracks for deletion
        local tracks_to_delete = {}
        
        for i = #selected_tracks, 1, -1 do
            local track_info = selected_tracks[i]
            if track_info.track and r.ValidatePtr(track_info.track, "MediaTrack*") then
                if IsTrackEmpty(track_info.track) then
                    tracks_to_delete[i] = true
                    made_changes = true
                end
            else
                -- Track was already deleted, remove from list
                table.remove(selected_tracks, i)
            end
        end
        
        -- Delete marked tracks (already in reverse order)
        for i = #selected_tracks, 1, -1 do
            if tracks_to_delete[i] then
                local track_info = selected_tracks[i]
                
                -- Store the depth before deletion
                local original_depth = r.GetMediaTrackInfo_Value(track_info.track, "I_FOLDERDEPTH")
                local track_idx = r.GetMediaTrackInfo_Value(track_info.track, "IP_TRACKNUMBER") - 1
                
                -- Delete the track
                r.DeleteTrack(track_info.track)
                
                -- Fix the folder hierarchy
                FixFolderDepthAfterDelete(track_idx, original_depth)
                
                -- Remove from our tracking list
                table.remove(selected_tracks, i)
            end
        end
        
        -- Update indices for remaining tracks (they may have shifted after deletions)
        for i = 1, #selected_tracks do
            if selected_tracks[i].track and r.ValidatePtr(selected_tracks[i].track, "MediaTrack*") then
                selected_tracks[i].index = r.GetMediaTrackInfo_Value(selected_tracks[i].track, "IP_TRACKNUMBER") - 1
                selected_tracks[i].depth = r.GetMediaTrackInfo_Value(selected_tracks[i].track, "I_FOLDERDEPTH")
            end
        end
        
        -- Re-sort by index
        table.sort(selected_tracks, function(a, b) return a.index > b.index end)
    end
end


---------------------------------
-------------- MAIN -------------
---------------------------------

-- reaper.APITest()
-- local time_init = reaper.time_precise()
-- reaper.ShowConsoleMsg("-- Script started\n")

-- Begin the undo block
reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

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
reaper.PreventUIRefresh(-1)
-- reaper.UpdateTimeline()
reaper.UpdateArrange()