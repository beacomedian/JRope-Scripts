--[[
   * Category:    FX
   * Description: FX; Online all active FX on selected tracks.lua
   * Author:      Archie (modified by Jesse Rope)
   * Repository:  https://github.com/ArchieScript/Archie_ReaScripts/raw/master/index.xml 
   * Version:     1.1
   * Changelog:
   *              v.1.0
   *                  + initial
   *              v.1.1 JRope Modification
   *                  + Skip FX that are manually bypassed
   *                  + Skip FX that have a bypass envelope (automation-managed)
   *                  # Fixed bypass envelope detection: use TrackFX_GetParamFromIdent(':bypass')
   *                    instead of hardcoded parameter index 0
--]]

    --======================================================================================
    --////////////  НАСТРОЙКИ  \\\\\\\\\\\\  SETTINGS  ////////////  НАСТРОЙКИ  \\\\\\\\\\\\
    --======================================================================================

    local MASTER = true;  -- Set to false to exclude the Master track from selection

    --======================================================================================
    --////////////// SCRIPT \\\\\\\\\\\\\\  SCRIPT  //////////////  SCRIPT  \\\\\\\\\\\\\\\\
    --======================================================================================

    --=========================================
    local function MODULE(file);
        local E,A=pcall(dofile,file);if not(E)then;reaper.ShowConsoleMsg("\n\nError - "..debug.getinfo(1,'S').source:match('.*[/\\](.+)')..'\nMISSING FILE / ОТСУТСТВУЕТ ФАЙЛ!\n'..file:gsub('\\','/'))return;end;
        if not A.VersArcFun("2.8.6",file,'')then;A=nil;return;end;return A;
    end; local Arc = MODULE((reaper.GetResourcePath()..'/Scripts/Archie-ReaScripts/Functions/Arc_Function_lua.lua'):gsub('\\','/'));
    if not Arc then return end;
    --=========================================


    -- Returns true if the given FX slot has a bypass envelope.
    --
    -- IMPORTANT: GetFXEnvelope requires the parameter index of the bypass control,
    -- which is NOT guaranteed to be 0. We ask REAPER for it explicitly using
    -- TrackFX_GetParamFromIdent with the special built-in identifier ':bypass'.
    -- This returns the correct index regardless of plugin type or parameter order.
    --
    -- The 'false' final argument tells REAPER to only *check* for the envelope —
    -- not create one if it doesn't exist, which would be an unwanted side effect.
    local function fx_has_bypass_envelope(track, fx_index)
        local byp_param = reaper.TrackFX_GetParamFromIdent(track, fx_index, ':bypass')
        local env = reaper.GetFXEnvelope(track, fx_index, byp_param, false)
        return env ~= nil
    end


    MASTER = MASTER == true;

    local count_sel_tracks = reaper.CountSelectedTracks2(0, MASTER);
    if count_sel_tracks == 0 then no_undo() return end;


    for i = 1, count_sel_tracks do
        local track = reaper.GetSelectedTrack2(0, i - 1, MASTER);

        for ifx = 1, reaper.TrackFX_GetCount(track) do
            local fx_index = ifx - 1;

            -- Gate 1: Skip FX that are already online. Nothing to do.
            local is_offline = reaper.TrackFX_GetOffline(track, fx_index)
            if not is_offline then goto continue end;

            -- Gate 2: Skip FX that are manually bypassed (disabled).
            -- We only want to bring back FX that are actually meant to be running.
            local is_enabled = reaper.TrackFX_GetEnabled(track, fx_index)
            if not is_enabled then goto continue end;

            -- Gate 3: Skip FX that have a bypass envelope.
            -- If automation is managing the bypass state, we should not override it.
            if fx_has_bypass_envelope(track, fx_index) then goto continue end;

            -- All gates passed: FX is offline, active, and not bypass-automated.
            -- Begin the undo block lazily — only once we know we'll actually make a change.
            if not UNDO then
                reaper.Undo_BeginBlock();
                reaper.PreventUIRefresh(1);
                UNDO = true;
            end;

            reaper.TrackFX_SetOffline(track, fx_index, false);  -- false = set online

            ::continue::
        end
    end


    if UNDO then
        reaper.PreventUIRefresh(-1);
        reaper.Undo_EndBlock('Online active FX on selected tracks', -1);
    else
        no_undo();
    end;
