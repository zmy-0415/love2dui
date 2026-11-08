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
local Mob = require("game.core.mob")
local Combat = require("game.core.combat")
local Boss = require("game.core.boss")
local Recipes = require("game.data.recipes")
local Save = require("game.core.save")

local Game = {}
Game.__index = Game

local T = World.TILE

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
    -- 初始装备：铜剑。M1 的开局就该能打，先让玩家砍死第一只矿虫再谈别的
    self.weaponSpec = {
        class = "sword", bladeTier = 1, hiltTier = 1, coreTier = 1,
        bladeMat = "copper", hiltMat = "wood",
    }
    self.player.weapon = Weapon.build(self.weaponSpec)
    self.player.attackKind = "sword"
    self.player.attackMat = "copper"
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
    -- 调试/测试用：累计挖掘数与拾取数，用来断言流程真的走通了
    self.stats = { dug = 0, picked = 0, placed = 0 }

    if opts.save then
        self:applySave(opts.save)
    end
    return self
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
    }
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

-- 一次命中的全部后果：火花、掉落、精英爆炸
function Game:onHit(m, dmg, dir, def)
    local cx, cy = m:center()
    self:spawnParticles(cx, cy, 7, {
        col = { 1.0, 0.78, 0.45 },
        spread = 150,
        vx = dir * 60,
        life = 0.28,
    })

    if m.dead then
        self.kills = self.kills + 1
        self:spawnParticles(cx, cy, 14, {
            col = { 0.85, 0.55, 0.35 }, spread = 190, life = 0.5, size = 3,
        })
        -- 掉落：不同怪给不同材料。M1 的合成线就吃这几种
        local dropKey = ({
            crawler = "chitin", flyer = "membrane", blob = "bile", golem = "core_stone",
        })[m.type]
        if dropKey then
            self:spawnDrop(dropKey, m.x / T, (m.y - 4) / T, 1)
        end
        if m.elite then
            self:eliteExplode(m)
        end
    end
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
        pr.vy = pr.vy + 240 * dt
        local nx = pr.x + pr.vx * dt
        local ny = pr.y + pr.vy * dt
        local dead = false

        if pr.t > pr.life then dead = true end
        if self.world:solidAtPixel(nx, ny) then
            dead = true
            self:spawnParticles(nx, ny, 5, { col = { 0.55, 0.75, 0.3 }, spread = 70, life = 0.24 })
        end
        -- 命中玩家
        if not dead and not p.dead then
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
    local keep = {}
    for i = 1, #self.mobs do
        local m = self.mobs[i]
        m:update(self, dt)
        -- 死透了（尸体动画播完）才移除
        local gone = m.dead and m.deadT > 0.55
        -- 掉出世界或离玩家太远的怪直接回收，防止越积越多
        local dx = m.x - self.player.x
        local dy = m.y - self.player.y
        if dx * dx + dy * dy > 2400 * 2400 then gone = true end
        if not gone then keep[#keep + 1] = m end
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
    -- 精英：8% 概率，只在中深层出现
    local elite = depth > 45 and ((self.time * 13) % 1) < 0.08
    self.mobs[#self.mobs + 1] = Mob.new(kind, sx, gy, { elite = elite })
end

-- ---------------------------------------------------------------- 合成
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
    if e.kind == "weapon" then
        self.weaponSpec = {
            class = e.weapon, bladeTier = e.tier, hiltTier = e.tier, coreTier = e.tier,
            bladeMat = e.material, hiltMat = e.tier >= 2 and "iron" or "wood",
        }
        self.player.weapon = Weapon.build(self.weaponSpec)
        self.player.attackKind = e.weapon
        self.player.attackMat = e.material
        -- 换了更强的武器，镐也跟着升一级：否则玩家打到铁却挖不动晶簇，
        -- 会被迫在武器和工具之间二选一，这不是我想让玩家纠结的地方
        if e.tier > self.player.pick.tier then
            self.player.pick.tier = e.tier
            self.player.pick.eff = 1.0 + (e.tier - 1) * 0.45
        end
    elseif e.kind == "heal" then
        self.player:heal(e.amount)
    end
    self.stats.crafted = (self.stats.crafted or 0) + 1
    return true
end

-- 当前能不能做，给 UI 用
function Game:canCraft(id)
    local r = Recipes.get(id)
    return r ~= nil and Recipes.canCraft(r, self.inv)
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
        self.weaponSpec = data.weapon
        p.weapon = Weapon.build(self.weaponSpec)
        p.attackKind = self.weaponSpec.class
        p.attackMat = self.weaponSpec.bladeMat
    end

    if data.inv then
        self.inv = Inv.new(40)
        for _, pair in ipairs(data.inv) do
            if pair[1] then self.inv:add(pair[1], pair[2] or 1) end
        end
    end

    if data.stats then self.stats = data.stats end

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

    if digDown and not aimMine and p.attackT <= 0 and not p.dead then
        Combat.start(p, input.attackKind or p.attackKind or "sword", p.attackMat or "copper")
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
