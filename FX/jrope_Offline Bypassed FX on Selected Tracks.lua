--[[
   * Category:    FX
   * Description: FX; Offline all inactive bypassed FX on selected tracks.lua
   * Author:      Archie (modified by Jesse Rope)
   * Repository:  https://github.com/ArchieScript/Archie_ReaScripts/raw/master/index.xml
   * Version:     1.1
   * Changelog:
   *              v.1.0
   *                  + initial
   *              v.1.1 JRope Modification
   *                  # Fixed bypass envelope detection: use TrackFX_GetParamFromIdent(':bypass')
   *                    instead of hardcoded parameter index 0, which was incorrectly offlining
   *                    FX that have an active bypass envelope
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

    -- Returns true if an FX is "truly inactive":
    --   1. It is not enabled (i.e. it IS bypassed), AND
    --   2. There is no bypass envelope automating that state.
    -- An FX with a bypass envelope is managed by automation and should not be
    -- touched by this script, even if it happens to be bypassed right now.
    local function fx_is_truly_inactive(track, fx_index)
        local is_enabled      = reaper.TrackFX_GetEnabled(track, fx_index)
        local has_bypass_env  = fx_has_bypass_envelope(track, fx_index)

        return (not is_enabled) and (not has_bypass_env)
    end


    MASTER = MASTER == true;

    local count_sel_tracks = reaper.CountSelectedTracks2(0, MASTER);
    if count_sel_tracks == 0 then no_undo() return end;


    for i = 1, count_sel_tracks do
        local track = reaper.GetSelectedTrack2(0, i - 1, MASTER);

        for ifx = 1, reaper.TrackFX_GetCount(track) do
            local fx_index = ifx - 1;

            -- Gate 1: Skip FX that are already offline. Nothing to do.
            local is_offline = reaper.TrackFX_GetOffline(track, fx_index)
            if is_offline then goto continue end;

            -- Gate 2: Skip FX that are active (enabled) or bypass-automated.
            -- We only want to take action on the truly inactive ones.
            if not fx_is_truly_inactive(track, fx_index) then goto continue end;

            -- Both gates passed: this FX is bypassed, not automated, and currently online.
            -- Begin the undo block lazily — only once we know we'll actually make a change.
            if not UNDO then
                reaper.Undo_BeginBlock();
                reaper.PreventUIRefresh(1);
                UNDO = true;
            end;

            reaper.TrackFX_SetOffline(track, fx_index, true);  -- true = set offline

            ::continue::
        end
    end


    if UNDO then
        reaper.PreventUIRefresh(-1);
        reaper.Undo_EndBlock('Offline inactive bypassed FX on selected tracks', -1);
    else
        no_undo();
    end;
