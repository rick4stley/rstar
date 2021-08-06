local aabb = require 'aabb'
local boxgen = {}

local function cuts(n) -- helper function for generate
    -- calculates how many levels of recursion are required 
    -- to split a space in n slices
    -- (in practice this function is equal to the logarithm of n in base 4)
    local sum = 1
    local cnum = 0
    while sum < n do
        sum = sum * 4
        cnum = cnum + 1
    end
    return cnum
end

function boxgen.generateSlices(n, radius) -- generates n non-overlapping random rectangles
    -- this function takes the space between -radius and +radius in both axis,
    -- and splits this square area recursively using 2 or 1 random cuts into cells.
    -- the end result is a table containing n rectangles which can't overlap.
    -- note: this function is experimental, there are uncovered cases like "what if I can't split a cell?".
    --       use at your own risk!
    local cnum = cuts(n)
    local tree = aabb.new(-radius, -radius, radius*2, radius*2)
    local traverse = { tree }
    local clevel, nextlevel = 1, 0
    local min_size = 40 -- for my box's sprite
    local lost_splits = 0
    local rects = 1

    while rects < n do
        local first = table.remove(traverse, 1)

        clevel = clevel - 1
        nextlevel = nextlevel + 4

        if clevel == 0 then
            clevel = nextlevel
            nextlevel = 0
            cnum = cnum - 1
        end

        local ahc, avc = math.floor(first.w / min_size), math.floor(first.h / min_size)

        if ahc >= 2 and avc >= 2 then
            local cutw, cuth = min_size * math.random(math.ceil(ahc * 0.4), math.floor(ahc * 0.6)), min_size * math.random(math.ceil(avc * 0.4), math.floor(avc * 0.6))
            
            local c = n-rects >= 4 and 4 or (n-rects+1)

            if c > 2 then
                for i = 1, c do
                    table.insert(traverse, aabb.new(
                        (i == 1 or i == 3) and first.x or (first.x + cutw), 
                        (i < 3) and first.y or (first.y + cuth),
                        (i == 1 or i == 3) and cutw or (first.w - cutw),
                        (i < 3) and cuth or (first.h - cuth)
                    ))
                end
            else
                for i = 1, c do
                    table.insert(traverse, aabb.new(
                        (i == 1) and first.x or (first.x + cutw), 
                        first.y,
                        (i == 1) and cutw or (first.w - cutw),
                        first.h
                    ))
                end  
            end
            rects = rects - 1 + c
        else
            lost_splits = lost_splits + 1
        end
    end

    --print(lost_splits)
    --print(#traverse)

    return traverse
end

return boxgen