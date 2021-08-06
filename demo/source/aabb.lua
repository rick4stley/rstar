-- This module works with Axis-Aligned Bounding-Boxes v1.0
--[[
    MIT LICENSE

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
]]--

local aabb = {}

function aabb.new(x, y, w, h)
    return {
        x = x or 0,
        y = y or 0,
        w = w or 1,
        h = h or 1,
    }
end

function aabb.mbr(group)
     -- note: this function should be edited in order to be used for general purpose
    local bx, by, bx2, by2 = aabb.viewport(group[1].box)
    bx2 = bx2 + bx
    by2 = by2 + by
    local entries = #group

    for i = 2, entries do
        local x, y, w, h = aabb.viewport(group[i].box)

        bx = (x < bx) and x or bx
        by = (y < by) and y or by
        bx2 = (x + w > bx2) and (x + w) or bx2
        by2 = (y + h > by2) and (y + h) or by2
    end

    return bx, by, (bx2 - bx), (by2 - by)
end

function aabb:position()
    return self.x, self.y
end

function aabb:size()
    return self.w, self.h
end

function aabb:viewport()
    return self.x, self.y, self.w, self.h
end

function aabb:set(x, y, w, h)
    self.x = x or self.x
    self.y = y or self.y
    self.w = w or self.w
    self.h = h or self.h
end

function aabb:copy()
    return aabb.new(aabb.viewport(self))
end

function aabb:area()
    return self.w * self.h
end

function aabb:perimeter()
    return self.w * 2 + self.h * 2
end

function aabb:commonViewport(other)
    local min, max = math.min, math.max
    local ox, oy, ow, oh = other.x, other.y, other.w, other.h
    local bx, by = min(self.x, ox), min(self.y, oy)
    local bw = max(self.x + self.w, ox + ow) - bx
    local bh = max(self.y + self.h, oy + oh) - by

    return bx, by, bw, bh
end

function aabb:commonAABB(other)
    return aabb.new(aabb.commonViewport(self, other))
end

function aabb:commonArea(other)
    local cx, cy, cw, ch = aabb.commonViewport(self, other)

    return cw * ch
end

function aabb:overlap(other)
    local ow, oh = aabb.size(other)
    local cx, cy, cw, ch = aabb.commonViewport(self, other)
    local ox = cw - (self.w + ow)
    local oy = ch - (self.h + oh)

    return ox, oy
end

function aabb:overlapArea(other)
    local ox, oy = aabb.overlap(self, other)

    return (ox < 0 and oy < 0) and ox * oy or 0
end

function aabb:center()
    return self.x + 0.5 * self.w, self.y + 0.5 * self.h
end

function aabb:intersects(other)
    local ow, oh = aabb.size(other)
    local ox, oy = aabb.overlap(self, other)
    local contains = (ox == -ow and oy == -oh) and 1 or ((ox == -self.w and oy == -self.h) and -1 or 0)

    return ox < 0 and oy < 0, contains
end

function aabb:inside(x, y)
    return x >= self.x and x < self.x + self.w and y >= self.y and y < self.y + self.h
end

local function distance(x, y, z, w)
    local dx, dy = z - x, w - y
    if dx == 0 or dy == 0 then 
        return math.max(math.abs(dx), math.abs(dy))
    else
        return math.sqrt(dx * dx + dy * dy)
    end
end

local function clamp(value, min, max)
    return value < max and (value > min and value or min) or max
end

function aabb:inrange(cx, cy, cr)
    local clx, cly = clamp(cx, self.x, self.x + self.w), clamp(cy, self.y, self.y + self.h)

    local d = distance(cx, cy, clx, cly)

    return d <= cr
end


--[[ How to draw the overlap region
love.graphics.rectangle('line',a2:viewport())
love.graphics.rectangle('line',a1:viewport())

local ox, oy = a1:overlap(a2)

if ox < 0 and oy < 0 then
    local rx = a2.x > a1.x and a2.x or a1.x
    local ry = a2.y > a1.y and a2.y or a1.y

    love.graphics.setColor(1,0.2,0.2,0.5)
    if (-ox == a2.w and -oy == a2.h) or (-ox == a1.w and -oy == a1.h) then
        love.graphics.setColor(0.2,1,0.2,0.5)
    end
    love.graphics.rectangle('fill', rx, ry, -ox, -oy)
end
]]

return aabb