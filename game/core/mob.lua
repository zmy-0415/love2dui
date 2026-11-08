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

    ---- M2：精英词缀 ----

    M1 只有一条「爆裂」，因为要先把「词缀能改变战斗行为」这件事验证掉。
    M2 扩到五条，选词缀的标准是**每条都要让玩家改一次打法**，而不是改数值：

        爆裂  死了炸一圈       → 砍死它的瞬间要后撤，所以「补刀顺序」变了
        迅捷  移速 ×1.55       → 追不上，只能提前站位或用霜蚀
        铁壁  韧性 ×2.6        → 剑砍不出硬直，必须换斧/锤
        再生  每秒回 2% 血     → 打不快就白打，逼玩家放弃消耗战
        分裂  死了变两只小的   → 单体武器打不完，只能换镰刀或远程

    五条里没有一条是「+20% 血量」。那种词缀玩家根本看不出来，
    只会觉得「这只怎么特别肉」，然后开始怀疑数值而不是调整打法。
]]

local Physics = require("game.core.physics")
local World = require("game.core.world")
local Status = require("game.core.status")

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

--[[
    五条精英词缀。字段全部是「行为参数」，没有一条直接加伤害——
    加伤害的词缀只会让怪更烦，加行为的词缀才让玩家换招。
]]
Mob.AFFIX = {
    burst = {
        name = "爆裂",
        hpMul = 2.2, dmgMul = 1.25, scaleMul = 1.3, poiseMul = 1.6,
        radius = 74,          -- 死亡爆炸半径
        desc = "死亡时炸一圈",
    },
    swift = {
        name = "迅捷",
        hpMul = 1.5, dmgMul = 1.1, scaleMul = 1.05, poiseMul = 1.0,
        speedMul = 1.55, chaseMul = 1.25,
        desc = "移速翻半，追不上",
    },
    iron = {
        name = "铁壁",
        hpMul = 2.0, dmgMul = 1.15, scaleMul = 1.3, poiseMul = 2.6,
        knockResist = 0.35,   -- 击退只剩 35%
        desc = "韧性极高，剑砍不出硬直",
    },
    regen = {
        name = "再生",
        hpMul = 1.8, dmgMul = 1.1, scaleMul = 1.15, poiseMul = 1.2,
        regen = 0.02,         -- 每秒回 2% 最大血
        desc = "每秒回 2% 血，拖着打就白打",
    },
    split = {
        name = "分裂",
        hpMul = 1.6, dmgMul = 1.0, scaleMul = 1.2, poiseMul = 1.0,
        splitInto = 2,
        desc = "死亡时分裂成两只小的",
    },
}

-- 顺序固定，供确定性抽取
Mob.AFFIX_ORDER = { "burst", "swift", "iron", "regen", "split" }

Mob.ELITE_SCALE = 1.3
Mob.ELITE_HP = 2.2

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
    self.affix = nil
    self.deathHandled = false
    self.spdMul = 1

    -- 精英：M1 只有一条「爆裂」，M2 扩到五条
    local affixId = opts.affix
    if not affixId and opts.elite then affixId = "burst" end
    if affixId then
        local A = Mob.AFFIX[affixId]
        if A then
            self.elite = true
            self.affix = affixId
            self.hp = self.hp * (A.hpMul or Mob.ELITE_HP)
            self.maxHp = self.hp
            self.dmg = self.dmg * (A.dmgMul or 1.2)
            self.scale = self.scale * (A.scaleMul or Mob.ELITE_SCALE)
            self.poiseMax = self.poiseMax * (A.poiseMul or 1.5)
            self.poise = self.poiseMax
            if A.speedMul then self.speed = self.speed * A.speedMul end
            if A.chaseMul then self.chase = self.chase * A.chaseMul end
            self.knockResist = A.knockResist or 0
            self.regen = A.regen or 0
            self.barW = 32
            self.barY = 38
        end
    end

    -- 分裂出来的小怪：不再分裂，体型和血量都缩一圈
    if opts.small then
        self.elite = false
        self.affix = nil
        self.hp = self.hp * 0.35
        self.maxHp = self.hp
        self.dmg = self.dmg * 0.7
        self.scale = self.scale * 0.68
        self.noSplit = true
        self.barW = 18
    end

    return self
end

function Mob:center()
    return self.x, self.y - self.h * 0.5
end

function Mob:alive()
    return not self.dead
end

--[[
    受击。poise 归零会硬直——这是「斧比剑重」能成立的地方：
    剑砍傀儡几乎打不出硬直，斧能，所以打高韧性目标必须换武器

    易伤（雷痕）在这里消耗，而不是在 Combat 里，是为了让**所有**伤害来源
    都吃这个加成：爆炸、掉落、Boss 的溅射都算。
    只在玩家挥砍里生效的话，玩家会发现「雷芯配爆炸没反应」。
]]
function Mob:hurt(dmg, dir, poise)
    if self.dead then return end

    -- 雷痕：+30%，一次性
    local vuln = Status.vulnMul(self)
    if vuln ~= 1 then
        dmg = dmg * vuln
        Status.consumeShock(self)
    end

    self.hp = self.hp - dmg
    self.hurtFlash = 0.14
    self.poise = self.poise - (poise or 0)
    if self.poise <= 0 then
        self.poise = self.poiseMax
        self.stagger = 0.45
    end

    local k = 1 - (self.knockResist or 0)
    self.vx = (dir or 1) * 55 * k
    if not self.gravity then self.vy = (dir or 1) * 20 * k end

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

    -- 元素状态：DoT / 减速。DoT 直接改 hp，不走 hurt（否则每跳都击退）
    if self.status then
        local before = self.hp
        Status.update(self, dt)
        if not self.dead and self.hp <= 0 then
            self.hp = 0
            self.dead = true
            self.deadT = 0
            self.anim = "dead"
        end
        -- 受 DoT 时闪一下，让「烧着了」这件事在视觉上有落点
        if self.hp < before then self.hurtFlash = math.max(self.hurtFlash, 0.06) end
    end
    -- 霜蚀减速
    self.spdMul = Status.speedMul(self)

    if self.dead then
        self.deadT = self.deadT + dt
        self.vx = self.vx * 0.9
        if self.gravity then self:walk(world, dt) else
            self.x = self.x + self.vx * dt
        end
        return
    end

    -- 再生：只回血不复活，所以它逼玩家「打快一点」而不是「不打」
    if self.regen and self.regen > 0 and self.hp < self.maxHp then
        self.hp = math.min(self.maxHp, self.hp + self.maxHp * self.regen * dt)
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
    local spd = self.speed * self.spdMul
    if aware then
        self.facing = dx > 0 and 1 or -1
        self.dir = self.facing
        self.vx = self.facing * spd * self.chase
        self.anim = "run"
    else
        self.vx = self.dir * spd * 0.55
        self.anim = "run"
    end

    if self.hitWall then
        self.dir = -self.dir
        self.facing = self.dir
        self.vx = self.dir * spd * 0.6
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
        local max = self.speed * self.chase * self.spdMul
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
                    dmg = self.dmg, kind = "venom", life = 3.0, hostile = true,
                })
            end
        end
    end
end

-- 石傀儡：慢、硬、伤害高。撞到墙会跳一下，避免被一格台阶卡住
function Mob:aiGolem(world, p, dx, dy, dist, aware, dt)
    if aware and math.abs(dy) < 60 then
        self.facing = dx > 0 and 1 or -1
        self.vx = self.facing * self.speed * self.chase * self.spdMul
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
