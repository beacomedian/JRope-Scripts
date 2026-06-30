--[[
 * Name: FX List
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.5
 * Provides:
   [main] . >
 * Link: https://www.jesserope.com
 * About:
   # A docked FX strip for the arrange view (dock to the left of the TCP).
     Shows each track's FX chain as a compact list with click actions to
     open/float/bypass/offline/delete FX and drag-to-move/copy between tracks.

   # This is a derivative of MFXlist by M Fabian (GPL v3),
     https://github.com/martinfabian/MFXlist — full credit to the original
     author. Requires the js_ReaScriptAPI extension
     (https://forum.cockos.com/showthread.php?t=212174).

   # Note: this is a deferred GUI script, so it does NOT use the standard
     jrope one-shot Undo_BeginBlock/main() MAIN wrapper; it runs its own
     defer loop (mfxlistMain) instead.
 * Changelog:
   # v1.0 - Port of MFXlist v0.9.9beta into the jrope repo with fixes:
   #        * Fixed offline-FX strikeout crash (fx.name -> fx.fxname).
   #        * Routed debug output through Common Functions Log()/ENABLE_DEBUG_LOG
   #          instead of the undefined Msg()/DO_DEBUG globals.
   #        * Removed undefined-name landmines in the right-click menu
   #          (MENU_NEXTDOCK / MENU_SETUP10 / setupForTesting branches).
   #        * Allowed negative saved window coordinates (multi-monitor).
   #        * Cleaned up exitScript's gfx.dock(-1) call.
   #        * Removed dead/non-working code (split, linear track search,
   #          sendTCPScrollMessage, findLeftDock, manageFocus, switchDocker,
   #          non-functional header blit buffer).
   # v1.1 - Fixed blank render when a track spacer occupies the top of the TCP
   #        (first-visible-track search now finds the top track even when its
   #        Y-position is pushed positive by a spacer).
   # v1.2 - Pinned-track support. Visible tracks are now found via the pin-aware
   #        reaper.GetTrackFromPoint() walk instead of a binary search over
   #        I_TCPY, so a pinned track's FX keep rendering regardless of scroll
   #        position, and tracks occluded behind a pin are neither drawn nor
   #        clickable. FX cells now paint an opaque background. (This walk also
   #        handles the top-spacer case natively, superseding the v1.1 search.)
   # v1.3 - Mark FX containers in the list (detected via fx_type == "Container").
   #        Marker style is the CONTAINER_MARKER_STYLE config: "triangle",
   #        "square", or "bracket". Containers keep the normal bypass/offline
   #        fade and strikeout.
   # v1.4 - Moved the right-click quick-add FX list (MENU_QUICKFX) into the
   #        user-settable config block with instructions on naming FX for
   #        TrackFX_AddByName.
   # v1.5 - Fixed crash on exit ("bad argument #2 to 'format'"): gfx.dock(-1)
   #        needs placeholder args to return the window coords; added a guard so
   #        missing coords no longer crash exitScript.
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

local string, table, math = string, table, math
local rpr, gfx = reaper, gfx
local CURR_PROJ = 0

-------------------------------------------
-- Variables with underscore are global
-- All caps denotes constants, do not assign to these in the code!
-- Non-constants are used to communicate between different parts of the code
MFXlist =
{
  -- user settable stuff
  COLOR_EMPTYSLOT = {40/255, 40/255, 40/255},
  COLOR_FXHOVERED = {1, 1, 0},
  COLOR_DROPMOVE = {0, 0, 1},
  COLOR_DROPCOPY = {0, 1, 0},
  COLOR_SELECTEDTRACK = {1, 1, 1},

  -- Determines whether to show FX type (JS, VST, etc) in the name
  SHOW_FXTYPE = false,

  -- How to mark FX containers in the list: "triangle", "square", or "bracket".
  -- (triangle/square use glyphs that depend on the GUI font; bracket is pure ASCII.)
  CONTAINER_MARKER_STYLE = "triangle",

  ----------------------------------------------------------------------------
  -- Quick-add FX menu. These entries appear at the top of the right-click menu
  -- (over a track's FX area); clicking one inserts that FX on the track.
  --
  -- Each string is passed straight to reaper.TrackFX_AddByName, so it must be a
  -- name REAPER can resolve. What to put here:
  --   * The FX name exactly as it shows in REAPER's FX browser / Add FX list,
  --     e.g. "ReaEQ", "ReaComp", "ReaDelay".
  --   * To force a specific format when the name is ambiguous, prefix with the
  --     type and a colon (no space):
  --        "VST:ReaEQ"      "VST3:Pro-Q 3"     "VSTi:Vital"
  --        "JS:Volume"      "AU:AUDelay"       "CLAP:Surge XT"
  --        "VIDEO:..." / "REC:..." are also valid prefixes.
  --   * For VSTs you may also use the file name, e.g. "ReaEQ.vst3".
  -- Matching is case-sensitive and matches the start of the name, so the more
  -- exact the string, the more reliable the insert. If an entry can't be
  -- resolved, REAPER simply adds nothing for that click.
  --
  -- Add, remove, or reorder freely; the menu and item count update automatically.
  -- An empty list { } hides the quick-add section entirely.
  ----------------------------------------------------------------------------
  MENU_QUICKFX = {"ReaEQ", "ReaComp", "Pro-Q 3", "Little Plate", "Altiverb"},

  -- Marker strings wrapped around a container's name, keyed by CONTAINER_MARKER_STYLE.
  CONTAINER_MARKERS = {
    triangle = { pre = "\u{25B8} ", post = "" },  -- prepend a triangle glyph
    square   = { pre = "\u{25A2} ", post = "" },  -- prepend a square glyph
    bracket  = { pre = "[",         post = "]" }, -- wrap the name in brackets
  },

  FX_DISABLEDA = 0.3, -- fade of name for disabled FX
  FX_OFFLINEDA = 0.1, -- even fainter for offlined FX


  -- Delay for return of focus during mouse wheel
  FOCUS_DELAY = 10,

  FONT_NAME1 = "Arial",
  FONT_NAME2 = "Courier New",
  FONT_SIZE1 = 14,
  FONT_SIZE2 = 16,
  FONT_FXNAME = 14,
  FONT_FXBOLD = 15,
  FONT_HEADER = 16,
  FONT_BOLDFLAG = 0x42000000,   -- bold
  FONT_ITFLAG = 0x49000000,     -- italics
  FONT_OUTFLAG = 0x4F000000,    -- outline
  FONT_BLURFLAG = 0x52000000,   -- blurred
  FONT_SHARPFLAG = 0x53000000,  -- sharpen
  FONT_UNDERFLAG = 0x55000000,  -- underline
  FONT_INVFLAG = 0x56000000,    -- invert

  -- Script specific constants, from here below change only if you really know what you are doing
  SCRIPT_VERSION = "v1.0",
  SCRIPT_NAME = "jrope FX List",
  SCRIPT_AUTHORS = {"M Fabian", "Jesse Rope"},
  SCRIPT_YEAR = "2020-2026",

  -- Mouse button and modifier key constants
  MB_LEFT = 1,
  MB_RIGHT = 2,

  MOD_CTRL = 4,
  MOD_SHIFT = 8,
  MOD_ALT = 16,
  MOD_WIN = 32,
  MOD_KEYS = 4+8+16+32,

  -- determines how far mouse can be moved between down and up to still be considered a left click
  -- this then also decides how much the mouse has to move with left MB down to be considered as dragging
  CLICK_RESOX = 30, -- maybe should not really care about horizontal moves?
  CLICK_RESOY = 10,

  -- Right click menu (MENU_QUICKFX is user-configurable; see the user-settable block above)
  MENU_STR = "Info|Quit",
  MENU_SHOWINFO = 1,
  MENU_QUIT = 2,

  -- Flag constants for TrackFX_Show(track, index, showFlag)
  FXCHAIN_HIDE = 0,
  FXCHAIN_SHOW = 1,
  FXFLOAT_HIDE = 2,
  FXFLOAT_SHOW = 3,

  -- flag constants for GetTrackState(track) return
  TRACK_FXENABLED = 4,
  TRACK_MUTED = 8,

  -- Height for FX slots, FX names are drawn centered (and clipped) inside this high rectangles
  SLOT_HEIGHT = 13, -- pixels high

  -- Gap between the first track and the master track (when visible)
  MASTER_GAP = 5,

  -- For matching and shrinking FX names
  MATCH_UPTOCOLON = "(.-:)",
  MATCH_UPTOSLASH = "(.-/)",

  -- Nondocked window size, and docker address (overridden from EXTSTATE if such exists)
  WIN_X = 1000,
  WIN_Y = 200,
  WIN_W = 200,
  WIN_H = 200,
  DOCKER_NUM = 512+1, -- 512 = left of arrange view, +1 == docked (not universally true)

  -- "Win" for Windows, "Mac" for Mac, "Linux" for Linux, determined when initializing
  WHAT_OS = nil, -- On Mac the y-coords go the other direction

  -- Window class names to look for
  CLASS_TCPDISPLAY = "REAPERTCPDisplay", -- this is the TCP where the track panes live

  TCP_HWND = nil, -- filled in when script initializes
  TCP_top = nil, -- Set on every defer before calling any other function
  TCP_bot = nil, -- Set on every defer before calling any other function

  MFX_HWND = nil, -- this is our own window, need this to make mousewheel work

  ACT_SCROLLVERT = 989, -- View: Scroll vertically (MIDI CC relative/mousewheel)
  ACT_ZOOMVERT = 991, -- View: Zoom vertically (MIDI CC relative/mousewheel)
  ACT_SCROLLVIEWDOWN = 40139, -- View: Scroll view down
  ACT_SCROLLVIEWUP = 40138, -- View: Scroll view up

  ACT_ZOOMINVERT = 40111, -- View: Zoom in vertical
  ACT_ZOOMOUTVERT = 40112, -- View: Zoom out vertical

  ACT_FXBROWSERWINDOW = 40271, -- View: Show FX browser window
  ALT_FXBROWSER = nil, -- Alternative FX browser, put command ID here
    -- "_RS490460a16d7e7bb0285ccb1891b67f8f59593a61", -- Quick Adder
    -- "_RS36fe8a223d7ec08e45d4e8569c9bc15b9e417dfa", -- Fast FX finder
  ALT_FXBROWSERTITLE = nil,

  CMD_FOCUSARRANGE = 0, -- SWS/BR: Focus arrange (_BR_FOCUS_ARRANGE_WND)
  CMD_FOCUSTRACKS = 0,  -- SWS/BR: Focus tracks (_BR_FOCUS_TRACKS)
  CMD_SCROLLTCPDOWN = 0,-- Xenakios/SWS: Scroll track view down (page)
  CMD_SCROLLTCPUP = 0,  -- Xenakios/SWS: Scroll track view up (page)

  -- Globally accessible variables used to communicate between different parts of the code
  mouse_y = nil, -- is set to mouse_y when mouse inside MFXlist, else nil
  track_hovered = nil, -- is set to the track (ptr) currently under mouse cursor, nil if mouse outside of client area
  fx_hovered = nil, -- is set to the index (1-based!) of FX under the mouse cursor, nil if mouse is outside of current track FX

  mbl_downx = nil, -- stores left mouse button down coords, used for left MB drag actions
  mbl_downy = nil,
  down_object = nil, -- {track, fx} stores left mouse button down object if any
  drag_object = nil, -- {track, fx} that is dragged, given by track_hovered, fx_hovered
  drag_endx = nil,
  drag_endy = nil,

  openwin_list = nil, -- list of currently open windows to help the external win-close focus issue
  count_down = 0,

  footer_text = "FX List", -- changes after initializing, shows name of currently hovered track
  header_text = "FX List", -- this doesn't really change after initializing, but could if useful

}
local MFXlist = MFXlist -- MFXlist has to be global for preset to work, here it becomes local


---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Load my common functions (provides Log(), gated by ENABLE_DEBUG_LOG)
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")


------------------------------------------ Stolen from https://stackoverflow.com/questions/41942289/display-contents-of-tables-in-lua
-- Recursive print of a table, returns a string
local function tprint (tbl, indent)
  if not indent then indent = 0 end
  local toprint = string.rep(" ", indent) .. "{\r\n"
  indent = indent + 2
  for k, v in pairs(tbl) do
    toprint = toprint .. string.rep(" ", indent)
    if (type(k) == "number") then
      toprint = toprint .. "[" .. k .. "] = "
    elseif (type(k) == "string") then
      toprint = toprint  .. k ..  "= "
    end
    if (type(v) == "number") then
      toprint = toprint .. v .. ",\r\n"
    elseif (type(v) == "string") then
      toprint = toprint .. "\"" .. v .. "\",\r\n"
    elseif (type(v) == "table") then
      toprint = toprint .. tprint(v, indent + 2) .. ",\r\n"
    else
      toprint = toprint .. "\"" .. tostring(v) .. "\",\r\n"
    end
  end
  toprint = toprint .. string.rep(" ", indent-2) .. "}"
  return toprint
end
-------------------------- Windows specific stuff here --------------------------------------------------------------
-------------------------------------------------------- Stolen from https://forum.cockos.com/showthread.php?t=230919
-- Requires js_ReaScriptAPI extension,
-- https://forum.cockos.com/showthread.php?t=212174
local function getClientBounds(hwnd)

  local ret, left, top, right, bottom = rpr.JS_Window_GetClientRect(hwnd)
  local height = bottom - top

  if MFXlist.WHAT_OS == "Mac" then height = top - bottom end

  return left, top, right-left, height

end --GetClientBounds
-----------------------------------------
local function getAllChildWindows(hwnd)

  local arr = rpr.new_array({}, 255)
  rpr.JS_Window_ArrayAllChild(hwnd, arr)
  return arr.table()

end -- getAllChildWindows
------------------------------------------
local function getTitleMatchWindows(title, exact)

  local reaperarray = rpr.new_array({}, 255)
  rpr.JS_Window_ArrayFind(title, exact, reaperarray)
  return reaperarray.table()

end -- getTitleMatchWindows
-----------------------------------------------------------------
-- Find the occurrance-th instance of a window named by classname
local function FindChildByClass(hwnd, classname, occurrence)

  local adr = getAllChildWindows(hwnd)
  local count = #adr
  for j = 1, count do
    local hwnd = rpr.JS_Window_HandleFromAddress(adr[j])
    if rpr.JS_Window_GetClassName(hwnd) == classname then
      occurrence = occurrence - 1
      if occurrence == 0 then
        return hwnd
      end
    end
  end

end --FindChildByClass
---------------------------------------------------------
-- Returns the HWND and the screen coordinates of the TCP
local function getTCPProperties()
-- get first reaper child window with classname "REAPERTCPDisplay".
  local tcp_hwnd = FindChildByClass(rpr.GetMainHwnd(), MFXlist.CLASS_TCPDISPLAY, 1)
  if tcp_hwnd then
    local x,y,w,h = getClientBounds(tcp_hwnd)
    return tcp_hwnd, x, y, w, h
  end
  return nil, -1, -1, -1, -1
end
------------------------------------------------------------------------------------
-- This works, except for when no modifier key is used, then it scrolls the arrange!
local function sendTCPWheelMessage(mbkeys, wheel, screenx, screeny)

  local retval = rpr.JS_WindowMessage_Send(MFXlist.TCP_HWND,
      "WM_MOUSEWHEEL",
      mbkeys, -- wParam, mouse buttons and modifier keys
      wheel, -- wParamHighWWord, wheel distance
      screenx, screeny) -- lParam, lParamHighWord, need to fake it is over TCP?

  return retval

end -- sendTCPWheelMessage
---------------------------------------------- SWS specific stuff go here
local function initSWSCommands()

  MFXlist.CMD_FOCUSARRANGE = rpr.NamedCommandLookup("_BR_FOCUS_ARRANGE_WND")
  MFXlist.CMD_FOCUSTRACKS = rpr.NamedCommandLookup("_BR_FOCUS_TRACKS")
  MFXlist.CMD_SCROLLTCPDOWN = rpr.NamedCommandLookup("_XENAKIOS_TVPAGEDOWN") -- scrolls TCP, but too much
  MFXlist.CMD_SCROLLTCPUP = rpr.NamedCommandLookup("_XENAKIOS_TVPAGEUP")

end
------------------------------------------------------
-- If given the command ID for alternative FX browser
-- replace that command ID by what Reaper returns for it
-- Open the browser to get its hwnd and title
-- The title is needed to toggle it open/close,
local function initAltFXBrowser()

  if MFXlist.ALT_FXBROWSER then

    local cmd = rpr.NamedCommandLookup(MFXlist.ALT_FXBROWSER)
    if cmd <= 0 then
      MFXlist.ALT_FXBROWSER = nil
      return
    end
    MFXlist.ALT_FXBROWSER = cmd
    rpr.PreventUIRefresh(1)
    rpr.Main_OnCommand(MFXlist.ALT_FXBROWSER, 0) -- open the window
    local hwnd = rpr.JS_Window_GetFocus()
    if not hwnd then
      Log("Could not get handle to Alt FX Browser window")
      MFXlist.ALT_FXBROWSER = nil
    else -- So we have the hwnd now, will it remain the same? Probably not
      MFXlist.ALT_FXBROWSERTITLE = rpr.JS_Window_GetTitle(hwnd)
      rpr.JS_WindowMessage_Post(hwnd, "WM_CLOSE", 0,0,0,0) -- if I close like this I guess I can reuse the hwnd
      Log("Title of Alt FX Browser: "..MFXlist.ALT_FXBROWSERTITLE)
    end
    rpr.PreventUIRefresh(-1)
  end

end -- initAltFXBrowser
------------------------------------------------
-- Fetches the action IDs for various commands
local function initCommands()

  initAltFXBrowser()

end -- initCommands
-----------------------------------------
-- Seems that the only way to affect last
-- touched track by scripting is to do:
local function setLastTouchedTrack(track)

  -- Save current track selection
  rpr.SetOnlyTrackSelected(track)
  -- set back current track selection

end -- setLastTouchedTrack
-----------------------------------------------------------
-- Set the focus to TCP so keystrokes go there
-- Called after (almost) every mouse click
function focusTCP()

  rpr.JS_Window_SetFocus(MFXlist.TCP_HWND)

end -- focusTCP
---------------
function focusMFX()

  rpr.JS_Window_SetFocus(MFXlist.MFX_HWND)

end -- focusMFX
----------------------------------------------------------
-- Simple linked list implementation for the openwin_list
linkedList = -- has to be global here, made local below
{
  head = nil,
  length = 0,

  new = function()
          local self = {}
          setmetatable(self, {__index = linkedList})
          return self
        end, -- new

  insert = function(self, element)
              self.head = {next = self.head, elem = element}
              self.length = self.length + 1
              return
            end, -- insert

  print = function(self, outputter)
            if not outputter then
              outputter = print
            end
            if not self.head then
              outputter("<empty list>")
              return
            end
            local ptr = self.head
            while ptr do
              outputter(ptr.elem)
              ptr = ptr.next
            end
          end, -- print

  find = function(self, element, compare)
          if not compare then
            compare = function(p1, p2) return p1 == p2 end
          end
          local ptr = self.head
          while ptr do
            if compare(ptr.elem, element) then
              return ptr
            end
            ptr = ptr.next
          end
          return ptr -- nil
        end, -- find

  -- Have to first find, then remove
  remove = function(self, ptr)
            if not ptr then return false end

            if ptr == self.head then
              self.head = self.head.next
              self.length = self.length - 1
              return true
            end
            local pptr = self.head
            while pptr do
              if pptr.next == ptr then
                pptr.next = ptr.next -- adjust links
                self.length = self.length - 1
                return true
              end
              pptr = pptr.next
            end
            return false -- not found
          end, -- remove (ptr)
}
local linkedList = linkedList
--------------------------------------------------------
local function formatFXNameAndType(fxname, fxtype, fxprefix)

  local trimmed_fx_name = fxname
  if fxtype == 2 then -- JS
    local segment = fxname:match(MFXlist.MATCH_UPTOSLASH)
    if segment and segment:len() >= 5 then
      trimmed_fx_name = fxname:gsub(MFXlist.MATCH_UPTOSLASH, "")
    end
  end

  -- Strip parenthesized text
  trimmed_fx_name = trimmed_fx_name:gsub("%([^()]*%)", "")

  -- For video processor we remove trailing " -- video processor"
  if fxtype == 6 then
    trimmed_fx_name = trimmed_fx_name:gsub(" -- video processor", "")
  end

  if MFXlist.SHOW_FXTYPE then
    trimmed_fx_name = fxprefix..trimmed_fx_name
  end

  return trimmed_fx_name

end
---------------------------------------------------
-- If this fx has a prefix in its name, return that
-- else, generate a prefix given the fxtype number
local function getFXPrefix(fxname, fxtype)

  local prefix = fxname:match(MFXlist.MATCH_UPTOCOLON)
  if prefix and prefix:len() <= 5 then -- 5, because "VSTi:" is 5 long
    return prefix, fxname:gsub(MFXlist.MATCH_UPTOCOLON.."%s", "") -- remove the prefix
  end

  if fxtype == 2 then
    return "JS:", fxname
  elseif fxtype == 3 then
    return "VST:", fxname
  elseif fxtype == 6 then
    return "VID:", fxname
  end

  return "", fxname

end -- getFXPrefix
--------------------------------------------------------
local function collectFX(track)
  assert(track, "collectFX: invalid parameter - track")

  local fxtab = {}

  local numfx = rpr.TrackFX_GetCount(track)
  for i = 1, numfx do
    local _, fxname = rpr.TrackFX_GetFXName(track, i-1, "")
    local fxtype = rpr.TrackFX_GetIOSize(track, i-1) -- This gets the type as a number
    local fxprefix
    fxprefix, fxname = getFXPrefix(fxname, fxtype)
    fxname = formatFXNameAndType(fxname, fxtype, fxprefix)
    -- Mark FX containers (keeps the normal bypass/offline alpha + strikeout, which
    -- drawTracks() applies from enabled/offlined regardless of the name string).
    local _, ftype = rpr.TrackFX_GetNamedConfigParm(track, i-1, "fx_type")
    local is_container = (ftype == "Container")
    if is_container then
      local m = MFXlist.CONTAINER_MARKERS[MFXlist.CONTAINER_MARKER_STYLE]
              or MFXlist.CONTAINER_MARKERS.triangle
      fxname = m.pre .. fxname .. m.post
    end
    local enabled =  rpr.TrackFX_GetEnabled(track, i-1)
    local offlined = rpr.TrackFX_GetOffline(track, i-1)
    table.insert(fxtab, {fxname = fxname, fxtype = fxtype, fxprefix = fxprefix, enabled = enabled, offlined = offlined, is_container = is_container})
  end
  return fxtab
end
------------------------------------------
local function getTrackPosAndHeight(track)
  assert(track, "getTrackPosAndHeight: invalid parameter - track")

  local height = rpr.GetMediaTrackInfo_Value(track, "I_WNDH") -- current TCP window height in pixels including envelopes
  local posy = rpr.GetMediaTrackInfo_Value(track, "I_TCPY") -- current TCP window Y-position in pixels relative to top of arrange view
  return posy, height

end -- getTrackPosAndHeight()
---------------------------------------------------------------------------
local function getTrackInfo(track)
  assert(track, "getTrackInfo: invalid parameter - track")

  local _, name = rpr.GetTrackName(track)
  local visible = rpr.IsTrackVisible(track, false) -- false for TCP (true for MCP)
  local enabled = rpr.GetMediaTrackInfo_Value(track, "I_FXEN") ~= 0 -- fx enabled, 0=bypassed, !0=fx active
  local selected = rpr.IsTrackSelected(track) -- true if selected, false if not
  local posy, height = getTrackPosAndHeight(track)
  local fx = collectFX(track)

  return {track = track, name = name, selected = selected, visible = visible, enabled = enabled, height = height, posy = posy, fx = fx}
end
------------------------------
local function collectTracks()
  local tracks = {}

  if rpr.GetMasterTrackVisibility() & 0x1 == 1 then -- Master track visible in TCP
    local master = rpr.GetMasterTrack(CURR_PROJ)
    local info = getTrackInfo(master)
    table.insert(tracks, info)
  end

  local numtracks = rpr.CountTracks(CURR_PROJ) -- excludes the master track, taken care of above
  for i = 1, numtracks do
    local track = rpr.GetTrack(CURR_PROJ, i-1)
    local info = getTrackInfo(track)
    table.insert(tracks, info)
  end

  return tracks
end
--------------------------------------------
-- Collect the tracks REAPER actually displays in the TCP, top to bottom.
--
-- We walk the TCP column in screen coords and ask reaper.GetTrackFromPoint() what
-- track is shown at each step. That API is pin-aware: it returns the track that is
-- visually on top, so pinned tracks are reported wherever REAPER draws them
-- (regardless of their list index) and tracks occluded *behind* a pin are never
-- returned. This replaces the old binary search over I_TCPY, which assumed the
-- visible tracks were a single contiguous index block and so dropped pinned tracks
-- and had no notion of occlusion.
--
-- Each collected track carries a clipped draw-rect (drawtop/drawbottom, both in
-- arrange-relative px) so a track partially scrolled behind a pin is not drawn over
-- the pinned band: drawtop = max(its I_TCPY, previous on-top track's bottom).
local function collectVisibleTracks()

  local sx, sy, sw, sh = getClientBounds(MFXlist.TCP_HWND) -- TCP screen rect
  local probe_x = math.floor(sx + 4) -- a few px into the TCP so we hit track panels
  local STEP_MIN = 4                 -- min advance (px) so the walk always terminates
  local master = rpr.GetMasterTrack(CURR_PROJ)

  local vistracks = {}
  local seen = {}
  local prev_bottom = nil -- bottom (arrange-relative px) of last collected on-top track
  local y = sy
  local guard = 0

  while y < sy + sh do
    guard = guard + 1
    if guard > 100000 then break end -- absolute safety net against a stuck walk

    local track = rpr.GetTrackFromPoint(probe_x, math.floor(y))
    if track and not seen[track] then
      seen[track] = true
      local trinfo = getTrackInfo(track)
      -- If GetTrackFromPoint returned it, it is on-screen; master may report
      -- IsTrackVisible == false, so include it explicitly.
      if trinfo.visible or track == master then
        local top = trinfo.posy
        local bottom = trinfo.posy + trinfo.height
        trinfo.drawtop = prev_bottom and math.max(top, prev_bottom) or top
        trinfo.drawbottom = bottom
        table.insert(vistracks, trinfo)
        prev_bottom = bottom
      end
      -- advance to this track's displayed bottom (but always make progress)
      y = math.max(sy + trinfo.posy + trinfo.height, y + STEP_MIN)
    else
      -- gap, track spacer, already-seen, or empty point: step a little
      y = y + STEP_MIN
    end
  end

  return vistracks

end -- collectVisibleTracks
-----------------------------
local function drawHeader()

  -- Draw over everything above the FX list drawing area
  gfx.set(MFXlist.COLOR_EMPTYSLOT[1], MFXlist.COLOR_EMPTYSLOT[2], MFXlist.COLOR_EMPTYSLOT[3])
  gfx.rect(0, 0, gfx.w, MFXlist.TCP_top)
  gfx.set(1, 1, 1, 0.7)
  gfx.x, gfx.y = 0, 0
  gfx.setfont(MFXlist.FONT_HEADER)
  gfx.drawstr(MFXlist.header_text, 5, gfx.w, MFXlist.TCP_top)
  gfx.a = MFXlist.FX_DISABLEDA
  gfx.line(0, MFXlist.TCP_top, gfx.w, MFXlist.TCP_top)

end -- drawHeader
------------------------------
local function drawFooter()

  -- Draw bottom line of FX list area (should not draw FX below this, it will be erased)
  gfx.line(0, MFXlist.TCP_bot, gfx.w, MFXlist.TCP_bot)
  gfx.set(MFXlist.COLOR_EMPTYSLOT[1], MFXlist.COLOR_EMPTYSLOT[2], MFXlist.COLOR_EMPTYSLOT[3])
  gfx.rect(0, MFXlist.TCP_bot + 1, gfx.w, gfx.h - MFXlist.TCP_bot - 1)

  local text = MFXlist.footer_text
  if text and text ~= "" then
    gfx.set(1, 1, 1, 0.7)
    gfx.setfont(MFXlist.FONT_FXNAME)
    gfx.x, gfx.y = 0, MFXlist.TCP_bot
    gfx.drawstr(text, 5, gfx.w, gfx.h) -- Note, the last two parameters are the right/bottom COORDS of the box to draw within, not width/height
  end

end -- drawFooter
----------------------------------------------------
local function drawSelectedIndicator(ycoord, height)

  gfx.set(MFXlist.COLOR_SELECTEDTRACK[1], MFXlist.COLOR_SELECTEDTRACK[2], MFXlist.COLOR_SELECTEDTRACK[3], 1)
  gfx.line(gfx.w-2, ycoord + 1, gfx.w-2, ycoord + height - 2)

end -- drawSelectedIndicator
----------------------------------
local function drawDropIndicator()

  if gfx.mouse_cap & MFXlist.MOD_CTRL == MFXlist.MOD_CTRL then
    gfx.set(MFXlist.COLOR_DROPCOPY[1], MFXlist.COLOR_DROPCOPY[2], MFXlist.COLOR_DROPCOPY[3])
  else
    gfx.set(MFXlist.COLOR_DROPMOVE[1], MFXlist.COLOR_DROPMOVE[2], MFXlist.COLOR_DROPMOVE[3])
  end
  gfx.line(10, gfx.y, gfx.w-10, gfx.y)

end -- drawDropIndicator
-----------------------
local function drawTracks()

  gfx.setfont(MFXlist.FONT_FXNAME)

  MFXlist.fx_hovered = nil
  MFXlist.track_hovered = nil

  local drawy = MFXlist.TCP_top

  local vistracks = collectVisibleTracks()
  local numtracks = #vistracks
  for i = 1, numtracks do
    gfx.set(1, 1, 1, gfx.a)
    local insidetrack = false -- used to send message from track to FX on track
    local trinfo = vistracks[i]
    local top = trinfo.drawtop or trinfo.posy                          -- clipped top (arrange-relative px)
    local bottom = trinfo.drawbottom or (trinfo.posy + trinfo.height)  -- clipped bottom
    local height = bottom - top                                        -- visible (clipped) height
    local selected = trinfo.selected
    local chainon = trinfo.enabled -- track FX chain enabled
    if height <= 0 then goto continue end -- fully occluded behind a pinned track
    -- if the mouse is currently inside this track's (clipped) rect
    if MFXlist.mouse_y and top <= MFXlist.mouse_y-drawy and MFXlist.mouse_y-drawy <= bottom then

      MFXlist.footer_text = trinfo.name
      insidetrack = true -- send message to FX part of code, see below
      MFXlist.track_hovered = trinfo.track

    end
    -- Opaque background first, so tracks occluded behind a pinned track cannot show through
    gfx.set(MFXlist.COLOR_EMPTYSLOT[1], MFXlist.COLOR_EMPTYSLOT[2], MFXlist.COLOR_EMPTYSLOT[3], 1)
    gfx.rect(0, drawy + top, gfx.w, height, 1)
    -- Draw bounding box for track FX
    gfx.set(1, 1, 1, MFXlist.FX_OFFLINEDA) -- bounding box is always drawn faint
    gfx.rect(0, drawy + top, gfx.w, height, (chainon and 0 or 1)) -- disabled chain is not filled with faint color
    -- Calc the number of FX slots to draw, and draw them
    local fxlist = trinfo.fx
    local numfxs = math.ceil(height / MFXlist.SLOT_HEIGHT) -- max num FX to show
    local count = math.min(#fxlist, numfxs)
    local cropy = drawy+bottom-1 -- crop FX name slot to this
    gfx.x, gfx.y = 0, drawy + top  -- drawing FX names start at this position
    for i = 1, count do
      local fx = fxlist[i]
      gfx.a = (fx.enabled and not fx.offlined and chainon) and 1 or MFXlist.FX_DISABLEDA -- disabled FX are shown faint
      -- if mouse hovers over this FX, draw it in different color
      if insidetrack and gfx.y <= MFXlist.mouse_y and MFXlist.mouse_y < gfx.y + MFXlist.SLOT_HEIGHT then

        gfx.set(MFXlist.COLOR_FXHOVERED[1], MFXlist.COLOR_FXHOVERED[2], MFXlist.COLOR_FXHOVERED[3], gfx.a)
        gfx.setfont(MFXlist.FONT_FXBOLD)
        MFXlist.fx_hovered = i -- store fx index (1-based!) for mouse click

      else

        gfx.setfont(MFXlist.FONT_FXNAME)
        gfx.set(1, 1, 1, gfx.a)

      end
      gfx.x = 0
      local corner = math.min(gfx.y + MFXlist.SLOT_HEIGHT, cropy) -- make sure to crop within the bounding track rect
      gfx.drawstr(fx.fxname, 1, gfx.w, corner)
      if fx.offlined then -- strikeout offlined FX

        local w, h = gfx.measurestr(fx.fxname)
        local y = gfx.y + MFXlist.SLOT_HEIGHT/2
        gfx.line((gfx.w-w)/2, y, (gfx.w+w)/2, y, gfx.a)

      end
      -- if dragging and are on top of this FX, show drop indicator above it
      if insidetrack and MFXlist.drag_object and MFXlist.drag_object[2] and MFXlist.fx_hovered == i then

        drawDropIndicator()

      end
      gfx.y = gfx.y + MFXlist.SLOT_HEIGHT

    end
    -- if dragging and not hovering any FX, draw drop indicator at end of FX chain
    if insidetrack and MFXlist.drag_object and MFXlist.drag_object[2] and not MFXlist.fx_hovered then

      drawDropIndicator()

    end

    if selected then
      drawSelectedIndicator(drawy + top, height)
    end

    ::continue::
  end

end -- drawTracks
-----------------------------------------------------------
-- Toggle open/close FX window (wtype == 2 for floating)
-- index is here 0-based!
-- wtype is 0 for FX chain window, 2 for floating FX window
local function handleToggleWindow(track, index, wtype)

  local openclose = rpr.TrackFX_GetOpen(track, index) and wtype or wtype + 1 -- 0,2: to close, 1,3: to open

  if ENABLE_DEBUG_LOG then
    local _, tname = rpr.GetTrackName(track)
    local _, fxname = rpr.TrackFX_GetFXName(track, index, "")
    Log("handleToggleWindow: "..tname..", "..fxname.." (openclose: "..openclose..", wtype: "..wtype..")")
  end

  rpr.TrackFX_Show(track, index, openclose)

  if openclose == wtype then -- just closed, remove from openwin_list, and focus TCP

    local compare = function(p1, p2) return p1[1] == p2[1] and p1[2] == p2[2] end
    local ptr = MFXlist.openwin_list:find({track, index}, compare)

    if ptr then -- what if not found (we get nil here)?

      MFXlist.openwin_list:remove(ptr)

    end

    if ENABLE_DEBUG_LOG then
      local str = (not ptr and "nil!" or "found")
      Log("Window "..str..", list size: "..MFXlist.openwin_list.length)
    end

    focusTCP()

  else -- just opened, add to openwin_list

    MFXlist.openwin_list:insert({track, index})

  end

end -- handleToggleWindow
-----------------------------------------
-- Shows it in Reaper's console (for now)
-- Always shown (not gated by ENABLE_DEBUG_LOG), since it is invoked explicitly
-- from the right-click menu.
local function showInfo()

  local width = math.tointeger(gfx.w)
  local height = math.tointeger(gfx.h)
  local x, y, w, h = getClientBounds(MFXlist.TCP_HWND) -- TCP screen coords

  rpr.ShowConsoleMsg("\n"..MFXlist.SCRIPT_NAME.." "..MFXlist.SCRIPT_VERSION..'\n')
  local authors = table.concat(MFXlist.SCRIPT_AUTHORS, ", ")
  rpr.ShowConsoleMsg(authors..", "..MFXlist.SCRIPT_YEAR..'\n')

  rpr.ShowConsoleMsg("Dock: "..math.tointeger(gfx.dock(-1))..", gfx.w: "..width..", gfx.h: "..height)
  rpr.ShowConsoleMsg("\nTCP area (screen coords): "..x..", "..y..", "..w..", "..h)
  rpr.ShowConsoleMsg("\nMFXlist header: 0, 0, "..width..", "..math.tointeger(MFXlist.TCP_top))
  rpr.ShowConsoleMsg("\nMFXlist track area: 0, "..math.tointeger(MFXlist.TCP_top)..", "..width..", "..math.tointeger(MFXlist.TCP_bot - MFXlist.TCP_top))
  rpr.ShowConsoleMsg("\nMFXlist footer: 0, "..math.tointeger(MFXlist.TCP_bot)..", "..width..", "..math.tointeger(height - MFXlist.TCP_bot))

  if ENABLE_DEBUG_LOG then
    Log("What OS? "..MFXlist.WHAT_OS)
    Log("gfx.ext_retina: "..gfx.ext_retina)
  end

end -- showInfo
---------------------------------------
local function setupMenu(quickfx)

  MFXlist.MENU_STR = "Show info|Quit"
  MFXlist.MENU_SHOWINFO = 1
  MFXlist.MENU_QUIT = 2

  if quickfx and MFXlist.MENU_QUICKFX and #MFXlist.MENU_QUICKFX > 0 then

    MFXlist.MENU_STR = table.concat(MFXlist.MENU_QUICKFX, "|").."||"..MFXlist.MENU_STR

    local fxnum = #MFXlist.MENU_QUICKFX
    MFXlist.MENU_SHOWINFO = fxnum + 1
    MFXlist.MENU_QUIT = fxnum + 2

  end

  return MFXlist.MENU_STR

end -- setupMenu
----------------------------------------
local function handleMenu(mcap, mx, my)

  local track = MFXlist.track_hovered
  local menustr = setupMenu(track)

  gfx.x, gfx.y = mx, my
  local ret = gfx.showmenu(menustr)
  if ret == MFXlist.MENU_QUIT then
    return ret
  elseif ret == MFXlist.MENU_SHOWINFO then
    showInfo(mx, my)
  elseif 0 < ret and ret < MFXlist.MENU_SHOWINFO then

    if track then

      local fxname = MFXlist.MENU_QUICKFX[ret]
      local index = rpr.TrackFX_AddByName(track, fxname, false, -10000)
      rpr.TrackFX_Show(track, index, 3) -- 3 == show floating window
      MFXlist.openwin_list:insert({track, index})

      if ENABLE_DEBUG_LOG then
        local _, tname = rpr.GetTrackName(track)
        Log("Track: "..tname..", added FX: "..fxname.." as index "..index)
      end

    end

  end

  return ret

end -- handleMenu
--------------------------------------------
-- Swap bits 2 and 3 (0-based from the left)
local function swapCtrlShft(bits)

  local mask = MFXlist.MOD_CTRL | MFXlist.MOD_SHIFT -- 0xC -- 1100
  local shftctrl = ((bits & MFXlist.MOD_CTRL) << 1) | ((bits & MFXlist.MOD_SHIFT) >> 1)

  return (bits & ~mask) | shftctrl

end -- swapCtrlShft
---------------------------------------------------------------
-- Mouse wheel over MFXlist, send the TCP a mousewheel message
-- These variables are global but locally to handleWheel
local prev_wheel = 0

local function handleWheel(mcap, mx, my)

  local wheel = gfx.mouse_wheel
  gfx.mouse_wheel = 0

  if wheel == 0 and prev_wheel == 0 then
    if MFXlist.count_down == 0 then return end

    MFXlist.count_down = MFXlist.count_down - 1
    if MFXlist.count_down == 0 then
      focusTCP() -- do this after count down
    end
    return

  end -- no wheeling, nothing more to do

  MFXlist.count_down = MFXlist.FOCUS_DELAY

  -- So here wheel ~= 0, if this is the first time we need to grab focus and wait one scan cycle to get mod keys
  if prev_wheel == 0 then -- remember current wheel so we can act on it on the next scan

    prev_wheel = wheel -- remember wheel value
    focusMFX() -- set focus so we get the mod keys
    MFXlist.count_down = 0 -- make sure we do not lose focus
    return

  end

  -- Here prev_wheel ~= 0 and focus is on MFX

  if mcap == 0 then -- no mod key

    if prev_wheel < 0 then
      rpr.Main_OnCommand(MFXlist.ACT_SCROLLVIEWDOWN, 0)
    else
      rpr.Main_OnCommand(MFXlist.ACT_SCROLLVIEWUP, 0)
    end

  elseif mcap & MFXlist.MOD_KEYS == MFXlist.MOD_CTRL then

    if prev_wheel < 0 then
      rpr.Main_OnCommand(MFXlist.ACT_ZOOMOUTVERT, 0)
    else
      rpr.Main_OnCommand(MFXlist.ACT_ZOOMINVERT, 0)
    end

  else
    sendTCPWheelMessage(mcap, prev_wheel, mx, my)

  end

  prev_wheel = 0

end -- handleMousewheel
-----------------------------------------------------------------------------
-- When FX chain or FX float win is opened, it is added to the openwin_list
-- If externally closed (ESC or top right X) it remains on the list
-- If there is no such win open, MFX has focus and need to give it away
-- Walk the list, if a window on the list is found that is not open, give the
-- focus to the TCP (ideally would be to the next window, but no idea how)
local function manageOpenWindows()

  if MFXlist.openwin_list.length > 0 then -- is it faster to check head for nil?
    local ptr = MFXlist.openwin_list.head
    while ptr do
      if not rpr.TrackFX_GetOpen(ptr.elem[1], ptr.elem[2]) then -- someone closed, but not me
        MFXlist.openwin_list:remove(ptr)
        focusTCP()
        return
      end
      ptr = ptr.next
    end
  end

end -- manageOpenWindows
------------------------------------------------------------
-- We get here ONLY if MFXlist.ALT_FXBROWSER is initialized
local function toggleAltFXBrowser()

  -- if already open, then close
  local hwnd = rpr.JS_Window_Find(MFXlist.ALT_FXBROWSERTITLE, true)
  if hwnd then
    rpr.JS_WindowMessage_Post(hwnd, "WM_CLOSE", 0,0,0,0)
    focusTCP()
  else -- open
    rpr.Main_OnCommand(MFXlist.ALT_FXBROWSER, 0)
  end

end -- toggleAltFXBrowser
----------------------------------------------
local function handleLeftMBclick(mcap, mx, my)

  local track = MFXlist.track_hovered
  local index = MFXlist.fx_hovered
  local modkeys = mcap & MFXlist.MOD_KEYS

  if not track then -- we clicked outside track area, header or footer

    if my < MFXlist.TCP_top then
      -- TODO! Left click over header, invoke command
    elseif my >= MFXlist.TCP_bot then
      -- TODO! Left click over footer. Anything useful to do?
    end
    focusTCP()
    return

  -- Left click inside track rect but not on FX, empty slot
  elseif not MFXlist.fx_hovered then -- so we hover over track but not any fx

    if modkeys == 0 then -- No modifier key, open Add FX dialog

      rpr.SetOnlyTrackSelected(track)

      if MFXlist.ALT_FXBROWSER then
        toggleAltFXBrowser()
      else
        rpr.Main_OnCommand(MFXlist.ACT_FXBROWSERWINDOW, 0)
      end

      return

    elseif modkeys == (MFXlist.MOD_SHIFT | MFXlist.MOD_CTRL | MFXlist.MOD_ALT) then
      focusTCP()
      return
    elseif modkeys == (MFXlist.MOD_SHIFT | MFXlist.MOD_ALT) then
      focusTCP()
      return
    elseif modkeys == (MFXlist.MOD_SHIFT | MFXlist.MOD_CTRL) then
      focusTCP()
      return
    elseif modkeys == (MFXlist.MOD_CTRL | MFXlist.MOD_ALT) then
      focusTCP()
      return
    elseif modkeys == MFXlist.MOD_SHIFT then
      focusTCP()
      return
    elseif modkeys == MFXlist.MOD_CTRL then
      -- Ctrl-left click over track empty slot, behave as with no Ctrl key
      local count = rpr.TrackFX_GetCount(track)
      if count == 0 then -- this case needs special treatment

        -- Quirk around Reaper anomaly here, FX chain window cannot open/close unless
        -- some FX is selected. So we add ReaEQ, open/close window, remove ReaEQ
        rpr.TrackFX_AddByName(track, "ReaEQ", false, -1)

        handleToggleWindow(track, 0, 0)

        rpr.TrackFX_Delete(track, 0)
        -- But the delete makes the window unfocused! Never mind for now.

      else -- if FX Chain is not empty, toggling works if some fx is selected

        handleToggleWindow(track, count-1, 0)

      end
      return

    elseif modkeys == MFXlist.MOD_ALT then
      focusTCP()
      return
    else
      -- Left click track with Win/Ctrl mod key not supported
    end
    return
  end

  -- Clicked on specific FX in track
  if modkeys == 0 then
    -- no mod key show/hide floating window for FX

    handleToggleWindow(track, index-1, 2)

  elseif modkeys == (MFXlist.MOD_SHIFT | MFXlist.MOD_CTRL | MFXlist.MOD_ALT) then
    focusTCP()
    return

  elseif modkeys == (MFXlist.MOD_SHIFT | MFXlist.MOD_ALT) then
    focusTCP()
    return

  elseif modkeys == (MFXlist.MOD_SHIFT | MFXlist.MOD_CTRL) then
    -- Shift+Ctrl+Left click on FX, toggle offline/online

    local isoffline = rpr.TrackFX_GetOffline(track, index-1)
    rpr.TrackFX_SetOffline(track, index-1, not isoffline)
    focusTCP()
    return

  elseif modkeys == (MFXlist.MOD_CTRL | MFXlist.MOD_ALT) then
    focusTCP()
    return

  elseif modkeys == MFXlist.MOD_SHIFT then
    -- Shift+Left click on FX, toggle enable/disable

    local endisabled = not rpr.TrackFX_GetEnabled(track, index-1)
    rpr.TrackFX_SetEnabled(track, index-1, endisabled)
    focusTCP()
    return

  elseif modkeys == MFXlist.MOD_CTRL then -- show/hide chain
    -- Ctrl+Left click on FX, toggle track FX Chain window with FX selected

    handleToggleWindow(track, index-1, 0)

  elseif modkeys == MFXlist.MOD_ALT then -- delete
    -- Alt+Left click on FX, delete FX

    rpr.TrackFX_Delete(track, index-1)
    focusTCP()
    return

  else
    -- Left click FX with Win/Ctrl mod key not supported
  end

end -- handleLeftMB
--------------------------------------------------------------------
local function withinResolution(mx, my)

return MFXlist.mbl_downx - MFXlist.CLICK_RESOX <= mx and
      mx <= MFXlist.mbl_downx + MFXlist.CLICK_RESOX and
      MFXlist.mbl_downy - MFXlist.CLICK_RESOY <= my and
      my <= MFXlist.mbl_downy + MFXlist.CLICK_RESOY

end -- insideResolution
------
local mblprev, mbrprev -- global but local, used only in handleMouse

local function handleMouse()

  local mx, my = gfx.mouse_x, gfx.mouse_y

  -- if we are not inside the client rect, we can just as well return (but not quit)
  if mx < 0 or gfx.w < mx or my < 0 or gfx.h < my then -- outside of client area
    MFXlist.mouse_y = nil
    MFXlist.footer_text = MFXlist.SCRIPT_NAME
    return true -- means "do not quit"
  end

  -- Are we inside the track draw area?
  if 0 <= mx and mx <= gfx.w and MFXlist.TCP_top <= my and my <= MFXlist.TCP_bot then
    -- this only works when docked (but then... lots of stuff here only works when docked)
    MFXlist.mouse_y = my

  else -- either in header or in footer

    MFXlist.fx_hovered = nil
    MFXlist.mouse_y = nil
    MFXlist.footer_text = MFXlist.SCRIPT_NAME

  end

  local mcap = gfx.mouse_cap
  local mbldown = mcap & MFXlist.MB_LEFT
  local mbrdown = mcap & MFXlist.MB_RIGHT

  handleWheel(mcap, mx, my)

  -- left mouse button up-flank
  if mbldown ~= MFXlist.MB_LEFT and mblprev == MFXlist.MB_LEFT then

    mblprev = 0
    -- Is up-flank within the resolution, then it is a click
    if withinResolution(mx, my) then

      handleLeftMBclick(mcap, mx, my)

    else -- this is drag end, aka drop

      -- If the drop is done outside of MFXlist, then strack and ttrack == nil
      local strack = MFXlist.drag_object and MFXlist.drag_object[1] or nil  -- source track
      local ttrack = MFXlist.track_hovered  -- target track
      if strack and ttrack then
        local sfxid = MFXlist.drag_object[2]  -- source fx id, can be nil
        local tfxid = MFXlist.fx_hovered      -- target fxid, can be nil

        -- Handle the drop
        if sfxid then
          if not tfxid then
            tfxid = rpr.TrackFX_GetCount(ttrack) + 1
          end
          -- If any combination of Ctrl is held down when dropping, then it is a copy
          local tomove = not (gfx.mouse_cap & MFXlist.MOD_CTRL == MFXlist.MOD_CTRL)
          rpr.TrackFX_CopyToTrack(strack, sfxid-1, ttrack, tfxid-1, tomove)
        end
      end

      -- Reset drag info
      MFXlist.mbl_downx, MFXlist.mbl_downy = nil, nil
      MFXlist.drag_object = nil
      MFXlist.down_object = nil

      focusTCP()

    end
  -- left mouse button down-flank, may be click or drag start
  elseif mbldown == MFXlist.MB_LEFT and mblprev ~= MFXlist.MB_LEFT then

    mblprev = MFXlist.MB_LEFT
    MFXlist.mbl_downx, MFXlist.mbl_downy = mx, my
    if MFXlist.track_hovered then
      MFXlist.down_object = {MFXlist.track_hovered, MFXlist.fx_hovered}
    else -- mouse down on header or footer
      MFXlist.down_object = nil
    end
    MFXlist.count_down = 0

  -- down now, down previously, maybe we are dragging
  elseif mbldown == MFXlist.MB_LEFT and mblprev == MFXlist.MB_LEFT then

    if not withinResolution(mx, my) then
      if not MFXlist.drag_object and MFXlist.down_object then

        MFXlist.drag_object = MFXlist.down_object
        MFXlist.count_down = 0 -- (try to) make sure we do not lose focus

        if ENABLE_DEBUG_LOG then
          local track = MFXlist.drag_object[1]
          local fxid = MFXlist.drag_object[2]
          if not track or not fxid then
            Log("track: "..(track and "valid" or "nil")..", fxid: "..(fxid and fxid or "nil"))
          else
            local _, tname = rpr.GetTrackName(track)
            local _, fxname = rpr.TrackFX_GetFXName(track, fxid-1, "")
            Log("Possible drag start: "..tname..", "..fxname)
          end
        end

      end
    end

  elseif mbldown ~= MFXlist.MB_LEFT and mblprev ~= MFXlist.MB_LEFT then

    -- is up now, was up previously, just idling

  end

  -- right mouse button down flank?
  if mbrdown == MFXlist.MB_RIGHT and mbrprev ~= MFXlist.MB_RIGHT then

    mbrprev = MFXlist.MB_RIGHT
    local ret = handleMenu(mcap, mx, my) -- onRightClick()
    if ret == MFXlist.MENU_QUIT then
      gfx.quit()
      return false -- tell the defer loop to quit
    end
  -- right mouse button up flank?
  elseif mbrdown ~= MFXlist.MB_RIGHT and mbrprev == MFXlist.MB_RIGHT then

    mbrprev = 0

  end

  return true

end -- handleMouse
-----------------------------
-- Write EXSTATE info
local function exitScript()

  -- gfx.dock(-1) alone returns only the dock state; pass placeholder args so the
  -- window x/y/w/h come back as the extra return values.
  local dockstate, wx, wy, ww, wh = gfx.dock(-1, 0, 0, 0, 0)
  local dockstr = string.format("%d", dockstate)
  rpr.SetExtState(MFXlist.SCRIPT_NAME, "dock", dockstr, true)

  if wx and wy and ww and wh then -- guard: don't crash on exit if coords are unavailable
    local coordstr = string.format("%d,%d,%d,%d", wx, wy, ww, wh)
    rpr.SetExtState(MFXlist.SCRIPT_NAME, "coords", coordstr, true)
  end

  rpr.SetExtState(MFXlist.SCRIPT_NAME, "version", MFXlist.SCRIPT_VERSION, true)

end -- exitScript
------------------------------------------------------------
-- Read EXSTATE info and set up in previous docker (if any)
local function openWindow()

  -- Dock state - not valid for Reaper v4 or earlier
  local dockstate = MFXlist.DOCKER_NUM
  if rpr.HasExtState(MFXlist.SCRIPT_NAME, "dock") then
      local extstate = rpr.GetExtState(MFXlist.SCRIPT_NAME, "dock")
      dockstate = tonumber(extstate)
  end
  local docker = dockstate

  -- If we are docked, these coords don't really matter, but still...
  -- (-?%d+ so that negative coords on multi-monitor setups parse correctly)
  if rpr.HasExtState(MFXlist.SCRIPT_NAME, "coords") then
      local coordstr = rpr.GetExtState(MFXlist.SCRIPT_NAME, "coords")
      local x, y, w, h = coordstr:match("(-?%d+),(-?%d+),(-?%d+),(-?%d+)")
      if x and y and w and h then
        MFXlist.WIN_X, MFXlist.WIN_Y, MFXlist.WIN_W, MFXlist.WIN_H = tonumber(x), tonumber(y), tonumber(w), tonumber(h)
      end
  end

  gfx.clear = MFXlist.COLOR_EMPTYSLOT[1] * 255 + MFXlist.COLOR_EMPTYSLOT[2] * 255 * 256 + MFXlist.COLOR_EMPTYSLOT[3] * 255 * 65536
  gfx.init(MFXlist.SCRIPT_NAME, MFXlist.WIN_W, MFXlist.WIN_H, docker, MFXlist.WIN_X, MFXlist.WIN_Y)

end -- openWindow
------------------------------------------------
local function initializeScript()

  local whatos = rpr.GetOS()
  if whatos:find("OSX") ~= nil or whatos:find("macOS") ~= nil then
    MFXlist.WHAT_OS = "Mac"
  elseif whatos:find("Win") ~= nil then
    MFXlist.WHAT_OS = "Win"
  else
    MFXlist.WHAT_OS = "Linux" -- this is really just a guess, but anyway...
  end

  local hwnd, x, y, w, h = getTCPProperties() -- TCP screen coordinates
  assert(hwnd, "Could not get TCP HWND, cannot do much now, sorry")
  MFXlist.TCP_HWND = hwnd

  rpr.atexit(exitScript)
  openWindow()

  MFXlist.MFX_HWND = rpr.JS_Window_GetFocus() -- I'm assuming we have the focus now

  initCommands()

  local cx, cy = gfx.screentoclient(x, y)
  MFXlist.TCP_top = cy
  MFXlist.TCP_bot = MFXlist.TCP_top + h

  gfx.line(0, cy, gfx.w, cy) -- line on level with TCP top (do not draw FX above this)
  gfx.line(0, cy + h, gfx.w, cy + h) -- line on level with TCP bottom (do not draw FX below this)

  if ENABLE_DEBUG_LOG then
    showInfo()
  end

  MFXlist.header_text = MFXlist.SCRIPT_NAME.." "..MFXlist.SCRIPT_VERSION

  gfx.setfont(MFXlist.FONT_FXNAME, MFXlist.FONT_NAME1, MFXlist.FONT_SIZE1)
  gfx.setfont(MFXlist.FONT_FXBOLD, MFXlist.FONT_NAME1, MFXlist.FONT_SIZE1, MFXlist.FONT_BOLDFLAG)
  gfx.setfont(MFXlist.FONT_HEADER, MFXlist.FONT_NAME2, MFXlist.FONT_SIZE2)

  MFXlist.openwin_list = linkedList.new()

  drawTracks()
  drawHeader()
  drawFooter()

  focusTCP()

end -- initializeScript
------------------------------------------------ Here is the main loop
local function mfxlistMain()

  local x, y, w, h = getClientBounds(MFXlist.TCP_HWND) -- screen coords of the TCP
  _, MFXlist.TCP_top = gfx.screentoclient(x, y) -- top y coord to draw FX at, above this only header stuff
  MFXlist.TCP_bot = MFXlist.TCP_top + h -- bottom y coord to draw FX at, below this only footer stuff

  rpr.PreventUIRefresh(1)

  drawTracks()
  drawHeader()
  drawFooter()

  local continue = handleMouse()

  rpr.PreventUIRefresh(-1)

  -- Check if we are to quit or not
  if gfx.getchar() < 0 or not continue then
    gfx.quit()
    return
  end

  manageOpenWindows()

  rpr.defer(mfxlistMain)

end -- mfxlistMain
------------------------------------------------ It all starts here, really

-- Adding preset awareness here
function Init()
  initializeScript()
  mfxlistMain() -- run main loop
end

if not preset_file_init then
  Init()
end
