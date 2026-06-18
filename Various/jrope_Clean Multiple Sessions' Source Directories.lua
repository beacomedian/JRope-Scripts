--[[
 * Name: JROPE - Clean Multiple Sessions' Source Directories (GUI)
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 2.4
 * Provides:
    [main] . >
 * Link: https://www.jesserope.com
 * noindex
 * About:
    # ReaImGui front-end for the unused-source cleanup tool.
    # Cross-platform scan across MULTIPLE source folders (recursively): finds
    # media files not referenced by ANY .rpp in the project folder.
    # Results show in-window; user can remove rows before a confirmed move.
    # Settings persist between launches.
 * Changelog:
    # 2.4 - Multiple source folders, recursive scanning, open trash folder when done.
    # 2.3 - Settings persist between launches (ext-state). Added About section.
    # 2.2 - Added optional console logging for diagnosing scan results.
    # 2.1 - Wired up cross-platform scan. Results list + per-row removal + confirmed move.
    # 2.0 - Rebuilt around a ReaImGui window. Added ignore-pattern input.
    # 1.0 - Initial console-based release (adapted from fbeauvaisc).
 * To Do:
    # Optional: progress feedback for very large projects.


]]



---------------------------------
---------- USER CONFIG ----------
---------------------------------

-- Ignore patterns the window starts with. The user can edit these live.
-- Each line is a plain substring: if a filename CONTAINS it, the file is protected.
local DEFAULT_IGNORE_PATTERNS = ".png\n.jpg\n.jpeg\n.mp4\n.mov"

-- Source subfolders (inside the project dir) to scan for unused media. One per
-- line; scan as many as you like (e.g. Audio, Photos, Video). Each is searched
-- recursively. This is just the STARTING value; it's editable in the window.
local DEFAULT_AUDIO_SUBFOLDERS = "Audio"

-- Subfolder (inside the project dir) we move unused files into. Not deleted.
-- This is just the STARTING value; it's editable in the window.
local DEFAULT_TRASH_SUBFOLDER = "temp_trash"

-- Print a detailed scan report to the REAPER console. Can also be toggled
-- live with the checkbox in the window; this is just the starting value.
-- local ENABLE_DEBUG_LOG = true -- use checkmark in GUI

-- When logging, cap each list in the report to this many items. A big project
-- can reference hundreds of files, and the console only keeps ~300 lines, so
-- without a cap the important paths at the top get pushed out of view.
local LOG_MAX_LIST = 25

-- Settings are remembered between launches under this name in REAPER's global
-- ext-state store (persists in reaper-extstate.ini). Change it only if you'd
-- want a clean slate of saved settings.
local EXT_STATE_SECTION = "JROPE_CleanSourceDir"


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR  = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
local r = reaper
local proj = 0

-- Path separator for the current OS (matches the idiom used elsewhere in the project).
local SEP = (r.GetOS():find("Win")) and "\\" or "/"

-- Load ReaImGui.
if not r.ImGui_GetBuiltinPath then
    r.MB("This script needs ReaImGui. Install it via ReaPack:\n\nExtensions > ReaPack > Browse packages > 'ReaImGui'.", "Missing dependency", 0)
    return
end
package.path = r.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.9'

local FLT_MIN = ImGui.NumericLimits_Float()


---------------------------------
------------- STATE -------------
---------------------------------

local state = {
    ignore_text      = DEFAULT_IGNORE_PATTERNS,
    audio_subfolders = DEFAULT_AUDIO_SUBFOLDERS,   -- multiline: one folder per line
    trash_subfolder  = DEFAULT_TRASH_SUBFOLDER,
    logging          = ENABLE_DEBUG_LOG,
    scanned          = false,   -- has a scan run yet?
    results          = {},      -- list of { path, name } records to clean
    excluded         = {},      -- records held back: { path, name, reason }
    manual_excluded  = {},      -- set of lowercased names the user held back manually
    status           = "",      -- one-line feedback under the buttons
    confirming       = false,   -- showing the move confirmation?
    want_close       = false,
    -- Resolved at scan time:
    project_dir = nil,
    source_dirs = {},   -- list of absolute source folders (each ends in SEP)
    trash_dir   = nil,
}


---------------------------------
--------- PERSISTENCE -----------
---------------------------------

-- REAPER's ext-state store only holds strings, so booleans are saved as "1"/"0".
-- The 'true' 3rd arg to SetExtState makes the value persist to disk (survives
-- restarts); without it the value would only last the current REAPER session.

local function saveSettings()
    r.SetExtState(EXT_STATE_SECTION, "ignore_text",      state.ignore_text,      true)
    r.SetExtState(EXT_STATE_SECTION, "audio_subfolders", state.audio_subfolders, true)
    r.SetExtState(EXT_STATE_SECTION, "trash_subfolder",  state.trash_subfolder,  true)
    r.SetExtState(EXT_STATE_SECTION, "logging",          state.logging and "1" or "0", true)
end

-- Load a saved string, returning a fallback if this key was never saved.
-- HasExtState lets us tell "saved as empty on purpose" apart from "never saved",
-- so a deliberately-blank folder list isn't overwritten by the default.
local function loadString(key, fallback)
    if r.HasExtState(EXT_STATE_SECTION, key) then
        return r.GetExtState(EXT_STATE_SECTION, key)
    end
    return fallback
end

local function loadSettings()
    state.ignore_text      = loadString("ignore_text",      DEFAULT_IGNORE_PATTERNS)
    state.audio_subfolders = loadString("audio_subfolders", DEFAULT_AUDIO_SUBFOLDERS)
    state.trash_subfolder  = loadString("trash_subfolder",  DEFAULT_TRASH_SUBFOLDER)
    if r.HasExtState(EXT_STATE_SECTION, "logging") then
        state.logging = r.GetExtState(EXT_STATE_SECTION, "logging") == "1"
    end
end


---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Console logging helper. No-ops when logging is disabled. We only call
-- :format when there are extra args, so a literal '%' in a plain message
-- (e.g. a path) can't trigger a format error.
local function log(fmt, ...)
    if not state.logging then return end
    if select('#', ...) > 0 then
        r.ShowConsoleMsg(fmt:format(...))
    else
        r.ShowConsoleMsg(fmt)
    end
end

-- Return a set's keys as a sorted list (for tidy, repeatable log output).
local function sortedKeys(set)
    local keys = {}
    for k in pairs(set) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

-- Log a plain list, capped at LOG_MAX_LIST items so a huge project can't
-- flood (and truncate) the console. Prints "... and N more" when capped.
local function logList(items)
    for i, item in ipairs(items) do
        if i > LOG_MAX_LIST then
            log("    ... and %d more (capped)\n", #items - LOG_MAX_LIST)
            break
        end
        log("    %s\n", item)
    end
end

-- Split a multiline text box into a clean list: one trimmed entry per line,
-- blank lines dropped. Shared by the ignore-patterns box and the folders box.
-- (For ignore patterns, a blank entry would be an empty substring that matches
-- EVERY file; for folders it would be a meaningless empty path. Dropping blanks
-- is correct for both.)
local function parseLines(text)
    local out = {}
    for line in text:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            table.insert(out, trimmed)
        end
    end
    return out
end

-- Ignore patterns are just the cleaned lines of the ignore box.
local function parseIgnorePatterns(text)
    return parseLines(text)
end

-- True if 'filename' is protected by the current ignore list.
-- Plain find (4th arg true) so dots are literal; both sides lowercased.
local function isIgnored(filename, patterns)
    local lowerName = filename:lower()
    for _, pat in ipairs(patterns) do
        if lowerName:find(pat:lower(), 1, true) then
            return true
        end
    end
    return false
end

-- List every file in a directory using REAPER's own enumerator (cross-platform).
-- A while-loop avoids the empty-directory edge case in the repeat/until idiom.
local function listFiles(dir)
    local files, i = {}, 0
    while true do
        local f = r.EnumerateFiles(dir, i)
        if not f or f == "" then break end
        files[#files + 1] = f
        i = i + 1
    end
    return files
end

-- List every SUBDIRECTORY of a directory (one level), cross-platform.
local function listSubdirs(dir)
    local dirs, i = {}, 0
    while true do
        local d = r.EnumerateSubdirectories(dir, i)
        if not d or d == "" then break end
        dirs[#dirs + 1] = d
        i = i + 1
    end
    return dirs
end

-- Recursively collect every file under 'dir' and its subfolders. Returns a list
-- of records { path = <folder it lives in, ending in SEP>, name = <filename> }.
-- We keep the full source folder per file so the move can find it again even
-- when it's nested several levels deep.
local function listFilesRecursive(dir)
    local results = {}
    for _, f in ipairs(listFiles(dir)) do
        results[#results + 1] = { path = dir, name = f }
    end
    for _, sub in ipairs(listSubdirs(dir)) do
        local subResults = listFilesRecursive(dir .. sub .. SEP)
        for _, rec in ipairs(subResults) do
            results[#results + 1] = rec
        end
    end
    return results
end

-- Reduce any file path (absolute or relative, either separator) to its bare filename.
local function basename(path)
    return path:match("[^/\\]+$") or path
end

-- Clean a user-typed subfolder name: trim spaces and strip any leading/trailing
-- slashes, so "  Audio/ " and "Audio" both resolve the same way. Returns "" if
-- the user cleared the field, which the caller treats as "the project folder
-- itself" (no subfolder).
local function cleanSubfolder(name)
    local trimmed = name:match("^%s*(.-)%s*$")    -- trim whitespace
    trimmed = trimmed:gsub("^[\\/]+", ""):gsub("[\\/]+$", "")  -- strip slashes
    return trimmed
end

-- Join the project dir with a (possibly empty) subfolder, always ending in SEP.
local function joinSubfolder(projectDir, subfolder)
    if subfolder == "" then
        return projectDir
    end
    return projectDir .. subfolder .. SEP
end

-- Does a directory exist? This is trickier than it sounds: reaper.file_exists
-- only ever returns true for regular FILES, never directories (on Windows it
-- returns false for any folder, with or without a trailing separator). The
-- reliable way to test a folder is to look for it among its parent's
-- subdirectories via reaper.EnumerateSubdirectories.
local function dirExists(path)
    path = path:gsub("[\\/]+$", "")                 -- strip trailing separator
    local parent, leaf = path:match("^(.*)[\\/]([^\\/]+)$")
    if not parent or not leaf then return false end

    local winOS = r.GetOS():find("Win") ~= nil       -- Windows is case-insensitive
    local target = winOS and leaf:lower() or leaf

    local i = 0
    while true do
        local sub = r.EnumerateSubdirectories(parent, i)
        if not sub then break end                    -- nil = no more subdirs
        local cmp = winOS and sub:lower() or sub
        if cmp == target then return true end
        i = i + 1
    end
    return false
end

-- Read one .rpp and record every media FILE it references (by lowercase basename).
-- We grab ALL "FILE ..." lines regardless of source type (WAVE/MP3/FLAC/etc),
-- which is more robust than the v1 approach of only catching <SOURCE WAVE.
local function collectReferences(rppPath, referenced)
    for line in io.lines(rppPath) do
        -- FILE "with spaces.wav"  or  FILE noSpaces.wav
        local fname = line:match('FILE%s+"([^"]+)"') or line:match('FILE%s+(%S+)')
        if fname and fname ~= "" then
            referenced[basename(fname):lower()] = true
        end
    end
end

-- The core scan. Pure: it reads the disk and returns data, no side effects.
-- Takes a LIST of source folders (absolute paths ending in SEP). Each is scanned
-- recursively. 'manualSet' is a set of lowercased filenames the user has
-- manually excluded in this session; those go to the excluded list too.
-- Returns:
--   unused      - records { path, name } that will be moved
--   excluded    - records { path, name, reason } held back ("pattern"/"manual")
--   referenced  - set of referenced basenames (for logging)
--   audioFiles  - list of every source file found, as records (for logging)
--   rppFiles    - list of .rpp filenames scanned (for logging)
local function scanForUnused(projectDir, sourceDirs, ignorePatterns, manualSet)
    manualSet = manualSet or {}

    -- 1. Find every .rpp in the project folder.
    local rppFiles = {}
    for _, f in ipairs(listFiles(projectDir)) do
        if f:lower():match("%.rpp$") then
            rppFiles[#rppFiles + 1] = f
        end
    end
    table.sort(rppFiles)

    -- 2. Build the set of filenames those projects reference.
    local referenced = {}
    for _, f in ipairs(rppFiles) do
        collectReferences(projectDir .. f, referenced)
    end

    -- 3. Recursively list every source folder, gathering records.
    local audioFiles = {}
    for _, dir in ipairs(sourceDirs) do
        for _, rec in ipairs(listFilesRecursive(dir)) do
            audioFiles[#audioFiles + 1] = rec
        end
    end
    table.sort(audioFiles, function(a, b) return a.name:lower() < b.name:lower() end)

    -- 4. Among unreferenced files, sort into "will move" vs "excluded".
    --    A file is excluded if an ignore pattern matches it (reason "pattern")
    --    or the user manually held it back earlier this session (reason "manual").
    --    Pattern takes priority in the label when both apply.
    local unused, excluded = {}, {}
    for _, rec in ipairs(audioFiles) do
        if not referenced[rec.name:lower()] then
            if isIgnored(rec.name, ignorePatterns) then
                excluded[#excluded + 1] = { path = rec.path, name = rec.name, reason = "pattern" }
            elseif manualSet[rec.name:lower()] then
                excluded[#excluded + 1] = { path = rec.path, name = rec.name, reason = "manual" }
            else
                unused[#unused + 1] = rec
            end
        end
    end

    return unused, excluded, referenced, audioFiles, rppFiles
end

-- Move one file into the trash folder, renaming to avoid clobbering.
local function moveToTrash(sourcePath, filename, trashDir)
    if not r.file_exists(sourcePath) then return false end

    local target = trashDir .. filename
    local counter = 1
    while r.file_exists(target) do
        local stem, ext = filename:match("(.+)%.(%w+)$")
        if stem then
            target = trashDir .. stem .. "_" .. counter .. "." .. ext
        else
            target = trashDir .. filename .. "_" .. counter
        end
        counter = counter + 1
    end

    return os.rename(sourcePath, target) ~= nil
end

-- Move the audio file plus its peak file (if present, best-effort).
-- 'rec' is a { path, name } record: path is the folder the file actually lives
-- in (which, with recursion + multiple folders, varies per file).
local function cleanFile(rec, trashDir)
    local moved = moveToTrash(rec.path .. rec.name, rec.name, trashDir)

    -- .reapeaks usually sits next to the audio; some setups use a 'peaks' subfolder.
    local peakName = rec.name .. ".reapeaks"
    if not moveToTrash(rec.path .. peakName, peakName, trashDir) then
        moveToTrash(rec.path .. "peaks" .. SEP .. peakName, peakName, trashDir)
    end

    return moved
end

-- Open a folder in the OS file browser (best-effort; needs the SWS extension's
-- CF_ShellExecute, which most users have. Silently does nothing if unavailable).
local function openDirectory(path)
    if r.CF_ShellExecute then
        r.CF_ShellExecute(path)
    end
end


local ctx = ImGui.CreateContext(SCRIPT_NAME or "Clean Source Directory")


---------------------------------
----------- ACTIONS -------------
---------------------------------

local function runScan()
    local _, projPath = r.EnumProjects(-1, "")
    if not projPath or projPath == "" then
        state.status = "Save the project first - the scan needs a project folder."
        log("[scan] Aborted: project has not been saved (no project folder).\n")
        return
    end

    state.project_dir = projPath:match("^(.*[\\/])")

    -- Resolve the list of source folders from the multiline field. A blank line
    -- (empty after cleaning) would mean "the project folder itself"; parseLines
    -- already drops blanks, so an all-blank box yields no folders -> we fall back
    -- to scanning the project dir directly.
    state.source_dirs = {}
    for _, name in ipairs(parseLines(state.audio_subfolders)) do
        state.source_dirs[#state.source_dirs + 1] = joinSubfolder(state.project_dir, cleanSubfolder(name))
    end
    if #state.source_dirs == 0 then
        state.source_dirs = { state.project_dir }
    end

    state.trash_dir = joinSubfolder(state.project_dir, cleanSubfolder(state.trash_subfolder))

    local patterns = parseIgnorePatterns(state.ignore_text)
    local unused, excluded, referenced, audioFiles, rppFiles =
        scanForUnused(state.project_dir, state.source_dirs, patterns, state.manual_excluded)

    ------------------------------------------------------------------
    -- Diagnostic report
    ------------------------------------------------------------------
    if state.logging then
        r.ClearConsole()
        log("=== JROPE Clean Source: scan report ===\n")
        log("(lists capped at %d items - the counts in parentheses are the true totals)\n\n", LOG_MAX_LIST)

        log("Project file : %s\n", projPath)
        log("Project dir  : %s\n", tostring(state.project_dir))
        log("Source dirs  (%d):\n", #state.source_dirs)
        for _, d in ipairs(state.source_dirs) do log("    %s\n", d) end
        log("Trash dir    : %s\n\n", tostring(state.trash_dir))

        log(".rpp files found in project dir (%d):\n", #rppFiles)
        logList(rppFiles)
        log("\n")

        local refList = sortedKeys(referenced)
        log("Filenames the project(s) reference (%d):\n", #refList)
        logList(refList)
        log("\n")

        log("Files found in source dirs (%d):\n", #audioFiles)
        if #audioFiles == 0 then
            log("    (none - check that the source dir paths above are correct!)\n")
        end
        for i, rec in ipairs(audioFiles) do
            if i > LOG_MAX_LIST then
                log("    ... and %d more (capped)\n", #audioFiles - LOG_MAX_LIST)
                break
            end
            local ref = referenced[rec.name:lower()] and "yes" or "no "
            local ign = isIgnored(rec.name, patterns) and "yes" or "no "
            local verdict
            if ign == "yes" then
                verdict = "kept (ignored)"
            elseif ref == "yes" then
                verdict = "used"
            else
                verdict = "UNUSED"
            end
            log("    %-45s ref=%s ign=%s -> %s\n", rec.name, ref, ign, verdict)
        end
        log("\n")

        log("Active ignore patterns (%d): %s\n\n", #patterns, table.concat(patterns, ", "))

        -- Key findings repeated at the very bottom. The console keeps the most
        -- RECENT lines, so this block is guaranteed visible even on a huge
        -- project where the top of the report has scrolled away.
        log("--- KEY FINDINGS (full detail is at the top of this report) ---\n")
        log("Source dirs scanned: %d\n", #state.source_dirs)
        log("Files in source dirs: %d\n", #audioFiles)
        log("Unused detected    : %d\n", #unused)
        log("===============================================================\n\n")
    end
    ------------------------------------------------------------------

    state.results = unused
    state.excluded = excluded
    state.scanned = true
    state.confirming = false
    state.status = ("Scanned %d .rpp file(s), %d source file(s). %d to move, %d excluded.")
        :format(#rppFiles, #audioFiles, #unused, #excluded)
end

local function runMove()
    -- Re-resolve the trash folder from the CURRENT field value. It would
    -- otherwise be frozen at scan time, so editing the trash name after a scan
    -- (but before moving) would silently use the old destination.
    if not state.project_dir then
        state.status = "Run a scan first."
        state.confirming = false
        return
    end
    state.trash_dir = joinSubfolder(state.project_dir, cleanSubfolder(state.trash_subfolder))

    -- Ensure the trash folder exists. RecursiveCreateDirectory is harmless if it
    -- already exists, so we can call it unconditionally, then verify with the
    -- now-reliable dirExists.
    r.RecursiveCreateDirectory(state.trash_dir, 0)

    if not dirExists(state.trash_dir) then
        state.status = "Could not create the trash folder: " .. tostring(state.trash_dir)
        state.confirming = false
        log("[move] Failed to create trash dir: %s\n", tostring(state.trash_dir))
        return
    end

    log("[move] Trash dir ready: %s\n", tostring(state.trash_dir))

    local movedCount, failCount = 0, 0
    for _, rec in ipairs(state.results) do
        if cleanFile(rec, state.trash_dir) then
            movedCount = movedCount + 1
            log("[move] %s  (from %s)\n", rec.name, rec.path)
        else
            failCount = failCount + 1
            log("[move] FAILED: %s  (from %s)\n", rec.name, rec.path)
        end
    end

    state.results = {}
    state.excluded = {}
    state.manual_excluded = {}
    state.scanned = false
    state.confirming = false
    state.status = ("Moved %d file(s) to '%s'.%s")
        :format(movedCount, cleanSubfolder(state.trash_subfolder), failCount > 0 and (" "..failCount.." could not be moved.") or "")
    log("[move] Done. %d moved, %d failed.\n", movedCount, failCount)

    -- Open the trash folder so the user can see what was moved.
    if movedCount > 0 then
        openDirectory(state.trash_dir)
    end
end


---------------------------------
------------- GUI ---------------
---------------------------------

-- Draw a scrollable list of file records, each with a small action button.
-- Shared by both the "to move" list and the "excluded" list so the row layout
-- (button + name + optional source path + reason) stays consistent.
--   id        - unique child-region id (lists must differ)
--   records   - the list to draw
--   btnLabel  - text on each row's button (e.g. "X" or "+")
--   showReason- if true, show the per-record reason in grey (excluded list)
-- Returns the index of the record whose button was clicked this frame, or nil.
-- (We return the index rather than acting here so the caller can mutate the
-- list AFTER the loop - never edit a list while iterating it.)
local function drawFileList(id, records, btnLabel, showReason)
    local clickedIndex = nil
    local showSource = #state.source_dirs > 1
    local list_h = ImGui.GetTextLineHeightWithSpacing(ctx) * 8
    if ImGui.BeginChild(ctx, id, 0, list_h) then
        for i, rec in ipairs(records) do
            ImGui.PushID(ctx, i)
            if ImGui.SmallButton(ctx, btnLabel) then
                clickedIndex = i
            end
            ImGui.SameLine(ctx)
            ImGui.Text(ctx, rec.name)
            if showSource then
                -- Strip the project-dir prefix so the shown path is short. Plain
                -- string ops (not patterns) avoid escaping headaches with the
                -- special characters common in Windows paths.
                local shortPath = rec.path
                if rec.path:sub(1, #state.project_dir) == state.project_dir then
                    shortPath = rec.path:sub(#state.project_dir + 1)
                end
                ImGui.SameLine(ctx)
                ImGui.TextColored(ctx, 0x808080FF, "  [" .. shortPath .. "]")
            end
            if showReason and rec.reason then
                ImGui.SameLine(ctx)
                ImGui.TextColored(ctx, 0x808080FF, "  (" .. rec.reason .. ")")
            end
            ImGui.PopID(ctx)
        end
        ImGui.EndChild(ctx)
    end
    return clickedIndex
end


local function drawWindow()
    ImGui.SetNextWindowSize(ctx, 460, 600, ImGui.Cond_FirstUseEver)

    local visible, open = ImGui.Begin(ctx, SCRIPT_NAME or "Clean Source Directory", true)
    if visible then

        --==== About (collapsible) ====--
        -- CollapsingHeader returns true only while it's expanded, so everything
        -- inside the 'if' is hidden when the user collapses it. It starts
        -- collapsed by default, which keeps the window tidy for repeat users.
        if ImGui.CollapsingHeader(ctx, "About...") then
            ImGui.TextWrapped(ctx,
                "This tool finds audio files in your projects' source folders that " ..
                "aren't used by the current or any other session in the same directory," ..
                "then moves them to a trash folder so you verify before deleting.")
            ImGui.Spacing(ctx)
            ImGui.BulletText(ctx, "It scans every .rpp in the project folder, not just the open one.")
            ImGui.BulletText(ctx, "Ignore patterns protect files you don't want touched.")
            ImGui.BulletText(ctx, "Review the results and add/remove files before moving.")
            ImGui.Spacing(ctx)
            ImGui.TextWrapped(ctx,
                "WARNING: Samples referenced by plugins cannot be detected! " ..
                "Be sure to validate any samplers you want to retain.")
            ImGui.Spacing(ctx)
            ImGui.Spacing(ctx)
        end

        --==== Ignore patterns ====--
        ImGui.SeparatorText(ctx, "Ignore patterns")
        ImGui.TextWrapped(ctx,
            "Files whose name contains any of these will never be moved. " ..
            "One pattern per line (e.g. .png, .mp4, _REFERENCE).")
        ImGui.Spacing(ctx)

        local box_h = ImGui.GetTextLineHeight(ctx) * 5
        local changed, newText = ImGui.InputTextMultiline(ctx, "##ignore", state.ignore_text, -1, box_h)
        if changed then
            state.ignore_text = newText
            saveSettings()
        end

        local patterns = parseIgnorePatterns(state.ignore_text)
        ImGui.TextColored(ctx, 0x9090FFFF,
            ("%d active pattern%s"):format(#patterns, #patterns == 1 and "" or "s"))

        ImGui.Spacing(ctx)

        --==== Folders ====--
        ImGui.SeparatorText(ctx, "Folders")
        ImGui.TextWrapped(ctx,
            "Source folders to scan (one per line), relative to your project " ..
            "folder. Each is searched recursively. Leave the box empty to scan " ..
            "the base project folder itself.")
        ImGui.Spacing(ctx)

        local folders_h = ImGui.GetTextLineHeight(ctx) * 4
        local arv, newFolders = ImGui.InputTextMultiline(ctx, "##folders", state.audio_subfolders, -1, folders_h)
        if arv then
            state.audio_subfolders = newFolders
            saveSettings()
        end

        local folderList = parseLines(state.audio_subfolders)
        ImGui.TextColored(ctx, 0x9090FFFF,
            ("%d source folder%s"):format(#folderList, #folderList == 1 and "" or "s"))

        ImGui.Spacing(ctx)
        local trv; trv, state.trash_subfolder = ImGui.InputText(ctx, "Trash subfolder", state.trash_subfolder)
        if trv then saveSettings() end

        ImGui.Spacing(ctx)
        if ImGui.Button(ctx, "Scan for unused files") then
            runScan()
        end
        ImGui.SameLine(ctx)
        local lrv; lrv, state.logging = ImGui.Checkbox(ctx, "Log to console", state.logging)
        if lrv then saveSettings() end

        --==== Results ====--
        if state.scanned then
            ImGui.Spacing(ctx)
            ImGui.SeparatorText(ctx, ("To move (%d)"):format(#state.results))

            if #state.results == 0 then
                ImGui.Text(ctx, "Nothing queued to move.")
            else
                ImGui.TextWrapped(ctx, "Click X to hold a file back (it moves to the excluded list below).")
                ImGui.Spacing(ctx)

                local removeIndex = drawFileList("##results", state.results, "X", false)
                if removeIndex then
                    -- Move the record to the excluded list, tagged as a manual hold,
                    -- and remember the name so a re-scan keeps it excluded too.
                    local rec = table.remove(state.results, removeIndex)
                    rec.reason = "manual"
                    state.excluded[#state.excluded + 1] = rec
                    state.manual_excluded[rec.name:lower()] = true
                end

                ImGui.Spacing(ctx)

                --==== Move / confirm ====--
                local trashLabel = cleanSubfolder(state.trash_subfolder)
                if trashLabel == "" then trashLabel = "(project folder)" end
                if not state.confirming then
                    if ImGui.Button(ctx, ("Move %d file(s) to %s"):format(#state.results, trashLabel)) then
                        state.confirming = true
                    end
                else
                    ImGui.TextWrapped(ctx,
                        ("Move %d file(s) into a '%s' folder in your project directory? " ..
                         "They are NOT deleted.")
                        :format(#state.results, trashLabel))
                    ImGui.Spacing(ctx)
                    if ImGui.Button(ctx, "Yes, move them") then
                        runMove()
                    end
                    ImGui.SameLine(ctx)
                    if ImGui.Button(ctx, "Cancel") then
                        state.confirming = false
                    end
                end
            end

            --==== Excluded files ====--
            ImGui.Spacing(ctx)
            ImGui.SeparatorText(ctx, ("Excluded - won't move (%d)"):format(#state.excluded))

            if #state.excluded == 0 then
                ImGui.Text(ctx, "No files are being excluded.")
            else
                ImGui.TextWrapped(ctx,
                    "These are unused but filtered by an ignore pattern or manually. " ..
                    "Click + to send one back to the move list.")
                ImGui.Spacing(ctx)

                local returnIndex = drawFileList("##excluded", state.excluded, "+", true)
                if returnIndex then
                    -- Send the record back to the move list. If it was a manual hold,
                    -- forget that so a re-scan won't re-exclude it. (A pattern-based
                    -- exclusion will come back on re-scan unless the user edits the
                    -- pattern - we note that in the status so it isn't a surprise.)
                    local rec = table.remove(state.excluded, returnIndex)
                    state.manual_excluded[rec.name:lower()] = nil
                    if rec.reason == "pattern" then
                        state.status = ("Returned '%s'. Note: an ignore pattern still matches it, so a re-scan will exclude it again unless you edit the pattern.")
                            :format(rec.name)
                    end
                    rec.reason = nil
                    state.results[#state.results + 1] = rec
                    table.sort(state.results, function(a, b) return a.name:lower() < b.name:lower() end)
                end
            end
        end

        --==== Status line ====--
        if state.status ~= "" then
            ImGui.Spacing(ctx)
            ImGui.Separator(ctx)
            ImGui.TextWrapped(ctx, state.status)
        end

        ImGui.End(ctx)
    end

    return open and not state.want_close
end


function main()
    if drawWindow() then
        r.defer(main)
    end
end


---------------------------------
-------------- MAIN -------------
---------------------------------

loadSettings()   -- restore the user's saved patterns/folders before drawing
main()
