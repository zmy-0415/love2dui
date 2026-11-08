--[[
    game/render/world.lua —— 世界渲染

    只画视口内的方块。视口 80×45 tile 时一帧约 3600 格，
    每格 3 次 rectangle，真机上完全无压力；软光栅出图会慢一些，但那是工具的事。

    画法先做「色块 + 明暗边」，不做瓦片贴图。理由：
      1) 现在要验的是地形可读性（能看出哪是土、哪是石、矿在哪、洞通向哪），
         不是材质细节。色块阶段就能判断，改起来也快。
      2) 贴图一上，任何地形改动都要重画一套图；色块阶段改生成器是零成本。
    到 M3 美术统一时，这里换成一个 tilemap 贴图查询即可，接口不变。

    矿物单独处理：整格变蓝/变橙的矿在满屏石头的画面里极难找，
    而且看起来很假。改成「石头底色 + 几粒矿斑」，稳定哈希决定斑点位置，
    不会随帧闪烁。
]]

local Tiles = require("game.core.tiles")
local World = require("game.core.world")

local R = {}

local T = World.TILE

-- 确定性整数哈希：让每格方块的纹理微差稳定不闪
local function h2(x, y)
    local n = x * 73856093 + y * 19349663
    n = n % 65536
    if n < 0 then n = n + 65536 end
    return n / 65535
end

-- 后端尺寸。love.graphics 用 getWidth()，软光栅直接有 w/h 字段
local function dims(g)
    local w = (g.getWidth and g.getWidth()) or g.w or 1280
    local h = (g.getHeight and g.getHeight()) or g.h or 720
    return w, h
end

-- 天空：从地平线往上的渐变。用横条模拟，条数按高度自适应
function R.drawSky(g, cam, world)
    local w, h = dims(g)
    local horizon = 26 * T     -- 世界地表大致高度
    local top = cam.y
    local bottom = cam.y + h

    -- 完全在地下：整屏用深色，避免洞穴里透出蓝天
    if top > horizon + 40 then
        g.setColor(0.055, 0.06, 0.075, 1)
        g.rectangle("fill", 0, 0, w, h)
        return
    end

    local bands = 12
    local bh = math.ceil(h / bands)
    for i = 0, bands - 1 do
        local sy = i * bh
        local wy = cam.y + sy
        -- 越高越深蓝
        local t = math.max(0, math.min(1, (horizon + 120 - wy) / (h + 200)))
        -- 越靠近地平线越暖越亮，远处压暗成深蓝。
        -- 之前整体太暗，地表看起来像深夜，玩家第一眼会以为自己在洞里
        local r = 0.20 + 0.16 * (1 - t)
        local gg = 0.26 + 0.22 * (1 - t)
        local b = 0.40 + 0.20 * (1 - t)
        g.setColor(r, gg, b, 1)
        g.rectangle("fill", 0, sy, w, bh + 1)
    end

    -- 地平线附近轻微压暗，给远景一点纵深。压太狠会把地表压成夜景
    if bottom > horizon - 60 then
        g.setColor(0.06, 0.07, 0.10, 0.28)
        g.rectangle("fill", 0, math.max(0, horizon - 70 - cam.y), w, h)
    end
end

-- 单格方块的底面 + 暴露面明暗。
--
-- 关键：只在「外面是空气」的那一侧画亮边/暗边。
-- 最早是每格四边都画，结果整屏全是等距横条，像百叶窗——方块之间的分界线
-- 反而比地形轮廓更抢眼。只画暴露面之后，平坦的岩体是一整片，洞口边缘才亮，
-- 视觉上会自动聚成「轮廓」，这正是要的效果。
local function drawBlock(g, world, sx, sy, def, tx, ty)
    local c = def.base
    local v = 0.94 + h2(tx, ty) * 0.12
    g.setColor(c[1] * v, c[2] * v, c[3] * v, 1)
    g.rectangle("fill", sx, sy, T, T)

    local l, d = def.light, def.dark
    -- 上表面受光
    if not world:filled(tx, ty - 1) then
        g.setColor(l[1], l[2], l[3], 0.55)
        g.rectangle("fill", sx, sy, T, 3)
    end
    -- 下表面落影
    if not world:filled(tx, ty + 1) then
        g.setColor(d[1], d[2], d[3], 0.85)
        g.rectangle("fill", sx, sy + T - 3, T, 3)
    end
    -- 侧面：左亮右暗，给一点方向感（光从左上打）
    if not world:filled(tx - 1, ty) then
        g.setColor(l[1], l[2], l[3], 0.22)
        g.rectangle("fill", sx, sy, 2, T)
    end
    if not world:filled(tx + 1, ty) then
        g.setColor(d[1], d[2], d[3], 0.45)
        g.rectangle("fill", sx + T - 2, sy, 2, T)
    end

    -- 内部极弱的颗粒，避免大片死平
    if h2(tx * 3, ty * 5) > 0.72 then
        g.setColor(d[1], d[2], d[3], 0.18)
        g.rectangle("fill", sx + 4, sy + 6, 3, 2)
    end
end

-- 矿：石头底 + 矿斑
local ORE = {
    copper  = { 0.62, 0.40, 0.20 },
    iron    = { 0.46, 0.50, 0.57 },
    crystal = { 0.31, 0.77, 0.87 },
}

local function drawOre(g, world, sx, sy, key, tx, ty)
    local stone = Tiles.byKey.stone
    local v = 0.94 + h2(tx, ty) * 0.10
    g.setColor(stone.base[1] * v, stone.base[2] * v, stone.base[3] * v, 1)
    g.rectangle("fill", sx, sy, T, T)

    -- 和普通岩石一样只画暴露面，矿脉才不会被横条切碎
    local l, d = stone.light, stone.dark
    if not world:filled(tx, ty - 1) then
        g.setColor(l[1], l[2], l[3], 0.5)
        g.rectangle("fill", sx, sy, T, 3)
    end
    if not world:filled(tx, ty + 1) then
        g.setColor(d[1], d[2], d[3], 0.8)
        g.rectangle("fill", sx, sy + T - 3, T, 3)
    end

    local col = ORE[key]
    -- 3 粒斑点，位置由格子坐标决定，因此永远长在同一个地方。
    -- 原来 5 粒 × 每格，整片矿脉看起来像「下雪」，反而掩盖了矿的轮廓
    for i = 1, 3 do
        local rx = 2 + math.floor(h2(tx * 7 + i, ty * 3 + i * 5) * (T - 6))
        local ry = 2 + math.floor(h2(tx * 3 + i * 11, ty * 7 + i) * (T - 6))
        local s = 2 + math.floor(h2(tx + i, ty - i) * 2)
        g.setColor(col[1], col[2], col[3], 1)
        g.rectangle("fill", sx + rx, sy + ry, s, s)
        -- 只提亮一档，不是加白色高光（加到接近 1 就变成雪点了）
        g.setColor(math.min(1, col[1] * 1.35), math.min(1, col[2] * 1.35), math.min(1, col[3] * 1.35), 0.9)
        g.rectangle("fill", sx + rx, sy + ry, s, 1)
    end

    if key == "crystal" then
        -- 晶簇给一个菱形，和方形矿斑区分开
        local cx, cy = sx + T * 0.5, sy + T * 0.5
        g.setColor(col[1], col[2], col[3], 0.95)
        g.polygon("fill", cx, cy - 6, cx + 5, cy, cx, cy + 6, cx - 5, cy)
        g.setColor(0.75, 0.95, 1.0, 0.55)
        g.polygon("fill", cx, cy - 6, cx + 2, cy - 2, cx, cy, cx - 2, cy - 2)
    end
end

-- 草皮：顶部一条草，下面是土
local function drawGrass(g, world, sx, sy, def, tx, ty)
    local dirt = Tiles.byKey.dirt
    local v = 0.94 + h2(tx, ty) * 0.12
    g.setColor(dirt.base[1] * v, dirt.base[2] * v, dirt.base[3] * v, 1)
    g.rectangle("fill", sx, sy, T, T)
    if not world:filled(tx, ty + 1) then
        g.setColor(dirt.dark[1], dirt.dark[2], dirt.dark[3], 0.8)
        g.rectangle("fill", sx, sy + T - 3, T, 3)
    end

    local c = def.base
    g.setColor(c[1], c[2], c[3], 1)
    g.rectangle("fill", sx, sy, T, 5)
    -- 参差的草边，不然地表是一条直角直线
    local n = 2 + math.floor(h2(tx, ty) * 3)
    for i = 1, n do
        local rx = math.floor(h2(tx * 5 + i, ty) * (T - 3))
        g.setColor(c[1] * 1.18, c[2] * 1.18, c[3] * 1.05, 1)
        g.rectangle("fill", sx + rx, sy + 5, 2, 2)
    end
end

-- 木头：竖纹
local function drawWood(g, world, sx, sy, def, tx, ty)
    local c = def.base
    local v = 0.92 + h2(tx, ty) * 0.12
    g.setColor(c[1] * v, c[2] * v, c[3] * v, 1)
    g.rectangle("fill", sx, sy, T, T)
    g.setColor(def.dark[1], def.dark[2], def.dark[3], 0.8)
    g.rectangle("fill", sx + 3, sy, 2, T)
    g.rectangle("fill", sx + T - 5, sy, 2, T)
    g.setColor(def.light[1], def.light[2], def.light[3], 0.35)
    g.rectangle("fill", sx + 6, sy, 1, T)
end

local SPECIAL = {
    grass = drawGrass,
    wood = drawWood,
}

-- 挖掘裂纹：进度越高，裂缝越多
local function drawCracks(g, sx, sy, prog)
    local n = math.floor(prog * 5) + 1
    g.setColor(0, 0, 0, 0.55)
    for i = 1, n do
        local a = h2(i * 13, i * 7) * T
        local b = h2(i * 5, i * 17) * T
        g.rectangle("fill", sx + math.floor(a), sy + math.floor(b), 2, 2)
    end
end

--- 画整屏世界
--  @param g 绘制后端（love.graphics 或 tools/softraster）
--  @param world 世界
--  @param cam { x, y, w, h } 视口左上角世界坐标与尺寸
function R.draw(g, world, cam)
    local w, h = cam.w, cam.h
    R.drawSky(g, cam, world)

    local tx0 = math.floor(cam.x / T)
    local ty0 = math.floor(cam.y / T)
    local tx1 = math.floor((cam.x + w) / T)
    local ty1 = math.floor((cam.y + h) / T)

    -- 1) 背景层：洞穴壁，整体压暗，不能抢前景
    for ty = ty0, ty1 do
        for tx = tx0, tx1 do
            local id = world:getBg(tx, ty)
            if id ~= Tiles.AIR then
                local def = Tiles.get(id)
                local sx = tx * T - cam.x
                local sy = ty * T - cam.y
                local c = def.base
                g.setColor(c[1], c[2], c[3], 1)
                g.rectangle("fill", sx, sy, T, T)
            end
        end
    end

    -- 2) 前景层
    for ty = ty0, ty1 do
        for tx = tx0, tx1 do
            local id = world:get(tx, ty)
            if id ~= Tiles.AIR then
                local def = Tiles.get(id)
                local sx = tx * T - cam.x
                local sy = ty * T - cam.y
                local key = def.key
                if ORE[key] then
                    drawOre(g, world, sx, sy, key, tx, ty)
                else
                    local fn = SPECIAL[key]
                    if fn then
                        fn(g, world, sx, sy, def, tx, ty)
                    elseif def.bg then
                        -- 背景方块即使被误放在前景层也只画暗色
                        local c = def.base
                        g.setColor(c[1], c[2], c[3], 1)
                        g.rectangle("fill", sx, sy, T, T)
                    else
                        drawBlock(g, world, sx, sy, def, tx, ty)
                    end
                end

                local dmg = world:damageAt(tx, ty)
                if dmg and dmg > 0.04 then
                    drawCracks(g, sx, sy, dmg)
                end
            end
        end
    end
end

-- 局部光照：在发光方块周围打一圈柔和的光。
-- 单独一遍是因为它要盖在所有方块之上；混在世界遍历里会被后画的方块压掉。
function R.drawGlow(g, world, cam)
    local tx0 = math.floor(cam.x / T)
    local ty0 = math.floor(cam.y / T)
    local tx1 = math.floor((cam.x + cam.w) / T)
    local ty1 = math.floor((cam.y + cam.h) / T)
    for ty = ty0, ty1 do
        for tx = tx0, tx1 do
            local def = Tiles.get(world:get(tx, ty))
            if def.glow > 0 then
                local cx = tx * T - cam.x + T * 0.5
                local cy = ty * T - cam.y + T * 0.5
                -- 三层同心圆近似径向衰减：比逐像素算光照便宜得多
                g.setColor(0.31, 0.77, 0.87, 0.05 * def.glow)
                g.circle("fill", cx, cy, 30)
                g.setColor(0.31, 0.77, 0.87, 0.07 * def.glow)
                g.circle("fill", cx, cy, 18)
                g.setColor(0.45, 0.90, 0.98, 0.10 * def.glow)
                g.circle("fill", cx, cy, 9)
            end
        end
    end
end

return R
