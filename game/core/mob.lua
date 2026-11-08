--[[
    game/core/mob.lua —— 怪物

    四类怪对应四套骨架，也对应四种「逼玩家做不同动作」的威胁：
        crawler 矿虫      直线冲撞，考走位（跳过去或侧闪）
        flyer   洞穴蝠    空中骚扰，考抬头与时机
        blob    腐化爬行者 远程毒液，考不要站着不动
        golem   石傀儡    高韧性高伤害，考破韧与绕后

    每种怪的 update 都只写「它想干什么」，不写「它怎么被画出来」。
    血量、韧性、击退这些公共部分放在 Mob 上，避免每种怪抄一遍。

    一个刻意的设计：所有怪在玩家离得远时只做巡逻，不追。
    这既是性能考虑（远处实体不进 AI），也是节奏考虑——
    玩家应该有「先观察、再决定打不打」的空间，而不是一进区域就被围。
]]

local Physics = require("game.core.physics")
local World = require("game.core.world")

local Mob = {}
Mob.__index = Mob

local T = World.TILE

-- 数值表。M1 的怪都按「玩家 100 血、初始剑 13 伤害」标定：
-- 矿虫两刀死、傀儡要砍十刀，玩家被打一下掉 8%~18%
local SPEC = {
    crawler = {
        kind = "crawler", hp = 42, dmg = 8, speed = 52, chase = 1.9,
        w = 12, h = 11, scale = 1.05, poise = 8, gravity = true,
        exp = 6,
    },
    flyer = {
        kind = "flyer", hp = 26, dmg = 6, speed = 78, chase = 2.2,
        w = 12, h = 10, scale = 1.0, poise = 4, gravity = false,
        exp = 5,
    },
    blob = {
        kind = "blob", hp = 58, dmg = 10, speed = 18, chase = 1.0,
        w = 14, h = 13, scale = 1.1, poise = 12, gravity = true,
        exp = 9, ranged = true, shootCd = 1.9, shootRange = 190,
    },
    golem = {
        kind = "golem", hp = 150, dmg = 19, speed = 34, chase = 1.0,
        w = 18, h = 30, scale = 1.0, poise = 44, gravity = true,
        exp = 24,
    },
}

Mob.SPEC = SPEC

function Mob.new(type, x, y, opts)
    opts = opts or {}
    local s = SPEC[type]
    if not s then error("未知怪物类型: " .. tostring(type)) end
    local self = setmetatable({}, Mob)
    self.type = type
    self.kind = s.kind
    self.x, self.y = x, y
    self.w, self.h = s.w, s.h
    self.vx, self.vy = 0, 0
    self.hp = s.hp
    self.maxHp = s.hp
    self.dmg = s.dmg
    self.speed = s.speed
    self.chase = s.chase
    self.scale = s.scale
    self.poiseMax = s.poise
    self.poise = s.poise
    self.gravity = s.gravity
    self.ranged = s.ranged
    self.shootCd = s.shootCd or 0
    self.shootRange = s.shootRange or 0
    self.shootTimer = 0.6 + (x % 7) * 0.1   -- 错开首轮射击，避免同屏怪同时喷

    self.facing = -1
    self.dir = 1
    self.animT = 0
    self.anim = "idle"
    self.hurtFlash = 0
    self.stagger = 0
    self.touchCd = 0
    self.think = 0
    self.dead = false
    self.deadT = 0
    self.barW = 22
    self.barY = 30
    self.exp = s.exp
    self.elite = false

    -- 精英词缀「爆裂」：血量翻倍、体型变大，死亡时炸一圈。
    -- 只做一条词缀，是为了先把「词缀能改变战斗行为」这件事验证掉
    if opts.elite then
        self.elite = true
        self.hp = self.hp * 2.2
        self.maxHp = self.hp
        self.dmg = self.dmg * 1.25
        self.scale = self.scale * 1.3
        self.poiseMax = self.poiseMax * 1.6
        self.poise = self.poiseMax
        self.barW = 32
        self.barY = 38
    end
    return self
end

function Mob:center()
    return self.x, self.y - self.h * 0.5
end

function Mob:alive()
    return not self.dead
end

-- 受击。poise 归零会硬直——这是「斧比剑重」能成立的地方：
-- 剑砍傀儡几乎打不出硬直，斧能，所以打高韧性目标必须换武器
function Mob:hurt(dmg, dir, poise)
    if self.dead then return end
    self.hp = self.hp - dmg
    self.hurtFlash = 0.14
    self.poise = self.poise - (poise or 0)
    if self.poise <= 0 then
        self.poise = self.poiseMax
        self.stagger = 0.45
    end
    self.vx = (dir or 1) * 55
    if not self.gravity then self.vy = (dir or 1) * 20 end
    if self.hp <= 0 then
        self.hp = 0
        self.dead = true
        self.deadT = 0
        self.anim = "dead"
    end
end

-- 地面怪：重力 + 碰撞
function Mob:walk(world, dt)
    self.vy = math.min(640, self.vy + 1000 * dt)
    Physics.move(world, self, dt)
end

-- 前方是否有地面。用来防止矿虫集体跳崖
function Mob:groundAhead(world)
    local ahead = self.x + self.facing * (self.w * 0.5 + 4)
    return Physics.groundBelow(world, ahead, self.y + 2, 3) ~= nil
end

function Mob:update(game, dt)
    local p = game.player
    local world = game.world

    self.animT = self.animT + dt
    self.hurtFlash = math.max(0, self.hurtFlash - dt)
    self.touchCd = math.max(0, self.touchCd - dt)
    if self.stagger > 0 then
        self.stagger = self.stagger - dt
        self.vx = self.vx * 0.86
    end

    if self.dead then
        self.deadT = self.deadT + dt
        self.vx = self.vx * 0.9
        if self.gravity then self:walk(world, dt) else
            self.x = self.x + self.vx * dt
        end
        return
    end

    local dx = p.x - self.x
    local dy = (p.y - p.h * 0.5) - (self.y - self.h * 0.5)
    local dist = math.sqrt(dx * dx + dy * dy)
    local aware = (not p.dead) and dist < 300 and math.abs(dy) < 110

    if self.stagger > 0 then
        -- 硬直期间不动，只滑行
        if self.gravity then self:walk(world, dt) end
        self.anim = "hurt"
        return
    end

    local s = SPEC[self.type]
    if self.type == "crawler" then
        self:aiCrawler(world, p, dx, dy, dist, aware, dt)
    elseif self.type == "flyer" then
        self:aiFlyer(world, p, dx, dy, dist, aware, dt)
    elseif self.type == "blob" then
        self:aiBlob(game, world, p, dx, dy, dist, aware, dt)
    elseif self.type == "golem" then
        self:aiGolem(world, p, dx, dy, dist, aware, dt)
    end

    if self.gravity then
        self:walk(world, dt)
    else
        self.x = self.x + self.vx * dt
        self.y = self.y + self.vy * dt
    end

    -- 接触伤害：怪碰到玩家就咬一口，有冷却
    if not p.dead and self.touchCd <= 0 and self:overlaps(p) then
        local dir = (p.x > self.x) and 1 or -1
        if p:hurt(self.dmg, dir) then
            self.touchCd = 0.8
            game:hitStop(0.05)
            game.cam:kick(2.2, 0.18)
        end
    end
end

-- 矩形重叠（玩家与怪）
function Mob:overlaps(p)
    local l1, r1 = self.x - self.w * 0.5, self.x + self.w * 0.5
    local t1, b1 = self.y - self.h, self.y
    local l2, r2 = p.x - p.w * 0.5, p.x + p.w * 0.5
    local t2, b2 = p.y - p.h, p.y
    return l1 < r2 and r1 > l2 and t1 < b2 and b1 > t2
end

-- 矿虫：看见就直线冲，撞墙或到悬崖边就换向
function Mob:aiCrawler(world, p, dx, dy, dist, aware, dt)
    if aware then
        self.facing = dx > 0 and 1 or -1
        self.dir = self.facing
        self.vx = self.facing * self.speed * self.chase
        self.anim = "run"
    else
        self.vx = self.dir * self.speed * 0.55
        self.anim = "run"
    end

    if self.hitWall then
        self.dir = -self.dir
        self.facing = self.dir
        self.vx = self.dir * self.speed * 0.6
    elseif self.onGround and not self:groundAhead(world) then
        -- 前方是空的：巡逻时掉头；追人时直接跳下去（追击比保命重要）
        if aware then
            self.vy = -260
        else
            self.dir = -self.dir
            self.facing = self.dir
        end
    end
end

-- 洞穴蝠：无重力，正弦摆动地扑过来
function Mob:aiFlyer(world, p, dx, dy, dist, aware, dt)
    if aware then
        self.facing = dx > 0 and 1 or -1
        local tx = p.x - self.facing * 6
        local ty = (p.y - p.h * 0.5) - 10
        local k = 3.2
        self.vx = (tx - self.x) * k
        self.vy = (ty - self.y) * k
        -- 正弦扰动：纯直线追踪太容易被预判，加了摆动才有「躲不开」的错觉
        self.vy = self.vy + math.sin(self.animT * 6) * 42
        local sp = math.sqrt(self.vx ^ 2 + self.vy ^ 2)
        local max = self.speed * self.chase
        if sp > max and sp > 0 then
            self.vx = self.vx / sp * max
            self.vy = self.vy / sp * max
        end
        self.anim = "idle"
    else
        self.vx = self.vx * 0.94
        self.vy = self.vy * 0.94 + math.sin(self.animT * 2.2) * 6
        self.anim = "idle"
    end

    -- 不穿墙：撞到就反弹一下，避免卡在岩层里抽搐
    if Physics.hits(world, self.x + self.vx * dt, self.y, self.w, self.h) then
        self.vx = -self.vx * 0.5
    end
    if Physics.hits(world, self.x, self.y + self.vy * dt, self.w, self.h) then
        self.vy = -self.vy * 0.5
    end
end

-- 腐化爬行者：站桩喷毒。它不追人，逼玩家主动清掉
function Mob:aiBlob(game, world, p, dx, dy, dist, aware, dt)
    self.facing = dx > 0 and 1 or -1
    self.anim = "idle"
    self.vx = self.vx * 0.9

    if aware and dist < self.shootRange then
        self.shootTimer = self.shootTimer - dt
        if self.shootTimer <= 0 then
            self.shootTimer = self.shootCd
            local cx, cy = self:center()
            local tx, ty = p.x, p.y - p.h * 0.5
            local ax, ay = tx - cx, ty - cy
            local len = math.sqrt(ax * ax + ay * ay)
            if len > 1 then
                ax, ay = ax / len, ay / len
                game:spawnProjectile({
                    x = cx, y = cy, vx = ax * 190, vy = ay * 190 - 30,
                    dmg = self.dmg, kind = "venom", life = 3.0,
                })
            end
        end
    end
end

-- 石傀儡：慢、硬、伤害高。撞到墙会跳一下，避免被一格台阶卡住
function Mob:aiGolem(world, p, dx, dy, dist, aware, dt)
    if aware and math.abs(dy) < 60 then
        self.facing = dx > 0 and 1 or -1
        self.vx = self.facing * self.speed * self.chase
        self.anim = "run"
        if self.hitWall and self.onGround then
            self.vy = -330
        end
    else
        self.vx = self.vx * 0.9
        self.anim = "idle"
    end
end

return Mob
