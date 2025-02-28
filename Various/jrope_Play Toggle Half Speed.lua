-- @description Play Toggle Half Speed and Reset Playrate on Stop
-- @author Stephen Schappler (modified by Jesse Rope)
-- @version 1.1
-- @about
--   Play at Half Speed or Toggle to Normal Speed if already playing, and Reset Playrate on Stop. Chose "New Instance" when retriggering.
-- @link https://www.stephenschappler.com
-- @changelog 
--   7/30/24 Creating the script
--   2/28/25 Modified to toggle playback speed if already playing

function play_toggle_half_speed()
  -- Check if transport is already playing
  local playstate = reaper.GetPlayState()
  
  if playstate == 1 then -- 1 means playing
    -- Get current playrate
    local current_playrate = reaper.Master_GetPlayRate()
    
    -- If already playing at half speed, change to normal speed
    if math.abs(current_playrate - 0.5) < 0.01 then -- Using a small threshold for floating point comparison
      reaper.CSurf_OnPlayRateChange(1.0)
    else
      -- If playing at normal speed or other speed, change to half speed
      reaper.CSurf_OnPlayRateChange(0.5)
    end
  else
    -- Not playing, so start playing at half speed
    reaper.CSurf_OnPlayRateChange(0.5)
    reaper.OnPlayButton()
  end
end
  
function reset_playrate_on_stop()
  -- Check if playback is stopped
  if reaper.GetPlayState() == 0 then -- 0 means stopped
    -- Reset the playrate to 1.0
    reaper.CSurf_OnPlayRateChange(1.0)
     
    -- Stop the deferred function
    return
  end
  
  -- Continuously defer the function to check for stop state
  reaper.defer(reset_playrate_on_stop)
end
  
-- Main function
reaper.Undo_BeginBlock() -- Begin the undo block
play_toggle_half_speed()
reaper.defer(reset_playrate_on_stop) -- Defer the reset function
reaper.Undo_EndBlock("Play Toggle Half Speed and Reset Playrate on Stop", -1) -- End the undo block
reaper.UpdateArrange() -- Update the arrangement view
