--[[
    game/game.lua —— 游戏主体

    把世界、玩家、相机、掉落、背包串起来，对外只暴露 new / update / draw。
    输入是一张普通的表，不读键盘也不读鼠标——这样同一个 update 可以被三种东西驱动：
    真机的 love 回调、无头测试里的脚本输入、以后录像回放的输入流。
    这个约束一旦破了，任何玩法改动都没法回归测试。

    绘制同理：g 既可以是 love.graphics，也可以是 tools/softraster。
    两边只要求 setColor / rectangle / circle / push / pop / translate / scale 这些。
]]

local World = require("game.core.world")
local Player = require("game.core.player")
local Camera = require("game.core.camera")
local Inv = require("game.core.inventory")
local Tiles = require("game.core.tiles")
local Physics = require("game.core.physics")
local WR = require("game.render.world")
local ER = require("game.render.entities")
local Weapon = require("game.art.weapon")
local Weapons = require("game.data.weapons")
local Mob = require("game.core.mob")
local Combat = require("game.core.combat")
local Boss = require("game.core.boss")
local Recipes = require("game.data.recipes")
local Forge = require("game.core.forge")
local Parts = require("game.data.parts")
local Status = require("game.core.status")
local Save = require("game.core.save")

local Game = {}
Game.__index = Game

local T = World.TILE

-- 开局武器：木柄 + 铜刃 + 无芯。为什么不是直接给铁：
-- 玩家得先感觉到「铜剑砍石傀儡很吃力」，才会去挖铁，
-- 也才会理解「斧的破韧」为什么值得为它花材料
local START_SPEC = {
    class = "sword",
    bladeMat = "copper", bladeTier = 1,
    hilt = "wood", hiltMat = "wood", hiltTier = 1,
    core = "none", coreMat = "crystal", coreTier = 0,
    affixes = {},
    seed = 1,
}

-- 掉落物配色：跟方块/矿的颜色走，捡的时候一眼知道是什么
local DROP_COL = {
    copper = { 0.72, 0.47, 0.24 },
    iron = { 0.62, 0.67, 0.74 },
    crystal = { 0.31, 0.77, 0.87 },
    dirt = { 0.42, 0.31, 0.20 },
    stone = { 0.36, 0.39, 0.44 },
    wood = { 0.42, 0.27, 0.15 },
    fiber = { 0.28, 0.45, 0.24 },
    -- 怪物材料
    chitin = { 0.55, 0.35, 0.29 },
    membrane = { 0.42, 0.34, 0.52 },
    bile = { 0.50, 0.68, 0.30 },
    core_stone = { 0.48, 0.50, 0.55 },
}

-- 方块掉落成什么物品
local function dropOf(id)
    local def = Tiles.get(id)
    return def.drop
end

function Game.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Game)
    self.vw = opts.w or 1280
    self.vh = opts.h or 720
    self.world = World.new(opts.mapW or 200, opts.mapH or 120, opts.seed or 20261108)
    local spawn = self.world:generate()
    self.player = Player.spawnAt(spawn)
    self.cam = Camera.new(self.vw, self.vh)
    self.cam:snap(self.player.x, self.player.y - self.player.h * 0.5, self.world)
    self.inv = Inv.new(40)
    self.drops = {}
    self.mobs = {}
    self.projectiles = {}
    self.particles = {}
    self.time = 0
    self.shakeAmount = 0
    -- hitstop：命中瞬间把世界时间压到 6%，持续 40~80ms。
    -- 这是打击感里性价比最高的一层，比任何特效都有效
    self.hitStopT = 0
    self.prevDig = false
    self.holdTime = 0
    self.spawnTimer = 2.0
    self.kills = 0
    -- 锻造计数：决定「第几次重铸」，也参与词条种子的推导
    self.forgeCount = 0
    -- 瞄准点（世界坐标），弓用它决定箭的方向。默认朝面朝方向
    self.aim = { x = self.player.x + 100, y = self.player.y - 20 }
    -- 调试/测试用：累计挖掘数与拾取数，用来断言流程真的走通了
    self.stats = { dug = 0, picked = 0, placed = 0, crafted = 0, forged = 0 }

    -- 初始装备。走和锻造完全相同的 equip 路径，
    -- 这样「开局武器」和「锻出来的武器」不会有第二条代码分支
    self:equip(START_SPEC)

    if opts.save then
        self:applySave(opts.save)
    end
    return self
end

--[[
    换武器。这是唯一的入口——开局、锻造、读档都走这里。

    为什么要有这个统一入口：M1 里「初始化」「合成」「读档」三处
    各自写了一遍「设 spec + 重建外观 + 设 attackKind」，加一个字段就要改三处，
    漏一处就会出现「读档后武器变成木剑但伤害还是铁的」这种鬼问题。
]]
function Game:equip(spec)
    self.weaponSpec = spec
    self.resolved = Weapons.resolve(spec)
    local p = self.player
    p.weapon = Weapon.build(spec)
    -- 攻击进行中换武器：直接结束当前这一刀，避免用旧数值结算完再换
    p.attackT = 0
    p.attack = self.resolved
    -- 镐跟着刃升级：否则玩家打到铁却挖不动晶簇，
    -- 会被迫在「换武器」和「换镐」之间二选一，这不是我想让玩家纠结的地方
    local bt = spec.bladeTier or 1
    if bt > (p.pick.tier or 1) then
        p.pick.tier = bt
        p.pick.eff = 1.0 + (bt - 1) * 0.45
    end
    return self.resolved
end

function Game:resize(w, h)
    self.vw, self.vh = w, h
    self.cam:resize(w, h)
    self.cam:clampTo(self.world)
end

-- 鼠标屏幕坐标 → 世界坐标
function Game:mouseWorld(mx, my)
    return mx + self.cam.x, my + self.cam.y
end

function Game:tileUnderMouse(mx, my)
    local wx, wy = self:mouseWorld(mx, my)
    return math.floor(wx / T), math.floor(wy / T)
end

-- ---------------------------------------------------------------- 掉落
function Game:spawnDrop(key, tx, ty, n)
    if not key then return end
    local d = {
        key = key,
        n = n or 1,
        x = (tx + 0.5) * T,
        y = (ty + 0.5) * T,
        vy = -80,
        t = 0,
        col = DROP_COL[key] or { 0.8, 0.8, 0.85 },
        settle = 0,
    }
    self.drops[#self.drops + 1] = d
    return d
end

function Game:updateDrops(dt)
    local p = self.player
    local keep = {}
    for i = 1, #self.drops do
        local d = self.drops[i]
        d.t = d.t + dt

        -- 简易落地：只在有空间时下落，落地就停。
        -- 不做完整刚体是刻意的——掉落物不需要在台阶上滑，只要看起来自然
        if d.settle <= 0 then
            d.vy = math.min(620, d.vy + 900 * dt)
            local ny = d.y + d.vy * dt
            if self.world:solidAtPixel(d.x, ny + 3) then
                local ty = math.floor((ny + 3) / T)
                d.y = ty * T - 3
                d.vy = 0
                d.settle = 1
            else
                d.y = ny
            end
        end

        -- 拾取：靠近就吸，入包失败（装不下）就留在地上
        local dx, dy = p.x - d.x, (p.y - p.h * 0.5) - d.y
        local dist2 = dx * dx + dy * dy
        if dist2 < 42 * 42 then
            -- 吸附：越近越快，避免「飘过去」的手感
            local k = 1 - math.exp(-12 * dt)
            d.x = d.x + dx * k
            d.y = d.y + dy * k
            if dist2 < 14 * 14 then
                local left = self.inv:add(d.key, d.n)
                if left <= 0 then
                    self.stats.picked = self.stats.picked + 1
                    d.picked = true
                else
                    d.n = left
                end
            end
        end

        if not d.picked then keep[#keep + 1] = d end
    end
    self.drops = keep
end

-- ---------------------------------------------------------------- 挖 / 放
function Game:tryDig(mx, my, holding, dt)
    local p = self.player
    if not holding then
        self.player.digging = false
        if self.player.digTarget then
            self.world:relaxDamage(self.player.digTarget.x, self.player.digTarget.y, dt)
        end
        return
    end
    local tx, ty = self:tileUnderMouse(mx, my)
    local broke, id = p:dig(self.world, tx, ty, dt, true)
    if broke then
        self.stats.dug = self.stats.dug + 1
        self:spawnDrop(dropOf(id), tx, ty, 1)
        -- 挖到矿核：Boss 被唤醒。这是玩家自己按下的开关，不是走进区域被动触发，
        -- 所以「被 Boss 打死」不会让人觉得莫名其妙
        if Tiles.get(id).key == "ore_core" then
            self:summonBoss()
        end
        -- 挖穿后必须清掉准星目标，否则准星会停在一格空气上继续框着
        self.player.digTarget = nil
        -- 挖掉方块后，地面上的草木失去支撑。M1 先不做连锁，只提醒这里该有
    end
end

function Game:tryPlace(mx, my, itemKey)
    local p = self.player
    local tx, ty = self:tileUnderMouse(mx, my)
    if not itemKey then return false end
    local def = Tiles.byKey[itemKey]
    if not def or def.bg then return false end
    if not p:canPlace(self.world, tx, ty) then return false end
    if self.inv:count(itemKey) <= 0 then return false end
    self.world:set(tx, ty, def.id)
    self.inv:take(itemKey, 1)
    self.stats.placed = self.stats.placed + 1
    return true
end

-- ---------------------------------------------------------------- 反馈
function Game:hitStop(d)
    self.hitStopT = math.max(self.hitStopT, d)
end

function Game:spawnParticles(x, y, n, opt)
    opt = opt or {}
    local spread = opt.spread or 120
    local col = opt.col or { 0.95, 0.85, 0.6 }
    for i = 1, n do
        -- 用确定性的伪随机：同一个命中在回放里会得到同样的火花，便于录屏对拍
        local a = (i * 2.399963) % (math.pi * 2)
        local sp = spread * (0.35 + ((i * 0.618) % 1) * 0.65)
        self.particles[#self.particles + 1] = {
            x = x, y = y,
            vx = math.cos(a) * sp + (opt.vx or 0),
            vy = math.sin(a) * sp - 40 + (opt.vy or 0),
            life = opt.life or 0.32,
            t = 0,
            col = col,
            size = opt.size or 2,
            grav = opt.grav or 620,
        }
    end
end

function Game:spawnProjectile(t)
    self.projectiles[#self.projectiles + 1] = {
        x = t.x, y = t.y, vx = t.vx, vy = t.vy,
        dmg = t.dmg or 8,
        kind = t.kind or "venom",
        life = t.life or 3,
        t = 0,
        -- hostile = true 表示「从怪飞向玩家」。默认 true 是为了兼容 M1 的毒液，
        -- 玩家的箭显式传 false
        hostile = (t.hostile ~= false),
        element = t.element,
        elementLv = t.elementLv,
        poise = t.poise or 0,
        hitSet = {},
    }
end

--[[
    放一箭。

    方向朝鼠标，不是朝面朝方向——这是弓和所有近战最根本的区别：
    近战问「我面向哪」，远程问「我要打哪」。
    如果箭也朝面朝方向，弓就退化成「射程很长的剑」，玩家只需要站桩按左键。

    起点往前挪 10 像素，避免箭一出生就撞在自己脚下那一格里。
]]
function Game:fireArrow(p, w)
    local dir = p.facing or 1
    local cx = p.x + dir * 10
    local cy = p.y - p.h * 0.55
    local ax, ay = self.aim.x - cx, self.aim.y - cy
    local len = math.sqrt(ax * ax + ay * ay)
    if len < 1 then
        ax, ay = dir, 0
    else
        ax, ay = ax / len, ay / len
    end
    -- 箭会比视觉略快一点，否则玩家看着箭慢慢飘过去，会提前走开
    local sp = w.ranged or 500
    self:spawnProjectile({
        x = cx, y = cy,
        vx = ax * sp, vy = ay * sp,
        dmg = w.damage,
        kind = "arrow",
        life = 1.6,
        hostile = false,
        element = w.element,
        elementLv = w.elementLv,
        poise = w.poise,
    })
    self:spawnParticles(cx, cy, 3, {
        col = { 0.85, 0.80, 0.60 }, spread = 40, life = 0.16, size = 1,
    })
end

function Game:onBossHit(b, dmg, res, weak)
    local cx, cy = b:center()
    self:spawnParticles(cx, cy, weak and 14 or 8, {
        col = weak and { 1.0, 0.85, 0.45 } or { 1.0, 0.70, 0.45 },
        spread = weak and 260 or 160,
        life = weak and 0.4 or 0.28,
        size = weak and 3 or 2,
    })
    if weak then
        self.cam:kick(3.5, 0.2)
        self:hitStop(0.04)
    end
    if res == "interrupt" then
        self.cam:kick(7, 0.4)
        self:hitStop(0.09)
    elseif res == "kill" then
        self.cam:kick(11, 0.8)
        self:hitStop(0.14)
        self:spawnParticles(cx, cy, 48, {
            col = { 1.0, 0.75, 0.45 }, spread = 380, life = 0.9, size = 3,
        })
        self.bossDefeated = true
    end
end

--[[
    一次命中的视觉后果。

    注意这里**不再处理死亡**（掉落、精英爆炸、计数都挪到 onMobDeath 了）。
    原因是 M2 加了元素 DoT：一只被点燃的怪可能在自己回合里烧死，
    那条路径根本不经过 onHit。如果死亡逻辑只写在 onHit 里，
    玩家会发现「烧死的怪不掉东西」——而玩家几乎一定会用燃烧磨血。
]]
function Game:onHit(m, dmg, dir, def, crit)
    local cx, cy = m:center()
    self:spawnParticles(cx, cy, crit and 12 or 7, {
        col = crit and { 1.0, 0.92, 0.60 } or { 1.0, 0.78, 0.45 },
        spread = crit and 210 or 150,
        vx = dir * 60,
        life = crit and 0.34 or 0.28,
        size = crit and 3 or 2,
    })
    if crit then
        self.cam:kick(2.6, 0.14)
    end
end

--[[
    怪物死亡的唯一出口。不管是被砍死、被烧死、被毒死、被爆炸炸死，
    都从这里走，所以「掉落」和「精英词缀」只需要写一遍。

    deathHandled 标志是必需的：updateMobs 每帧都会看到 dead=true 的怪，
    没有这个标志就会每帧掉一次材料、每帧炸一圈。
]]
function Game:onMobDeath(m)
    if m.deathHandled then return end
    m.deathHandled = true
    self.kills = self.kills + 1

    local cx, cy = m:center()
    self:spawnParticles(cx, cy, 14, {
        col = { 0.85, 0.55, 0.35 }, spread = 190, life = 0.5, size = 3,
    })

    -- 掉落：不同怪给不同材料。M2 的锻造线同时吃方块材料和怪物材料
    local dropKey = ({
        crawler = "chitin", flyer = "membrane", blob = "bile", golem = "core_stone",
    })[m.type]
    if dropKey then
        self:spawnDrop(dropKey, m.x / T, (m.y - 4) / T, 1)
        -- 精英掉两份：这是「值得打」的唯一理由，
        -- 如果精英和普通怪掉一样多，玩家会绕开它们
        if m.elite then
            self:spawnDrop(dropKey, m.x / T, (m.y - 8) / T, 2)
        end
    end

    if m.affix == "burst" then
        self:eliteExplode(m)
    elseif m.affix == "split" then
        self:eliteSplit(m)
    end

    -- 收割词条：击杀回血。放在这里而不是 onHit，理由同上——烧死也该回血
    local w = self.resolved
    if w and w.killHeal then
        self.player:heal(w.killHeal)
    end
end

-- 精英「分裂」：死亡时变两只小的。
-- 这条词缀专门惩罚单体武器：一锤砸死一只变成两只，玩家会后悔没用镰刀
function Game:eliteSplit(m)
    if m.noSplit then return end
    local n = Mob.AFFIX.split.splitInto or 2
    for i = 1, n do
        local off = (i == 1) and -14 or 14
        local child = Mob.new(m.type, m.x + off, m.y, { small = true })
        child.facing = (i == 1) and -1 or 1
        self.mobs[#self.mobs + 1] = child
    end
    self.cam:kick(3, 0.22)
    self:spawnParticles(m.x, m.y - m.h * 0.5, 16, {
        col = { 0.75, 0.55, 0.85 }, spread = 180, life = 0.42, size = 2,
    })
end

-- 精英「爆裂」：死亡时炸一圈。伤害不高，但能逼玩家在砍死它的瞬间后撤，
-- 于是「先杀精英」这件事有了额外代价，不再是无脑选择
function Game:eliteExplode(m)
    local cx, cy = m:center()
    m.burst = 0.28
    self:spawnParticles(cx, cy, 26, {
        col = { 1.0, 0.45, 0.25 }, spread = 300, life = 0.55, size = 3,
    })
    self.cam:kick(6, 0.35)
    local p = self.player
    local dx, dy = p.x - cx, (p.y - p.h * 0.5) - cy
    if dx * dx + dy * dy < 74 * 74 then
        p:hurt(math.floor(m.dmg * 0.9), (p.x > cx) and 1 or -1)
    end
    for i = 1, #self.mobs do
        local o = self.mobs[i]
        if o ~= m and o:alive() then
            local ox, oy = o:center()
            if (ox - cx) ^ 2 + (oy - cy) ^ 2 < 74 * 74 then
                o:hurt(m.dmg * 0.6, (ox > cx) and 1 or -1, 20)
            end
        end
    end
end

-- ---------------------------------------------------------------- 投射物 / 粒子
function Game:updateProjectiles(dt)
    local p = self.player
    local keep = {}
    for i = 1, #self.projectiles do
        local pr = self.projectiles[i]
        pr.t = pr.t + dt
        -- 箭走平射（重力 90），毒液走抛物线（240）。这个差别是给玩家看的：
        -- 一眼就能判断「这团东西是冲我来的」还是「我刚射出去的」
        local isArrow = (pr.kind == "arrow")
        pr.vy = pr.vy + (isArrow and 90 or 240) * dt
        local nx = pr.x + pr.vx * dt
        local ny = pr.y + pr.vy * dt
        local dead = false

        if pr.t > pr.life then dead = true end
        if self.world:solidAtPixel(nx, ny) then
            dead = true
            local col = isArrow and { 0.72, 0.70, 0.58 } or { 0.55, 0.75, 0.3 }
            self:spawnParticles(nx, ny, 5, { col = col, spread = 70, life = 0.24 })
        end

        if not dead and pr.hostile then
            -- 命中玩家
            if not p.dead then
                local dx, dy = nx - p.x, ny - (p.y - p.h * 0.5)
                if dx * dx + dy * dy < 12 * 12 then
                    if p:hurt(pr.dmg, (p.x > nx) and 1 or -1) then
                        dead = true
                        self:hitStop(0.04)
                        self.cam:kick(2, 0.16)
                        self:spawnParticles(nx, ny, 8, { col = { 0.6, 0.85, 0.35 }, spread = 110 })
                    end
                end
            end

        elseif not dead then
            -- 玩家的箭：打怪、打 Boss。用「点 vs 矩形外扩 4px」而不是圆，
            -- 因为箭是一根细长的东西，用圆判定会让它「擦着翅膀过去却没中」
            local hit = nil
            for j = 1, #self.mobs do
                local m = self.mobs[j]
                if m:alive() and not pr.hitSet[m] then
                    if nx > m.x - m.w * 0.5 - 4 and nx < m.x + m.w * 0.5 + 4
                        and ny > m.y - m.h - 4 and ny < m.y + 4 then
                        hit = m
                        break
                    end
                end
            end
            if hit then
                pr.hitSet[hit] = true
                dead = true
                local dir = (hit.x >= nx) and 1 or -1
                hit:hurt(pr.dmg, dir, pr.poise)
                if pr.element then Status.apply(hit, pr.element, pr.elementLv) end
                if self.resolved and self.resolved.leech and self.resolved.leech > 0 and not p.dead then
                    p:heal(self.resolved.leech)
                end
                self:hitStop(0.03)
                self.cam:kick(1.4, 0.12)
                self:onHit(hit, pr.dmg, dir, self.resolved, false)
            else
                local b = self.boss
                if b and b:alive() and not b.underground and not pr.hitSet.boss then
                    local bx0, by0, bx1, by1 = b:hitbox()
                    if nx > bx0 and nx < bx1 and ny > by0 and ny < by1 then
                        pr.hitSet.boss = true
                        dead = true
                        local res = b:hurt(pr.dmg, (b.x >= nx) and 1 or -1, pr.poise, false)
                        if pr.element then Status.apply(b, pr.element, pr.elementLv) end
                        self:onBossHit(b, pr.dmg, res, false)
                    end
                end
            end
        end

        pr.x, pr.y = nx, ny
        if not dead then keep[#keep + 1] = pr end
    end
    self.projectiles = keep
end

function Game:updateParticles(dt)
    local keep = {}
    for i = 1, #self.particles do
        local q = self.particles[i]
        q.t = q.t + dt
        if q.t < q.life then
            q.vy = q.vy + q.grav * dt
            q.vx = q.vx * (1 - 2.2 * dt)
            q.x = q.x + q.vx * dt
            q.y = q.y + q.vy * dt
            keep[#keep + 1] = q
        end
    end
    self.particles = keep
end

-- ---------------------------------------------------------------- 怪物
function Game:updateMobs(dt)
    -- 记下进入这一帧时的数量：循环里可能因为「分裂」而往 self.mobs 追加新怪，
    -- 边遍历边追加会让 #self.mobs 在循环中途变化，行为不可预测。
    -- 先处理旧的一批，结束后再把新生的接回来
    local n = #self.mobs
    local keep = {}
    for i = 1, n do
        local m = self.mobs[i]
        m:update(self, dt)
        if m.dead then self:onMobDeath(m) end
        -- 死透了（尸体动画播完）才移除
        local gone = m.dead and m.deadT > 0.55
        -- 掉出世界或离玩家太远的怪直接回收，防止越积越多
        local dx = m.x - self.player.x
        local dy = m.y - self.player.y
        if dx * dx + dy * dy > 2400 * 2400 then gone = true end
        if not gone then keep[#keep + 1] = m end
    end
    for i = n + 1, #self.mobs do
        keep[#keep + 1] = self.mobs[i]
    end
    self.mobs = keep
end

-- 刷怪：M1 用最简单的规则——固定间隔，在玩家两侧屏幕外找地面生成。
-- 设计文档里的「自然方块权重 / 同屏上限 / 距离限制」是 M2 的事，
-- 现在只需要「有怪可打」，不要提前把规则做复杂
function Game:trySpawn(dt)
    if #self.mobs >= 7 then return end
    self.spawnTimer = self.spawnTimer - dt
    if self.spawnTimer > 0 then return end
    self.spawnTimer = 2.6 + (self.time % 1.4)

    local p = self.player
    local side = (math.floor(self.time * 3) % 2 == 0) and 1 or -1
    local dist = 380 + (self.time * 37) % 160
    local sx = p.x + side * dist
    local tx = math.floor(sx / T)
    if tx < 2 or tx >= self.world.w - 2 then return end

    local gy = Physics.groundBelow(self.world, sx, p.y - 120, 60)
    if not gy then return end
    -- 不在玩家脚下生成：突然在背后冒出来是最廉价也最招人烦的偷袭
    if math.abs(gy - p.y) > 260 then return end

    local depth = gy / T
    local roll = (self.time * 0.37) % 1
    local kind
    if depth < 40 then
        kind = roll < 0.5 and "crawler" or "flyer"
    elseif depth < 75 then
        kind = roll < 0.34 and "crawler" or (roll < 0.66 and "flyer" or "blob")
    else
        kind = roll < 0.28 and "crawler" or (roll < 0.52 and "blob" or (roll < 0.8 and "golem" or "flyer"))
    end
    -- 精英：10% 概率，只在中深层出现。
    -- 词缀按时间做确定性轮换，所以同一局里不会一直是「爆裂」——
    -- 玩家打久了会依次遇到五种，从而学会五种应对方式
    local opts = {}
    if depth > 45 and ((self.time * 13) % 1) < 0.10 then
        local idx = 1 + math.floor((self.time * 7919) % #Mob.AFFIX_ORDER)
        opts.affix = Mob.AFFIX_ORDER[idx]
    end
    self.mobs[#self.mobs + 1] = Mob.new(kind, sx, gy, opts)
end

-- ---------------------------------------------------------------- 合成 / 锻造

--- 消耗品配方（口粮之类）。武器不再走这里——它们走 forge。
-- 成功返回 true, nil；失败返回 false, 原因
function Game:craft(id)
    local r = Recipes.get(id)
    if not r then return false, "未知配方" end
    if not Recipes.canCraft(r, self.inv) then
        return false, "材料不足：" .. Recipes.missing(r, self.inv)
    end
    -- 先扣材料再做效果。反过来的话，如果效果失败材料就白扣了
    for key, n in pairs(r.cost) do
        self.inv:take(key, n)
    end

    local e = r.effect
    if e.kind == "heal" then
        self.player:heal(e.amount)
    elseif e.kind == "weapon" then
        -- 兼容旧配方：一条配方直接给一把武器，内部仍然走 equip
        self:equip({
            class = e.weapon, bladeMat = e.material, bladeTier = e.tier,
            hilt = "wood", hiltTier = e.tier, core = "none", coreTier = 0,
            affixes = {}, seed = 1,
        })
    end
    self.stats.crafted = (self.stats.crafted or 0) + 1
    return true
end

-- 当前能不能做，给 UI 用
function Game:canCraft(id)
    local r = Recipes.get(id)
    return r ~= nil and Recipes.canCraft(r, self.inv)
end

--[[
    锻造。spec = { class, bladeMat, hilt, core }，seed 可选（测试用）。
    返回 ok, err, affixes

    注意这是**重铸**也是「第一次造」——同一个接口。
    玩家想刷词条就再点一次，材料够就行。刻意不做「洗练石」之类的中间道具：
    多一层货币只会让「我再试一次」这个动作多一次犹豫。
]]
function Game:forge(spec, seed)
    return Forge.assemble(self, spec, seed)
end

-- 锻造预览（不消耗材料）
function Game:previewForge(spec)
    local r = Forge.preview(spec)
    r.canMake = Forge.canAssemble(spec, self.inv)
    r.missing = r.canMake and "" or Forge.missing(spec, self.inv)
    return r
end

-- ---------------------------------------------------------------- Boss
function Game:summonBoss()
    if self.boss then return end
    local p = self.player
    self.boss = Boss.new(p.x + 150, p.y)
    self.boss.y = p.y
    self.cam:kick(9, 0.7)
    self:hitStop(0.10)
    self:spawnParticles(p.x + 150, p.y - 20, 34, {
        col = { 0.85, 0.55, 0.40 }, spread = 300, life = 0.8, size = 3,
    })
end

-- 给 Boss 与事件用的生成接口：自动贴地
function Game:spawnMob(kind, x, y, opts)
    local gy = Physics.groundBelow(self.world, x, y - 24, 40) or y
    local m = Mob.new(kind, x, gy, opts)
    self.mobs[#self.mobs + 1] = m
    return m
end

-- ---------------------------------------------------------------- 存档
function Game:serialize()
    local p = self.player
    local inv = {}
    for i = 1, self.inv.size do
        local s = self.inv.slots[i]
        if s then inv[#inv + 1] = { s.key, s.n } end
    end
    return {
        v = Save.VERSION,
        seed = self.world.seed,
        mapW = self.world.w,
        mapH = self.world.h,
        player = {
            x = p.x, y = p.y, hp = p.hp, stamina = p.stamina, facing = p.facing,
            pickTier = p.pick.tier, pickEff = p.pick.eff,
        },
        weapon = self.weaponSpec,
        inv = inv,
        forgeCount = self.forgeCount,
        edits = self.world.edits,
        boss = self.boss and {
            hp = self.boss.hp, phase = self.boss.phase, defeated = self.bossDefeated,
            state = self.boss.state,
        } or nil,
        stats = self.stats,
    }
end

function Game:applySave(data)
    if not data or data.v ~= Save.VERSION then return false end
    self.world:applyEdits(data.edits)

    local p = self.player
    local pd = data.player or {}
    if pd.x and pd.y then
        p.x, p.y = pd.x, pd.y
        self.cam:snap(p.x, p.y - p.h * 0.5, self.world)
    end
    p.hp = pd.hp or p.hp
    p.stamina = pd.stamina or p.stamina
    p.facing = pd.facing or p.facing
    p.pick.tier = pd.pickTier or p.pick.tier
    p.pick.eff = pd.pickEff or p.pick.eff

    if data.weapon then
        self:equip(data.weapon)
    end

    if data.inv then
        self.inv = Inv.new(40)
        for _, pair in ipairs(data.inv) do
            if pair[1] then self.inv:add(pair[1], pair[2] or 1) end
        end
    end

    if data.stats then self.stats = data.stats end
    if data.forgeCount then self.forgeCount = data.forgeCount end

    if data.boss then
        self:summonBoss()
        if self.boss then
            self.boss.hp = data.boss.hp or self.boss.hp
            self.boss.phase = data.boss.phase or 1
            self.boss.state = data.boss.state or "burrow"
            if self.boss.phase >= 3 then
                self.boss.state = "split"
                self.boss.underground = false
            end
            if data.boss.defeated or self.boss.hp <= 0 then
                self.boss.dead = true
                self.boss.defeated = true
                self.bossDefeated = true
            end
        end
    end
    return true
end

function Game:save(slot)
    return Save.write(slot or "rift_save.lua", Save.encode(self:serialize()))
end

-- 有存档就载入，没有就新建。返回值第二个表示是否读了档
function Game.loadOrNew(opts, slot)
    slot = slot or "rift_save.lua"
    local text = Save.read(slot)
    local data = Save.decode(text)
    if data and data.v == Save.VERSION then
        local g = Game.new({
            w = opts.w, h = opts.h,
            seed = data.seed, mapW = data.mapW, mapH = data.mapH,
            save = data,
        })
        return g, true
    end
    return Game.new(opts), false
end

-- ---------------------------------------------------------------- 主循环
-- input 字段：
--   left/right/jump/jumpPressed  移动
--   dig     按住鼠标左键（短按攻击，长按挖掘）
--   place   放置（右键按下那一帧为 true）
--   mouseX/mouseY  屏幕坐标
--   placeItem      要放的物品 key（默认用背包第一个方块）
function Game:update(dt, input)
    input = input or {}
    -- 卡帧保护：窗口被拖动后 dt 可能是几秒，一帧走完全部物理会穿墙
    if dt > 0.1 then dt = 0.1 end
    self.time = self.time + dt

    -- hitstop：世界时间被压到 6%，但输入计时和相机抖动仍按真实时间走，
    -- 否则冻结期间玩家会感觉「按键没反应」
    local wdt = dt
    if self.hitStopT > 0 then
        self.hitStopT = self.hitStopT - dt
        wdt = dt * 0.06
    end

    local p = self.player
    local mx = input.mouseX or self.vw * 0.5
    local my = input.mouseY or self.vh * 0.5

    -- 左键承担两件事，靠「鼠标指着什么」来分：
    --   指着可挖方块 → 挖掘（按住即挖，不用先挥空一刀）
    --   指着空气/怪   → 朝面朝方向挥砍，按住就连续挥
    -- 之所以不按「按下/长按」分：挖矿时每格都先挥一刀太难玩。
    -- 但设计文档担心「战斗中把脚下挖崩」，所以真正有威胁的怪在附近时，
    -- 挖掘退回长按 0.30s——战斗中想改地形，得先脱离战斗节奏
    local digDown = input.dig and true or false
    self.prevDig = digDown
    if digDown then
        self.holdTime = self.holdTime + dt
    else
        self.holdTime = 0
    end

    local tx, ty = self:tileUnderMouse(mx, my)
    local reach = World.TILE * 4.2
    local ecx, ecy = p:center()
    local gx, gy = (tx + 0.5) * T, (ty + 0.5) * T
    local inReach = (gx - ecx) ^ 2 + (gy - ecy) ^ 2 <= reach * reach
    local aimMine = inReach and Tiles.canMine(self.world:get(tx, ty), p.pick.tier)

    -- 3 秒内有活怪贴近就算战斗状态
    local inCombat = false
    for i = 1, #self.mobs do
        local m = self.mobs[i]
        if m:alive() then
            local dx, dy = m.x - p.x, m.y - p.y
            if dx * dx + dy * dy < 260 * 260 then inCombat = true break end
        end
    end

    -- 瞄准点（世界坐标）。弓用它决定箭飞向哪，近战不用。
    -- 每帧都更新，而不是开火那一帧才读：这样切武器时准星不会「先指错一下」
    local awx, awy = self:mouseWorld(mx, my)
    self.aim.x, self.aim.y = awx, awy

    if digDown and not aimMine and p.attackT <= 0 and not p.dead then
        Combat.start(p, input.weapon or self.resolved)
    end

    local needHold = inCombat and 0.30 or 0
    local digging = digDown and aimMine and self.holdTime >= needHold

    p:update(self.world, {
        left = input.left,
        right = input.right,
        jump = input.jump,
        jumpPressed = input.jumpPressed,
    }, wdt)

    self:tryDig(mx, my, digging, wdt)

    Combat.update(self, wdt)

    if input.place then
        local item = input.placeItem
        if not item then
            for i = 1, self.inv.size do
                local s = self.inv.slots[i]
                if s then
                    local def = Tiles.byKey[s.key]
                    if def and not def.bg and def.solid then item = s.key break end
                end
            end
        end
        self:tryPlace(mx, my, item)
    end

    self:updateMobs(wdt)
    if self.boss then
        self.boss:update(self, wdt)
        -- 击败判定放在这里而不是命中回调里：不管是怎么死的（近战、爆炸、掉进岩浆）
        -- 都能收尾，避免只有某一条伤害路径能触发胜利
        if self.boss.dead and not self.bossDefeated then
            self.bossDefeated = true
        end
    end
    self:updateProjectiles(wdt)
    self:updateParticles(wdt)
    self:updateDrops(wdt)
    self:trySpawn(dt)

    -- 相机跟玩家的身体中心，不是脚底：跟脚底会让画面在跳跃时整体上下弹
    self.cam:follow(p.x, p.y - p.h * 0.5, self.world, dt)
    self.cam:updateShake(dt)
end

function Game:draw(g)
    local cam = {
        x = self.cam.x + self.cam:offsetX(),
        y = self.cam.y + self.cam:offsetY(),
        w = self.vw,
        h = self.vh,
    }
    WR.draw(g, self.world, cam)
    WR.drawGlow(g, self.world, cam)

    for i = 1, #self.drops do ER.drop(g, self.drops[i], cam) end
    if self.boss then ER.boss(g, self.boss, cam) end
    for i = 1, #self.mobs do ER.mob(g, self.mobs[i], cam) end
    ER.projectiles(g, self.projectiles, cam)
    ER.digCursor(g, self.player, self.world, cam)
    ER.player(g, self.player, cam)
    ER.particles(g, self.particles, cam)
    ER.bossBar(g, self)
end

return Game
