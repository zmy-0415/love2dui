--[[
    game/core/boss.lua —— 石喉（第一个 Boss，也是教学关）

    设计意图（来自 docs/game-design.md 8.3）：这一场要教会玩家三件事。
        阶段 1  看地面裂纹预判钻出位置        → 预判
        阶段 2  钻出的同时放小怪，必须边躲边清   → 清场优先级
        阶段 3  只剩尾节是真弱点，打不断就吃全屏 → 打弱点
    打完这三个阶段，玩家就掌握了这套战斗语言，后面的 Boss 才有地方加新东西。

    实现上刻意「藏起来」而不是「硬扛」：阶段 1/2 大部分时间 Boss 在地下，
    玩家看不到它，只能看裂纹。这么做一是省美术，二是它逼玩家抬头看地面，
    这个动作本身就是教学。

    血量按 M1 的实际 DPS 定的：初始剑 13 伤害 / 0.355 秒 ≈ 36 DPS，
    900 血约 25 秒纯输出，算上躲闪与清怪，一场 45~60 秒。
]]

local World = require("game.core.world")
local Status = require("game.core.status")

local Boss = {}
Boss.__index = Boss

local T = World.TILE

Boss.MAX_HP = 900
Boss.NAME = "石喉"

function Boss.new(x, y)
    return setmetatable({
        kind = "stoneMaw",
        x = x, y = y,
        w = 64, h = 36,
        hp = Boss.MAX_HP, maxHp = Boss.MAX_HP,
        phase = 1,
        state = "burrow",
        timer = 1.4,
        underground = true,
        targetX = x,
        vx = 0, vy = 0,
        facing = -1,
        animT = 0,
        flash = 0,
        dead = false,
        deadT = 0,
        -- 阶段 3 的 AOE 蓄力
        aoeTimer = 3.0,
        aoeWind = nil,
        aoeDamage = 0,
        aoeNeed = 55,
        dmg = 22,
        touchCd = 0,
    }, Boss)
end

function Boss:alive()
    return not self.dead
end

function Boss:center()
    return self.x - 18, self.y - self.h * 0.5
end

-- 整体判定框：身体主要往头后面延伸
function Boss:hitbox()
    return self.x - self.w, self.y - self.h, self.x + 16, self.y
end

-- 尾部弱点框（仅阶段 3 有意义）
function Boss:weakBox()
    local cx = self.x - self.w + 10
    return cx - 16, self.y - self.h * 0.8, cx + 16, self.y
end

function Boss:hurt(dmg, dir, poise, weak)
    if self.dead then return false end

    -- 雷痕易伤，与普通怪一致：所有伤害来源都能吃到
    local vuln = Status.vulnMul(self)
    if vuln ~= 1 then
        dmg = dmg * vuln
        Status.consumeShock(self)
    end

    self.hp = self.hp - dmg
    self.flash = 0.13

    -- 阶段 3 的 AOE 靠输出打断：这是「DPS 检查」，也是唯一能让玩家
    -- 在打不过时意识到「该换武器了」的时刻
    if self.aoeWind then
        self.aoeDamage = self.aoeDamage + dmg
        if self.aoeDamage >= self.aoeNeed then
            self.aoeWind = nil
            self.aoeDamage = 0
            self.aoeTimer = 3.4
            self.stagger = 1.6
            return "interrupt"
        end
    end

    if self.hp <= 0 then
        self.hp = 0
        self.dead = true
        self.deadT = 0
        self.underground = false
        return "kill"
    end
    return weak and "weak" or "hit"
end

function Boss:onPhase(game)
    if self.phase == 3 then
        -- 阶段 3：从地下钻出来，展开三节，停在场地中央
        self.underground = false
        self.state = "split"
        self.aoeTimer = 3.0
        self.aoeWind = nil
        self.vx = 0
        game.cam:kick(7, 0.5)
        game:hitStop(0.09)
        local cx, cy = self:center()
        game:spawnParticles(cx, cy, 30, {
            col = { 1.0, 0.55, 0.35 }, spread = 320, life = 0.7, size = 3,
        })
    else
        game.cam:kick(4, 0.3)
    end
end

-- 阶段 1/2：钻地 → 裂纹预警 → 钻出 → 冲撞 → 再钻地
function Boss:updateBurrow(game, p, dt)
    -- 每个状态都要递减自己的计时器。漏了这一句，Boss 会永远停在第一个状态，
    -- 而且不会报错——只是整场战斗一次都不钻出来
    self.timer = self.timer - dt

    if self.state == "burrow" then
        self.underground = true
        -- 地下跟随玩家：慢一点，玩家能感觉到「它在下面找我」但追不上跑动的人
        self.x = self.x + (p.x - self.x) * (1 - math.exp(-1.6 * dt))
        if self.timer <= 0 then
            self.state = "telegraph"
            self.timer = 0.75
            self.targetX = p.x
            self.y = p.y
        end

    elseif self.state == "telegraph" then
        -- 这 0.75 秒就是全部教学：地面裂开，玩家有时间走开
        if self.timer <= 0 then
            self.state = "emerge"
            self.timer = 0.45
            self.underground = false
            self.x = self.targetX
            game.cam:kick(6, 0.28)
            game:hitStop(0.05)
            local cx, cy = self:center()
            game:spawnParticles(self.x, self.y, 22, {
                col = { 0.75, 0.62, 0.45 }, spread = 240, life = 0.55, size = 3,
            })
            -- 钻出瞬间站得太近会被顶飞
            local dx, dy = p.x - self.x, p.y - p.y
            if math.abs(p.x - self.x) < 46 and math.abs(p.y - self.y) < 60 then
                p:hurt(self.dmg, (p.x > self.x) and 1 or -1)
            end
        end

    elseif self.state == "emerge" then
        if self.timer <= 0 then
            self.state = "charge"
            self.timer = 1.05
            self.facing = (p.x > self.x) and 1 or -1
            self.vx = self.facing * 300
            -- 阶段 2 起，每次钻出放两只矿虫：玩家必须在躲冲撞的间隙决定先清谁
            if self.phase >= 2 then
                for i = 1, 2 do
                    local sx = self.x + (i == 1 and -34 or 34)
                    local gy = game.world and self.y
                    game:spawnMob("crawler", sx, gy, {})
                end
            end
        end

    elseif self.state == "charge" then
        self.x = self.x + self.vx * dt
        if self.touchCd > 0 then self.touchCd = self.touchCd - dt end
        -- 撞到玩家
        if not p.dead and self.touchCd <= 0 then
            local dx = p.x - self.x
            if math.abs(dx) < 40 and math.abs(p.y - self.y) < 40 then
                if p:hurt(self.dmg, (p.x > self.x) and 1 or -1) then
                    self.touchCd = 0.9
                    game:hitStop(0.06)
                    game.cam:kick(6, 0.3)
                end
            end
        end
        -- 撞到硬地形就停下钻回去
        local aheadX = self.x + self.facing * 26
        local hitWall = game.world:solidAt(math.floor(aheadX / T), math.floor((self.y - 12) / T))
        if self.timer <= 0 or hitWall or self.x < 40 or self.x > game.world.w * T - 40 then
            self.state = "burrow"
            self.timer = 1.5
            self.vx = 0
        end
    end
end

-- 阶段 3：不动，靠 AOE 逼玩家输出；打不断就吃伤害
function Boss:updateSplit(game, p, dt)
    self.vx = 0
    self.underground = false
    self.facing = (p.x > self.x) and 1 or -1

    if self.stagger and self.stagger > 0 then
        self.stagger = self.stagger - dt
        return
    end

    if self.aoeWind then
        self.aoeWind = self.aoeWind - dt
        if self.aoeWind <= 0 then
            self.aoeWind = nil
            self.aoeTimer = 6.2
            -- 没被打断：全屏震波
            game.cam:kick(9, 0.5)
            game:hitStop(0.08)
            local cx, cy = self:center()
            game:spawnParticles(cx, cy, 40, {
                col = { 1.0, 0.45, 0.3 }, spread = 380, life = 0.7, size = 3,
            })
            -- 只打圈子里的东西。之前是无条件打玩家，和画面上的红圈对不上
            local R = 150
            for i = 1, #game.mobs do
                local m = game.mobs[i]
                if m:alive() then
                    local mx, my = m:center()
                    if (mx - cx) ^ 2 + (my - cy) ^ 2 < R * R then
                        m:hurt(40, (mx > cx) and 1 or -1, 40)
                    end
                end
            end
            if not p.dead then
                local px, py = p.x, p.y - p.h * 0.5
                if (px - cx) ^ 2 + (py - cy) ^ 2 < R * R then
                    p:hurt(30, (p.x > cx) and 1 or -1)
                end
            end
        end
    else
        self.aoeTimer = self.aoeTimer - dt
        if self.aoeTimer <= 0 then
            self.aoeWind = 2.6
            self.aoeDamage = 0
            game.cam:kick(3, 0.4)
        end
    end
end

function Boss:update(game, dt)
    self.animT = self.animT + dt
    self.flash = math.max(0, self.flash - dt)

    if self.dead then
        self.deadT = self.deadT + dt
        return
    end

    -- 元素状态：燃烧/剧毒磨血在 Boss 身上同样生效。
    -- 不这么做的话「炎芯」在整场 Boss 战里等于没词条，
    -- 而打 Boss 恰恰是最需要持续输出的场景
    if self.status then
        Status.update(self, dt)
        if self.hp <= 0 then
            self.hp = 0
            self.dead = true
            self.deadT = 0
            self.underground = false
            return
        end
    end

    local p = game.player
    local frac = self.hp / self.maxHp
    local want = (frac > 0.70) and 1 or ((frac > 0.35) and 2 or 3)
    if want > self.phase then
        self.phase = want
        self:onPhase(game)
    end

    if self.phase < 3 then
        self:updateBurrow(game, p, dt)
    else
        self:updateSplit(game, p, dt)
    end
end

return Boss
