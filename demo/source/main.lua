local aabb = require 'aabb'
local game = require 'game'

function love.load()
    game.load()
end

function love.mousemoved(x, y)

end

function love.mousepressed(x, y)
    
end

function love.keyreleased(code)
    game.key(code)
end

function love.wheelmoved(x, y)
    game.scroll(y)
end

function love.draw()
    --g.draw(sprite.tank, 360, 280, 0, 1, 1, 24, 36)
    --g.setColor(0,1,0.5,0.3)
    game.draw()
end

function love.update(dt)
    game.update(dt)
end

function love.quit()
    
end