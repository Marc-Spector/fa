-----------------------------------------------------------------
-- File     : /lua/sim/MarkerUtilities.lua
-- Summary  : Aim of this file is to work with markers without
-- worrying about unneccesary table allocations. All base game
-- functionality allocates a new table when you wish to retrieve
-- a sequence of markers. This file implicitly stores a sequence
-- of markers and returns a reference, unless you explicitly
-- want a new table with unique values.

-- Extractor / hydrocarbon markers are setup different from the other
-- markers. As an example, you can not flush these markers. This
-- is done to support adaptive maps and the crazy rush mode.

-- Contains various debug facilities to help understand the
-- state that is stored in this file.

-- Supports crazyrush-like maps.
-----------------------------------------------------------------

local StringSplit = import("/lua/system/utils.lua").StringSplit
local TableDeepCopy = table.deepcopy

---@alias MarkerType 'Mass' | 'Hydrocarbon' | 'Spawn' | 'Air Path Node' | 'Land Path Node' | 'Water Path Node' | 'Ampibious Path Node' | 'Transport Marker' | 'Naval Area' | 'Naval Link' | 'Rally Point' | 'Expansion Area' | 'Protected Experimental Construction'

---@class MarkerData
---@field size number
---@field resource boolean
---@field type string
---@field orientation Vector
---@field position Vector
---@field color Color | nil
---@field adjacentTo string         # used by old pathing markers to identify the neighbors
---@field name? string              # used by spawn markers
---@field NavLayer NavLayers        # Navigational layer that this marker is on, only defined for resources
---@field NavLabel number | nil     # Navigational label of the graph this marker is on, only defined for resources and when AIs are in-game

--- Contains all the markers that are part of the map, including markers of chains
local AllMarkers = Scenario.MasterChain._MASTERCHAIN_.Markers

---@return MarkerData[]
function GetAllMarkers()
    return AllMarkers
end

--- Retrieves a single marker on the map.
---@param name string
---@return MarkerData
function GetMarker(name)
    return AllMarkers[name]
end

--- Represents a cache of markers to prevent re-populating tables
local MarkerCache = {}

-- Pre-enable the caching of resource markers, to support adaptive maps
MarkerCache["Mass"] = { Count = 0, Markers = {} }
MarkerCache["Hydrocarbon"] = { Count = 0, Markers = {} }
MarkerCache["Spawn"] = { Count = 0, Markers = {} }

local armies = table.hash(ListArmies())
for k, marker in AllMarkers do
    if armies[k] then
        marker.name = k
        MarkerCache["Spawn"].Count = MarkerCache["Spawn"].Count + 1
        MarkerCache["Spawn"].Markers[MarkerCache["Spawn"].Count] = marker
    end
end

--- Retrieves all markers of a given type. This is a shallow copy,
-- which means the reference is copied but the values are not. If you
-- need a copy with unique values use GetMarkerByTypeDeep instead.
-- Common marker types are:
-- - "Mass", "Hydrocarbon", "Spawn"
-- - "Air Path Node", "Land Path Node", "Water Path Node", "Amphibious Path Node"
-- - "Transport Marker", "Naval Area", "Naval Link", "Rally Point", "Expansion Area"
-- - "Protected Experimental Construction"
-- The list is not limited to these marker types - any marker that has a 'type' property
-- can be cached. You can find them in the <map>_save.lua file.
---@param type string The type of marker to retrieve.
---@return MarkerData[]
---@return number
function GetMarkersByType(type)

    -- check if it is cached and return that
    local cache = MarkerCache[type]
    if cache then
        return cache.Markers, cache.Count
    end

    -- prepare cache population
    local ms = {}
    local n = 1

    -- find all the relevant markers
    for k, marker in AllMarkers do
        if marker.type == type then
            ms[n] = marker
            n = n + 1
        end
    end

    -- tell us about it, for now
    SPEW("Caching " .. n - 1 .. " markers of type " .. type .. "!")

    -- construct the cache
    cache = {
        Count = n - 1,
        Markers = ms
    }

    -- cache it and return it
    MarkerCache[type] = cache
    return cache.Markers, cache.Count
end

--- Retrieves all markers of a given type. This is a deep copy
-- and involves a lot of additional allocations. Do not use this
-- unless you strictly need to.
---@param type string
---@return MarkerData[]
---@return number
function GetMarkersByTypeDeep(type)
    local markers, number = GetMarkersByType(type)
    return TableDeepCopy(markers), number
end

--- Flushes the cache of a certain type. Does not remove
-- existing references.
---@param type string The type to flush.
function FlushMarkerCacheByType(type)

    -- give developer a warning, you can't do this
    if type == "Mass" or type == "Hydrocarbon" or type == "Spawn" then
        WARN("Unable to flush resource markers from the cache - it can cause issues for adaptive maps.")
        return
    end

    MarkerCache[type] = false
end

--- Flushes the entire marker cache. Does not remove existing references.
function FlushMarkerCache()

    -- copy over for consistency
    local cache = {}
    cache.Mass = MarkerCache.Mass
    cache.Hydrocarbon = MarkerCache.Hydrocarbon
    cache.Spawn = MarkerCache.Spawn

    MarkerCache = cache
end

--- Contains all the chains that are part of the map
local AllChains = Scenario.Chains

--- Represents a cache of chains to prevent re-populating tables
local ChainCache = {}

--- Retrieves a chain of markers. Throws an error if the chain
-- does not exist. This is a shallow copy, which means the
-- reference is copied but the values are not. If you need a
-- copy with unique values use GetMarkerByTypeDeep instead.
---@param name MarkerChain The type of marker to retrieve.
---@return MarkerData
---@return number
function GetMarkersInChain(name)
    -- check if it is cached and return that
    local cache = ChainCache[name]
    if cache then
        return cache.Markers, cache.Count
    end

    -- check if chain exists
    local chain = AllChains[name]
    if not chain then
        error('ERROR: Invalid Chain Named- ' .. name, 2)
    end

    -- prepare cache population
    local ms = {}
    local n = 1

    -- find all the relevant markers
    for k, elem in chain.Markers do
        ms[n] = elem.position
        n = n + 1
    end

    -- construct the cache
    cache = {
        Count = n - 1,
        Markers = ms
    }

    -- cache it and return it
    ChainCache[name] = cache
    return cache.Markers, cache.Count
end

--- Retrieves a chain of markers. Throws an error if the
-- chain does not exist. This is a deep copy and involves
-- a lot of additional allocations. Do not use this unless
-- you strictly need to.
---@param type MarkerChain The type of marker to retrieve.
---@return MarkerData[]
---@return number
function GetMarkersInChainDeep(type)
    local markers, count = GetMarkersInChain(type)
    return TableDeepCopy(markers), count
end

--- Flushes the chain cache of a certain type. Does not
-- remove existing references.
---@param name MarkerChain The type to flush.
function FlushChainCacheByName(name)
    ChainCache[name] = false
end

--- Flushes the chain cache. Does not remove existing references.
-- @param type The type to flush.
function FlushChainCache()
    ChainCache = {}
end

--- Retrieves the name / key values of the marker types that are in
-- the cache. This returns a new table in each call - do not use in
-- production code. Useful in combination with ToggleDebugMarkersByType.
-- returns Table with names and the number of names.
function DebugGetMarkerTypesInCache()

    -- allocate a table
    local next = 1
    local types = {}

    -- retrieve all names
    for k, cache in MarkerCache do
        types[next] = k
        next = next + 1
    end

    return types, next - 1
end

--- Keeps track of all marker debugging threads
local DebugMarkerThreads = {}
local DebugMarkerSuspend = {}

--- Debugs the marker cache of a given type by drawing it on-screen. Useful
-- to check for errors. Can be toggled on and off by calling it again.
---@param type MarkerChain The type of markers you wish to debug.
function ToggleDebugMarkersByType(type)

    SPEW("Toggled type to debug: " .. type)

    -- get the thread if it exists
    local thread = DebugMarkerThreads[type]
    if not thread then

        -- make the thread if it did not exist yet
        thread = ForkThread(
            function()

                local labelToColor = import("/lua/shared/navgenerator.lua").LabelToColor

                while true do

                    -- check if we should sleep or not
                    if DebugMarkerSuspend[type] then
                        SuspendCurrentThread()
                    end

                    -- draw out all markers
                    local markers, count = GetMarkersByType(type)
                    for k = 1, count do
                        local marker = markers[k]
                        DrawCircle(marker.position, marker.size or 1, marker.color or 'ffffffff')

                        if marker.NavLabel then
                            DrawCircle(marker.position, (marker.size or 1) + 1, labelToColor(marker.NavLabel))
                        end

                        -- useful for pathing markers
                        if marker.adjacentTo then
                            for _, neighbour in StringSplit(marker.adjacentTo, " ") do
                                local neighbour = AllMarkers[neighbour]
                                if neighbour then
                                    DrawLine(marker.position, neighbour.position, marker.color or 'ffffffff')
                                end
                            end
                        end
                    end

                    WaitTicks(2)
                end
            end
        )

        -- store it and return
        DebugMarkerSuspend[type] = false
        DebugMarkerThreads[type] = thread
        return
    end

    -- enable the thread if it should not be suspended
    DebugMarkerSuspend[type] = not DebugMarkerSuspend[type]
    if not DebugMarkerSuspend[type] then
        ResumeThread(thread)
    end

    -- keep track of it
    DebugMarkerThreads[type] = thread
end

--- Retrieves the name / key values of the chains that are in the
-- cache. This returns a new table in each call - do not use in
-- production code.  Useful in combination with ToggleDebugMarkersByType.
---@return string[]
---@return number
function DebugGetChainNamesInCache()

    -- allocate a table
    local next = 1
    local types = {}

    -- retrieve all names
    for k, cache in ChainCache do
        types[next] = k
        next = next + 1
    end

    return types, next - 1
end

--- Keeps track of all chain debugging threads
local DebugChainThreads = {}
local DebugChainSuspend = {}

--- Debugs the chain cache of a given type by drawing it on-screen. Useful
-- to check for errors. Can be toggled on and off by calling it again.
---@param name MarkerChain The name of the chain you wish to debug.
function ToggleDebugChainByName(name)

    SPEW("Toggled chain to debug: " .. name)

    -- get the thread if it exists
    local thread = DebugChainThreads[name]
    if not thread then

        -- make the thread if it did not exist yet
        thread = ForkThread(
            function()
                while true do

                    -- check if we should suspend ourselves
                    if DebugChainSuspend[name] then
                        SuspendCurrentThread()
                    end

                    -- draw out all markers
                    local markers, count = GetMarkersInChain(name)
                    if count > 1 then
                        for k = 1, count - 1 do
                            local curr = markers[k]
                            local next = markers[k + 1]
                            DrawLinePop(curr.position, next.position, curr.color or next.color or 'ffffffff')
                        end

                        -- draw out a single marker
                    else
                        if count == 1 then
                            local marker = markers[1]
                            DrawCircle(marker.position, marker.size or 1, marker.color or 'ffffffff')
                        else
                            WARN("Trying to debug draw an empty chain: " .. name)
                        end
                    end

                    WaitTicks(2)
                end
            end
        )

        -- store it and return
        DebugChainSuspend[name] = false
        DebugChainThreads[name] = thread
        return
    end

    -- resume thread it is should not be suspended
    DebugChainSuspend[name] = not DebugChainSuspend[name]
    if not DebugChainSuspend[name] then
        ResumeThread(thread)
    end

    -- keep track of it
    DebugChainThreads[name] = thread
end

do

    -- hook to cache markers created on the fly by crazy rush type of games
    local OldCreateResourceDeposit = _G.CreateResourceDeposit
    _G.CreateResourceDeposit = function(type, x, y, z, size)

        local NavUtils = import("/lua/sim/navutils.lua")

        -- fix to terrain height
        y = GetTerrainHeight(x, z)
        OldCreateResourceDeposit(type, x, y, z, size)

        local position = Vector(x, y, z)
        local orientation = Vector(0, -0, 0)

        ---@type NavLayers
        local layer = 'Land'
        if y < GetSurfaceHeight(x, z) then
            layer = 'Amphibious'
        end

        ---@type number | nil
        local label = nil
        if NavUtils.IsGenerated() then
            label = NavUtils.GetLabel(layer, { x, y, z })
        end

        -- commented values are used by the editor and not by the game
        ---@type MarkerData
        local marker = nil
        if type == 'Mass' then
            marker = {
                size = size,
                resource = true,
                type = type,
                orientation = orientation,
                position = position,

                NavLayer = layer,
                NavLabel = label,
            }
        else
            marker = {
                size = size,
                resource = true,
                type = type,
                orientation = orientation,
                position = position,

                NavLayer = layer,
                NavLabel = label,
            }
        end

        -- make sure cache exists
        local markers, count = GetMarkersByType(type)
        MarkerCache[type].Count = count + 1
        MarkerCache[type].Markers[count + 1] = marker
    end
end
