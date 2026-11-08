--[[
    game/core/physics.lua —— AABB 方块碰撞

    只有一件事：把一个矩形体沿网格推出去，不穿墙、能站住。

    三个必须做对的细节：
      1. 分轴移动。合起来算的话，贴着墙走会被墙「粘住」，这是同类实现最常见的 bug。
      2. 小步长。一帧位移超过半格时，逐格扫会直接跳过薄墙；按半格切分。
      3. 浮点贴边要留 epsilon。贴着地时 bottom 恰好等于 tile 边界，不加 eps 会被判成
         永远在重叠，于是每帧都被弹开一点，表现为持续抖动。

    坐标系：body.x 是水平中心，body.y 是脚底。这样角色绘制的原点（脚底中心）
    和碰撞盒原点一致，不用在两套坐标之间来回换算——换算点越少，错位越少。
]]

local Tiles = require("game.core.tiles")
local World = require("game.core.world")

local P = {}

P.EPS = 0.001
P.MAX_STEP = World.TILE * 0.5

-- 矩形是否与任意实心方块重叠
function P.hits(world, x, y, w, h)
    local T = World.TILE
    local left = x - w * 0.5
    local right = x + w * 0.5
    local top = y - h
    local bottom = y
    local tx0 = math.floor((left + P.EPS) / T)
    local tx1 = math.floor((right - P.EPS) / T)
    local ty0 = math.floor((top + P.EPS) / T)
    local ty1 = math.floor((bottom - P.EPS) / T)
    for ty = ty0, ty1 do
        for tx = tx0, tx1 do
            if world:solidAt(tx, ty) then return true end
        end
    end
    return false
end

function P.overlapsAt(world, body, x, y)
    return P.hits(world, x, y, body.w, body.h)
end

-- 水平推出到刚好贴墙的位置
local function resolveX(world, body, dir)
    local T = World.TILE
    if dir > 0 then
        local tileX = math.floor((body.x + body.w * 0.5) / T)
        body.x = tileX * T - body.w * 0.5 - P.EPS
    else
        local tileX = math.floor((body.x - body.w * 0.5) / T)
        body.x = (tileX + 1) * T + body.w * 0.5 + P.EPS
    end
end

local function resolveY(world, body, dir)
    local T = World.TILE
    if dir > 0 then
        local tileY = math.floor(body.y / T)
        body.y = tileY * T - P.EPS
    else
        local tileY = math.floor((body.y - body.h) / T)
        body.y = (tileY + 1) * T + body.h + P.EPS
    end
end

-- 推进一个 body。会写回 x / y / vx / vy，并设置 body.onGround / body.hitWall / body.hitCeil
function P.move(world, body, dt)
    body.onGround = false
    body.hitWall = false
    body.hitCeil = false
    if dt <= 0 then return end

    -- 按半格切分：一帧 60fps 下落最快约 600px/s = 10px，本来不会穿；
    -- 但冲刺、击退、爆炸会给出更大的瞬时速度，所以这里统一兜住
    local dist = math.max(math.abs(body.vx), math.abs(body.vy)) * dt
    local steps = math.ceil(dist / P.MAX_STEP)
    if steps < 1 then steps = 1 end
    if steps > 16 then steps = 16 end
    local sdt = dt / steps

    for _ = 1, steps do
        -- 水平
        if body.vx ~= 0 then
            body.x = body.x + body.vx * sdt
            if P.hits(world, body.x, body.y, body.w, body.h) then
                local dir = body.vx > 0 and 1 or -1
                resolveX(world, body, dir)
                body.vx = 0
                body.hitWall = true
                body.wallDir = dir
                -- 推出后若仍重叠（卡在方块里），说明是外部原因，硬退半格避免死锁
                if P.hits(world, body.x, body.y, body.w, body.h) then
                    body.x = body.x - dir * (World.TILE * 0.5)
                end
            end
        end

        -- 垂直
        if body.vy ~= 0 then
            body.y = body.y + body.vy * sdt
            if P.hits(world, body.x, body.y, body.w, body.h) then
                local dir = body.vy > 0 and 1 or -1
                resolveY(world, body, dir)
                if dir > 0 then body.onGround = true else body.hitCeil = true end
                body.vy = 0
            end
        end
    end
end

-- 脚下是否踩实（用于土狼时间，独立于 move，不需要速度）
function P.grounded(world, body)
    return P.hits(world, body.x, body.y + P.EPS * 2, body.w, body.h)
end

-- 从一点向下找第一个实心方块的 y（像素）。找不到返回 nil。
-- 生成怪、放置掉落物、相机限位都要用
function P.groundBelow(world, px, py, maxTiles)
    local T = World.TILE
    local tx = math.floor(px / T)
    local ty = math.floor(py / T)
    for i = 0, maxTiles or 40 do
        if world:solidAt(tx, ty + i) then
            return (ty + i) * T
        end
    end
    return nil
end

return P
