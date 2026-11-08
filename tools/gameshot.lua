--[[
    tools/gameshot.lua —— 游戏画面截图（不需要显卡）

    用 tools/softraster 把 Game 渲染成 BMP，再交给 tools/topng.py 转 PNG。
    这是没有 OpenGL 时唯一能看见游戏的办法，同时也是视觉回归的手段：
    同一份输入脚本，出来的图应该逐像素稳定。

    用法（项目根目录）：
        luajit tools/gameshot.lua <输出路径> [场景] [放大倍数]

    场景：surface（地表） / cave（洞穴） / boss（石喉战） / mine（挖矿）
]]

local here = (arg and arg[0]) or "tools/gameshot.lua"
local root = here:match("^(.*)[/\\][^/\\]+$") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local sr = require("tools.softraster")
local Game = require("game.game")
local Mob = require("game.core.mob")
local World = require("game.core.world")

local out = arg[1] or "shot.bmp"
local scene = arg[2] or "surface"
local scale = tonumber(arg[3] or "2") or 2

local VW, VH = 640, 360
local game = Game.new({ w = VW, h = VH, seed = 20261108 })
local p = game.player

local function settle(frames)
    for _ = 1, frames or 20 do game:update(1 / 60, {}) end
end

local function goTo(tx, ty)
    p.x, p.y = (tx + 0.5) * World.TILE, ty * World.TILE
    game.cam:snap(p.x, p.y - p.h * 0.5, game.world)
end

if scene == "surface" then
    settle(40)
    -- 往右走一段，让画面里有树和草地
    for _ = 1, 50 do game:update(1 / 60, { right = true }) end
    -- 两只怪，展示战斗元素
    game.mobs[#game.mobs + 1] = Mob.new("crawler", p.x + 70, p.y)
    game.mobs[#game.mobs + 1] = Mob.new("flyer", p.x + 130, p.y - 60)
    for _ = 1, 16 do game:update(1 / 60, {}) end

elseif scene == "cave" then
    local sx = math.floor(game.world.spawn.x / World.TILE)
    goTo(sx - 6, 62)
    settle(20)
    game.mobs[#game.mobs + 1] = Mob.new("crawler", p.x + 60, p.y - 8)
    game.mobs[#game.mobs + 1] = Mob.new("blob", p.x + 120, p.y - 8)
    for _ = 1, 20 do game:update(1 / 60, {}) end

elseif scene == "mine" then
    settle(30)
    -- 对着脚边的土按住左键：挖掘进度条会显示出来
    for _ = 1, 26 do
        game:update(1 / 60, { dig = true, mouseX = VW * 0.54, mouseY = VH * 0.62 })
    end

elseif scene == "boss" then
    local cx = game.world.coreX
    local cy = game.world.coreY
    goTo(cx - 4, cy + 6)
    settle(20)
    game:summonBoss()
    local b = game.boss
    -- 打到阶段 3，展示三节躯体、尾节弱点与 AOE 蓄力
    b:hurt(b.maxHp * 0.68, 1, 0, false)
    for _ = 1, 20 do game:update(1 / 60, {}) end
    for _ = 1, 400 do
        game:update(1 / 60, {})
        if b.aoeWind and b.aoeWind < 1.5 then break end
    end
end

local g = sr.new(VW, VH)
game:draw(g)

local function save(bmp, path)
    if scale > 1 then
        local big = sr.new(bmp.w * scale, bmp.h * scale)
        for y = 0, bmp.h - 1 do
            for x = 0, bmp.w - 1 do
                local r, gg, b = bmp.getPixel(x, y)
                big.setColor(r / 255, gg / 255, b / 255, 1)
                big.rectangle("fill", x * scale, y * scale, scale, scale)
            end
        end
        big.saveBMP(path)
    else
        bmp.saveBMP(path)
    end
end

save(g, out)
print(string.format("[gameshot] %s  %dx%d ×%d  dug=%d kills=%d",
    scene, VW, VH, scale, game.stats.dug, game.kills))
