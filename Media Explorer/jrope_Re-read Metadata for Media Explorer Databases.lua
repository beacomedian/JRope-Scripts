--[[
 * Name: Re-read Metadata for Media Explorer Databases
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 0.5
 * Provides:
    [main=main,mediaexplorer] . >
 * Link: https://www.jesserope.com
 * About:
    # After adding/changing Media Explorer metadata columns (and restarting REAPER),
    # database entries still show blank values until their metadata is re-read.
    # This does that in bulk.
    #
    # REAPER has no "re-read a whole database" command, so this drives the per-file
    # commands: Select all (40041) + Re-read metadata (42076). For "all databases"
    # it walks the shortcuts tree with the keyboard, re-reading each DB it lands on.
    #
    # IMPORTANT: re-reading is synchronous - REAPER is UNRESPONSIVE while a database
    # is scanned (no live progress within a single database; the bar advances between
    # databases). Large libraries can take a long time.
    #
    # Two modes:
    #   - "Re-read current database" : the database currently shown (reliable)
    #   - "Re-read ALL databases"    : walk the tree and do every one (experimental)
    #
    # Requires the SWS extension, js_ReaScriptAPI, and ReaImGui.
 * Changelog:
    # v0.5 - Public Alpha
 * To Do:
    # The currently-shown database is skipped by the all-databases walk (it's the
    #   combo's current value); run "current database" for it, or start from a folder.
]]

---------------------------------
---------- USER CONFIG ----------
---------------------------------

ENABLE_DEBUG_LOG = false

-- Pause (seconds) after a tree move before reading where we landed, in case the
-- Media Explorer loads the node's file list asynchronously. Too short and slow-
-- loading databases get read stale (and skipped).
local POST_NAV_DELAY = 0.35


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local r = reaper

-- Media Explorer WM_COMMAND ids (captured with the ME Probe helper)
local CMD_SELECT_ALL = 40041
local CMD_REREAD     = 42076
local CMD_RESCAN_ALL = 42085  -- rescan all databases for NEW files (optional pre-step)

local ID_DB_COMBO = 1002
local ID_TREE     = 1000

-- Win32 / TreeView bits
local VK_HOME, VK_DOWN = 0x24, 0x28
local TVM_GETNEXTITEM  = 0x110A
local TVGN_CARET       = 0x0009

local ctx = nil


---------------------------------
----------- FUNCTIONS -----------
---------------------------------

local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")


local function get_me()
  return r.JS_Window_Find(r.JS_Localize("Media Explorer", "common"), true) or nil
end

local function get_window_text(hwnd)
  local t = r.JS_Window_GetTitle(hwnd)
  if type(t) == "string" then return t end
  local _, s = r.JS_Window_GetTitle(hwnd, "", 1024); return s or ""
end

local function me_cmd(mx, cmd)  -- synchronous; blocks until REAPER finishes
  r.JS_WindowMessage_Send(mx, "WM_COMMAND", cmd, 0, 0, 0)
  Log("Sent ME command:", cmd)
end

local function combo_title(mx)
  local c = r.JS_Window_FindChildByID(mx, ID_DB_COMBO)
  return c and get_window_text(c) or ""
end

local function get_tree(mx) return r.JS_Window_FindChildByID(mx, ID_TREE) end

local function tree_key(tree, vk)
  r.JS_Window_SetFocus(tree)
  r.JS_WindowMessage_Send(tree, "WM_KEYDOWN", vk, 0, 0, 0)
  r.JS_WindowMessage_Send(tree, "WM_KEYUP", vk, 0, 0, 0)
end

-- Truncated caret handle; only ever compared for equality (movement detection).
local function tree_caret(tree)
  return r.BR_Win32_SendMessage(tree, TVM_GETNEXTITEM, TVGN_CARET, 0) or 0
end

-- Rough count of databases from the MediaDB folder (each is an NN.ReaperFileList).
-- Only used to size the progress bar; the walk finds the real ones.
local function estimate_db_count()
  local mdb = r.GetResourcePath() .. "/MediaDB"
  local n, i = 0, 0
  while true do
    local f = r.EnumerateFiles(mdb, i)
    if not f then break end
    if f:lower():match("%.reaperfilelist$") then n = n + 1 end
    i = i + 1
  end
  return n
end


---------------------------------
------------ STATE --------------
---------------------------------

local G = {
  status      = "Ready. Choose a mode below.",
  est_total   = 0,
  processed   = 0,
  progress    = 0,     -- 0..1
  gap         = 10.0,  -- seconds to wait between databases (window to press STOP)
  rescan_first = false,
  window_open = true,
  confirm     = nil,   -- "current" | "all" pending confirmation
}

local run = {
  active = false, cancel = false, mode = nil,
  phase = "", t_next = 0,
  last_title = "", cur_title = "",
  moved = false, last_caret = 0,
}


---------------------------------
----------- RUNNERS -------------
---------------------------------

local function finish(msgtext)
  run.active = false
  G.status = msgtext
end

-- CURRENT DATABASE: two frames - announce (so the status renders), then the
-- blocking select-all + re-read.
local function step_current(mx, now)
  if run.phase == "announce" then
    G.status = "Re-reading current database... REAPER will be unresponsive until done."
    G.progress = 0
    run.phase = "work"
  elseif run.phase == "work" then
    me_cmd(mx, CMD_SELECT_ALL)
    me_cmd(mx, CMD_REREAD)
    G.progress = 1
    finish("Done. Re-read the current database.")
  end
end

-- ALL DATABASES: keyboard-walk the tree, re-reading whenever the shown location
-- changes to a "DB:" entry.
local function step_all(mx, now)
  local tree = get_tree(mx)
  if not tree then finish("Couldn't find the Media Explorer tree."); return end
  if run.cancel then finish(string.format("Cancelled after %d database(s).", G.processed)); return end

  if run.phase == "home" then
    tree_key(tree, VK_HOME)
    run.last_title = combo_title(mx)  -- current node: skip re-processing it
    run.moved, run.last_caret = false, tree_caret(tree)
    run.t_next, run.phase = now + POST_NAV_DELAY, "eval"

  elseif run.phase == "nav" then
    run.last_caret = tree_caret(tree)
    tree_key(tree, VK_DOWN)
    run.moved = true
    run.t_next, run.phase = now + POST_NAV_DELAY, "eval"

  elseif run.phase == "eval" then
    if now < run.t_next then return end
    if run.moved and tree_caret(tree) == run.last_caret then
      finish(string.format("Done. Re-read %d database(s).", G.processed)); return
    end
    run.moved = false
    local title = combo_title(mx)
    Log("Walk landed on:", title, "| changed:", tostring(title ~= run.last_title), "| processed:", G.processed)
    if title ~= run.last_title then
      run.last_title = title
      if title:match("^%s*DB:") then
        run.cur_title = title
        G.status = string.format("Re-reading %s  (%d/~%d)  - REAPER will be unresponsive...",
          title, G.processed + 1, math.max(G.est_total, G.processed + 1))
        G.progress = G.processed / math.max(G.est_total, G.processed + 1)
        run.phase = "read"   -- draw renders the status this frame; work happens next
        return
      end
    end
    run.phase = "nav"

  elseif run.phase == "read" then
    me_cmd(mx, CMD_SELECT_ALL)
    me_cmd(mx, CMD_REREAD)              -- BLOCKS (REAPER frozen)
    G.processed = G.processed + 1
    G.progress = G.processed / math.max(G.est_total, G.processed)
    run.t_next = now + G.gap
    run.phase = "cooldown"

  elseif run.phase == "cooldown" then
    -- Responsive window between databases so STOP can interrupt the run.
    local remain = run.t_next - now
    if remain <= 0 then
      run.phase = "nav"
    else
      G.status = string.format("Re-read %s. Next database in %.0fs - press STOP to interrupt.",
        run.cur_title, remain)
    end
  end
end

local function step_run()
  if not run.active then return end
  local mx = get_me()
  if not mx then finish("Media Explorer closed - stopped."); return end
  local now = r.time_precise()
  if run.mode == "current" then step_current(mx, now)
  else step_all(mx, now) end
end

local function begin_run(mode)
  local mx = get_me()
  if not mx then G.status = "Media Explorer isn't open."; return end
  if mode == "all" and G.rescan_first then me_cmd(mx, CMD_RESCAN_ALL) end
  G.processed, G.progress = 0, 0
  run.active, run.cancel, run.mode = true, false, mode
  run.phase = (mode == "current") and "announce" or "home"
  run.last_title, run.moved, run.last_caret = "", false, 0
  G.status = (mode == "current") and "Starting..." or "Walking databases..."
end


---------------------------------
------------- GUI ---------------
---------------------------------

local function draw()
  r.ImGui_SetNextWindowSize(ctx, 580, 430, r.ImGui_Cond_FirstUseEver())
  local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true)
  if not open then G.window_open = false; r.ImGui_End(ctx); return end

  if visible then
    r.ImGui_TextWrapped(ctx,
      "Re-reads embedded metadata into the Media Explorer's database cache so newly " ..
      "added columns get populated. Run this after adding columns and RESTARTING REAPER.")
    r.ImGui_Spacing(ctx)
    r.ImGui_TextColored(ctx, 0xFFCA28FF,
      "Note: REAPER freezes while each database is scanned - this is unavoidable.")
    r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx); r.ImGui_Spacing(ctx)

    local busy = run.active
    if busy then r.ImGui_BeginDisabled(ctx, true) end

    if r.ImGui_Button(ctx, "Re-read current database") then G.confirm = "current" end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Re-read ALL databases (experimental)") then G.confirm = "all" end

    local _, rf = r.ImGui_Checkbox(ctx, "Scan all databases for new files first", G.rescan_first)
    G.rescan_first = rf

    if busy then r.ImGui_EndDisabled(ctx) end

    -- Gap slider stays enabled during a run so you can tune it on the fly.
    r.ImGui_SetNextItemWidth(ctx, 220)
    local _, gv = r.ImGui_SliderDouble(ctx, "Gap between databases (s)", G.gap, 0.0, 60.0, "%.0f")
    G.gap = gv

    r.ImGui_Spacing(ctx)
    if run.active then
      if r.ImGui_Button(ctx, "STOP (takes effect between databases)") then run.cancel = true end
    end

    r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx); r.ImGui_Spacing(ctx)

    r.ImGui_Text(ctx, string.format("Databases (estimated): %d", G.est_total))
    r.ImGui_ProgressBar(ctx, G.progress, -1, 0,
      string.format("%d / ~%d", G.processed, math.max(G.est_total, G.processed)))
    r.ImGui_Spacing(ctx)
    -- Colour the status: RED while a database is scanning (REAPER frozen / about to
    -- freeze), GREEN during the cooldown gap (your window to press STOP).
    local status_col = nil
    if run.active then
      status_col = (run.phase == "cooldown") and 0x66BB6AFF or 0xEF5350FF
    end
    if status_col then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), status_col) end
    r.ImGui_TextWrapped(ctx, "Status: " .. G.status)
    if status_col then r.ImGui_PopStyleColor(ctx) end
  end

  r.ImGui_End(ctx)
end

local function loop()
  if not G.window_open then return end

  -- Handle a pending confirmation between frames (modal MB must not run mid-frame).
  if G.confirm then
    local mode = G.confirm; G.confirm = nil
    local text
    if mode == "current" then
      text = "Re-read metadata for every file in the CURRENT database?\n\n" ..
             "REAPER will be UNRESPONSIVE until it finishes (can be a while on big databases)."
    else
      text = string.format("Re-read metadata for ALL databases (~%d)?\n\n" ..
             "REAPER will FREEZE while each one is scanned, one after another - this can take " ..
             "a very long time for large libraries. You can STOP between databases.", G.est_total)
    end
    if r.MB(text, "Confirm re-read", 1) == 1 then begin_run(mode) end
  end

  step_run()
  draw()
  r.defer(loop)
end


---------------------------------
------------- MAIN --------------
---------------------------------

if not (r.BR_Win32_SendMessage and r.BR_Win32_GetPrivateProfileString) then
  r.MB("This script requires the SWS extension.", "ERROR: SWS missing", 0); return
end
if not (r.APIExists and r.APIExists("JS_Window_Find") and r.APIExists("JS_WindowMessage_Send")) then
  r.MB("This script requires js_ReaScriptAPI (install via ReaPack).", "ERROR: js_ReaScriptAPI missing", 0); return
end
if not r.APIExists("ImGui_CreateContext") then
  r.MB("This script requires ReaImGui (install via ReaPack).", "ERROR: ReaImGui missing", 0); return
end
if not get_me() then
  r.MB("Open the Media Explorer first, then run this script.", "Re-read Metadata", 0); return
end

G.est_total = estimate_db_count()
ctx = r.ImGui_CreateContext(SCRIPT_NAME)
r.defer(loop)
