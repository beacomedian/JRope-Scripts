--[[
 * Name: Delete Muted Tracks Among Selected (Respecting Folder Hierarchy)
 * Author: Jesse Rope
 * AI: Claude Opus 5
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
    [main] . >
 * About:
    # Removes selected tracks that are muted while keeping the folder hierarchy of the
    # remaining tracks intact. Only a track's own mute button counts (tracks silenced by a
    # muted parent are not treated as muted).
    # If a selected muted folder contains tracks that wouldn't otherwise be deleted
    # (unmuted or unselected children), you're asked whether to delete the folder along
    # with everything inside it. Cancel aborts without deleting anything.
    # A muted folder whose children all get deleted is removed too.
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
local r = reaper
local proj = 0

local MB_YESNOCANCEL = 3
local MB_RESULT_YES = 6
local MB_RESULT_CANCEL = 2

---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Load my common functions
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")

local function IsMuted(track)
    return r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
end

-- Returns the track indices of a folder's descendants as first, last (last < first if none).
local function GetFolderChildRange(folder_idx)
    local depth = 1
    local last = folder_idx
    local track_count = r.CountTracks(proj)
    while depth > 0 and last < track_count - 1 do
        last = last + 1
        depth = depth + r.GetMediaTrackInfo_Value(r.GetTrack(proj, last), "I_FOLDERDEPTH")
    end
    return folder_idx + 1, last
end

-- Selects only the folder and scrolls it into view so it's visible while the prompt is up.
-- UI refresh is re-enabled for the prompt, since main() runs inside PreventUIRefresh.
local function AskAboutFolder(track, msg)
    r.SetOnlyTrackSelected(track)
    r.Main_OnCommand(40913, 0) -- Track: Vertical scroll selected tracks into view
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    local result = r.ShowMessageBox(msg, "Delete Muted Tracks", MB_YESNOCANCEL)
    r.PreventUIRefresh(1)
    return result
end

function main()
    local sel_track_count = RequireSelectedTracks("No tracks selected.")
    if not sel_track_count then return end
    Log("Selected tracks:", sel_track_count)

    local selected_tracks = {}
    local is_selected = {}
    for i = 0, sel_track_count - 1 do
        local track = r.GetSelectedTrack(proj, i)
        selected_tracks[#selected_tracks + 1] = track
        is_selected[track] = true
    end

    -- Top-down so an outer folder is asked about before any folder nested inside it
    table.sort(selected_tracks, function(a, b)
        return r.GetMediaTrackInfo_Value(a, "IP_TRACKNUMBER") < r.GetMediaTrackInfo_Value(b, "IP_TRACKNUMBER")
    end)

    -- Ask about muted folders up front so Cancel can abort before anything is deleted.
    -- delete_with_contents[folder] = true (delete whole folder) / false (keep if it still has children)
    local delete_with_contents = {}
    local covered_until = -1 -- last track index inside a folder already marked for full deletion
    local selection_changed = false
    for _, track in ipairs(selected_tracks) do
        local idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
        if idx > covered_until and IsMuted(track) and r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
            local first, last = GetFolderChildRange(idx)
            local unmuted, unselected = 0, 0
            for i = first, last do
                local child = r.GetTrack(proj, i)
                if not IsMuted(child) then
                    unmuted = unmuted + 1
                elseif not is_selected[child] then
                    unselected = unselected + 1
                end
            end
            local _, name = r.GetTrackName(track)
            Log("Muted folder:", name, "unmuted children:", unmuted, "unselected muted children:", unselected)

            if unmuted + unselected > 0 then
                local msg = ('Muted folder "%s" contains:\n'):format(name)
                if unmuted > 0 then msg = msg .. ("  %d unmuted track(s)\n"):format(unmuted) end
                if unselected > 0 then msg = msg .. ("  %d unselected muted track(s)\n"):format(unselected) end
                msg = msg .. "\nDelete this folder and ALL tracks inside it?\n\n"
                    .. "Yes = delete folder and contents\nNo = keep this folder\nCancel = abort script"
                local result = AskAboutFolder(track, msg)
                selection_changed = true
                if result == MB_RESULT_CANCEL then
                    RestoreSelectedTracks(selected_tracks)
                    Log("Cancelled by user")
                    return
                end
                delete_with_contents[track] = (result == MB_RESULT_YES)
                if delete_with_contents[track] then covered_until = last end
                Log("  Delete with contents:", delete_with_contents[track])
            end
        end
    end

    if selection_changed then RestoreSelectedTracks(selected_tracks) end

    -- Delete bottom-up: removing a track never shifts the indices of tracks above it,
    -- and a folder's children are handled before the folder itself.
    local deleted = 0
    for i = #selected_tracks, 1, -1 do
        local track = selected_tracks[i]
        -- Pointer may be gone if it was inside a folder deleted with its contents
        if r.ValidatePtr(track, "MediaTrack*") and IsMuted(track) then
            local _, name = r.GetTrackName(track)
            local is_folder = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1

            if is_folder and not delete_with_contents[track] then
                Log("Keeping muted folder with children:", name)
            else
                local n = DeleteTrackPreservingHierarchy(track, true)
                Log("Deleted:", name, "(" .. n .. " track(s))")
                deleted = deleted + n
            end
        end
    end

    Log("Total tracks deleted:", deleted)
end


---------------------------------
-------------- MAIN -------------
---------------------------------

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

main()

reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, -1)
reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
