--[[
 * Name: Batch Phase Alignment
 * Author: Jesse Rope
 * AI: Claude Opus 4.8 Medium
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 0.1
 * Provides:
    [main] . >
 * Link: https://www.jesserope.com
 * About:
    # Batch Phase Alignment
    #
    # REAPER's "Phase Align Items" tool (action 43466) uses only the FIRST selected
    # item as the reference for the ENTIRE selection. This script works around that:
    # it captures the current item selection, logically separates it into vertical 
    # column groups, then runs Phase Align on each column on its own
    # so every column is aligned against its own reference item.
    #
    # The top item in each column group is the reference item.
    #
    # It drives the modeless "Phase Align Items" dialog directly: for each column it
    # selects that column's items, clicks the dialog's "Apply" button (control 1057)
    # via js_ReaScriptAPI, then waits for the analysis to finish before moving on.
    #
    # Completion is detected by watching for the dialog to become enabled again and
    # for the transient progress windows to close (see WAIT SETTINGS below). The first
    # run is verbose (ENABLE_DEBUG_LOG) so the console shows exactly which windows
    # appear/disappear during processing — useful if the wait logic needs tuning.
    #
    # NOTE: this is an asynchronous, dialog-driven script, so it does NOT use the
    # standard Undo_BeginBlock wrapper — Phase Align creates its own undo points.
    #
    # Requires js_ReaScriptAPI (install via ReaPack).
 * Changelog:
    # 0.1 - Initial WIP.
 * To Do:
    # Confirm on real projects whether Apply re-reads the live selection (keep dialog
    #   open) or snapshots it at open time (set REOPEN_PER_COLUMN = true).
    # Once the progress-window signature is known, tighten completion detection.
]]

---------------------------------
---------- USER CONFIG ----------
---------------------------------

-- Must be global (no `local`) so the shared Log() in Common Functions can read it.
ENABLE_DEBUG_LOG = true  -- true = verbose console output (recommended until proven out)

-- ---- grouping -------------------------------------------------------------
-- Items are grouped into a column when their time extents overlap. This tolerance
-- (seconds) is added to the overlap test: 0 = touching/overlapping items group;
-- a small positive value bridges tiny gaps; a small negative value requires real overlap.
local OVERLAP_TOLERANCE = -0.1

-- Phase alignment needs 2+ items. Columns with a single item are skipped by default.
local SKIP_SINGLE_ITEM_COLUMNS = true

-- ---- dialog handling ------------------------------------------------------
-- false: open the dialog once and re-Apply per column (assumes Apply re-reads the
--        live selection each time — cleaner, preserves your dialog options).
-- true : close and reopen the dialog for every column (use if keep-open aligns every
--        column to the first column's reference).
local REOPEN_PER_COLUMN = false

-- Close the dialog when finished (only if this script was the one that opened it).
local CLOSE_DIALOG_WHEN_DONE = false

-- ---- dialog settings (controls that reset when the dialog reopens) --------
-- One-time diagnostic: the first time the dialog is found, dump every child control
-- (id / class / title) to the console so you can identify a control by id. Leave off
-- unless you need to find a new control.
local DUMP_DIALOG_CONTROLS = true

-- A dropdown (ComboBox) selection to force before every Apply. The dialog resets this
-- to its default each time it reopens, so the script re-asserts it per column. Set the
-- control ID and the EXACT option text you want. Leave COMBO_SETTING_ID nil to skip.
--
-- Phase Align Items: control 1001 defaults to "Adjust all items together"; batch
-- alignment needs "Adjust each item separately" so each column aligns on its own.
local COMBO_SETTING_ID   = 1001
local COMBO_SETTING_TEXT = "Adjust each item separately" -- "Adjust each track separately"

-- A numeric Edit field to force before every Apply (also resets on reopen). Set the
-- control ID and the value you want. Phase Align Items: control 1011 defaults to 20.
-- Leave EDIT_SETTING_ID nil to leave the field at whatever the dialog defaults to.
local EDIT_SETTING_ID    = 1011
local EDIT_SETTING_VALUE = 100

-- ---- wait settings (completion detection, "approach A") -------------------
local IDLE_DEBOUNCE      = 0.40  -- s the run must look idle before we call it done
local BUSY_START_GRACE   = 1.00  -- s after Apply with no detected busy state => assume no-op/fast
local COLUMN_TIMEOUT     = 120.0 -- s hard cap per column before we abort and report
local DIALOG_OPEN_TIMEOUT = 5.0  -- s to wait for the dialog to appear after opening it


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
local r = reaper
local proj = 0

local OPEN_CMD     = 43466              -- action that opens the Phase Align Items dialog
local DIALOG_TITLE = "Phase Align Items"
local APPLY_ID     = 1057               -- "Apply" button control ID inside the dialog
local WS_DISABLED  = 0x08000000         -- window style bit set while the dialog is busy
local CB_SETCURSEL  = "0x014E"          -- Win32 combobox message: select item by index
local CBN_SELCHANGE = 1                 -- combobox notification: selection changed (WM_COMMAND high word)
local EN_CHANGE     = 0x0300            -- edit notification: text changed (WM_COMMAND high word)


---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Load my common functions
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")


-- ---- selection helpers ----------------------------------------------------
local function select_only(items)
  UnselectAllItems()
  for _, it in ipairs(items) do r.SetMediaItemSelected(it, true) end
  r.UpdateArrange()
end

local function capture_selection()
  local sel = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    sel[#sel + 1] = r.GetSelectedMediaItem(0, i)
  end
  return sel
end


-- ---- clustering: split selected items into time-overlapping columns --------
local function build_columns()
  local items = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local it  = r.GetSelectedMediaItem(0, i)
    local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
    items[#items + 1] = { item = it, s = pos, e = pos + len }
  end
  table.sort(items, function(a, b) return a.s < b.s end)

  local columns, cur = {}, nil
  for _, it in ipairs(items) do
    if cur and it.s <= (cur.max_e + OVERLAP_TOLERANCE) then
      cur.items[#cur.items + 1] = it.item
      if it.e > cur.max_e then cur.max_e = it.e end
    else
      cur = { items = { it.item }, min_s = it.s, max_e = it.e }
      columns[#columns + 1] = cur
    end
  end
  return columns
end


-- ---- window helpers -------------------------------------------------------
local function find_dialog()
  return r.JS_Window_Find(DIALOG_TITLE, true) or nil
end

-- Set of currently-open top-level window addresses.
local function top_window_set()
  local arr = r.new_array({}, 2048)
  local n = r.JS_Window_ArrayAllTop(arr)
  local set = {}
  if n and n >= 1 then
    for _, a in ipairs(arr.table()) do set[a] = true end
  end
  return set
end

-- Top-level windows present now that were NOT in `baseline` (i.e. transient popups
-- such as progress dialogs that appeared after we hit Apply). Returns addr->{class,title}.
local function extra_windows(baseline)
  local extra = {}
  for a in pairs(top_window_set()) do
    if not baseline[a] then
      local h = r.JS_Window_HandleFromAddress(a)
      if h then
        local cls = r.JS_Window_GetClassName(h)
        local ttl = r.JS_Window_GetTitle(h)
        extra[a] = { class = tostring(cls or "?"), title = tostring(ttl or "") }
      end
    end
  end
  return extra
end

local function dialog_is_disabled(dlg)
  if not dlg then return false end
  local style = math.floor(r.JS_Window_GetLong(dlg, "STYLE") or 0)
  return (style & WS_DISABLED) ~= 0
end

-- Find a direct/descendant child control of `dlg` by its control ID.
local function find_control(dlg, id)
  local arr = r.new_array({}, 4096)
  r.JS_Window_ArrayAllChild(dlg, arr)
  for _, a in ipairs(arr.table()) do
    local h = r.JS_Window_HandleFromAddress(a)
    if h and math.floor(r.JS_Window_GetLong(h, "ID") or 0) == id then
      return h
    end
  end
  return nil
end

-- One-time diagnostic: list every control in the dialog so a target checkbox can be
-- identified by id/class/title.
local function dump_dialog_controls(dlg)
  local arr = r.new_array({}, 4096)
  r.JS_Window_ArrayAllChild(dlg, arr)
  local addrs = arr.table()
  Log(string.format("---- dialog controls (%d): id | class | title ----", #addrs))
  for _, a in ipairs(addrs) do
    local h = r.JS_Window_HandleFromAddress(a)
    if h then
      local id  = math.floor(r.JS_Window_GetLong(h, "ID") or 0)
      local cls = tostring(r.JS_Window_GetClassName(h) or "?")
      local ttl = tostring(r.JS_Window_GetTitle(h) or "")
      Log(string.format("   id=%-6d %-16s %q", id, cls, ttl))
    end
  end
  Log("---- end dialog controls ----")
end

-- Ensure a ComboBox is set to a given option, matched by its exact text.
--
-- We can't read each item's text directly (CB_GETLBTEXT needs a string buffer the API
-- won't pass), so we match by side effect: for each index we send CB_SETCURSEL, then read
-- the combo's window text (JS_Window_GetTitle returns a combobox's current selection).
-- When it matches `text` we stop and notify the dialog with CBN_SELCHANGE so it registers
-- the change as if the user had picked it. If no option matches, we restore the original
-- selection so we never leave the combo on the wrong value.
local MAX_COMBO_OPTIONS = 64
local function ensure_combo_selected(dlg, id, text)
  local h = find_control(dlg, id)
  if not h then
    Log(string.format("[setting] combo id=%d not found in dialog.", id))
    return
  end

  local original = tostring(r.JS_Window_GetTitle(h) or "")
  if original == text then
    Log(string.format("[setting] combo id=%d already '%s'.", id, text))
    return
  end

  local found
  for i = 0, MAX_COMBO_OPTIONS - 1 do
    r.JS_WindowMessage_Send(h, CB_SETCURSEL, i, 0, 0, 0)
    local cur = tostring(r.JS_Window_GetTitle(h) or "")
    if cur == text then found = i; break end
    if cur == "" then break end  -- index past the end of the list
  end

  if not found then
    -- Restore whatever was selected before we scanned.
    for i = 0, MAX_COMBO_OPTIONS - 1 do
      r.JS_WindowMessage_Send(h, CB_SETCURSEL, i, 0, 0, 0)
      if tostring(r.JS_Window_GetTitle(h) or "") == original then break end
    end
    Log(string.format("[setting] combo id=%d has no option '%s' — left as '%s'.",
      id, text, original))
    return
  end

  -- Notify the dialog exactly as a user selection would (WM_COMMAND / CBN_SELCHANGE).
  r.JS_WindowMessage_Send(dlg, "WM_COMMAND", id, CBN_SELCHANGE, 0, 0)
  Log(string.format("[setting] combo id=%d set to '%s' (index %d).", id, text, found))
end

-- Ensure an Edit field holds a given value. Sets the control's text (JS_Window_SetTitle
-- = SetWindowText) and fires EN_CHANGE, since programmatic text changes don't raise it on
-- their own and the dialog may rely on it. Idempotent: skips if already correct.
local function ensure_edit_value(dlg, id, value)
  local h = find_control(dlg, id)
  if not h then
    Log(string.format("[setting] edit id=%d not found in dialog.", id))
    return
  end
  local want = tostring(value)
  local cur  = tostring(r.JS_Window_GetTitle(h) or "")
  if cur == want then
    Log(string.format("[setting] edit id=%d already '%s'.", id, want))
    return
  end
  r.JS_Window_SetTitle(h, want)
  r.JS_WindowMessage_Send(dlg, "WM_COMMAND", id, EN_CHANGE, 0, 0)
  Log(string.format("[setting] edit id=%d set to '%s' (was '%s').", id, want, cur))
end


---------------------------------
------- STATE MACHINE -----------
---------------------------------

local columns
local orig_selection
local state = "prep"
local col_index = 1

-- per-column working state
local we_opened_dialog = false
local open_issued, open_t
local closed_for_reopen
local baseline, col_start, saw_busy, idle_since, prev_extra

local processed_count, skipped_count = 0, 0
local abort_reason = nil
local dumped_controls = false  -- one-shot guard for DUMP_DIALOG_CONTROLS

local function count_extra(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local function log_window_changes(now_extra)
  -- log windows that just appeared / disappeared, for progress-window discovery
  for a, w in pairs(now_extra) do
    if not prev_extra[a] then
      Log(string.format("   + window appeared  hwnd=0x%X class=%s title=%q", a, w.class, w.title))
    end
  end
  for a, w in pairs(prev_extra) do
    if not now_extra[a] then
      Log(string.format("   - window closed    hwnd=0x%X class=%s title=%q", a, w.class, w.title))
    end
  end
  prev_extra = now_extra
end

local function finish_column()
  processed_count = processed_count + 1
  Log(string.format("[column %d] done.", col_index))
  col_index = col_index + 1
  state = "prep"
end

local function abort(reason)
  abort_reason = reason
  state = "finish"
end


local function tick_prep()
  if col_index > #columns then state = "finish"; return end
  local col = columns[col_index]

  if SKIP_SINGLE_ITEM_COLUMNS and #col.items < 2 then
    Log(string.format("[column %d] skipped (only %d item).", col_index, #col.items))
    skipped_count = skipped_count + 1
    col_index = col_index + 1
    return -- stay in prep, handle next column next tick
  end

  Log(string.format("[column %d/%d] %d items, %.3f..%.3f s — selecting.",
    col_index, #columns, #col.items, col.min_s, col.max_e))
  select_only(col.items)

  -- reset per-column dialog/open state
  open_issued, open_t = false, nil
  closed_for_reopen = false
  state = "ensure_dialog"
end


local function tick_ensure_dialog()
  local dlg = find_dialog()

  -- reopen mode: make sure any existing dialog is closed first (once per column)
  if REOPEN_PER_COLUMN and dlg and not closed_for_reopen then
    Log(string.format("[column %d] closing dialog to reopen fresh.", col_index))
    r.JS_WindowMessage_Send(dlg, "WM_CLOSE", 0, 0, 0, 0)
    closed_for_reopen = true
    return
  end
  if REOPEN_PER_COLUMN and dlg and closed_for_reopen then
    return -- still waiting for the old dialog to disappear
  end

  if not dlg then
    if not open_issued then
      Log(string.format("[column %d] opening dialog (action %d).", col_index, OPEN_CMD))
      r.Main_OnCommand(OPEN_CMD, 0)
      we_opened_dialog = true
      open_issued = true
      open_t = r.time_precise()
    elseif r.time_precise() - open_t > DIALOG_OPEN_TIMEOUT then
      abort("dialog did not appear within " .. DIALOG_OPEN_TIMEOUT .. "s")
    end
    return
  end

  -- dialog is present. One-shot: dump its controls so a target checkbox can be found.
  if DUMP_DIALOG_CONTROLS and not dumped_controls then
    dump_dialog_controls(dlg)
    dumped_controls = true
  end

  -- Force the configured dropdown selection (it resets each time the dialog reopens).
  if COMBO_SETTING_ID then
    ensure_combo_selected(dlg, COMBO_SETTING_ID, COMBO_SETTING_TEXT)
  end

  -- Force the configured numeric Edit field (also resets on reopen).
  if EDIT_SETTING_ID then
    ensure_edit_value(dlg, EDIT_SETTING_ID, EDIT_SETTING_VALUE)
  end

  -- snapshot baseline, fire Apply, begin waiting
  baseline   = top_window_set()
  saw_busy   = false
  idle_since = nil
  prev_extra = {}
  col_start  = r.time_precise()
  Log(string.format("[column %d] applying phase alignment.", col_index))
  r.JS_Window_OnCommand(dlg, APPLY_ID)
  state = "await_done"
end


local function tick_await_done()
  local now = r.time_precise()
  if now - col_start > COLUMN_TIMEOUT then
    abort(string.format("column %d exceeded %.0fs timeout", col_index, COLUMN_TIMEOUT))
    return
  end

  local dlg = find_dialog()
  local now_extra = extra_windows(baseline)
  log_window_changes(now_extra)

  -- Dialog vanished. If processing happened (or the grace elapsed) treat as done;
  -- the next column will simply reopen it. Otherwise something went wrong.
  if not dlg then
    if saw_busy or (now - col_start >= BUSY_START_GRACE) then
      Log(string.format("[column %d] dialog closed after Apply — treating as complete.", col_index))
      finish_column()
    else
      abort("dialog closed unexpectedly before processing started")
    end
    return
  end

  local busy = dialog_is_disabled(dlg) or (count_extra(now_extra) > 0)

  if busy then
    saw_busy = true
    idle_since = nil
    return
  end

  if saw_busy then
    idle_since = idle_since or now
    if now - idle_since >= IDLE_DEBOUNCE then finish_column() end
  else
    -- never observed a busy state; if the grace period passed, assume fast/no-op
    if now - col_start >= BUSY_START_GRACE then
      Log(string.format("[column %d] no busy state observed (fast or no-op).", col_index))
      finish_column()
    end
  end
end


local function tick_finish()
  -- close the dialog if we opened it and are asked to
  if CLOSE_DIALOG_WHEN_DONE and we_opened_dialog then
    local dlg = find_dialog()
    if dlg then r.JS_WindowMessage_Send(dlg, "WM_CLOSE", 0, 0, 0, 0) end
  end

  -- restore the user's original selection
  if orig_selection then select_only(orig_selection) end
  r.UpdateArrange()

  local summary
  if abort_reason then
    summary = string.format("Batch Phase Alignment ABORTED: %s\n\nProcessed %d, skipped %d.",
      abort_reason, processed_count, skipped_count)
  else
    summary = string.format("Batch Phase Alignment complete.\n\nProcessed %d column(s), skipped %d.",
      processed_count, skipped_count)
  end
  Log(summary)
  r.ShowMessageBox(summary, "Batch Phase Alignment", 0)
  -- state machine ends: do not re-defer
end


local dispatch = {
  prep          = tick_prep,
  ensure_dialog = tick_ensure_dialog,
  await_done    = tick_await_done,
}

local function loop()
  local fn = dispatch[state]
  if fn then fn() end
  -- Any tick that sets state to "finish" ends the run: finalize once, no re-defer.
  if state == "finish" then
    tick_finish()
    return
  end
  r.defer(loop)
end


---------------------------------
-------------- MAIN -------------
---------------------------------

local function start()
  -- guards
  if not (r.APIExists and r.APIExists("JS_Window_OnCommand")) then
    r.ShowMessageBox("This script requires js_ReaScriptAPI (install via ReaPack).",
      "Batch Phase Alignment", 0)
    return
  end
  if not RequireSelectedItems("Select the items you want to phase-align first.") then
    return
  end

  orig_selection = capture_selection()
  columns = build_columns()

  Log(string.format("\n==================== BATCH PHASE ALIGNMENT ====================\n" ..
    "Selected items: %d  ->  %d column(s)", #orig_selection, #columns))
  for i, c in ipairs(columns) do
    Log(string.format("  column %d: %d items  %.3f..%.3f s", i, #c.items, c.min_s, c.max_e))
  end

  if #columns == 0 then
    r.ShowMessageBox("No columns to process.", "Batch Phase Alignment", 0)
    return
  end

  state = "prep"
  col_index = 1
  r.defer(loop)
end

start()
