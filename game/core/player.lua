--[[
    game/core/player.lua —— 玩家状态与移动

    只放「数据 + 每帧怎么变」，不放绘制，也不读键盘。
    输入由场景层采集成一个 table 传进来，这样测试里可以直接喂一串输入，
    也不用为了写测试去伪造 love.keyboard。

    手感参数集中放在 TUNE 里。这些数字决定了这个游戏「能不能玩」，
    后面要反复调，所以必须一眼全看到，不能散在各处。
]]

local Physics = require("game.core.physics")
local Tiles = require("game.core.tiles")
local World = require("game.core.world")

local Player = {}
Player.__index = Player

-- 手感参数（像素 / 秒）
local TUNE = {
    accel       = 1500,   -- 地面加速度
    airAccel    = 950,    -- 空中加速度：比地面低，但不能太低，否则跳跃失去控制感
    maxSpeed    = 122,
    friction    = 1700,   -- 松手减速
    airDrag     = 260,    -- 空中减速（很小，保留惯性）
    gravity     = 980,
    maxFall     = 620,
    jumpSpeed   = 348,    -- 起跳初速，配合重力约 62px ≈ 3.8 格
    jumpCut     = 0.45,   -- 提前松手时垂直速度乘这个值，实现「短跳/长跳」
    coyote      = 0.10,   -- 走出平台后仍可起跳的宽限
    jumpBuffer  = 0.12,   -- 落地前按跳，落地瞬间自动起跳
    staminaRegen = 26,
}
Player.TUNE = TUNE

Player.WIDTH = 10
Player.HEIGHT = 24

function Player.new(x, y)
    return setmetatable({
        x = x, y = y,
        w = Player.WIDTH, h = Player.HEIGHT,
        vx = 0, vy = 0,
        facing = 1,
        onGround = false,
        coyote = 0,
        jumpBuf = 0,
        hp = 100, maxHp = 100,
        stamina = 100, maxStamina = 100,
        invuln = 0,           -- 受击无敌时间
        hurtFlash = 0,        -- 受击闪白剩余时间（渲染用）
        dead = false,
        -- 挖掘工具：M1 只有一把镐，等级随进度升
        pick = { tier = 1, eff = 1.0 },
        -- 动作状态，供渲染层选姿势
        state = "idle",
        stateTime = 0,
        animT = 0,
        -- 挖矿：目标格与是否在挖（由场景每帧写入）
        digTarget = nil,
        digging = false,
        -- 攻击（M1 战斗用）
        attackT = 0,
        attackKind = nil,
    }, Player)
end

function Player:box()
    return self.x, self.y, self.w, self.h
end

function Player:center()
    return self.x, self.y - self.h * 0.5
end

-- 把玩家放到世界出生点上：脚底贴地
function Player.spawnAt(spawn)
    local p = Player.new(spawn.x, spawn.y)
    p.onGround = true
    return p
end

local function approach(v, target, delta)
    if v < target then
        v = v + delta
        if v > target then v = target end
    elseif v > target then
        v = v - delta
        if v < target then v = target end
    end
    return v
end

-- 输入字段：left / right / jump（按住） / jumpPressed（本帧按下） / dig（按住）
function Player:update(world, input, dt)
    if self.dead then
        self.state = "dead"
        self.stateTime = self.stateTime + dt
        self.animT = self.animT + dt
        return
    end

    input = input or {}
    local T = TUNE

    -- ---- 水平
    local dir = 0
    if input.left then dir = dir - 1 end
    if input.right then dir = dir + 1 end
    if dir ~= 0 then self.facing = dir end

    local accel = self.onGround and T.accel or T.airAccel
    if dir ~= 0 then
        self.vx = self.vx + dir * accel * dt
        if self.vx > T.maxSpeed then self.vx = T.maxSpeed end
        if self.vx < -T.maxSpeed then self.vx = -T.maxSpeed end
    else
        local drag = self.onGround and T.friction or T.airDrag
        self.vx = approach(self.vx, 0, drag * dt)
    end

    -- ---- 跳跃：土狼时间 + 输入缓冲
    if self.onGround then self.coyote = T.coyote else self.coyote = math.max(0, self.coyote - dt) end
    if input.jumpPressed then self.jumpBuf = T.jumpBuffer else self.jumpBuf = math.max(0, self.jumpBuf - dt) end

    if self.jumpBuf > 0 and self.coyote > 0 then
        self.vy = -T.jumpSpeed
        self.jumpBuf = 0
        self.coyote = 0
        self.onGround = false
    end
    -- 提前松手 → 短跳。不加这个，所有跳跃都一个高度，平台关会很难玩
    if not input.jump and self.vy < 0 then
        self.vy = self.vy * (1 - T.jumpCut * math.min(1, dt * 30))
    end

    -- ---- 重力
    self.vy = self.vy + T.gravity * dt
    if self.vy > T.maxFall then self.vy = T.maxFall end

    Physics.move(world, self, dt)

    -- ---- 计时器
    self.animT = self.animT + dt
    self.invuln = math.max(0, self.invuln - dt)
    self.hurtFlash = math.max(0, self.hurtFlash - dt)

    -- ---- 耐力
    if self.digging then
        self.stamina = math.max(0, self.stamina - 18 * dt)
    else
        self.stamina = math.min(self.maxStamina, self.stamina + T.staminaRegen * dt)
    end
    -- 耐力见底时挖不动，但不会卡住：低于 1 就停，恢复一点后能继续
    if self.stamina <= 0.5 then self.digging = false end

    -- ---- 状态机（只用于选动作，不参与物理）
    local want = "idle"
    if self.attackT > 0 then
        want = "attack"
    elseif not self.onGround then
        want = self.vy < -40 and "jump" or "fall"
    elseif self.digging then
        want = "dig"
    elseif math.abs(self.vx) > 12 then
        want = "run"
    end
    if want ~= self.state then
        self.state = want
        self.stateTime = 0
    else
        self.stateTime = self.stateTime + dt
    end
end

-- 受击。方向 dir 用来决定击退朝哪边（+1 向右）
function Player:hurt(amount, dir)
    if self.dead or self.invuln > 0 then return false end
    self.hp = math.max(0, self.hp - amount)
    self.invuln = 0.55
    self.hurtFlash = 0.18
    self.vx = (dir or -self.facing) * 150
    self.vy = math.min(self.vy, -130)
    if self.hp <= 0 then
        self.dead = true
        self.state = "dead"
        self.stateTime = 0
    end
    return true
end

function Player:heal(amount)
    if self.dead then return end
    self.hp = math.min(self.maxHp, self.hp + amount)
end

-- 挖掘：由场景每帧告诉玩家「现在指着哪一格、按没按住」
-- 返回 (是否挖穿, 方块 id)
function Player:dig(world, tx, ty, dt, holding)
    if self.dead or not holding then
        self.digging = false
        return false
    end
    if not world:inBounds(tx, ty) then
        self.digging = false
        return false
    end
    local id = world:get(tx, ty)
    if not Tiles.mineable(id) then
        self.digging = false
        return false
    end
    -- 够不着就不挖。判定用格中心，避免站在边缘时「隔着一格挖到里面」
    local cx = (tx + 0.5) * World.TILE
    local cy = (ty + 0.5) * World.TILE
    local ex, ey = self:center()
    if (cx - ex) ^ 2 + (cy - ey) ^ 2 > (World.TILE * 4.2) ^ 2 then
        self.digging = false
        return false
    end

    self.digging = true
    self.digTarget = { x = tx, y = ty }
    local broke, brokeId = world:dig(tx, ty, dt, self.pick.eff, self.pick.tier)
    if broke then
        self.digging = false
        return true, brokeId
    end
    return false
end

-- 放置：不允许放进自己身体，也不允许悬空放在无支撑处（简单规则，建造手感够用）
function Player:canPlace(world, tx, ty)
    if not world:inBounds(tx, ty) then return false end
    if world:get(tx, ty) ~= Tiles.AIR then return false end
    local T = World.TILE
    local px, py = (tx + 0.5) * T, (ty + 0.5) * T
    local ex, ey = self:center()
    if math.abs(px - ex) < (self.w * 0.5 + T * 0.5) and math.abs(py - ey) < (self.h * 0.5 + T * 0.5) then
        return false
    end
    local ex2, ey2 = self:center()
    if (px - ex2) ^ 2 + (py - ey2) ^ 2 > (World.TILE * 4.2) ^ 2 then return false end
    -- 至少一边挨着已有方块，否则可以在半空乱放
    return world:solidAt(tx - 1, ty) or world:solidAt(tx + 1, ty)
        or world:solidAt(tx, ty - 1) or world:solidAt(tx, ty + 1)
        or world:get(tx, ty - 1) ~= Tiles.AIR
end

return Player
