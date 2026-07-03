--[[
 * Name: JROPE - Export Mix Change List to HTML
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.0
 * Provides:
    [main] . >
 * Link: https://www.jesserope.com
 * About:
    # Writes an HTML "change list" / mix snapshot for the current session.
    # For each track it reports volume (dB), pan, the FX added (names, with
    # bypass/offline flags) and every aux send/receive the track uses.
    # Tracks are rendered with the same folder hierarchy and colors as the
    # session. The file is saved into the session directory, named
    # "<session> - Mix Change List - YYYY-MM-DD HH-MM-SS.html".
    #
    # Selection rule: if no tracks are selected the whole session is exported,
    # otherwise only the selected tracks (their folder ancestry is shown for
    # context but greyed out).
    #
    # Note: this is a snapshot of the CURRENT mix state - run it after making
    # your adjustments and each file timestamps that moment for easy tracking.
 * Changelog:
    # Initial Release
 * To Do:
    #

]]



---------------------------------
---------- USER CONFIG ----------
---------------------------------

-- Must be global (no `local`) so the shared Log() in Common Functions can read it.
ENABLE_DEBUG_LOG = true  -- set to true to print debug output to the REAPER console

-- Open the generated file in the default browser when finished.
local OPEN_WHEN_DONE = true


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local SCRIPT_DIR = ({reaper.get_action_context()})[2]:sub(1,({reaper.get_action_context()})[2]:find("\\[^\\]*$"))
local r = reaper
local proj = 0


---------------------------------
----------- FUNCTIONS -----------
---------------------------------

-- Load my common functions
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local parent_path = script_path:match([[^(.*[\/])[^\/]-[\/]$]])
package.path = parent_path .. "Functions/?.lua;" .. package.path
require("jrope__Common Functions")


-- Escape a string for safe insertion into HTML text/attribute content.
local function EscapeHTML(s)
  s = tostring(s or "")
  return (s:gsub("[&<>\"']", {
    ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;",
    ["\""] = "&quot;", ["'"] = "&#39;",
  }))
end

-- Remove characters that are illegal in Windows filenames.
local function SanitizeFilename(s)
  return (tostring(s or ""):gsub('[<>:"/\\|%?%*]', "-"))
end

-- Native track color -> "#rrggbb". Returns nil when the track has no custom color.
local function TrackColorHex(track)
  local native = r.GetTrackColor(track)
  if native == 0 then return nil end
  local rr, gg, bb = r.ColorFromNative(native)
  return string.format("#%02x%02x%02x", rr, gg, bb)
end

-- Format a linear track volume (D_VOL) as a dB string. 0 -> "-inf".
local function FormatVolume(linear)
  if linear <= 0 then return "-inf dB" end
  local db = LinearTodB(linear)
  if math.abs(db) < 0.05 then return "0.0 dB" end
  return string.format("%+.1f dB", db)
end

-- Format a pan value (-1..1) as a readable "<n>% L/R" / "C".
local function FormatPan(pan)
  if math.abs(pan) < 0.005 then return "C" end
  local pct = math.floor(math.abs(pan) * 100 + 0.5)
  return string.format("%d%% %s", pct, pan < 0 and "L" or "R")
end

-- Track display name, falling back to "Track N" when unnamed.
local function TrackName(track)
  local _, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  if not name or name == "" then
    name = "Track " .. math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
  end
  return name
end

-- Active FX on a track. Bypassed / offline FX are treated as null and skipped.
-- Each entry: { plugin = <plug-in name>, alias = <user-set name or nil> }.
local function GetTrackFX(track)
  local fx = {}
  for i = 0, r.TrackFX_GetCount(track) - 1 do
    local enabled = r.TrackFX_GetEnabled(track, i)
    local offline = r.TrackFX_GetOffline(track, i)
    if enabled and not offline then
      -- "fx_name" = underlying plug-in; "renamed_name" = the user's custom label.
      local _, plugin = r.TrackFX_GetNamedConfigParm(track, i, "fx_name")
      local _, alias  = r.TrackFX_GetNamedConfigParm(track, i, "renamed_name")
      if not plugin or plugin == "" then
        local _, disp = r.TrackFX_GetFXName(track, i, "")
        plugin = disp
      end
      if alias == "" or alias == plugin then alias = nil end
      fx[#fx + 1] = { plugin = plugin, alias = alias }
    end
  end
  return fx
end

-- Aux sends FROM this track: { {dest=, vol=}, ... }
local function GetTrackSends(track)
  local sends = {}
  for i = 0, r.GetTrackNumSends(track, 0) - 1 do
    local dest = r.GetTrackSendInfo_Value(track, 0, i, "P_DESTTRACK")
    local vol = r.GetTrackSendInfo_Value(track, 0, i, "D_VOL")
    local muted = r.GetTrackSendInfo_Value(track, 0, i, "B_MUTE") == 1
    sends[#sends + 1] = { dest = TrackName(dest), vol = FormatVolume(vol), muted = muted }
  end
  return sends
end

-- Aux receives INTO this track: { {src=, vol=}, ... }
local function GetTrackReceives(track)
  local recvs = {}
  for i = 0, r.GetTrackNumSends(track, -1) - 1 do
    local src = r.GetTrackSendInfo_Value(track, -1, i, "P_SRCTRACK")
    local vol = r.GetTrackSendInfo_Value(track, -1, i, "D_VOL")
    local muted = r.GetTrackSendInfo_Value(track, -1, i, "B_MUTE") == 1
    recvs[#recvs + 1] = { src = TrackName(src), vol = FormatVolume(vol), muted = muted }
  end
  return recvs
end


-- Build the inner HTML for a single track block. Only properties that differ
-- from their default are shown; a track with no adjustments at all is rendered
-- with a dimmed name and nothing else.
local function RenderTrack(track, depth)
  local color = TrackColorHex(track) or "#666666"
  local name = EscapeHTML(TrackName(track))

  -- Gather state, deciding which values are adjustments (non-default).
  local linear = r.GetMediaTrackInfo_Value(track, "D_VOL")
  local vol_default = (linear > 0) and (math.abs(LinearTodB(linear)) < 0.05)
  local pan = r.GetMediaTrackInfo_Value(track, "D_PAN")
  local pan_default = math.abs(pan) < 0.005
  local muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
  local fx = GetTrackFX(track)
  local sends = GetTrackSends(track)
  local recvs = GetTrackReceives(track)

  local has_adj = (not vol_default) or (not pan_default) or muted
    or (#fx > 0) or (#sends > 0) or (#recvs > 0)

  local out = {}
  out[#out + 1] = string.format(
    '<div class="track%s" style="margin-left:%dpx;border-left-color:%s">',
    has_adj and "" or " noadj", depth * 22, color)

  -- Header row: color swatch + name + non-default levels.
  out[#out + 1] = '<div class="thead">'
  out[#out + 1] = string.format('<span class="swatch" style="background:%s"></span>', color)
  out[#out + 1] = string.format('<span class="tname%s">%s</span>', has_adj and "" or " dim", name)
  if muted then out[#out + 1] = '<span class="badge mute">MUTED</span>' end
  if not vol_default then
    out[#out + 1] = string.format('<span class="lvl">Vol <b>%s</b></span>',
      EscapeHTML(FormatVolume(linear)))
  end
  if not pan_default then
    out[#out + 1] = string.format('<span class="lvl">Pan <b>%s</b></span>',
      EscapeHTML(FormatPan(pan)))
  end
  out[#out + 1] = '</div>'

  -- FX (only when there is at least one active plug-in).
  if #fx > 0 then
    local parts = {}
    for _, f in ipairs(fx) do
      if f.alias then
        parts[#parts + 1] = string.format('<span class="fx">%s</span> <span class="plug">(%s)</span>',
          EscapeHTML(f.alias), EscapeHTML(f.plugin))
      else
        parts[#parts + 1] = string.format('<span class="fx">%s</span>', EscapeHTML(f.plugin))
      end
    end
    out[#out + 1] = '<div class="detail"><span class="label">FX:</span> ' ..
      table.concat(parts, ", ") .. '</div>'
  end

  -- Aux sends (only when present).
  if #sends > 0 then
    local parts = {}
    for _, s in ipairs(sends) do
      parts[#parts + 1] = string.format('&#8594; %s (%s)%s',
        EscapeHTML(s.dest), EscapeHTML(s.vol), s.muted and " [muted]" or "")
    end
    out[#out + 1] = '<div class="detail"><span class="label">Aux sends:</span> ' ..
      table.concat(parts, ", ") .. '</div>'
  end

  -- Aux receives (only when present).
  if #recvs > 0 then
    local parts = {}
    for _, rc in ipairs(recvs) do
      parts[#parts + 1] = string.format('&#8592; %s (%s)%s',
        EscapeHTML(rc.src), EscapeHTML(rc.vol), rc.muted and " [muted]" or "")
    end
    out[#out + 1] = '<div class="detail"><span class="label">Aux receives:</span> ' ..
      table.concat(parts, ", ") .. '</div>'
  end

  out[#out + 1] = '</div>'
  return table.concat(out, "\n")
end


function main()
  -- Resolve the session directory + name.
  local _, projfn = r.EnumProjects(-1, "")
  if not projfn or projfn == "" then
    r.ShowMessageBox("Save the project first - the change list is written into the session folder.",
      "Export Mix Change List", 0)
    return
  end
  local session_dir = projfn:match("^(.*[\\/])")
  local session_name = projfn:match("([^\\/]+)%.[Rr][Pp][Pp]$") or "Session"

  -- Determine which tracks to include. No selection -> whole session,
  -- otherwise ONLY the selected tracks.
  local sel_count = r.CountSelectedTracks(0)
  local include = {}  -- MediaTrack* -> true
  for i = 0, sel_count - 1 do
    local t = r.GetSelectedTrack(0, i)
    include[t] = true
    Log("Selected:", TrackName(t))
  end
  Log("Selected track count:", sel_count, "(0 = whole session)")

  local total_tracks = r.CountTracks(0)
  if total_tracks == 0 then
    r.ShowMessageBox("This session has no tracks.", "Export Mix Change List", 0)
    return
  end

  -- Walk all tracks to keep folder depth accurate, but only emit included ones.
  -- Indentation still reflects each track's real depth in the session.
  local body = {}
  local depth = 0
  local rendered = 0
  for i = 0, total_tracks - 1 do
    local track = r.GetTrack(0, i)
    if (sel_count == 0) or include[track] then
      body[#body + 1] = RenderTrack(track, depth)
      rendered = rendered + 1
    end
    depth = depth + r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if depth < 0 then depth = 0 end
  end

  local stamp_human = os.date("%Y-%m-%d %H:%M:%S")
  local stamp_file = os.date("%Y-%m-%d %H-%M-%S")
  local scope = (sel_count == 0)
    and string.format("Whole session (%d tracks)", total_tracks)
    or string.format("%d selected track(s)", rendered)

  -- Assemble the full HTML document.
  local html = string.format([[<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>%s - Mix Change List</title>
<style>
  body { font-family: -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
         background: #1e1f22; color: #e8e8e8; margin: 0; padding: 28px 32px; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  .meta { color: #9aa0a6; font-size: 13px; margin-bottom: 22px; }
  .meta b { color: #cfd3d7; }
  .track { border-left: 5px solid #666; background: #26272b; border-radius: 4px;
           padding: 8px 12px; margin-bottom: 6px; }
  .track.noadj { background: #202125; padding: 5px 12px; }
  .thead { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
  .swatch { width: 14px; height: 14px; border-radius: 3px; display: inline-block;
            box-shadow: 0 0 0 1px rgba(255,255,255,.15); flex: none; }
  .tname { font-weight: 600; font-size: 15px; }
  .tname.dim { font-weight: 500; color: #6b7075; }
  .lvl { font-size: 12px; color: #9aa0a6; }
  .lvl b { color: #e8e8e8; }
  .badge { font-size: 10px; padding: 1px 6px; border-radius: 3px; font-weight: 700; }
  .badge.mute { background: #5a2d2d; color: #ffb3b3; }
  .detail { font-size: 13px; color: #c4c8cc; margin: 5px 0 0 24px; }
  .label { color: #8ab4f8; font-weight: 600; }
  .fx { color: #e8e8e8; }
  .plug { color: #9aa0a6; font-size: 12px; }
  .footer { color: #6b7075; font-size: 11px; margin-top: 28px; }
</style>
</head>
<body>
<h1>%s &mdash; Mix Change List</h1>
<div class="meta">
  Generated <b>%s</b> &nbsp;&middot;&nbsp; Scope: <b>%s</b><br>
  Snapshot of current mix state: volume, pan, FX, and aux sends/receives per track.
</div>
%s
<div class="footer">Generated by jrope_%s</div>
</body>
</html>
]],
    EscapeHTML(session_name),
    EscapeHTML(session_name),
    EscapeHTML(stamp_human),
    EscapeHTML(scope),
    table.concat(body, "\n"),
    EscapeHTML(SCRIPT_NAME))

  -- Write the file.
  local filename = string.format("%s - Mix Change List - %s.html",
    SanitizeFilename(session_name), stamp_file)
  local filepath = session_dir .. filename
  local f, err = io.open(filepath, "w")
  if not f then
    r.ShowMessageBox("Could not write file:\n" .. tostring(err), "Export Mix Change List", 0)
    return
  end
  f:write(html)
  f:close()
  Log("Wrote change list:", filepath)

  if OPEN_WHEN_DONE then
    if r.CF_ShellExecute then
      r.CF_ShellExecute(filepath)
    else
      os.execute('start "" "' .. filepath .. '"')
    end
  end

  r.ShowMessageBox("Mix change list saved:\n\n" .. filepath, "Export Mix Change List", 0)
end


---------------------------------
-------------- MAIN -------------
---------------------------------

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

main()

reaper.Undo_EndBlock("jrope_"..SCRIPT_NAME, -1)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
