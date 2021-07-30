--[[
    R*Tree 1.0

    IMPORTANT! READ:
    This Lua module is a implementation of the data structure R*Tree.
    This structure is a variant of the R-Tree, originally proposed by A. Guttman.

    This implementation works with 2D AABB (Axis-Aligned Bounding-Boxes), and a
    helper module should be distributed togheter with this module to complete it's
    functionalities.
    In practice, with 2D AABB, we mean a Lua table of the kind:

        local example_aabb = {
            x = 0,
            y = 15,
            w = 30,
            h = 25,
        }

    were x and y are the position coordinates, and w and h are width and height of the box.
    The module can be required in your main script to create aabbs to perform area searches,
    and to generate quickly the content of the tree. In any case creating these boxes like 
    in the above example is enough.

    For more detailed informations, this is the official repository on GitHub:
        https://github.com/rick4stley/rstar

    References:
        [The original paper, by A. Guttman] http://www-db.deis.unibo.it/courses/SI-LS/papers/Gut84.pdf
        [R*Tree paper, by N. Beckmann, H. Kriegel, R. Schneider, B. Seeger] https://infolab.usc.edu/csci599/Fall2001/paper/rstar-tree.pdf

    The MIT license

    Copyright (c) 2021 Daniele Gurizzan

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

local aabb = require 'aabb'
local CAN_DRAW = love ~= nil
if CAN_DRAW then
    if love.getVersion == nil then
        CAN_DRAW = love._version_minor ~= nil and love._version_minor >= 7
    end
end

local rsnode = {}
rsnode.__index = rsnode

function rsnode.new(tree, is_leaf, child1, child2) -- creates a r* tree node instance
    -- this class is private, and is used to implement nodes
    tree.bid_counter = tree.bid_counter + 1
    local result = {
        id = tree.bid_counter,
        is_leaf = is_leaf,
        children = {},
        box = aabb.new(),
        parent = nil,
    }
    if child1 then
        result.children[1] = child1
        child1.parent = result
        if child2 then
            result.children[2] = child2
            child2.parent = result
        end
        if is_leaf then
            for i = 1, #result.children do
                tree.entries[result.children[i].id] = result
            end
        end
        aabb.set(result.box, aabb.mbr(result.children))
    end
    setmetatable(result, rsnode)
    return result
end

function rsnode:isOverfilled(tree)
    return #self.children > tree.M
end

function rsnode:isUnderfilled(tree)
    return #self.children < tree.m
end

function rsnode:add(tree, child)
    table.insert(self.children, child)

    if #self.children == 1 then
        aabb.set(self.box, aabb.viewport(child.box))
    else
        aabb.set(self.box, aabb.commonViewport(self.box, child.box))
    end
    if not self.is_leaf then
        child.parent = self 
    else
        tree.entries[child.id] = self
    end
end

function rsnode:remove(tree, entry_id) -- removes a entry (only for leaves)
    if self.is_leaf then
        local i, found = 0, false
        while (not found) and i <= #self.children do
            i = i + 1
            found = self.children[i].id == entry_id
        end
        if found then 
            local entry = table.remove(self.children, i)
            tree.entries[entry.id] = nil
            if #self.children > 0 then
                aabb.set(self.box, aabb.mbr(self.children))
            end
            return entry.box
        end
    end
end

function rsnode:removeNode(node_id) -- removes a child (only for branches)
    if not self.is_leaf then
        local i, found = 0, false
        while (not found) and i <= #self.children do
            i = i + 1
            found = self.children[i].id == node_id
        end
        if found then 
            local node = table.remove(self.children, i)
            aabb.set(self.box, aabb.mbr(self.children))
            return node
        end
    end
end

function rsnode:destroy() -- releases all references (not needed really buuuuuut)
    while #self.children > 0 do
        table.remove(self.children)
    end
    self.children = nil
    self.box = nil
end

local rstar = {
    _VERSION = '1.0',
}
rstar.__index = rstar

function rstar.new(settings) -- creates a new instance of r* tree
    local result = {
        -- default parameters, based on best-values showed in the paper
        -- note: you should provide this on creation, and never set them manually
        m = 8, -- minimum number of chilren per node (40% of M) [2;M/2]
        M = 20, -- maximum number of children per node
        reinsert_p = 6, -- how many nodes to reinsert on overflow (30% of M) [1;M)
        reinsert_method = 1, -- 1) distance-to-center 2) distance-to-center of mass (see distanceSort)
        choice_p = 20, -- how many nodes to check in chooseLeaf, used to lower cpu time (proposed: 32) [1;M]
        -- "private" aka "don't touch this please" variables
        id_counter = -1, -- used to assign ids to entries (for deletion)
        bid_counter = -1, -- used to assign ids to nodes
        height = 0, -- stores the current tree height
        root = nil,
        entries = {}, -- contains for each entry, a reference to its corresponding leaf node
        overflow_mem = {}, -- auxiliary table, used to store level overflow (yes/no) during insertion
    }

    if settings then -- read settings
        if type(settings.M) == 'number' then
            result.M = math.max(math.floor(settings.M), 4)
        end

        if type(settings.m) == 'number' then
            result.m = math.min(math.max(math.floor(settings.m), 2), math.floor(result.M * 0.5))
        end

        if type(settings.reinsert_p) == 'number' then
            local f = math.floor(settings.reinsert_p)
            if f > 0 and f < result.M then
                result.reinsert_p = f
            end
        end

        if settings.reinsert_method == 'weighted' then
            result.reinsert_method = 2
        end

        if type(settings.choice_p) == 'number' then
            result.choice_p = math.min(math.floor(settings.choice_p), result.M)
        else
            result.choice_p = result.M
        end
    end

    setmetatable(result, rstar)
    return result
end

local insert -- defined below, this statement must be here because insert, overflow and reinsert have a cyclic reference

local function sortD(a, b)
    return a[2] > b[2]
end

local distanceSort = { -- two methods that can be used to determine the order of reisertion of a node's children
    function(node) -- good for more uniform/randomized data, this is the original variant
        -- puts node's children in d, coupling them with their center's distance from node's center point
        -- then using sortD, sorts d by distance value in decreasing order
        local d = {}
        local mx, my = aabb.center(node.box)
        local children = node.children
    
        while #children > 0 do -- build up of d
            local r = table.remove(children)
            local cx, cy = aabb.center(r.box)
            local dx, dy = cx - mx, cy - my
            table.insert(d, {r, math.sqrt(dx*dx + dy*dy)})
        end
    
        table.sort(d, sortD) -- sort d
        return d
    end,
    function(node) -- good for more spotty/clustered data
        -- this is a variant of the function above, accomplishes the same result.
        -- the difference is that it first calculates the medium point between node's children
        -- and uses that as center
        local d = {}
        local sx, sy = 0, 0
        local children = node.children

        for i = 1, #children do -- medium point (center of mass) calculation
            local cx, cy = aabb.center(children[i].box)
            sx = sx + cx
            sy = sy + cy
        end
        local mx, my = sx / #children, sy / #children
    
        while #children > 0 do
            local r = table.remove(children)
            local cx, cy = aabb.center(r.box)
            local dx, dy = cx - mx, cy - my
            table.insert(d, {r, math.sqrt(dx*dx + dy*dy)})
        end
    
        table.sort(d, sortD)
        return d
    end,
}

local function reinsert(tree, node, level) -- reinserts reinsert_p children from node
    -- puts node's children in a ordered table, and removes the first reinsert_p children
    -- going in increasing order of distance value
    local sorted = distanceSort[tree.reinsert_method](node)
    local j = 0
    local reinserting = {}

    for i = 0, tree.reinsert_p-1 do -- separate candidates
        table.insert(reinserting, table.remove(sorted, tree.reinsert_p - i)[1])
    end

    while #sorted > 0 do -- put back remaining children
        node:add(tree, table.remove(sorted)[1])
    end

    while #reinserting > 0 do -- reinsert candidates
        insert(tree, table.remove(reinserting, 1), level)
    end
end

local axisSort = { -- helper functions used to sort items by their coordinates
    {
        function(a, b) return a.box.x < b.box.x end,
        function(a, b) return a.box.y < b.box.y end,
    },
    {
        function(a, b) return a.box.x + a.box.w < b.box.x + b.box.w end,
        function(a, b) return a.box.y + a.box.h < b.box.y + b.box.h end,
    },
}

local function determineSplit(tree, node) -- split's helper function
    -- determines the best way to split node, going through M - 2*m + 2 distributions in two groups.
    -- let b1 be the bounding box of the first group, and b2 bounding box of the second:
    -- if the sum of b1's and b2's perimeter is minimum, this is a better distribution;
    -- else if it is the same of the current minimum, choose the one with least overlap between b1 and b2.
    -- if the values are equal (very rare), choose the distribution which has less overall area.
    -- this is done for each axis, and using top-left corner sorting first and bottom-right corner then
    -- returns the axis (1 = x, 2 = y), the way used to sort (1 = top-left, 2 = bottom-right), how many items go in the first group
    local auxbox = aabb.new()
    local aux = {}
    local dist = tree.M - 2*tree.m + 2
    local s = {0, 0}
    local min_overlap, min_area
    local chosen, chosen_dist
    local dists = {{},{}}
    local children = node.children -- to waste less memory, this algorithm acts directly on the node
    -- {x, y} <=> {1, 2}
    for i = 1, 2 do -- axis loop
        local sw = {0, 0}

        for w = 1, 2 do -- sorting method loop

            table.sort(children, axisSort[i][w])

            for k = 1, dist do -- distributions loop
                if k == 1 then -- put at least m items in the first group
                    for j = 1, tree.m do
                        table.insert(aux, table.remove(children, 1))
                    end
                else
                    table.insert(aux, table.remove(children, 1))
                end

                aabb.set(node.box, aabb.mbr(aux)) -- adjust node's box
                aabb.set(auxbox, aabb.mbr(children)) -- adjust auxbox (second group bb)
                local first_p = aabb.perimeter(node.box)
                local second_p = aabb.perimeter(auxbox)
                -- for distribution choice
                local overlap = aabb.overlapArea(node.box, auxbox)
                local area = aabb.area(node.box) + aabb.area(auxbox)

                if k == 1 or overlap < min_overlap then -- compare overlap values and area values (on first iteration this is not done)
                    min_overlap = overlap
                    if k > 1 then
                        min_area = (min_area == nil and area) or (area < min_area and area or min_area)
                    end
                    dists[i][w] = (tree.m-1)+k -- store the new distribution
                elseif overlap == min_overlap and min_area and area < min_area then
                    min_area = area
                    dists[i][w] = (tree.m-1)+k
                end

                sw[w] = sw[w] + first_p + second_p -- store the sum of perimeters
            end

            while #aux > 0 do table.insert(children, table.remove(aux)) end -- put back removed children
        end

        s[i] = sw[1] < sw[2] and sw[1] or sw[2] -- choose lower sum
        chosen_dist = sw[1] < sw[2] and 1 or 2 -- choose sort method
    end

    chosen = (s[1] < s[2] and 1 or 2) -- choose the axis

    return chosen, chosen_dist, dists[chosen][chosen_dist]
end

local function split(tree, node) -- splits a node in two
    local axis, value, distribution = determineSplit(tree, node)
    local theotherhalf = rsnode.new(tree, node.is_leaf)
    local children = node.children

    table.sort(children, axisSort[axis][value]) -- sort again with the best settings

    while #children > distribution do -- put second group in the other half
        theotherhalf:add(tree, table.remove(children))
    end

    aabb.set(node.box, aabb.mbr(children)) -- adjust node's box

    return theotherhalf
end

local function overflow(tree, node, level) -- takes care of node overflow
    -- implements one of the core features of r* tree: forced reinsertion
    -- if node is not the root (level == height) or the level already overflowed split this node;
    -- else call reinsert on the node and set the overflow of the current level to true ("it happened")
    -- note: level is stored as the distance from leaves (leaf level is 0)
    if level == tree.height or tree.overflow_mem[level] then
        return split(tree, node)
    else
        tree.overflow_mem[level] = true
        reinsert(tree, node, level)
    end
end

local function chooseBranch(node, inserting, auxbox) -- choose the best branch node to put inserting
    -- chooses node's child which box would enlarge the least, if it included inserting.
    -- in case of same enlargement values, choose the child with smaller area
    -- return the chosen child's position in node.children
    local min_enlargement
    local chosen
    local children = node.children

    for i = 1, #children do
        aabb.set(auxbox, aabb.commonViewport(children[i].box, inserting.box)) -- auxbox would be the resulting box if children[i] included inserting
        local enlargement = aabb.area(auxbox) - aabb.area(children[i].box)

        if i == 1 or enlargement < min_enlargement then
            min_enlargement = enlargement
            chosen = i
        elseif enlargement == min_enlargement and aabb.area(children[chosen].box) < aabb.area(children[i].box) then
            chosen = i
        end
    end

    return chosen
end

local function sortA(a, b) -- again, helper function
    return a[2] < b[2]
end

local function chooseLeaf(p, node, inserting, auxbox) -- choose the best leaf node to put inserting
    -- compared to chooseBranch it's a little more complex:
    -- sorts node's leaves by increasing area englargement, using the auxiliary table a;
    -- then for the first p leaves (or all when p > #children), calculates how much overlap with other leaves would gain if choosen
    -- for insertion, if there's a match on said value wins who arrived first.
    -- this would be a quadratic cost algorithm, but with p it can be sped up in exchange of accuracy.
    -- note: in the paper 32 is the raccomended value for p.
    -- return the chosen leaf's position in node.children
    local a = {}
    local children = node.children

    for i = 1, #children do -- enlargement calculation
        aabb.set(auxbox, aabb.commonViewport(children[i].box, inserting.box))
        local enlargement = aabb.area(auxbox) - aabb.area(children[i].box)
        table.insert(a, {i, enlargement})
    end

    table.sort(a, sortA)

    local min_overlap
    local chosen
    local scan = math.min(p, #children)
    for i = 1, scan do -- overlap enlargement calculation
        local pos = a[i][1]
        local current = children[pos]
        local overlap_sum = 0

        aabb.set(auxbox, aabb.commonViewport(current.box, inserting.box))
        for j = 1, #children do
            if j ~= pos then -- don't check leaves against themselves
                overlap_sum = overlap_sum + (aabb.overlapArea(auxbox, children[j].box) - aabb.overlapArea(current.box, children[j].box))
            end
        end

        if i == 1 or overlap_sum < min_overlap then
            min_overlap = overlap_sum
            chosen = pos
        end
    end

    return chosen
end

local function chooseSubtree(tree, node, level) -- choose the best location for insertion
    -- uses helper functions chooseLeaf and chooseBranch to descend the tree from
    -- root to level, choosing the best path
    -- returns the node that will host node argument
    local n = tree.root
    local auxbox = aabb.new()

    for i = 1, tree.height - level - 1 do -- stop at level - 1
        if n.children[1].is_leaf then
            n = n.children[chooseLeaf(tree.choice_p, n, node, auxbox)]
        else
            n = n.children[chooseBranch(n, node, auxbox)]
        end
    end

    return n
end

insert = function(tree, node, level) -- inserts any kind of item in the tree
    local container = chooseSubtree(tree, node, level)
    container:add(tree, node) -- put node in the corresponding parent

    while container ~= nil do -- ascend the tree, propagate overflows or simply adjust nodes on the path to root
        local new_half = nil
        if container:isOverfilled(tree) then
            new_half = overflow(tree, container, level)
        end

        if new_half ~= nil then
            if container.parent == nil then -- when root splits, create a new one and increment height
                tree.root = rsnode.new(tree, false, container, new_half)
                tree.height = tree.height + 1
                container = tree.root
            else
                container.parent:add(tree, new_half)
            end
        elseif container.parent then -- adjust parent if no split occurred
            aabb.set(container.parent.box, aabb.mbr(container.parent.children))
        end

        container = container.parent -- ascend
        level = level + 1 -- ascend
    end
end

function rstar:insert(item) -- insertion method
    -- create a new entry table {id, box}, and if the tree is empty create root;
    -- else call insert with this tree, the new entry and leaf level.
    -- lastly clear overflow_mem and return the identifier to the entry
    self.id_counter = self.id_counter + 1
    local new_entry = {id = self.id_counter, box = item}

    if self.height == 0 then
        self.root = rsnode.new(self, true, new_entry)
        self.height = 1
    else
        insert(self, new_entry, 0)
        for i = 0, self.height do
            self.overflow_mem[i] = nil
        end
    end

    return self.id_counter
end

function rstar:delete(id) -- deletion method
    -- deletes a specific entry from the tree, if the leaf where it was is under-filled,
    -- the node must be destroyed and remaining entries inserted again.
    -- this can cause a propagation upwards, that could eventually lead to tree height shrinking.
    -- in rsnode:add() the node registered the entry [id] in tree.entries:
    -- to check for existance/obtain entry's parent just access entries table.
    -- returns the removed entry's box
    if self.entries[id] == nil then return end

    local n = self.entries[id]
    local removed = n.box -- get a second reference to return n
    self.entries[id]:remove(self, id) -- remove n from its parent
    local q = {} -- store remvoed items
    local lc = 0 -- level counter

    while n.parent ~= nil do -- ascend the tree, coupling removed nodes with their level (stop before root)
        local p = n.parent

        if n:isUnderfilled(self) then
            local nr = p:removeNode(n.id)
            table.insert(q, {lc, nr})
        else
            aabb.set(p.box, aabb.mbr(p.children))
        end

        lc = lc + 1
        n = p
    end

    while #q > 0 do -- proceed to insert again orphaned nodes (under-filled node's children)
        local level, node = unpack(table.remove(q)) -- start from higher nodes (closer to root)

        while #node.children > 0 do
            insert(self, table.remove(node.children), level)
        end

        node:destroy() -- destroy the under-filled node
    end

    if (not self.root.is_leaf) and #self.root.children == 1 then
        -- if root is a branch, and remained with only 1 child, set this child to be the root and decrement height
        local old = self.root
        self.root = old.children[1]
        self.root.parent = nil
        old:destroy()
        self.height = self.height - 1
    end

    if self.root.is_leaf and #self.root.children == 0 then
        -- if root is a lead and remained with no children, set the tree to be empty again
        self.root:destroy()
        self.root = nil
        self.height = 0
    end

    return removed
end

function rstar:search(s, result) -- area search method
    -- collects all entries which intersect with s, and puts them in the table result
    if self.root then
        local traverse = { self.root }

        while #traverse > 0 do
            local first = table.remove(traverse, 1)

            for i = 1, #first.children do
                if aabb.intersects(s, first.children[i].box) then
                    table.insert(first.is_leaf and result or traverse, first.children[i])
                end
            end
        end
    end
end

function rstar:select(p, result) -- selection method
    -- collects all entries which contain the point p, and puts them in result
    if self.root then
        local traverse = { self.root }
        local px, py = p.x, p.y

        while #traverse > 0 do
            local first = table.remove(traverse, 1)

            for i = 1, #first.children do
                if aabb.inside(first.children[i].box, px, py) then
                    table.insert(first.is_leaf and result or traverse, first.children[i])
                end
            end
        end
    end
end

local lc = {
    {1,0,0,0.5},
    {0,1,1,0.5},
    {1,1,0,0.5},
    {1,0,1,0.5},
    {0,0,1,0.5}
}

function rstar:draw(only_boxes) -- debug method, draws a tree with a max height of 5
    -- visits the tree by level drawing the whole structure with different colors.
    -- allows to draw just boxes
    -- this method is meant to be used in LOVE2D framework
    if CAN_DRAW and self.root and self.height <= 5 then
        local lg = love.graphics
        local traverse = { self.root }
        local thislevel = 1
        local nextlevel = 1
        local level = 0
        lg.setLineStyle('rough')

        while #traverse > 0 do
            local first = table.remove(traverse, 1)
            thislevel = thislevel - 1

            if thislevel == 0 then
                level = level + 1
                thislevel = nextlevel
                nextlevel = 0
            end

            if only_boxes == false then
                lg.setColor(lc[level])
                lg.rectangle('line', aabb.viewport(first.box))
            end

            if first.is_leaf then
                lg.setColor(1,1,1)

                for i = 1, #first.children do
                    lg.rectangle('line', aabb.viewport(first.children[i].box))
                end
            else
                for i = 1, #first.children do
                    table.insert(traverse, first.children[i])
                end
                nextlevel = nextlevel + #first.children
            end
        end
        lg.setLineStyle('smooth')
    end
end

return rstar
