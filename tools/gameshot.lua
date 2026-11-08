--[[
    tools/gameshot.lua —— 游戏画面截图（不需要显卡）

    用 tools/softraster 把 Game 渲染成 BMP，再交给 tools/topng.py 转 PNG。
    这是没有 OpenGL 时唯一能看见游戏的办法，同时也是视觉回归的手段：
    同一份输入脚本，出来的图应该逐像素稳定。

    用法（项目根目录）：
        luajit tools/gameshot.lua <输出路径> [场景] [放大倍数]

    场景：surface（地表） / cave（洞穴） / boss（石喉战） / mine（挖矿）
          combat（M2 战斗：元素状态 + 多目标 + 箭）
]]

local here = (arg and arg[0]) or "tools/gameshot.lua"
local root = here:match("^(.*)[/\\][^/\\]+$") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local sr = require("tools.softraster")
local Game = require("game.game")
local Mob = require("game.core.mob")
local World = require("game.core.world")
local Status = require("game.core.status")

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

elseif scene == "combat" then
    -- M2 的战斗展示：镰刀（群体不衰减）+ 三种元素状态 + 精英标记 + 飞行中的箭
    settle(30)
    for _ = 1, 40 do game:update(1 / 60, { right = true }) end
    game:equip({
        class = "sickle", bladeMat = "crystal", bladeTier = 3,
        hilt = "bone", hiltMat = "bone", hiltTier = 2,
        core = "ember", coreMat = "ember", coreTier = 1,
        affixes = { "sharp", "keen" }, seed = 7,
    })
    p.facing = 1

    -- 三只矿虫错开摆，各自挂一种元素。
    -- 两个细节都是踩出来的：
    --   间距 > 血条宽度(22)，否则三条血条叠成一条，看起来像只有一只
    --   起点 > 镰刀射程(36)，否则最后摆姿势那几帧会真的砍死一只，
    --     图上就变成「一只粉色尸体 + 两条血条」
    local keys = { "burn", "chill", "venom" }
    local frac = { 0.66, 0.44, 0.26 }
    for i = 1, 3 do
        local m = Mob.new("crawler", p.x + 62 + (i - 1) * 30, p.y)
        m.hp = m.maxHp * frac[i]
        m.hurtFlash = 0
        Status.apply(m, keys[i], 1)
        game.mobs[#game.mobs + 1] = m
    end

    -- 精英（铁壁）放右边空地，避免血条压在树干上
    local el = game:spawnMob("golem", p.x + 240, p.y, { affix = "iron" })
    if el then
        el.hp = el.maxHp * 0.52
        el.hurtFlash = 0
    end

    -- 两支飞行中的箭（手动放，避免为了画箭去换武器，把镰刀从画面里换掉）
    game:spawnProjectile({
        x = p.x + 108, y = p.y - 26, vx = 420, vy = -26,
        dmg = 20, kind = "arrow", life = 2, hostile = false,
    })
    game:spawnProjectile({
        x = p.x + 152, y = p.y - 34, vx = 420, vy = 4,
        dmg = 20, kind = "arrow", life = 2, hostile = false,
    })

    -- 空挥一刀，让画面停在判定窗口中间（武器在挥动的姿态）。
    -- 用 Combat.start 手动起手，之后不再按左键——否则 update 里会重新
    -- 判断「指着空气就攻击」，一路砍到判定窗口结束
    require("game.core.combat").start(p, game.resolved)
    for _ = 1, 9 do game:update(1 / 60, { mouseX = VW * 0.5 + 40, mouseY = VH * 0.5 }) end

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
