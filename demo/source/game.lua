local aabb = require 'aabb'
local rstar = require 'rstar'
local boxgen = require 'generate'
local g = love.graphics
local pi = math.pi
local lv

if love.getVersion ~= nil then -- for love's version compatibility
    local maj, min = love.getVersion()
    lv = maj > 0 and maj or min
else
    lv = love._version_minor
end
-- color components are 0-1 in love 11 but 0-255 in 0.10 and below
local color_mode = lv < 11 and 1 or 1/256

local game = { -- game's module object
    current_scene = 'menu', -- the game is organised in scenes
    scene = {},
    sprite = {}, -- sprites used by the game
    boxes = {}, -- list of box objects
    font = {}, -- fonts used by the game
    box_patches = {}, -- quads to draw boxes of any size with the same asset
    zoom = 1.5,
    visible_boxes = {}, -- boxes which must be draw on screen (see updateVisibleBoxes:95)
}

local function spawnBoxes(n, world_radius) -- spawn n random boxes, within the radius given
    local nboxes = #game.boxes -- wipe away the old stuff
    for i = 1, nboxes do
        local b = table.remove(game.boxes)
        game.tree:delete(b.id)
    end

    local slices = boxgen.generateSlices(n, world_radius) -- create random rectangles

    for i = 1, #slices do -- further randomization and creation of boxes
        local s = slices[i]
        local w, h = math.max(32, math.random(s.w - 20)), math.max(32, math.random(s.h - 20))
        local x, y = math.random(s.w - w) - 1, math.random(s.h - h) - 1
        s.x = s.x + x 
        s.y = s.y + y 
        s.w = w 
        s.h = h
        
        table.insert(game.boxes, { id = game.tree:insert(s), box = s })
    end
end

local function drawBox(box) -- draws a box object
    local iw, ih = box.w - 32, box.h - 32 -- asset specific

    if iw > 0 and ih > 0 then -- draw fill
        g.draw(game.sprite.box, game.box_patches[5], box.x + 16, box.y + 16, 0, iw, ih)
    end

    if iw > 0 then -- draw top and bottom edges
        g.draw(game.sprite.box, game.box_patches[2], box.x + 16, box.y, 0, iw, 1)
        g.draw(game.sprite.box, game.box_patches[8], box.x + 16, box.y + ih + 16, 0, iw, 1)
    end

    if ih > 0 then -- draw left and right edges
        g.draw(game.sprite.box, game.box_patches[4], box.x, box.y + 16, 0, 1, ih)
        g.draw(game.sprite.box, game.box_patches[6], box.x + iw + 16, box.y + 16, 0, 1, ih)
    end

    -- draw corners
    g.draw(game.sprite.box, game.box_patches[1], box.x, box.y)
    g.draw(game.sprite.box, game.box_patches[3], box.x + iw + 16, box.y)
    g.draw(game.sprite.box, game.box_patches[7], box.x, box.y + ih + 16)
    g.draw(game.sprite.box, game.box_patches[9], box.x + iw + 16, box.y + ih + 16)
end

local function findBox(id) -- finds a box in game.boxes using its id
    local p, found = 0, false

    for i = 1, #game.boxes do
        found = game.boxes[i].id == id
        if found then 
            p = i
            break
        end
    end

    return found, p
end

local function deleteBox(id) -- delete a box from game.boxes and game.tree
    local found, pos = findBox(id)
    if found then
        table.remove(game.boxes, pos)
        game.tree:delete(id)
    end
end

local function updateVisibleBoxes() -- queries the tree to get the visible boxes
    local nb = #game.visible_boxes
    for i = 1, nb do
        table.remove(game.visible_boxes)
    end
    -- use the screen to filter boxes, since the game uses camera transformations coordinates are quickly converted
    local sx, sy, sw, sh = game.player.x - 400 / game.zoom, game.player.y - 280 / game.zoom, 800 / game.zoom, 560 / game.zoom
    -- note: rstar:range and rstar:search are altered to return the number of intersections they performed,
    -- normally they would not return any value
    game.draw_visited_avg = 0.5 * (game.draw_visited_avg + game.tree:search(aabb.new(sx, sy, sw, sh), game.visible_boxes))
end

local function clamp(value, min, max) -- clamping function
    return value < max and (value > min and value or min) or max
end

local function getCollisionResponse() -- collision detection and resolution between the tank and boxes
    local p = game.player
    local collisions = {}
    -- fill the collisions table and update the average intersections
    -- note: see updateVisibleBoxes
    game.collision_visited_avg = 0.5 * (game.collision_visited_avg + game.tree:range(p.hitbox, collisions))

    game.collision_check_n = #collisions -- update info on screen

     -- loop through collisions to push the tank away from collided boxes
    for i = 1, #collisions do
        -- this is a enhanced version of aabb.inrange and is known as clapming method
        local curr = collisions[i].box
        local clx, cly = clamp(p.hitbox.x, curr.x, curr.x + curr.w), clamp(p.hitbox.y, curr.y, curr.y + curr.h)
        local dx, dy = clx - p.hitbox.x, cly - p.hitbox.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < p.hitbox.r then
            local displacement = p.hitbox.r - d
            local dvx, dvy = dx / d, dy / d

            p.hitbox.x = p.hitbox.x + (-dvx) * displacement
            p.hitbox.y = p.hitbox.y + (-dvy) * displacement
        end
    end
end

local function lineVSline(x1, y1, x2, y2, x3, y3, x4, y4) -- segment intersection
    -- checks if the two segments {(x1,y1);(x2,y2)} and {(x3,y3);(x4,y4)} intersect
    -- returns if the intersection exists and eventually the coordinates
    local tn = (x1 - x3)*(y3 - y4) - (y1 - y3)*(x3 - x4)
    local un = (x2 - x1)*(y1 - y3) - (y2 - y1)*(x1 - x3)
    local d = (x1 - x2)*(y3 - y4) - (y1 - y2)*(x3 - x4)

    local tc = tn == 0 or ((tn > 0 and d > 0 and tn <= d) or (tn < 0 and d < 0 and tn >= d))
    if not tc then return false end
    local uc = un == 0 or ((un > 0 and d > 0 and un <= d) or (un < 0 and d < 0 and un >= d))
    if not uc then return false end

    local u, t = un / d, tn / d

    if t >= 0 and t <= 1 then
        return true, x1 + t*(x2 - x1), y1 + t*(y2 - y1)
    else
        return true, x3 + u*(x4 - x3), y3 + u*(y4 - y3)
    end
end

local function updateTargetMarker() -- uses raycasting to put a little target on the aimed box
    local aim_area = { x = game.player.x, y = game.player.y, r = game.player.aim_range }
    local inrange = {}
    game.tree:range(aim_area, inrange)
    local rx1, ry1, rx2, ry2 -- aim ray from the tank
    rx1 = game.player.x
    ry1 = game.player.y
    rx2 = game.player.x + math.cos(game.player.r) * game.player.aim_range
    ry2 = game.player.y + math.sin(game.player.r) * game.player.aim_range
    local px, py -- where to put the target
    local md -- minimum distance
    local first = true

    game.raycasting_check_n = #inrange -- update on screen info

    for i = 1, #inrange do -- loop through boxes in aim range
        local box = inrange[i].box
        for j = 1, 4 do -- for each edge of the box test intersection with the aim ray
            local ex1, ey1, ex2, ey2 
            ex1 = (j ~= 2) and box.x or box.x + box.w
            ey1 = (j ~= 3) and box.y or box.y + box.h
            ex2 = (j == 2 or j == 4) and ex1 or box.x + box.w
            ey2 = (j == 1 or j == 3) and ey1 or box.y + box.h
            local intersect, ix, iy = lineVSline(rx1, ry1, rx2, ry2, ex1, ey1, ex2, ey2)

            if intersect then
                local dx, dy = ix - rx1, iy - ry1
                local d = math.sqrt(dx * dx + dy * dy)
                if first or d < md then -- choose the closest point to the tank
                    md = d
                    px = ix
                    py = iy
                    first = false
                end
            end
        end
    end

    game.target_marker.visible = px ~= nil

    if game.target_marker.visible then
        game.target_marker.x = px
        game.target_marker.y = py
    end

end

local function newGame() -- reset the current status creating a new game
    -- spawn 1000 boxes (+9 because is maximum number of them that could occupy 
    -- the spawn area of the tank, and should therefore be removed
    math.randomseed(os.time())
    spawnBoxes(1009, 2000)

    -- init the player
    game.player.x = 0
    game.player.y = 0
    game.player.r = -0.5 * pi
    game.player.hitbox.x = 0
    game.player.hitbox.y = 0
    game.player.shooting = false

    -- init the bullet
    game.bullet.vx = 0 
    game.bullet.vy = 0

    -- clear scraps
    local ns = #game.scraps
    for i = 1, ns do
        table.remove(game.scraps)
    end
    
    -- delete boxes which would collide with the player
    local rm = {}
    game.tree:range(game.player.hitbox, rm)
    local rm_num = #rm
    for i = 1, rm_num do
        local e = table.remove(rm)
        deleteBox(e.id)
    end
    -- delete extra boxes so they become 1000
    local rm_num = #game.boxes - 1000
    for i = 1, rm_num do
        local e = table.remove(game.boxes, 1)
        game.tree:delete(e.id)
    end

    -- initialize collision checking and raycasting count to 0
    game.collision_check_n = 0
    game.raycasting_check_n = 0
	
	game.collision_visited_avg = 0 -- average of intersections per collision query
    game.draw_visited_avg = 0 -- average of intersections per draw filtering query

    -- get initially visible boxes and target marker display status
    updateVisibleBoxes()
    updateTargetMarker()
    -- clear collisions
    getCollisionResponse()
end

function game.load() -- loads assets and setups the demo gameplay
    g.setDefaultFilter('nearest','nearest') -- for pixel art
    -- loading sprites
    game.sprite.tank = g.newImage('res/tank.png')
    game.sprite.bullet = g.newImage('res/bullet.png')
    game.sprite.box = g.newImage('res/box.png')
    game.sprite.target = g.newImage('res/target.png')
    game.sprite.scraps = g.newImage('res/scraps.png')
    -- loading fonts
    game.font.prompt = g.newFont(14)
    game.font.title = g.newFont(32)
    game.font.paragraph = g.newFont(16)

    g.setBackgroundColor(94*color_mode, 113*color_mode, 142*color_mode) -- nice background color

    game.tree = rstar.new() -- create the R*Tree for hitboxes
    game.player = { -- player data
        x = 0, y = 0, r = -0.5 * pi, vx = 0, vy = 0, spd = 80,
        shooting = false, hitbox = { x = 0, y = 0, r = 28 }, -- a circular hitbox
        aim_range = 150,
    }
    game.bullet = { -- bullet data
        x = 0, y = 0, vx = 0, vy = 0, spd = 200, 
        active = false, hitbox = { x = 0, y = 0, r = 3 }
    }
    game.target_marker = { -- target marker data
        x = 0, y = 0, visible = false
    }

    for i = 1, 9 do -- quads to draw boxes the game uses the 9-patches technique
        table.insert(game.box_patches, g.newQuad(
            math.mod(i-1, 3) * 16, 
            math.floor((i-1) / 3) * 16, 
            (i == 2 or i == 8 or i == 5) and 1 or 16, 
            (i == 4 or i == 6 or i == 5) and 1 or 16, 48, 48))
    end

    game.debug = true -- display or not debug graphics
    game.scraps = {} -- just fancy

    newGame() -- create a new game
end

-- game scenes
game.scene.menu = {
    draw = function()
        g.setFont(game.font.title)
        g.printf('Welcome to the official rstar demo!', 60, 50, 680, 'left')
        g.setFont(game.font.paragraph)
        g.printf('To demonstrate the use of the rstar library, I made this project which includes a little game as a example situation.'
        ..'\nWhile you move around in a tank and shoot to boxes, the game will prompt you data about the peformance of some tasks.'
        ..'\nYou can watch the tree structure evolving as you destroy boxes. Leaf nodes (yellow corners) will show you how boxes are grouped, '
        ..'and what happens when a entry is deleted.'
            
        ..'\n\nThe features tested here are:'
        ..'\n - Collision detection (bullet vs box, tank vs box)'
        ..'\n - Drawing optimization'
        ..'\n - Raycasting'
        ..'\n - Tree deletion (exploded boxes)'
        
        ..'\n\nCommands'
        ..'\nTurn with A and D, and move with W and S. When the target is locked, a icon will appear where the bullet is going to hit: press F to fire. To toggle debug graphics, press H.'
        ..'\nIt is also possible to zoom in and out with your mouse wheel, try it.'
        ..'\n\nPress any key to start the demo!'
        , 60, 110, 680, 'left')
        g.setFont(game.font.prompt)
        g.printf('made by Rick Astley', -4, 540, 800, 'right')
    end,
}
game.scene.pause = {
    draw = function()
        g.setFont(game.font.title)
        g.printf('Pause', 60, 70, 680, 'left')
        g.setFont(game.font.paragraph)
        g.printf('Press P again to go back to gameplay.'
        ..'\nIf you want to start a new game, press R.'
        ..'\nClose the window to quit.'
        ..'\n\nForgot game commands?'
        ..'\nA, D: Turn left and right'
        ..'\nW, S: Move forwards and backwards'
        ..'\nF: Fire a bullet'
        ..'\nH: Hide/Show debug graphics'
        ..'\nMouse wheel: Zoom in and out'
        , 60, 140, 680, 'left')
        g.setFont(game.font.prompt)
        g.printf('made by Rick Astley', -4, 540, 800, 'right')
    end,
}
game.scene.play = {
    update = function(dt) -- updates the whole gameplay
        local p = game.player
        p.vx = 0 -- reset player's velocity
        p.vy = 0

        -- lock the player if shooting
        if not p.shooting then
            -- get turning direction input (both keys cause the value to get equal to 0)
            local td = (love.keyboard.isDown('a') and -1 or 0) + (love.keyboard.isDown('d') and 1 or 0)
            -- get movement direction input (same as above)
            local md = (love.keyboard.isDown('s') and -1 or 0) + (love.keyboard.isDown('w') and 1 or 0)

            -- enable the player to fire a bullet if they did not move, and the target is locked
            local fire = (td == 0) and (md == 0) and love.keyboard.isDown('f') and game.target_marker.visible

            if fire then -- stop the function immediately if the player fired
                -- set the game to shooting state and initialise the bullet
                p.shooting = true
                local b = game.bullet
                b.visible = true
                b.vx = math.cos(p.r)
                b.vy = math.sin(p.r)
                b.x = p.x + b.vx * 43
                b.y = p.y + b.vy * 43
                b.hitbox.x = b.x
                b.hitbox.y = b.y
                -- hide the target marker
                game.target_marker.visible = false
                return -- not cool
            end

            -- turn the tank (if its going backwards invert the direction to keep it realistic)
            p.r = p.r + td * (md ~= 0 and md or 1) * dt*2

            -- if there's movement, calculate velocity using the angle p.r
            if md ~= 0 then
                local dx, dy = math.cos(p.r), math.sin(p.r)
                p.vx = dx * md
                p.vy = dy * md
            end
            -- update the position of the tank
            p.x = p.x + p.vx * dt * p.spd
            p.y = p.y + p.vy * dt * p.spd
            -- move the player's hitbox along
            p.hitbox.x = p.x
            p.hitbox.y = p.y

            -- test collisions with boxes and push the tank away
            getCollisionResponse()

            -- sync the position with the hitbox
            p.x = p.hitbox.x
            p.y = p.hitbox.y

            -- update visible boxes if there was any movement
            if md ~= 0 then
                updateVisibleBoxes()
            end

            -- update the target marker
            if md ~= 0 or td ~= 0 then
                updateTargetMarker()
            end
        else
            -- update the bullet
            local b = game.bullet

            b.x = b.x + b.spd * b.vx * dt
            b.y = b.y + b.spd * b.vy * dt
            b.hitbox.x = b.x
            b.hitbox.y = b.y

            -- test for collision
            local collisions = {}
            game.tree:range(b.hitbox, collisions)

            -- destroy boxes hit by the bullet
            for i = 1, #collisions do
                deleteBox(collisions[i].id) -- destroy the box
                table.insert(game.scraps, { aabb.center(collisions[i].box) }) -- put some scraps where the box was
            end

            if #collisions > 0 then
                b.visible = false -- hide the bullet like to fake its explosion
                p.shooting = false -- return control to the player
                b.vx = 0 b.vy = 0 -- stop the bullet
                updateVisibleBoxes()
            end
        end
    end,

    draw = function()
        local p = game.player

        g.push()
        g.scale(game.zoom)
        g.translate(-p.x + (0.5 * g.getWidth()) / game.zoom, -p.y + (0.5 * g.getHeight()) / game.zoom)

        -- scraps
        for i = 1, #game.scraps do
            local sx, sy = unpack(game.scraps[i]) -- unpack the position table (see bullet update section)
            g.draw(game.sprite.scraps, sx - 24, sy - 24)
        end
        -- boxes
        g.draw(game.sprite.tank, p.x, p.y, p.r, 1, 1, 28, 24)
        for i = 1, #game.visible_boxes do
            drawBox(game.visible_boxes[i].box)
        end
        if p.shooting then
            -- bullet
            g.draw(game.sprite.bullet, game.bullet.x - 3, game.bullet.y - 3)
        elseif game.target_marker.visible then
            -- target marker
            g.draw(game.sprite.target, game.target_marker.x - 4, game.target_marker.y - 4)
        end
        if game.debug then
            -- player hitbox
            g.setColor(0, 255*color_mode, 127*color_mode, 0.3)
            g.circle('fill', p.hitbox.x, p.hitbox.y, p.hitbox.r)
            -- aim range
            g.setColor(255*color_mode, 0, 0, 0.3)
            g.circle('line', p.x, p.y, p.aim_range)
            g.line(game.player.x, game.player.y, game.player.x + math.cos(p.r) * game.player.aim_range, game.player.y + math.sin(p.r) * game.player.aim_range)
            -- tree
            game.tree:draw(false, true)
        end

        g.pop()
        
        -- prompts
        g.setFont(game.font.prompt)
        g.setColor(0,0,0,0.4)
        g.rectangle('fill', 0, 0, 800, 42)
        g.rectangle('fill', 0, 538, 800, 22)

        g.setColor(255*color_mode, 255*color_mode, 255*color_mode)
        local output = 'Total boxes: %u | Boxes being drawn: %u | Boxes tested for collision: %u | Boxes tested for raycasting: %u'
        local output2 = 'Tree average intersections for collision detection: %u | Tree average intersections for drawing: %u'
        g.printf(output:format(#game.boxes, #game.visible_boxes, game.collision_check_n, game.raycasting_check_n), 2, 2, 796, 'left')
        g.printf(output2:format(game.collision_visited_avg, game.draw_visited_avg), 2, 22, 796, 'left')
        g.printf('Press P to open pause menu.', 0, 542, 800, 'center')
        g.printf(('position: %i, %i'):format(game.player.x, game.player.y), -2, 542, 800, 'right')
        g.printf('target locked: ' .. (game.target_marker.visible and 'yes' or 'no'), 2, 542, 800, 'left')
    end,
}

function game.key(code) -- keyboard input
    code = code:lower()
    if game.current_scene == 'play' then
        if code == 'p' then
            game.current_scene = 'pause'
        elseif code == 'h' then
            game.debug = not game.debug
        end
    elseif game.current_scene == 'menu' then
        game.current_scene = 'play'
    elseif game.current_scene == 'pause' then
        if code == 'p' then
            game.current_scene = 'play'
        elseif code == 'r' then
            newGame()
            game.current_scene = 'play'
        end
    end
end

function game.scroll(amount) -- scroll input
    game.zoom = clamp(game.zoom + amount * 0.5, 1, 3)
    updateVisibleBoxes()
end

function game.draw()
    game.scene[game.current_scene].draw()
end

function game.update(dt)
    if game.scene[game.current_scene].update then
        game.scene[game.current_scene].update(dt)
    end
end

return game