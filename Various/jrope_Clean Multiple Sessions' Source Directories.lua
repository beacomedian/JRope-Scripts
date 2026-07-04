--[[
 * Name: JROPE - Clean Multiple Sessions' Source Directories (GUI)
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 2.8
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
    # 2.8 - Keep subproject render proxies: a "<sub>.rpp-PROX" (and its peaks) is now
      kept whenever the "<sub>.rpp" it renders from is referenced.
    # 2.7 - Moves now preserve each file's folder hierarchy inside the trash folder.
      Added an "In unused folder" section to restore files individually or all at once.
    # 2.6 - Animated progress bar while scanning (scan now runs incrementally as a
      coroutine, so the window stays responsive on large projects).
    # 2.5 - Scan .rpp files recursively so nested subprojects also count as sessions
      whose referenced media is protected from cleanup.
    # 2.4 - Multiple source folders, recursive scanning, open trash folder when done.
    # 2.3 - Settings persist between launches (ext-state). Added About section.
    # 2.2 - Added optional console logging for diagnosing scan results.
    # 2.1 - Wired up cross-platform scan. Results list + per-row removal + confirmed move.
    # 2.0 - Rebuilt around a ReaImGui window. Added ignore-pattern input.
    # 1.0 - Initial console-based release (adapted from fbeauvaisc).
 * To Do:
    #


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

-- How many milliseconds of scan work to do per frame. The scan runs as a
-- coroutine that pauses (yields) once this budget is spent, so the progress
-- window can repaint. Higher = faster scan, choppier animation; lower =
-- smoother animation, slower scan.
local SCAN_FRAME_BUDGET_MS = 30

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
    -- Live scan state (a scan runs incrementally across defer frames so the
    -- window can show a progress bar instead of freezing on big projects).
    scanning      = false,  -- is a scan in progress right now?
    scan_co       = nil,    -- the scan coroutine while it runs
    scan_label    = "",     -- current scan phase, shown by the progress bar
    scan_count    = 0,      -- running item count for the current phase
    progress      = -1.0,   -- 0..1 = determinate fill; <0 = indeterminate bounce
    -- Contents of the trash/unused folder, for the restore section.
    trash_contents = {},    -- records { path, name } currently sitting in trash
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

-- Is this source file used by any scanned project?
-- Direct hit: its basename is in the referenced set.
-- Subproject proxy: a file named "<sub>.rpp-PROX" is REAPER's auto-rendered audio
-- for the subproject "<sub>.rpp". The parent .rpp references only the .rpp (see
-- collectReferences), so the .rpp-PROX beside it is never in 'referenced' on its
-- own - but it must ride along whenever its .rpp is referenced. We detect that by
-- stripping the "-prox" suffix and re-checking. Same for a ".reapeaks" peak file
-- sitting next to a referenced source.
local function isReferenced(name, referenced)
    local lower = name:lower()
    if referenced[lower] then return true end

    -- "<sub>.rpp-PROX" -> keep if "<sub>.rpp" is referenced.
    local proxBase = lower:match("^(.*%.rpp)%-prox$")
    if proxBase and referenced[proxBase] then return true end

    -- "<file>.reapeaks" -> keep if "<file>" is used (peaks follow their audio).
    -- Recurse so a proxy's peak ("<sub>.rpp-PROX.reapeaks") is caught via the
    -- proxy rule above.
    local peakBase = lower:match("^(.-)%.reapeaks$")
    if peakBase and isReferenced(peakBase, referenced) then return true end

    return false
end

-- The core scan, as a COROUTINE. Same logic and return values as before, but it
-- pauses (coroutine.yield) periodically so the caller can repaint a progress bar
-- between bursts of work instead of freezing on a big project. It updates
-- state.scan_label / scan_count / progress as it goes.
--
-- Takes a LIST of source folders (absolute paths ending in SEP), each scanned
-- recursively. 'manualSet' is a set of lowercased filenames the user manually
-- excluded this session; those go to the excluded list too.
-- Returns (when the coroutine finishes):
--   unused      - records { path, name } that will be moved
--   excluded    - records { path, name, reason } held back ("pattern"/"manual")
--   referenced  - set of referenced basenames (for logging)
--   audioFiles  - list of every source file found, as records (for logging)
--   rppFiles    - list of .rpp display names scanned (for logging)
local function makeScanCoroutine(projectDir, sourceDirs, ignorePatterns, manualSet, trashDir)
    manualSet = manualSet or {}

    -- Windows paths compare case-insensitively; normalise for the trash-skip test.
    local winOS = r.GetOS():find("Win") ~= nil
    local function samePath(a, b)
        if winOS then return a:lower() == b:lower() end
        return a == b
    end

    return coroutine.create(function()

        -- Recursively visit every file under 'dir', calling onFile(dir, name)
        -- for each. Yields after every subdirectory and every 200 files so a deep
        -- tree can't block the UI. (Replaces the old listFilesRecursive: same walk,
        -- but able to pause.) Skips the trash folder so files already moved there
        -- (which now keep their original hierarchy) aren't re-detected as unused.
        local seen = 0
        local function walk(dir, onFile)
            for _, f in ipairs(listFiles(dir)) do
                onFile(dir, f)
                seen = seen + 1
                if seen % 200 == 0 then coroutine.yield() end
            end
            for _, sub in ipairs(listSubdirs(dir)) do
                local subDir = dir .. sub .. SEP
                if not (trashDir and samePath(subDir, trashDir)) then
                    walk(subDir, onFile)
                end
                coroutine.yield()
            end
        end

        -- 1. Find every .rpp anywhere under the project folder (recursively), so
        --    nested subprojects (e.g. Subprojects/Wind/*.rpp) also count as
        --    sessions whose referenced media must be kept. We match ONLY names
        --    ending in .rpp, so rendered proxies (.rpp-PROX) aren't parsed.
        --    Indeterminate progress: we don't know the tree size up front.
        state.scan_label = "Finding project files (.rpp)..."
        state.progress   = -1.0
        state.scan_count = 0
        local rppRecords = {}
        walk(projectDir, function(dir, name)
            if name:lower():match("%.rpp$") then
                rppRecords[#rppRecords + 1] = { path = dir, name = name }
                state.scan_count = #rppRecords
            end
        end)
        table.sort(rppRecords, function(a, b)
            return (a.path .. a.name):lower() < (b.path .. b.name):lower()
        end)

        -- Display names for logging: relative to the project dir where possible,
        -- so a nested subproject shows as "Subprojects\Wind\...rpp" not an
        -- absolute path.
        local rppFiles = {}
        for _, rec in ipairs(rppRecords) do
            local full = rec.path .. rec.name
            if full:sub(1, #projectDir) == projectDir then
                rppFiles[#rppFiles + 1] = full:sub(#projectDir + 1)
            else
                rppFiles[#rppFiles + 1] = full
            end
        end

        -- 2. Build the set of filenames those projects reference. Determinate now
        --    that we know the .rpp count.
        state.scan_label = "Reading project references..."
        state.scan_count = 0
        local referenced = {}
        for i, rec in ipairs(rppRecords) do
            collectReferences(rec.path .. rec.name, referenced)
            state.scan_count = i
            state.progress   = (#rppRecords > 0) and (i / #rppRecords) or 1.0
            coroutine.yield()
        end

        -- 3. Recursively list every source folder, gathering records.
        --    Indeterminate again.
        state.scan_label = "Listing source files..."
        state.progress   = -1.0
        state.scan_count = 0
        local audioFiles = {}
        for _, dir in ipairs(sourceDirs) do
            walk(dir, function(fdir, name)
                audioFiles[#audioFiles + 1] = { path = fdir, name = name }
                state.scan_count = #audioFiles
            end)
        end
        table.sort(audioFiles, function(a, b) return a.name:lower() < b.name:lower() end)

        -- 4. Among unreferenced files, sort into "will move" vs "excluded".
        --    A file is excluded if an ignore pattern matches it (reason "pattern")
        --    or the user manually held it back earlier this session (reason
        --    "manual"). Pattern takes priority in the label when both apply.
        state.scan_label = "Checking for unused files..."
        state.scan_count = 0
        local unused, excluded = {}, {}
        for i, rec in ipairs(audioFiles) do
            if not isReferenced(rec.name, referenced) then
                if isIgnored(rec.name, ignorePatterns) then
                    excluded[#excluded + 1] = { path = rec.path, name = rec.name, reason = "pattern" }
                elseif manualSet[rec.name:lower()] then
                    excluded[#excluded + 1] = { path = rec.path, name = rec.name, reason = "manual" }
                else
                    unused[#unused + 1] = rec
                end
            end
            state.scan_count = i
            state.progress   = (#audioFiles > 0) and (i / #audioFiles) or 1.0
            if i % 200 == 0 then coroutine.yield() end
        end

        return unused, excluded, referenced, audioFiles, rppFiles
    end)
end

-- Return 'path' (a folder ending in SEP) relative to 'base' (also ending in SEP),
-- i.e. the part below base. Returns "" when path IS base, or when path isn't
-- under base at all (caller then falls back to base with no subfolder).
local function relativeUnder(path, base)
    if base and #base > 0 and path:sub(1, #base) == base then
        return path:sub(#base + 1)
    end
    return ""
end

-- Move one file into destDir, creating destDir if needed and renaming to avoid
-- clobbering an existing file there. Returns the final target path on success,
-- or nil if the source was missing or the rename failed.
local function moveFile(sourcePath, destDir, filename)
    if not r.file_exists(sourcePath) then return nil end

    r.RecursiveCreateDirectory(destDir, 0)   -- harmless if it already exists

    local target = destDir .. filename
    local counter = 1
    while r.file_exists(target) do
        local stem, ext = filename:match("(.+)%.(%w+)$")
        if stem then
            target = destDir .. stem .. "_" .. counter .. "." .. ext
        else
            target = destDir .. filename .. "_" .. counter
        end
        counter = counter + 1
    end

    if os.rename(sourcePath, target) then return target end
    return nil
end

-- Move the audio file (plus its peak file, best-effort) into the trash,
-- PRESERVING its folder position relative to the project. E.g.
--   <proj>\Audio Files\Wind\x.wav  ->  <trash>\Audio Files\Wind\x.wav
-- Keeping the hierarchy means two files with the same name in different folders
-- no longer collide in the trash, and each file can be restored to exactly
-- where it came from.
-- 'rec' is a { path, name } record: path is the folder the file lives in.
local function cleanFile(rec, trashDir, projectDir)
    local destDir = trashDir .. relativeUnder(rec.path, projectDir)
    local moved   = moveFile(rec.path .. rec.name, destDir, rec.name) ~= nil

    -- .reapeaks usually sits next to the audio; some setups use a 'peaks' subfolder.
    local peakName = rec.name .. ".reapeaks"
    if not moveFile(rec.path .. peakName, destDir, peakName) then
        moveFile(rec.path .. "peaks" .. SEP .. peakName, destDir, peakName)
    end

    return moved
end

-- Restore a file from the trash back to its original location. Because cleanFile
-- preserved the hierarchy under the trash folder, the file's path relative to the
-- trash folder IS its path relative to the project - so we just mirror it back.
-- Moves the peak file alongside too (best-effort).
local function restoreFile(rec, trashDir, projectDir)
    local destDir = projectDir .. relativeUnder(rec.path, trashDir)
    local moved   = moveFile(rec.path .. rec.name, destDir, rec.name) ~= nil

    local peakName = rec.name .. ".reapeaks"
    moveFile(rec.path .. peakName, destDir, peakName)

    return moved
end

-- List every file under 'dir' and its subfolders as { path, name } records.
-- Synchronous (used only for the trash folder, which is small); .reapeaks peak
-- files are skipped so the restore list shows only the media the user recognises
-- (peaks ride along with their audio during restore).
local function listTreeRecords(dir)
    local out = {}
    local function walk(d)
        for _, f in ipairs(listFiles(d)) do
            if not f:lower():match("%.reapeaks$") then
                out[#out + 1] = { path = d, name = f }
            end
        end
        for _, sub in ipairs(listSubdirs(d)) do
            walk(d .. sub .. SEP)
        end
    end
    walk(dir)
    return out
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

-- The folder of the currently open project, or nil if it hasn't been saved.
local function resolveProjectDir()
    local _, projPath = r.EnumProjects(-1, "")
    if not projPath or projPath == "" then return nil end
    return projPath:match("^(.*[\\/])")
end

-- Rebuild state.trash_contents from whatever is currently in the trash folder,
-- resolving the trash path from the CURRENT project + trash-subfolder field so
-- the restore list stays correct even before the first scan or after the field
-- is edited. Cheap enough to call synchronously (the trash folder is small).
local function refreshTrashContents()
    state.trash_contents = {}

    local projectDir = resolveProjectDir()
    if not projectDir then return end
    state.project_dir = state.project_dir or projectDir

    local trashDir = joinSubfolder(projectDir, cleanSubfolder(state.trash_subfolder))
    state.trash_dir = trashDir
    if not dirExists(trashDir) then return end

    local recs = listTreeRecords(trashDir)
    table.sort(recs, function(a, b) return a.name:lower() < b.name:lower() end)
    state.trash_contents = recs
end

-- Start a scan: resolve the folders, then hand the heavy disk work to a
-- coroutine that advanceScan() drives across frames. Returns immediately so the
-- window keeps painting (and shows a progress bar) while the scan runs.
local function beginScan()
    if state.scanning then return end   -- already running; ignore repeat clicks

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

    -- Stash the inputs the finishing report needs, then kick off the coroutine.
    state.scan_projPath = projPath
    state.scan_patterns = parseIgnorePatterns(state.ignore_text)
    state.scan_co  = makeScanCoroutine(state.project_dir, state.source_dirs,
                                       state.scan_patterns, state.manual_excluded,
                                       state.trash_dir)
    state.scanning   = true
    state.scanned    = false   -- hide any previous results while the new scan runs
    state.confirming = false
    state.scan_label = "Starting scan..."
    state.scan_count = 0
    state.progress   = -1.0
    state.status     = "Scanning..."
end

-- Called when the scan coroutine finishes. Prints the diagnostic report (if
-- logging) and commits the results into state. Same body as the old synchronous
-- tail of runScan; the locals now arrive as arguments.
local function finishScan(unused, excluded, referenced, audioFiles, rppFiles)
    local projPath = state.scan_projPath
    local patterns = state.scan_patterns

    ------------------------------------------------------------------
    -- Diagnostic report
    ------------------------------------------------------------------
    if state.logging then
        r.ClearConsole()
        log("=== JROPE Clean Source: scan report ===\n")
        log("(lists capped at %d items - the counts in parentheses are the true totals)\n\n", LOG_MAX_LIST)

        log("Project file : %s\n", tostring(projPath))
        log("Project dir  : %s\n", tostring(state.project_dir))
        log("Source dirs  (%d):\n", #state.source_dirs)
        for _, d in ipairs(state.source_dirs) do log("    %s\n", d) end
        log("Trash dir    : %s\n\n", tostring(state.trash_dir))

        log(".rpp files found under project dir, incl. subprojects (%d):\n", #rppFiles)
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
            local ref = isReferenced(rec.name, referenced) and "yes" or "no "
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

-- Drive the scan coroutine for up to SCAN_FRAME_BUDGET_MS this frame. Resumes it
-- repeatedly until the budget is spent (still work to do) or it finishes.
-- Call once per frame from the GUI loop while state.scanning is true.
local function advanceScan()
    local deadline = r.time_precise() + SCAN_FRAME_BUDGET_MS / 1000.0
    repeat
        local ok, a, b, c, d, e = coroutine.resume(state.scan_co)

        if not ok then
            -- Coroutine hit a Lua error. Abandon the scan and surface it.
            state.scanning = false
            state.scan_co  = nil
            state.status   = "Scan error: " .. tostring(a)
            log("[scan] coroutine error: %s\n", tostring(a))
            return
        end

        if coroutine.status(state.scan_co) == "dead" then
            -- a..e are the coroutine's return values (the scan results).
            state.scanning = false
            state.scan_co  = nil
            state.progress = 1.0
            finishScan(a, b, c, d, e)
            return
        end
    until r.time_precise() >= deadline
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
        if cleanFile(rec, state.trash_dir, state.project_dir) then
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

    -- Refresh the restore list so the just-moved files appear in it.
    refreshTrashContents()

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


-- Draw the trash/unused-folder list: each row has a "Restore" button and shows
-- the file's folder relative to the trash dir (so the preserved hierarchy is
-- visible). Returns the index whose Restore button was clicked this frame, or nil.
local function drawTrashList(id, records)
    local clickedIndex = nil
    local list_h = ImGui.GetTextLineHeightWithSpacing(ctx) * 8
    if ImGui.BeginChild(ctx, id, 0, list_h) then
        for i, rec in ipairs(records) do
            ImGui.PushID(ctx, i)
            if ImGui.SmallButton(ctx, "Restore") then
                clickedIndex = i
            end
            ImGui.SameLine(ctx)
            ImGui.Text(ctx, rec.name)
            -- Show the sub-path within the trash folder (== its original location
            -- relative to the project), so the user sees where it will go back to.
            local rel = rec.path
            if state.trash_dir and rec.path:sub(1, #state.trash_dir) == state.trash_dir then
                rel = rec.path:sub(#state.trash_dir + 1)
            end
            if rel ~= "" then
                ImGui.SameLine(ctx)
                ImGui.TextColored(ctx, 0x808080FF, "  [" .. rel .. "]")
            end
            ImGui.PopID(ctx)
        end
        ImGui.EndChild(ctx)
    end
    return clickedIndex
end


-- Draw a progress bar spanning the window width, using the DrawList API.
-- 'frac' >= 0 draws a solid fill of that fraction (0..1). 'frac' < 0 draws an
-- indeterminate "bounce" chip that slides back and forth, for phases whose total
-- isn't known up front (the recursive directory walks). We draw manually rather
-- than use ImGui.ProgressBar because that widget mishandles a negative fraction.
local function drawProgressBar(frac)
    local BAR_H   = 18
    local COL_BG   = 0x333333FF
    local COL_FILL = 0x4DA6FFFF
    local COL_BORD = 0x888888FF

    local dl       = ImGui.GetWindowDrawList(ctx)
    local x0, y0   = ImGui.GetCursorScreenPos(ctx)
    local avail_w  = ImGui.GetContentRegionAvail(ctx)
    local x1, y1   = x0 + avail_w, y0 + BAR_H

    ImGui.DrawList_AddRectFilled(dl, x0, y0, x1, y1, COL_BG)

    if frac >= 0 then
        -- Determinate: solid fill from the left.
        local fx = x0 + avail_w * math.max(0.0, math.min(1.0, frac))
        if fx > x0 then
            ImGui.DrawList_AddRectFilled(dl, x0, y0, fx, y1, COL_FILL)
        end
    else
        -- Indeterminate: a chip ~30% wide bouncing left<->right off wall-clock
        -- time, so it animates at a constant speed regardless of frame rate.
        local t     = ImGui.GetTime(ctx)
        local chipW = avail_w * 0.30
        local span  = avail_w - chipW
        local tri   = math.abs((((t * 0.6) % 2) - 1))   -- 0->1->0 triangle wave
        local cx0   = x0 + span * tri
        ImGui.DrawList_AddRectFilled(dl, cx0, y0, cx0 + chipW, y1, COL_FILL)
    end

    ImGui.DrawList_AddRect(dl, x0, y0, x1, y1, COL_BORD)
    ImGui.Dummy(ctx, avail_w, BAR_H)   -- advance layout cursor past the bar
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
            ImGui.BulletText(ctx, "Moved files keep their folder structure and can be restored below.")
            ImGui.Spacing(ctx)
            ImGui.TextWrapped(ctx,
                "WARNING: Samples referenced by plugins cannot be detected! " ..
                "Be sure to relaunch and review samplers before deleting source.")
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
        -- Disable the scan button (and the logging checkbox) while a scan runs so
        -- the user can't start a second one on top of the coroutine in flight.
        -- Latch the flag ONCE for this frame: the button's own click flips
        -- state.scanning mid-frame, so gating Begin/EndDisabled on the live value
        -- would leave them unbalanced (EndDisabled without a matching Begin).
        local disabled = state.scanning
        if disabled then ImGui.BeginDisabled(ctx) end
        if ImGui.Button(ctx, "Scan for unused files") then
            beginScan()
        end
        ImGui.SameLine(ctx)
        local lrv; lrv, state.logging = ImGui.Checkbox(ctx, "Log to console", state.logging)
        if lrv then saveSettings() end
        if disabled then ImGui.EndDisabled(ctx) end

        --==== Scan progress ====--
        if state.scanning then
            ImGui.Spacing(ctx)
            ImGui.Text(ctx, state.scan_label ~= "" and state.scan_label or "Scanning...")
            drawProgressBar(state.progress)
            -- A live count under the bar: percentage for determinate phases,
            -- a running tally for the indeterminate directory walks.
            if state.progress >= 0 then
                ImGui.Text(ctx, ("%d%%  (%d items)"):format(math.floor(state.progress * 100), state.scan_count))
            else
                ImGui.Text(ctx, ("%d found so far..."):format(state.scan_count))
            end
        end

        --==== Results ====--
        if state.scanned and not state.scanning then
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

        --==== Unused folder (restore) ====--
        -- Shows what's currently sitting in the trash folder, with buttons to put
        -- files back where they came from. Hidden mid-scan to keep the UI calm.
        if not state.scanning then
            ImGui.Spacing(ctx)
            ImGui.SeparatorText(ctx, ("In unused folder (%d)"):format(#state.trash_contents))

            if ImGui.SmallButton(ctx, "Refresh") then
                refreshTrashContents()
            end

            if #state.trash_contents == 0 then
                ImGui.SameLine(ctx)
                ImGui.Text(ctx, "Empty (nothing to restore).")
            else
                ImGui.SameLine(ctx)
                if ImGui.SmallButton(ctx, "Restore all") then
                    local n = #state.trash_contents
                    for _, rec in ipairs(state.trash_contents) do
                        restoreFile(rec, state.trash_dir, state.project_dir)
                    end
                    refreshTrashContents()
                    state.status = ("Restored %d file(s) from the unused folder."):format(n)
                end

                ImGui.TextWrapped(ctx,
                    "Files moved here are shown with their original folder in grey. " ..
                    "Click Restore to put one back in place.")
                ImGui.Spacing(ctx)

                local restoreIndex = drawTrashList("##trash", state.trash_contents)
                if restoreIndex then
                    local rec = state.trash_contents[restoreIndex]
                    restoreFile(rec, state.trash_dir, state.project_dir)
                    refreshTrashContents()
                    state.status = ("Restored '%s'."):format(rec.name)
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
    -- Advance the scan a slice at a time BEFORE drawing, so the window paints the
    -- updated progress/results this frame. advanceScan() clears state.scanning
    -- (and calls finishScan) once the coroutine completes.
    if state.scanning then
        advanceScan()
    end
    if drawWindow() then
        r.defer(main)
    end
end


---------------------------------
-------------- MAIN -------------
---------------------------------

loadSettings()          -- restore the user's saved patterns/folders before drawing
refreshTrashContents()  -- populate the restore list from any existing trash folder
main()
