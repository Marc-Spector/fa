
--******************************************************************************************************
--** Copyright (c) 2022  Willem 'Jip' Wijnia
--** 
--** Permission is hereby granted, free of charge, to any person obtaining a copy
--** of this software and associated documentation files (the "Software"), to deal
--** in the Software without restriction, including without limitation the rights
--** to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--** copies of the Software, and to permit persons to whom the Software is
--** furnished to do so, subject to the following conditions:
--** 
--** The above copyright notice and this permission notice shall be included in all
--** copies or substantial portions of the Software.
--** 
--** THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--** IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--** FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--** AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--** LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--** OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--** SOFTWARE.
--******************************************************************************************************

local Shared = import("/lua/shared/navgenerator.lua")

---@alias NavTerrainCache number[][]
---@alias NavDepthCache number[][]
---@alias NavAverageDepthCache number[][]
---@alias NavHorizontalPathCache boolean[][]
---@alias NavVerticalPathCache boolean[][]
---@alias NavPathCache boolean[][]
---@alias NavTerrainBlockCache boolean[][]
---@alias NavLabelCache number[][]

local Statistics = {
    CulledLabels = 0
}

--- TODO: should this be dynamic, based on playable area?
--- Number of blocks that encompass the map, per axis
---@type number
local LabelCompressionTreesPerAxis = 16

--- Maximum height difference that is considered to be pathable, within a single oGrid
---@type number
local MaxHeightDifference = 0.75

--- Maximum depth that amphibious units consider to be pathable
---@type number
local MaxWaterDepthAmphibious = 25

--- Minimum dept that Naval units consider to be pathable
---@type number
local MinWaterDepthNaval = 1.5

-- Generated data

---@class NavGrids
---@field Land? NavGrid
---@field Water? NavGrid
---@field Hover? NavGrid
---@field Amphibious? NavGrid
---@field Air? NavGrid
NavGrids = { }

---@class NavLabelMetadata
---@field Node CompressedLabelTreeLeaf
---@field Area number
---@field Layer NavLayers
---@field NumberOfExtractors number
---@field NumberOfHydrocarbons number
---@field ExtractorMarkers MarkerData[]
---@field HydrocarbonMarkers MarkerData[]
-- ---@field NumberOfSpawns number
-- ---@field NumberOfExpansions number
-- ---@field NumberOfDefensePoints number
-- ---@field ExpansionMarkers MarkerData[]
-- ---@field DefensePointMarkers MarkerData[]

---@type table<number, NavLabelMetadata>
NavLabels = { }

local Generated = false
---@return boolean
function IsGenerated()
    return Generated
end

local CompressedTreeIdentifier = 0
---@return number
local function GenerateCompressedTreeIdentifier()
    CompressedTreeIdentifier = CompressedTreeIdentifier + 1
    return CompressedTreeIdentifier
end

local LabelIdentifier = 0
---@return number
local function GenerateLabelIdentifier()
    LabelIdentifier = LabelIdentifier + 1
    return LabelIdentifier
end

-- Shared data with UI

---@type NavLayerData
local NavLayerData = Shared.CreateEmptyNavLayerData()

local tl = { 0, 0, 0 }
local tr = { 0, 0, 0 }
local bl = { 0, 0, 0 }
local br = { 0, 0, 0 }

--- Draws a square on the map
---@param px number
---@param pz number
---@param c number
---@param color string
local function DrawSquare(px, pz, c, color, inset)
    inset = inset or 0
    tl[1], tl[2], tl[3] = px + inset, GetSurfaceHeight(px + inset, pz + inset), pz + inset
    tr[1], tr[2], tr[3] = px + c - inset, GetSurfaceHeight(px + c - inset, pz + inset), pz + inset
    bl[1], bl[2], bl[3] = px + inset, GetSurfaceHeight(px + inset, pz + c - inset), pz + c - inset
    br[1], br[2], br[3] = px + c - inset, GetSurfaceHeight(px + c - inset, pz + c - inset), pz + c - inset

    DrawLine(tl, tr, color)
    DrawLine(tl, bl, color)
    DrawLine(br, bl, color)
    DrawLine(br, tr, color)
end

---@class NavGrid
---@field Layer NavLayers
---@field TreeSize number
---@field Trees CompressedLabelTree[][]
NavGrid = ClassSimple {

    ---@param self NavGrid
    ---@param layer NavLayers
    __init = function(self, layer, treeSize)
        self.Trees = { }
        for z = 0, LabelCompressionTreesPerAxis - 1 do
            self.Trees[z] = { }
        end

        self.TreeSize = treeSize
        self.Layer = layer
    end,

    Simplify = function(self)
        for z = 0, LabelCompressionTreesPerAxis - 1 do
            for x = 0, LabelCompressionTreesPerAxis - 1 do
                self.Trees[z][x]:Simplify()
            end
        end
    end,

    --- Adds a compressed label tree to the navigational grid
    ---@param self NavGrid
    ---@param z number index
    ---@param x number index
    ---@param labelTree CompressedLabelTree
    AddTree = function (self, z, x, labelTree)
        self.Trees[z][x] = labelTree
    end,

    --- Returns the leaf that encompasses the position, or nil if no leaf does
    ---@param self NavGrid
    ---@param position Vector A position in world space
    ---@return CompressedLabelTreeLeaf?
    FindLeaf = function(self, position)
        return self:FindLeafXZ(position[1], position[3])
    end,

    --- Returns the leaf that encompasses the x / z coordinates, or nil if no leaf does
    ---@param self NavGrid
    ---@param x number x-coordinate, in world space
    ---@param z number z-coordinate, in world space
    ---@return CompressedLabelTreeLeaf?
    FindLeafXZ = function(self, x, z)
        if x > 0 and z > 0 then
            local bx = (x / self.TreeSize) ^ 0
            local bz = (z / self.TreeSize) ^ 0
            local labelTree = self.Trees[bz][bx]
            if labelTree then
                return labelTree:FindLeafXZ(x, z)
            end
        end

        return nil
    end,

    ---@param self NavGrid
    GenerateNeighbors = function(self)
        for z = 0, LabelCompressionTreesPerAxis - 1 do
            for x = 0, LabelCompressionTreesPerAxis - 1 do
                self.Trees[z][x]:GenerateDirectNeighbors(self)
            end
        end

        for z = 0, LabelCompressionTreesPerAxis - 1 do
            for x = 0, LabelCompressionTreesPerAxis - 1 do
                self.Trees[z][x]:GenerateCornerNeighbors(self)
            end
        end
    end,

    ---@param self NavGrid
    GenerateLabels = function(self)
        local labelStart = LabelIdentifier
        local stack = { }
        for z = 0, LabelCompressionTreesPerAxis - 1 do
            for x = 0, LabelCompressionTreesPerAxis - 1 do
                self.Trees[z][x]:GenerateLabels(stack)
            end
        end

        local labelEnd = LabelIdentifier
        NavLayerData[self.Layer].Labels = labelEnd - labelStart
    end,

    ---@param self NavGrid
    Precompute = function(self)
        for z = 0, LabelCompressionTreesPerAxis - 1 do
            for x = 0, LabelCompressionTreesPerAxis - 1 do
                self.Trees[z][x]:PrecomputePhase1()
            end
        end

        for z = 0, LabelCompressionTreesPerAxis - 1 do
            for x = 0, LabelCompressionTreesPerAxis - 1 do
                self.Trees[z][x]:PrecomputePhase2()
            end
        end
    end,

    --- Draws all trees with the correct layer color
    ---@param self NavGrid
    Draw = function(self)
        for z = 0, LabelCompressionTreesPerAxis - 1 do
            for x = 0, LabelCompressionTreesPerAxis - 1 do
                self.Trees[z][x]:Draw(Shared.LayerColors[self.Layer])
            end
        end
    end,

    --- Draws all trees with their corresponding labels
    ---@param self NavGrid
    DrawLabels = function(self, inset)
        for z = 0, LabelCompressionTreesPerAxis - 1 do
            for x = 0, LabelCompressionTreesPerAxis - 1 do
                self.Trees[z][x]:DrawLabels(inset)
            end
        end
    end,
}

-- defined here, as it is a recursive class
local CompressedLabelTree

--- The leaf of the compression tree, with additional properties used during path finding
---@class CompressedLabelTreeLeaf : CompressedLabelTree
---@field label number                                      # Label for efficient `CanPathTo` check
---@field neighbors table<number, CompressedLabelTreeLeaf>  # Neighbors of this leaf that acts like a graph
---@field neighborDistances table<number, number>           # Distance to each neighbor neighbors
---@field neighborDirections table<number, any>             # Normalized direction to each neighbor
---@field px number                                         # x-coordinate of center in world space
---@field pz number                                         # z-coordinate of center in world space
---@field From CompressedLabelTreeLeaf
---@field AcquiredCosts number
---@field TotalCosts number
---@field Seen number   

--- A simplified quad tree that acts as a compression of the pathing capabilities of a section of the heightmap
---@class CompressedLabelTree
---@field identifier number     # Unique number used for table operations
---@field layer NavLayers       # Layer that this label tree is operating on, used for debugging
---@field bx number             # Location of top-left corner, in world space
---@field bz number             # Location of top-left corner, in world space
---@field ox number             # Offset of top-left corner, in world space
---@field oz number             # Offset of top-left corner, in world space
---@field c number              # Element count starting at { bx + ox, bz + oz } that describes the square that is covered
---@field children? CompressedLabelTree[]                   # Is populated if we are a node
---@field label? number                                     # Is populated if we are a leaf
---@field neighbors? table<number, CompressedLabelTree>     # Is populated if we are a leaf
---@field neighborDistances? table<number, number>          # Is populated if we are a leaf
---@field neighborDirections? table<number, any>            # Is populated if we are a leaf
---@field px? number                                        # Is populated if we are a leaf
---@field pz? number                                        # Is populated if we are a leaf
CompressedLabelTree = ClassSimple {

    ---@param self CompressedLabelTree
    ---@param bx number
    ---@param bz number
    ---@param c number
    __init = function(self, layer, bx, bz, c, ox, oz)
        self.identifier = GenerateCompressedTreeIdentifier()

        self.layer = layer
        self.bx = bx
        self.bz = bz
        self.c = c

        self.ox = ox or 0
        self.oz = oz or 0

        -- these are technically obsolete, but are here for code readability
        self.children = nil
        self.label = nil
        self.neighbors = nil
    end,

    --- Compresses the cache using a quad tree, significantly reducing the amount of data stored. At this point
    --- the label cache only exists of 0s and -1s
    ---@param self CompressedLabelTree
    ---@param rCache NavLabelCache
    Compress = function(self, rCache, compressionThreshold)
        -- base case, if we're a square of 4 then we skip the children and become very pessimistic
        if self.c <= compressionThreshold then
            local value = rCache[self.oz + 1][self.ox + 1]
            local uniform = true
            for z = self.oz + 1, self.oz + self.c do
                for x = self.ox + 1, self.ox + self.c do
                    uniform = uniform and (value == rCache[z][x])
                    if not uniform  then
                        break
                    end
                end
            end

            if uniform then 
                self.label = value

                if self.label >= 0 then 
                    NavLayerData[self.layer].PathableLeafs = NavLayerData[self.layer].PathableLeafs + 1
                else 
                    NavLayerData[self.layer].UnpathableLeafs = NavLayerData[self.layer].UnpathableLeafs + 1
                end
            else 
                self.label = -1
                NavLayerData[self.layer].UnpathableLeafs = NavLayerData[self.layer].UnpathableLeafs + 1
            end

            return
        end

        -- recursive case where we do make children
        local value = rCache[self.oz + 1][self.ox + 1]
        local uniform = true 
        for z = self.oz + 1, self.oz + self.c do
            for x = self.ox + 1, self.ox + self.c do
                uniform = uniform and (value == rCache[z][x])
                if not uniform then
                    break
                end
            end
        end

        if uniform then
            -- we're uniform, so we're good
            self.label = value

            if self.label >= 0 then 
                NavLayerData[self.layer].PathableLeafs = NavLayerData[self.layer].PathableLeafs + 1
            else
                NavLayerData[self.layer].UnpathableLeafs = NavLayerData[self.layer].UnpathableLeafs + 1
            end
        else
            -- we're not uniform, split up to children
            local hc = 0.5 * self.c
            self.children = {
                CompressedLabelTree(self.layer, self.bx, self.bz, hc, self.ox, self.oz),
                CompressedLabelTree(self.layer, self.bx, self.bz, hc, self.ox + hc, self.oz),
                CompressedLabelTree(self.layer, self.bx, self.bz, hc, self.ox, self.oz + hc),
                CompressedLabelTree(self.layer, self.bx, self.bz, hc, self.ox + hc, self.oz + hc)
            }

            for k, child in self.children do
                child:Compress(rCache, compressionThreshold)
            end

            NavLayerData[self.layer].Subdivisions = NavLayerData[self.layer].Subdivisions + 1
        end
    end,

    --- Generates the following neighbors, when they are valid:
    --- ```
    --- 0 | 1 | 0
    --- 1 | x | 1
    --- 0 | 1 | 0
    --- ```
    ---@param self CompressedLabelTree
    ---@param root NavGrid
    GenerateDirectNeighbors = function(self, root)
        -- do not generate neighbors for non-pathable cells to save memory
        if self.label == -1 then
            return
        end

        -- nodes do not have neighbors, only leafs do
        if self.children then
            for _, child in self.children do
                child:GenerateDirectNeighbors(root)
            end
            return
        end

        -- we are a leaf, so find those neighbors!
        local x1 = self.bx + self.ox
        local z1 = self.bz + self.oz
        local size = self.c
        local x2 = x1 + size
        local z2 = z1 + size
        local x1Outside, z1Outside = x1 - 0.5, z1 - 0.5
        local x2Outside, z2Outside = x2 + 0.5, z2 + 0.5

        local neighbors = {}
        self.neighbors = neighbors

        -- scan top-left -> top-right
        for k = x1, x2 - 1 do
            local x = k + 0.5
            -- DrawCircle({x, GetSurfaceHeight(x, z1Outside), z1Outside}, 0.5, 'ff0000')
            local neighbor = root:FindLeafXZ(x, z1Outside)
            if neighbor then
                k = k + neighbor.c - 1
                if neighbor.label >= 0 then
                    neighbors[neighbor.identifier] = neighbor
                end
            else 
                break
            end
        end

        -- scan bottom-left -> bottom-right
        for k = x1, x2 - 1 do
            local x = k + 0.5
            -- DrawCircle({x, GetSurfaceHeight(x, z2Outside), z2Outside}, 0.5, 'ff0000')
            local neighbor = root:FindLeafXZ(x, z2Outside)
            if neighbor then
                k = k + neighbor.c - 1
                if neighbor.label >= 0 then
                    neighbors[neighbor.identifier] = neighbor
                end
            else 
                break
            end
        end

        -- scan left-top -> left-bottom
        for k = z1, z2 - 1 do
            z = k + 0.5
            -- DrawCircle({x1Outside, GetSurfaceHeight(x1Outside, z), z}, 0.5, 'ff0000')
            local neighbor = root:FindLeafXZ(x1Outside, z)
            if neighbor then
                k = k + neighbor.c - 1
                if neighbor.label >= 0 then
                    neighbors[neighbor.identifier] = neighbor
                end
            else 
                break
            end
        end

        -- scan right-top -> right-bottom
        for k = z1, z2 - 1 do
            z = k + 0.5
            -- DrawCircle({x2Outside, GetSurfaceHeight(x2Outside, z), z}, 0.5, 'ff0000')
            local neighbor = root:FindLeafXZ(x2Outside, z)
            if neighbor then
                k = k + neighbor.c - 1
                if neighbor.label >= 0 then
                    neighbors[neighbor.identifier] = neighbor
                end
            else 
                break
            end
        end
    end,

    --- Generates the following neighbors, when they are valid:
    --- ```
    --- 1 | 0 | 1
    --- 0 | x | 0
    --- 1 | 0 | 1
    --- ```
    ---@param self CompressedLabelTree
    ---@param root NavGrid
    GenerateCornerNeighbors = function(self, root)
        -- do not generate neighbors for non-pathable cells to save memory
        local label = self.label
        if label == -1 then
            return
        end

        -- nodes do not have neighbors, only leafs do
        if self.children then
            for _, child in self.children do
                child:GenerateCornerNeighbors(root)
            end
            return
        end

        -- we are a leaf, so find those neighbors!
        local neighbors = self.neighbors
        local x1 = self.bx + self.ox
        local z1 = self.bz + self.oz
        local size = self.c
        local x2 = x1 + size
        local z2 = z1 + size
        local x1Outside, z1Outside = x1 - 0.5, z1 - 0.5
        local x2Outside, z2Outside = x2 + 0.5, z2 + 0.5

        -- scan top-left
        local a, b
        local neighbor = root:FindLeafXZ(x1Outside, z1Outside)
        -- DrawCircle({x1Outside, GetSurfaceHeight(x1Outside, z1Outside), z1Outside}, 0.5, 'ff0000')
        if neighbor and neighbor.label >= 0 then
            a = root:FindLeafXZ(x1Outside + 1, z1Outside)
            b = root:FindLeafXZ(x1Outside, z1Outside + 1)

            if a and b and label == a.label and label == b.label then
                neighbors[neighbor.identifier] = neighbor
            end
        end

        -- scan top-right
        neighbor = root:FindLeafXZ(x2Outside, z1Outside)
        -- DrawCircle({x2Outside, GetSurfaceHeight(x2Outside, z1Outside), z1Outside}, 0.5, 'ff0000')
        if neighbor and neighbor.label >= 0 then
            a = root:FindLeafXZ(x2Outside -1, z1Outside)
            b = root:FindLeafXZ(x2Outside, z1Outside + 1)

            if a and b and label == a.label and label == b.label then
                neighbors[neighbor.identifier] = neighbor
            end
        end

        -- scan bottom-left
        -- DrawCircle({x1Outside, GetSurfaceHeight(x1Outside, z2Outside), z2Outside}, 0.5, 'ff0000')
        neighbor = root:FindLeafXZ(x1Outside, z2Outside)
        if neighbor and neighbor.label >= 0 then
            a = root:FindLeafXZ(x1Outside + 1, z2Outside)
            b = root:FindLeafXZ(x1Outside, z2Outside - 1)

            if a and b and label == a.label and label == b.label then
                neighbors[neighbor.identifier] = neighbor
            end
        end

        -- scan bottom-right
        -- DrawCircle({x2Outside, GetSurfaceHeight(x2Outside, z2Outside), z2Outside}, 0.5, 'ff0000')
        neighbor = root:FindLeafXZ(x2Outside, z2Outside)
        if neighbor and neighbor.label >= 0 then
            a = root:FindLeafXZ(x2Outside - 1, z2Outside)
            b = root:FindLeafXZ(x2Outside, z2Outside - 1)

            if a and b and label == a.label and label == b.label then
                neighbors[neighbor.identifier] = neighbor
            end
        end

        NavLayerData[self.layer].Neighbors = NavLayerData[self.layer].Neighbors + table.getsize(neighbors)
    end,

    ---@param self CompressedLabelTree
    ---@param stack table
    GenerateLabels = function(self, stack)
        -- leaf case
        if self.label then

            -- check if we are unassigned (labels start at 1)
            if self.label == 0 then

                -- we can hit a stack overflow if we do this recursively, therefore we do a 
                -- depth first search using a stack that we re-use for better performance
                local free = 1
                local label = GenerateLabelIdentifier()

                NavLabels[label] = {
                    Area = 0,
                    Node = self --[[@as CompressedLabelTreeLeaf]],
                    Layer = self.layer,
                    NumberOfExtractors = 0,
                    NumberOfHydrocarbons = 0,
                    ExtractorMarkers = { },
                    HydrocarbonMarkers = { },
                }

                local metadata = NavLabels[label]

                -- assign the label, and then search through our neighbors to assign the same label to them
                self.label = label
                metadata.Area = metadata.Area + (( 0.01 * self.c) * ( 0.01 * self.c))

                -- add our pathable neighbors to the stack
                for _, neighbor in self.neighbors do
                    if neighbor.label == 0 then
                        stack[free] = neighbor
                        free = free + 1
                    end

                    if neighbor.label > 0 then 
                        WARN("Something fishy happened")
                    end
                end

                -- do depth first search
                while free > 1 do

                    -- retrieve from stack
                    local other = stack[free - 1]
                    free = free - 1

                    -- assign label, manage metadata
                    other.label = label
                    metadata.Area = metadata.Area + (( 0.01 * other.c) * ( 0.01 * other.c))

                    -- add unlabelled neighbors
                    for _, neighbor in other.neighbors do
                        if neighbor.label == 0 then
                            stack[free] = neighbor
                            free = free + 1
                        end
                    end
                end
            end

            return
        end

        -- node case
        for _, child in self.children do
            child:GenerateLabels(stack)
        end
    end,

    ---@param self CompressedLabelTreeLeaf
    PrecomputePhase1 = function(self)
        if self.children then 
            for k, child in self.children do
                child:PrecomputePhase1()
            end
        else 
            if self.neighbors then
                self.px = self.bx + self.ox + 0.5 * self.c
                self.pz = self.bz + self.oz + 0.5 * self.c
            end
        end
    end,

    ---@param self CompressedLabelTreeLeaf
    PrecomputePhase2 = function(self)
        if self.children then 
            for k, child in self.children do
                child:PrecomputePhase2()
            end
        else 
            if self.neighbors then
                self.neighborDirections = { }
                self.neighborDistances = { }

                for k, neighbor in self.neighbors do
                    local dx = neighbor.px - self.px
                    local dz = neighbor.pz - self.pz
                    self.neighborDirections[k] = { dx, dz}
                    self.neighborDistances[k] = math.sqrt(dx * dx + dz * dz)
                end
            end
        end
    end,

    ---@param self CompressedLabelTreeLeaf
    ---@param other CompressedLabelTreeLeaf
    ---@return number
    DistanceTo = function(self, other)
        local dx = self.px - other.px
        local dz = self.pz - other.pz
        return math.sqrt(dx * dx + dz * dz)
    end,

    --- Returns the leaf that encompasses the position, or nil if no leaf does
    ---@param self CompressedLabelTree
    ---@param position Vector A position in world space
    ---@return CompressedLabelTreeLeaf?
    FindLeaf = function(self, position)
        return self:FindLeafXZ(position[1], position[3])
    end,

    --- Returns the leaf that encompasses the position, or nil if no leaf does
    ---@param self CompressedLabelTree
    ---@param x number x-coordinate, in world space
    ---@param z number z-coordinate, in world space
    ---@return CompressedLabelTreeLeaf?
    FindLeafXZ = function(self, x, z)
        local x1 = self.bx + self.ox
        local z1 = self.bz + self.oz
        local size = self.c
        -- Check if it's inside our rectangle the first time only
        if x < x1 or x1 + size < x or z < z1 or z1 + size < z then
            return nil
        end
        return self:_FindLeafXZ(x - self.bx, z - self.bz)
    end;

    ---@param self CompressedLabelTree
    ---@param x number
    ---@param z number
    ---@return CompressedLabelTreeLeaf?
    _FindLeafXZ = function(self, x, z)
        local children = self.children
        if children then
            local hsize = self.c * 0.5
            local hx, hz = self.ox + hsize, self.oz + hsize
            local child
            if z < hz then
                if x < hx then
                    child = children[1] -- top left
                else
                    child = children[2] -- top right
                end
            else
                if x < hx then
                    child = children[3] -- bottom left
                else
                    child = children[4] -- bottom right
                end
            end
            if child then
                return child:_FindLeafXZ(x, z)
            end
        else
            return self --[[@as CompressedLabelTreeLeaf]]
        end
    end;

    ---@param self CompressedLabelTree
    ---@param color Color
    Draw = function(self, color, inset)
        if self.label != nil then
            if self.label >= 0 then
                DrawSquare(self.bx + self.ox, self.bz + self.oz, self.c, color, inset)
            end
        else
            for _, child in self.children do
                child:Draw(color, inset)
            end
        end
    end,

    ---@param self CompressedLabelTree
    DrawLabels = function(self, inset)
        if self.label != nil then
            if self.label >= 0 then
                DrawSquare(self.bx + self.ox, self.bz + self.oz, self.c, Shared.LabelToColor(self.label), inset)
            end
        else
            for _, child in self.children do
                child:DrawLabels(inset)
            end
        end
    end,
}

---@param cells number
---@return NavTerrainCache
---@return NavDepthCache
---@return NavAverageDepthCache
---@return NavHorizontalPathCache
---@return NavVerticalPathCache
---@return NavPathCache
---@return NavTerrainBlockCache
---@return NavLabelCache
function InitCaches(cells)
    local tCache, dCache, daCache, pxCache, pzCache, pCache, bCache, rCache = {}, {}, {}, {}, {}, {}, {}, {}

    -- these need one additional element, as they represent the corners / sides of the cell we're evaluating
    for z = 1, cells + 1 do
        tCache[z] = {}
        dCache[z] = {}
        pxCache[z] = {}
        pzCache[z] = {}
        for x = 1, cells + 1 do
            tCache[z][x] = -1
            dCache[z][x] = -1
            pxCache[z][x] = true
            pzCache[z][x] = true
        end
    end

    -- these represent the cell as a whole, and therefore do not need an additional element
    for z = 1, cells do
        pCache[z] = {}
        bCache[z] = {}
        rCache[z] = {}
        daCache[z] = {}
        for x = 1, cells do
            pCache[z][x] = false
            bCache[z][x] = false
            rCache[z][x] = -1
            daCache[z][x] = -1
        end
    end

    return tCache, dCache, daCache, pxCache, pzCache, pCache, bCache, rCache
end

--- Populates the caches for the given label tree,
--- Heavily inspired by the code written by Softles
---@param labelTree CompressedLabelTree
---@param tCache NavTerrainCache
---@param dCache NavDepthCache
---@param daCache NavAverageDepthCache
---@param pxCache NavHorizontalPathCache
---@param pzCache NavVerticalPathCache
---@param pCache NavPathCache
---@param bCache NavTerrainBlockCache
function PopulateCaches(labelTree, tCache, dCache, daCache, pxCache, pzCache, pCache, bCache)
    local MathAbs = math.abs
    local Mathmax = math.max
    local GetTerrainHeight = GetTerrainHeight
    local GetSurfaceHeight = GetSurfaceHeight
    local GetTerrainType = GetTerrainType

    local size = labelTree.c
    local bx, bz = labelTree.bx, labelTree.bz

    -- scan / cache terrain and depth
    for z = 1, size + 1 do
        local absZ = bz + z - 1
        for x = 1, size + 1 do
            local absX = bx + x - 1
            local terrain = GetTerrainHeight(absX, absZ)
            local surface = GetSurfaceHeight(absX, absZ)

            tCache[z][x] = terrain
            dCache[z][x] = surface - terrain

            -- DrawSquare(x - 0.15, z - 0.15, 0.3, 'ff0000')
        end
    end

    -- scan / cache cliff walkability
    for z = 1, size + 1 do
        for x = 1, size do
            pxCache[z][x] = MathAbs(tCache[z][x] - tCache[z][x + 1]) < MaxHeightDifference
        end
    end

    for z = 1, size do
        for x = 1, size + 1 do
            pzCache[z][x] = MathAbs(tCache[z][x] - tCache[z + 1][x]) < MaxHeightDifference
        end
    end

    -- compute cliff walkability
    -- compute average depth
    -- compute terrain type
    for z = 1, size do
        local absZ = bz + z
        for x = 1, size do
            local absX = bx + x
            pCache[z][x] = pxCache[z][x] and pzCache[z][x] and pxCache[z + 1][x] and pzCache[z][x + 1]
            daCache[z][x] = (dCache[z][x] + dCache[z + 1][x] + dCache[z][x + 1] + dCache[z + 1][x + 1]) * 0.25
            bCache[z][x] = not GetTerrainType(absX, absZ).Blocking

            -- local color = 'ff0000'
            -- if pCache[lz][lx] == 0 then
            --     color = '00ff00'
            -- end

            -- DrawSquare(labelTree.bx + x + 0.35, labelTree.bz + z + 0.35, 0.3, color)
        end
    end
end

---@param labelTree CompressedLabelTree
---@param daCache NavAverageDepthCache
---@param bCache NavTerrainBlockCache
---@param pCache NavPathCache
---@param rCache NavLabelCache
function ComputeLandPathingMatrix(labelTree, daCache, pCache, bCache, rCache)
    local size = labelTree.c
    for z = 1, size do
        for x = 1, size do
            if  daCache[z][x] <= 0 and -- should be on land
                bCache[z][x] and       -- should have accessible terrain type
                pCache[z][x]           -- should be flat enough
            then
                rCache[z][x] = 0
                --DrawSquare(labelTree.bx + x + 0.3, labelTree.bz + z + 0.3, 0.4, '00ff00')
            else
                rCache[z][x] = -1
            end
        end
    end
end

---@param labelTree CompressedLabelTree
---@param daCache NavAverageDepthCache
---@param bCache NavTerrainBlockCache
---@param pCache NavPathCache
---@param rCache NavLabelCache
function ComputeHoverPathingMatrix(labelTree, daCache, pCache, bCache, rCache)
    local size = labelTree.c
    for z = 1, size do
        for x = 1, size do
            if bCache[z][x] and (        -- should have accessible terrain type
                daCache[z][x] >= 1 or -- can either be on water
                pCache[z][x]             -- or on flat enough terrain
            ) then
                rCache[z][x] = 0
                --DrawSquare(labelTree.bx + x + 0.4, labelTree.bz + z + 0.4, 0.2, '00b3b3')
            else
                rCache[z][x] = -1
            end
        end
    end
end

---@param labelTree CompressedLabelTree
---@param daCache NavAverageDepthCache
---@param bCache NavTerrainBlockCache
---@param pCache NavPathCache
---@param rCache NavLabelCache
function ComputeNavalPathingMatrix(labelTree, daCache, pCache, bCache, rCache)
    local size = labelTree.c
    for z = 1, size do
        for x = 1, size do
            if daCache[z][x] >= MinWaterDepthNaval and -- should be deep enough
                bCache[z][x] -- should have accessible terrain type
            then
                rCache[z][x] = 0
                --DrawSquare(labelTree.bx + x + 0.45, labelTree.bz + z + 0.45, 0.1, '0000ff')
            else -- this is inaccessible
                rCache[z][x] = -1
            end
        end
    end
end

---@param labelTree CompressedLabelTree
---@param daCache NavAverageDepthCache
---@param bCache NavTerrainBlockCache
---@param pCache NavPathCache
---@param rCache NavLabelCache
function ComputeAmphPathingMatrix(labelTree, daCache, pCache, bCache, rCache)
    local size = labelTree.c
    for z = 1, size do
        for x = 1, size do
            if daCache[z][x] <= MaxWaterDepthAmphibious and -- should be on land
                bCache[z][x] and -- should have accessible terrain type
                pCache[z][x] -- should be flat enough
            then
                rCache[z][x] = 0
                --DrawSquare(labelTree.bx + x + 0.35, labelTree.bz + z + 0.35, 0.3, 'ffa500')
            else -- this is inaccessible
                rCache[z][x] = -1
            end
        end
    end
end

---@param labelTree CompressedLabelTree
---@param daCache NavAverageDepthCache
---@param bCache NavTerrainBlockCache
---@param pCache NavPathCache
---@param rCache NavLabelCache
function ComputeAirPathingMatrix(labelTree, daCache, pCache, bCache, rCache)
    local size = labelTree.c
    for z = 1, size do
        for x = 1, size do
            rCache[z][x] = 0
        end
    end
end

--- Generates the compression grids based on the heightmap
---@param size number (square) size of each cell of the compression grid
---@param threshold number (square) size of the smallest acceptable leafs, used for culling
local function GenerateCompressionGrids(size, threshold)

    local navLand = NavGrids['Land']                --[[@as NavGrid]]
    local navWater = NavGrids['Water']              --[[@as NavGrid]]
    local navHover = NavGrids['Hover']              --[[@as NavGrid]]
    local navAmphibious = NavGrids['Amphibious']    --[[@as NavGrid]]
    local navAir = NavGrids['Air']                  --[[@as NavGrid]]

    local tCache, dCache, daCache, pxCache, pzCache, pCache, bCache, rCache = InitCaches(size)

    for z = 0, LabelCompressionTreesPerAxis - 1 do
        local blockZ = z * size
        for x = 0, LabelCompressionTreesPerAxis - 1 do
            local blockX = x * size
            local labelTreeLand = CompressedLabelTree('Land', blockX, blockZ, size)
            local labelTreeNaval = CompressedLabelTree('Water', blockX, blockZ, size)
            local labelTreeHover = CompressedLabelTree('Hover', blockX, blockZ, size)
            local labelTreeAmph = CompressedLabelTree('Amphibious', blockX, blockZ, size)
            local labelTreeAir = CompressedLabelTree('Air', blockX, blockZ, size)

            -- pre-computing the caches is irrelevant layer-wise, so we just pick the Land layer
            PopulateCaches(labelTreeLand, tCache, dCache,  daCache, pxCache, pzCache,  pCache, bCache)

            ComputeLandPathingMatrix(labelTreeLand,        daCache,                    pCache, bCache, rCache)
            labelTreeLand:Compress(rCache, threshold)
            navLand:AddTree(z, x, labelTreeLand)

            ComputeNavalPathingMatrix(labelTreeNaval,      daCache,                    pCache, bCache, rCache)
            labelTreeNaval:Compress(rCache, 2 * threshold)
            navWater:AddTree(z, x, labelTreeNaval)

            ComputeHoverPathingMatrix(labelTreeHover,      daCache,                    pCache, bCache, rCache)
            labelTreeHover:Compress(rCache, threshold)
            navHover:AddTree(z, x, labelTreeHover)

            ComputeAmphPathingMatrix(labelTreeAmph,        daCache,                    pCache, bCache, rCache)
            labelTreeAmph:Compress(rCache, threshold)
            navAmphibious:AddTree(z, x, labelTreeAmph)

            ComputeAirPathingMatrix(labelTreeAir,          daCache,                    pCache, bCache, rCache)
            labelTreeAir:Compress(rCache, threshold)
            navAir:AddTree(z, x, labelTreeAir)
        end
    end
end

--- Generates graphs that we can traverse, based on the compression grids
local function GenerateGraphs()
    local navLand = NavGrids['Land']                --[[@as NavGrid]]
    local navWater = NavGrids['Water']              --[[@as NavGrid]]
    local navHover = NavGrids['Hover']              --[[@as NavGrid]]
    local navAmphibious = NavGrids['Amphibious']    --[[@as NavGrid]]
    local navAir = NavGrids['Air']                  --[[@as NavGrid]]

    navLand:GenerateNeighbors()
    navWater:GenerateNeighbors()
    navHover:GenerateNeighbors()
    navAmphibious:GenerateNeighbors()
    navAir:GenerateNeighbors()

    navLand:GenerateLabels()
    navWater:GenerateLabels()
    navAmphibious:GenerateLabels()
    navHover:GenerateLabels()
    navAir:GenerateLabels()

    navLand:Precompute()
    navWater:Precompute()
    navHover:Precompute()
    navAmphibious:Precompute()
    navAir:Precompute()
end

--- Culls generated labels that are too small and have no meaning
local function GenerateCullLabels()
    local navLabels = NavLabels

    local culledLabels = 0

    ---@type CompressedLabelTreeLeaf[]
    local stack = { }
    local count = 1
    for k, _ in navLabels do
        local metadata = navLabels[k]
        if metadata.Area < 0.2 and metadata.NumberOfExtractors == 0 and metadata.NumberOfHydrocarbons == 0 then
            culledLabels = culledLabels + 1

            -- cull node
            local node = metadata.Node
            node.label = -1

            -- find all neighbors and cull those too
            count = 1
            stack[1] = metadata.Node
            while count > 0 do
                node = stack[count]
                count = count - 1
                for k, neighbor in node.neighbors do
                    if neighbor.label > 0 then
                        neighbor.label = -1
                        count = count + 1
                        stack[count] = neighbor
                    end
                end
            end
        end
    end

    Statistics.CulledLabels = culledLabels
    SPEW(string.format("NavGenerator - culled %d labels", culledLabels))
end

--- Generates metadata for markers for quick access
local function GenerateMarkerMetadata()
    local navLabels = NavLabels

    local grids = {
        Land = NavGrids['Land'],
        Amphibious = NavGrids['Amphibious']
    }
    
    local extractors, en = import("/lua/sim/markerutilities.lua").GetMarkersByType('Mass')
    for k = 1, en do
        local extractor = extractors[k]
        for layer, grid in grids do
            local label = grid:FindLeaf(extractor.position).label

            if label > 0 then
                navLabels[label].NumberOfExtractors = navLabels[label].NumberOfExtractors + 1
                table.insert(navLabels[label].ExtractorMarkers, extractor)

                if not extractor.NavLabel then
                    extractor.NavLabel = label
                    extractor.NavLayer = layer
                end
            end
        end
    end

    local hydrocarbons, hn = import("/lua/sim/markerutilities.lua").GetMarkersByType('Hydrocarbon')
    for k = 1, hn do
        local hydro = hydrocarbons[k]
        for layer, grid in grids do
            local label = grid:FindLeaf(hydro.position).label

            if label > 0 then
                navLabels[label].NumberOfExtractors = navLabels[label].NumberOfExtractors + 1
                table.insert(navLabels[label].ExtractorMarkers, hydro)

                if not hydro.NavLabel then
                    hydro.NavLabel = label
                    hydro.NavLayer = layer
                end
            end
        end
    end
end

--- Generates a navigational mesh based on the heightmap
function Generate()

    -- reset state
    NavGrids = { }
    NavLabels = { }
    LabelIdentifier = 0

    local start = GetSystemTimeSecondsOnlyForProfileUse()
    print(string.format(" -- Navigational mesh generator -- "))

    NavLayerData = Shared.CreateEmptyNavLayerData()

    ---@type number
    local MapSize = ScenarioInfo.size[1]

    ---@type number
    local CompressionTreeSize = MapSize / LabelCompressionTreesPerAxis

    ---@type number
    local compressionThreshold = 2

    if MapSize > 1024 then
        compressionThreshold = 4
    end

    NavGrids['Land'] = NavGrid('Land', CompressionTreeSize)
    NavGrids['Water'] = NavGrid('Water', CompressionTreeSize)
    NavGrids['Hover'] = NavGrid('Hover', CompressionTreeSize)
    NavGrids['Amphibious'] = NavGrid('Amphibious', CompressionTreeSize)
    NavGrids['Air'] = NavGrid('Air', CompressionTreeSize)

    GenerateCompressionGrids(CompressionTreeSize, compressionThreshold)
    print(string.format("generated compression trees: %f", GetSystemTimeSecondsOnlyForProfileUse() - start))

    GenerateGraphs()
    print(string.format("generated neighbors and labels: %f", GetSystemTimeSecondsOnlyForProfileUse() - start))
    
    GenerateMarkerMetadata()
    print(string.format("generated marker metadata: %f", GetSystemTimeSecondsOnlyForProfileUse() - start))

    GenerateCullLabels()
    print(string.format("cleaning up generated data: %f", GetSystemTimeSecondsOnlyForProfileUse() - start))

    -- allows debugging tools to function
    import("/lua/sim/navdebug.lua")

    -- pass data to sync
    Sync.NavLayerData = NavLayerData

    SPEW(string.format("Generated navigational mesh in %f seconds", GetSystemTimeSecondsOnlyForProfileUse() - start))
    Generated = true
end
