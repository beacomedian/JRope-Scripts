--[[
 * Name: Import Wwise Mixer to Track Hierarchy
 * Author: Jesse Rope
 * Repository: github.com/beacomedian/JRope-Scripts
 * Licence: GPL v3
 * REAPER: 7.4
 * Version: 1.4
 * Provides:
    [main] . > 
 * Link: https://www.jesserope.com
 * About:
    # Prompts the user to select a Wwise Master Mixer work unit (.wwu),
    # parses the Bus hierarchy from its XML, and creates a matching
    # folder/track hierarchy in the current Reaper project.
    # Each Bus becomes a track. Buses with children become folder tracks.
    # Bus volume (BusVolume property) is applied to each track where present.
    # Bus color (Color property) is mapped to Reaper track colors.
 * Changelog:
    # v1.4 - Added SKIP_BUSES filter: buses whose names contain any listed
    #         string are skipped along with their entire subtree.
    # v1.3 - Added Wwise color index -> Reaper track color mapping
    # v1.2 - Fixed parser: Bus tags only recognized inside <ChildrenList> blocks.
    #         Added handling for self-closing <Bus .../> tags.
    # v1.1 - Fixed folder depth close values for nested folder trees
    # v1.0 - Initial Release
 * To Do:
    # Verify color hex values against actual Wwise palette (see USER CONFIG note)
]]


---------------------------------
---------- USER CONFIG ----------
---------------------------------

-- Set to true to skip the root "Master Audio Bus" track and start from its
-- children. Useful if your project already has a master fader track.
local SKIP_ROOT_BUS = false

-- Set to true to apply BusVolume property values to Reaper track volumes.
-- Wwise BusVolume is in dB. Converted to linear via: 10^(dB/20)
local APPLY_VOLUME = true

-- Set to true to apply Wwise bus colors as Reaper track colors.
-- Colors are sampled from the Wwise color palette screenshot.
-- If any color looks wrong, find its index below and adjust the hex value.
-- Format: 0x1BBGGRR  (Reaper stores colors as BGR with 0x1000000 flag)
local APPLY_COLOR = true

-- List of strings to filter out during import.
-- Any bus whose name contains one of these strings (case-insensitive partial
-- match) will be skipped entirely, along with its whole subtree of children.
-- Add as many strings as you like, separated by commas.
-- Example: { "z_TEST", "Secondary No Output", "_OLD" }
-- Leave empty ({}) to import everything.
local SKIP_BUSES = { "z_TEST", "Secondary", "Control Signals" }

-- Wwise color index -> Reaper color integer
-- Index 0 = no color assigned (leaves track at Reaper default, no color set)
-- Indices 1-27 are the Wwise palette slots.
--
-- *** THESE ARE SAMPLED FROM A SCREENSHOT — verify against your Wwise palette ***
-- To adjust: convert your target RGB to Reaper format:
--   reaper_int = 0x1000000 | R | (G * 256) | (B * 65536)
-- Example: pure red (255,0,0) = 0x10000FF
--
local WWISE_COLORS = {
    [0]  = 0,          -- no color / use Reaper default
    [1]  = 0x1C8823C,  -- blue          rgb(60, 130, 200)
    [2]  = 0x1E6AA50,  -- sky blue      rgb(80, 170, 230)
    [3]  = 0x1C8B428,  -- teal          rgb(40, 180, 200)
    [4]  = 0x15AAA3C,  -- green         rgb(60, 170, 90)
    [5]  = 0x13CBE78,  -- lime          rgb(120, 190, 60)
    [6]  = 0x132C8A0,  -- yellow-green  rgb(160, 200, 50)
    [7]  = 0x132B4C8,  -- yellow        rgb(200, 180, 50)
    [8]  = 0x1328CC8,  -- amber         rgb(200, 140, 50)
    [9]  = 0x12864C8,  -- orange        rgb(200, 100, 40)
    [10] = 0x14646C8,  -- red-orange    rgb(200, 70, 70)
    [11] = 0x12828B4,  -- red           rgb(180, 40, 40)
    [12] = 0x1783CC8,  -- magenta       rgb(200, 60, 120)
    [13] = 0x1B4468C,  -- purple        rgb(140, 70, 180)
    [14] = 0x11EAAC8,  -- gold          rgb(200, 170, 30)
    [15] = 0x1B49646,  -- steel blue    rgb(70, 150, 180)
    [16] = 0x1C86E6E,  -- periwinkle    rgb(110, 110, 200)
    [17] = 0x1964696,  -- violet        rgb(150, 70, 150)
    [18] = 0x18C46C8,  -- hot pink      rgb(200, 70, 140)
    [19] = 0x1503CB4,  -- dark rose     rgb(180, 60, 80)
    [20] = 0x14678C8,  -- burnt orange  rgb(200, 120, 70)
    [21] = 0x1508296,  -- khaki         rgb(150, 130, 80)
    [22] = 0x15A8C5A,  -- muted green   rgb(90, 140, 90)
    [23] = 0x18C7846,  -- slate blue    rgb(70, 120, 140)
    [24] = 0x18C5064,  -- muted purple  rgb(100, 80, 140)
    [25] = 0x1645078,  -- mauve         rgb(120, 80, 100)
    [26] = 0x150648C,  -- brown         rgb(140, 100, 80)
    [27] = 0x1787878,  -- gray          rgb(120, 120, 120)
}


---------------------------------
----------- CONSTANTS -----------
---------------------------------

local SCRIPT_NAME = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local r = reaper
local proj = 0


---------------------------------
----------- FUNCTIONS -----------
---------------------------------

local function dBToLinear(db)
    return 10 ^ (db / 20)
end


-- ---------------------------------------------------------------
-- parseXML_busHierarchy(filepath)
--
--   Parses a Wwise .wwu Master Mixer work unit.
--   Only Bus tags inside <ChildrenList> blocks are treated as
--   hierarchy nodes — Bus references in <DuckingList> etc. are ignored.
--
--   Each node table has:
--     .name     (string)  the Bus Name attribute
--     .volume   (number|nil)  BusVolume in dB if set
--     .color    (number|nil)  Wwise Color index if set (0 = no color)
--     .children (table)  ordered list of child nodes
-- ---------------------------------------------------------------
local function parseXML_busHierarchy(filepath)

    local file = io.open(filepath, "r")
    if not file then
        r.ShowMessageBox("Could not open file:\n" .. filepath, "Error", 0)
        return nil
    end
    local content = file:read("*all")
    file:close()

    local bus_stack = {}
    local root_nodes = {}
    local children_list_depth = 0
    local capturing_volume = false
    local current_bus_for_volume = nil

    for line in content:gmatch("[^\n]+") do

        -- Track <ChildrenList> depth so we only pick up Bus tags that are
        -- actual children, not Bus references in DuckingList/ReferenceList/etc.
        if line:match("<ChildrenList>") then
            children_list_depth = children_list_depth + 1
        end
        if line:match("</ChildrenList>") then
            children_list_depth = children_list_depth - 1
        end

        if children_list_depth > 0 then

            -- Self-closing Bus tag: <Bus Name="Foo" ID="..."/>
            -- Has no children or content — do not push onto the stack.
            local self_closing_name = line:match('<Bus%s+Name="([^"]+)"[^>]*/>')
            if self_closing_name then
                local node = { name = self_closing_name, volume = nil, color = nil, children = {} }
                if #bus_stack > 0 then
                    table.insert(bus_stack[#bus_stack].children, node)
                else
                    table.insert(root_nodes, node)
                end

            else
                -- Normal opening Bus tag: <Bus Name="Foo" ID="...">
                local bus_name = line:match('<Bus%s+Name="([^"]+)"')
                if bus_name then
                    local node = { name = bus_name, volume = nil, color = nil, children = {} }
                    if #bus_stack > 0 then
                        table.insert(bus_stack[#bus_stack].children, node)
                    else
                        table.insert(root_nodes, node)
                    end
                    table.insert(bus_stack, node)
                end
            end
        end

        -- </Bus> always pops the stack — it appears outside </ChildrenList>
        if line:match("</Bus>") then
            if #bus_stack > 0 then table.remove(bus_stack) end
            capturing_volume = false
            current_bus_for_volume = nil
        end

        -- ---- BusVolume property ----
        -- Inline form: <Property Name="BusVolume" Type="Real64" Value="-3"/>
        local inline_vol = line:match('Name="BusVolume"[^/]* Value="([^"]+)"')
        if inline_vol then
            if bus_stack[#bus_stack] then
                bus_stack[#bus_stack].volume = tonumber(inline_vol)
            end
        end
        -- Block form: value on the following <Value> line
        if line:match('Name="BusVolume"') and not inline_vol then
            capturing_volume = true
            current_bus_for_volume = bus_stack[#bus_stack]
        end
        if capturing_volume then
            local vol_val = line:match("<Value>([^<]+)</Value>")
            if vol_val and current_bus_for_volume then
                current_bus_for_volume.volume = tonumber(vol_val)
                capturing_volume = false
                current_bus_for_volume = nil
            end
        end
        if capturing_volume and line:match("</PropertyList>") then
            capturing_volume = false
            current_bus_for_volume = nil
        end

        -- ---- Color property ----
        -- Always appears as an inline attribute:
        -- <Property Name="Color" Type="int16" Value="7"/>
        -- This is only present when OverrideColor is True for that bus.
        -- Buses that inherit their parent's color have no Color property.
        local color_val = line:match('Name="Color"%s+Type="int16"%s+Value="([^"]+)"')
        if color_val then
            if bus_stack[#bus_stack] then
                bus_stack[#bus_stack].color = tonumber(color_val)
            end
        end

    end

    return root_nodes
end


-- ---------------------------------------------------------------
-- shouldSkip(name)
--   Returns true if the bus name matches any entry in SKIP_BUSES.
--   Matching is case-insensitive and partial — "TEST" matches "z_TEST",
--   "test_bus", "MY_TEST_RIG", etc.
--
--   How it works:
--     string.lower() converts both the bus name and the filter string to
--     lowercase before comparing, so capitalisation never matters.
--     string.find() returns the start/end position of the first match, or
--     nil if there is no match. We only care whether a match exists (not
--     where), so checking "~= nil" is sufficient.
-- ---------------------------------------------------------------
local function shouldSkip(name)
    if #SKIP_BUSES == 0 then return false end
    local name_lower = string.lower(name)
    for _, filter in ipairs(SKIP_BUSES) do
        if string.find(name_lower, string.lower(filter), 1, true) ~= nil then
            -- The fourth argument `true` to string.find disables Lua pattern
            -- matching and does a plain text search instead. This means
            -- filter strings like "z_TEST" are treated literally — the
            -- underscore is just an underscore, not a pattern wildcard.
            return true
        end
    end
    return false
end


-- ---------------------------------------------------------------
-- createTracksFromNode(node, insert_index_ref)
--
--   Recursively creates Reaper tracks from the parsed bus tree.
--   Returns the index of the last track inserted in this subtree
--   so the caller can accumulate folder-close depth signals on it.
-- ---------------------------------------------------------------
local function createTracksFromNode(node, insert_index_ref)

    local idx = insert_index_ref[1]

    r.InsertTrackAtIndex(idx, false)
    local track = r.GetTrack(proj, idx)

    -- Name
    r.GetSetMediaTrackInfo_String(track, "P_NAME", node.name, true)

    -- Volume
    if APPLY_VOLUME and node.volume ~= nil then
        r.SetMediaTrackInfo_Value(track, "D_VOL", dBToLinear(node.volume))
    end

    -- Color
    -- node.color is the Wwise index (1-27), or nil if no Color property was set.
    -- We look it up in WWISE_COLORS. Index 0 means "no override" so we skip it.
    if APPLY_COLOR and node.color ~= nil then
        local reaper_color = WWISE_COLORS[node.color]
        if reaper_color and reaper_color ~= 0 then
            r.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", reaper_color)
        end
    end

    insert_index_ref[1] = insert_index_ref[1] + 1

    local last_track_idx = idx

    -- Filter children: build a list of children that are not being skipped.
    -- We do this before deciding whether to mark the track as a folder,
    -- so a bus whose only children are all filtered out stays a normal track.
    local visible_children = {}
    for _, child in ipairs(node.children) do
        if not shouldSkip(child.name) then
            table.insert(visible_children, child)
        end
    end

    if #visible_children > 0 then
        r.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 1)

        for _, child in ipairs(visible_children) do
            last_track_idx = createTracksFromNode(child, insert_index_ref)
        end

        -- Subtract 1 from the last track's depth to close this folder level.
        -- Values accumulate correctly for multiply-nested closes.
        local last_track = r.GetTrack(proj, last_track_idx)
        if last_track then
            local current_depth = r.GetMediaTrackInfo_Value(last_track, "I_FOLDERDEPTH")
            r.SetMediaTrackInfo_Value(last_track, "I_FOLDERDEPTH", current_depth - 1)
        end
    end

    return last_track_idx
end


-- ---------------------------------------------------------------
-- main()
-- ---------------------------------------------------------------
function main()

    local retval, filepath = r.GetUserFileNameForRead("", "Select Wwise Work Unit (.wwu)", ".wwu")
    if retval == false or filepath == "" then return end

    local bus_tree = parseXML_busHierarchy(filepath)

    if not bus_tree or #bus_tree == 0 then
        r.ShowMessageBox(
            "No Bus objects found in the selected file.\nMake sure this is a Wwise Master Mixer work unit.",
            "Import Failed", 0
        )
        return
    end

    local buses_to_import = {}

    if SKIP_ROOT_BUS then
        if bus_tree[1] and #bus_tree[1].children > 0 then
            for _, child in ipairs(bus_tree[1].children) do
                table.insert(buses_to_import, child)
            end
        else
            buses_to_import = bus_tree
        end
    else
        buses_to_import = bus_tree
    end

    local existing_track_count = r.CountTracks(proj)
    local insert_index_ref = { existing_track_count }
    local skipped_count = 0

    for _, bus_node in ipairs(buses_to_import) do
        if shouldSkip(bus_node.name) then
            skipped_count = skipped_count + 1
        else
            createTracksFromNode(bus_node, insert_index_ref)
        end
    end

    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()

    local total_created = insert_index_ref[1] - existing_track_count
    local skip_msg = skipped_count > 0 and ("\nSkipped " .. skipped_count .. " top-level bus(es).") or ""
    r.ShowMessageBox(
        "Done! Created " .. total_created .. " track(s) from:\n" .. filepath .. skip_msg,
        "Wwise Mixer Import",
        0
    )

end


---------------------------------
-------------- MAIN -------------
---------------------------------

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

main()

reaper.Undo_EndBlock("jrope_" .. SCRIPT_NAME, -1)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()