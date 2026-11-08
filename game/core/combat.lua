--[[
    game/core/combat.lua —— 玩家攻击结算

    只在 active 窗口里做判定，每个敌人每次挥砍只吃一次伤害。
    这两条是「打击感」的技术前提：如果整段动画都在判定，玩家会看到
    怪物被连续打出三四下伤害数字，看起来像卡了；如果同一个敌人能重复命中，
    一刀就等于三刀，所有数值平衡都失效。

    判定框用矩形而不是扇形。扇形看起来更"物理正确"，但在 16px 的像素游戏里
    玩家对「差一点点」的容忍度很低，矩形（并且比视觉大一圈）实际手感更好。
    这是 Terraria 一类游戏沿用多年的做法，不是偷懒。

    命中之后的反馈分三层，缺一层手感就会"发飘"：
        hitstop   时间短暂冻结（最有效的一层，几乎决定打击感的上限）
        shake     相机抖动
        particle  火花，给视觉一个落点

    ---- M2 ----

    这里不再知道「剑」或「斧」是什么，只知道一个 resolve 过的数值包 w。
    这样做的好处是：加第九把武器、加第三条词条都不用动这个文件。
    代价是 Combat 无法针对某把武器写特例——这是有意的约束，
    一旦开始写「如果是斧就……」，八把武器的交互组合很快就会失控。

    多目标衰减（falloff）放在这里而不是 mob 上，因为它是「这一刀」的属性：
    同一把镰刀打一只怪和打五只怪，单体伤害应该一样；
    同一把剑打五只怪，第五只只该吃一半——这是「群体 vs 单体」的区分点。
]]

local Weapons = require("game.data.weapons")
local Status = require("game.core.status")
local Rng = require("game.core.rng")

local Combat = {}

-- 暴击倍率。1.7 是刻意选的：再高会让「暴击词条」压过一切，
-- 再低玩家感觉不到那一下特别重
Combat.CRIT_MULT = 1.7

--[[
    玩家发起一次攻击。后摇内不能再次发起（M2 仍不做取消）。

    w 可以是：
        resolve 过的数值包（正常路径）
        武器类型字符串（旧调用/测试用，按无柄无芯解析）
]]
function Combat.start(p, w)
    if p.dead then return false end
    if p.attackT and p.attackT > 0 then return false end
    if type(w) == "string" then
        w = Weapons.resolve({ class = w })
    end
    w = w or Weapons.resolve({ class = "sword" })

    p.attack = w
    p.attackDur = w.dur
    p.attackT = w.dur
    p.hitSet = {}
    p.fired = false
    p.critSeq = p.critSeq or 0

    -- 出刀瞬间把横向速度压一下：不然玩家会一边冲刺一边挥砍，
    -- 判定框跟着人飞，看起来像"滑铲攻击"。
    -- 压多少由武器决定：匕首 0.72（几乎不减速），战锤 0.20（等于钉住）
    p.vx = p.vx * (w.mobility or 0.35)
    return true
end

-- 当前是否处在判定窗口
function Combat.inActive(p)
    if not p.attackT or p.attackT <= 0 then return false end
    local w = p.attack
    if not w then return false end
    local elapsed = p.attackDur - p.attackT
    return elapsed >= w.windup and elapsed <= w.windup + w.active
end

-- 判定矩形（世界坐标）
function Combat.hitbox(p)
    local w = p.attack
    if not w then return nil end
    local cy = p.y - p.h * 0.5
    local x0, x1
    if p.facing > 0 then
        x0 = p.x - w.back
        x1 = p.x + w.reach
    else
        x0 = p.x - w.reach
        x1 = p.x + w.back
    end
    return x0, cy - w.halfH, x1, cy + w.halfH
end

local function overlapsBox(hx0, hy0, hx1, hy1, m)
    local l, r = m.x - m.w * 0.5, m.x + m.w * 0.5
    local t, b = m.y - m.h, m.y
    return hx0 < r and hx1 > l and hy0 < b and hy1 > t
end

-- 0~1 的确定性随机：同一把武器、同一局、同一刀序，结果永远一样
local function roll01(seed, n)
    local h = Rng.hash(seed or 0, n)
    h = math.abs(h) % 1000003
    return h / 1000003
end

--[[
    先做「词条 + 暴击」的修正，再交给 mob:hurt 做状态修正与扣血。
    分工是这样切的：

        Combat   管「这一刀本身的强度」——衰减、暴击、硬直加成
        Mob:hurt 管「目标身上的修正」——雷痕易伤、击退抗性

    为什么易伤放在目标那边而不是这里：爆炸、Boss 溅射、以后的陷阱
    都要吃同一个加成。只在玩家挥砍里写一次，玩家会发现「雷芯配爆炸没反应」。
]]
function Combat.rollDamage(game, p, m, w, falloffMult)
    local dmg = w.damage * falloffMult
    local crit = false

    -- 残忍：对硬直中的目标加成。必须读 m.stagger 的**当前**值，
    -- 不能等 hurt 把它改了之后再读
    if w.staggerBonus and m.stagger and m.stagger > 0 then
        dmg = dmg * (1 + w.staggerBonus)
    end

    -- 暴击
    if w.crit and w.crit > 0 then
        p.critSeq = (p.critSeq or 0) + 1
        local seed = (w.spec and w.spec.seed) or 0
        if roll01(seed, p.critSeq) < w.crit then
            crit = true
            dmg = dmg * Combat.CRIT_MULT
        end
    end

    return dmg, crit
end

--[[
    推进攻击并结算。返回本帧命中的目标数量。
]]
function Combat.update(game, dt)
    local p = game.player
    if not p.attackT or p.attackT <= 0 then return 0 end

    local prev = p.attackT
    p.attackT = math.max(0, p.attackT - dt)
    local w = p.attack
    if not w then return 0 end

    local elapsed0 = p.attackDur - prev
    local elapsed1 = p.attackDur - p.attackT
    local a0 = w.windup
    local a1 = w.windup + w.active
    -- 判定窗口与这一帧的时间区间有交集才算
    if elapsed1 < a0 or elapsed0 > a1 then return 0 end

    -- 远程武器：判定窗口一开就放一支箭，然后这一刀就没有近战判定了。
    -- 放在这里而不是 start 里，是为了让「前摇」真的存在——
    -- 玩家看得见抬弓，也来得及因为「对面冲过来了」而后悔
    if w.ranged then
        if not p.fired then
            p.fired = true
            game:fireArrow(p, w)
        end
        return 0
    end

    local hx0, hy0, hx1, hy1 = Combat.hitbox(p)
    if not hx0 then return 0 end
    p.hitSet = p.hitSet or {}
    local hits = 0

    for i = 1, #game.mobs do
        local m = game.mobs[i]
        if m:alive() and not p.hitSet[m] and overlapsBox(hx0, hy0, hx1, hy1, m) then
            p.hitSet[m] = true
            hits = hits + 1
            -- 第 n 个目标乘 falloff^(n-1)：镰刀 falloff=1 所以不衰减，
            -- 大剑 falloff=0.78 所以第二个只剩 78%
            local mult = (w.falloff or 1) ^ (hits - 1)
            local dmg, crit = Combat.rollDamage(game, p, m, w, mult)
            local dir = (m.x >= p.x) and 1 or -1
            m:hurt(dmg, dir, w.poise)
            if w.element then Status.apply(m, w.element, w.elementLv) end
            if w.leech and w.leech > 0 and not p.dead then p:heal(w.leech) end
            game:onHit(m, dmg, dir, w, crit)
        end
    end

    -- Boss 单独判定：它有个「尾巴弱点」，打中弱点要额外给反馈，
    -- 所以不能和普通怪走同一套 hurt 流程
    local b = game.boss
    if b and b:alive() and not b.underground and not p.hitSet.boss then
        local bx0, by0, bx1, by1 = b:hitbox()
        if hx0 < bx1 and hx1 > bx0 and hy0 < by1 and hy1 > by0 then
            p.hitSet.boss = true
            local mult, weak = 1, false
            if b.phase == 3 then
                local wx0, wy0, wx1, wy1 = b:weakBox()
                if hx0 < wx1 and hx1 > wx0 and hy0 < wy1 and hy1 > wy0 then
                    mult, weak = 2.2, true
                    -- 破城词条：只对弱点生效，所以它不会让打小怪变强
                    if w.weakBonus then mult = mult * (1 + w.weakBonus) end
                end
            end
            local dmg = w.damage * mult
            if w.staggerBonus then dmg = dmg * (1 + w.staggerBonus) end
            local res = b:hurt(dmg, (b.x >= p.x) and 1 or -1, w.poise, weak)
            if w.element then Status.apply(b, w.element, w.elementLv) end
            hits = hits + 1
            game:onBossHit(b, dmg, res, weak)
        end
    end

    if hits > 0 then
        game:hitStop(w.hitstop)
        game.cam:kick(w.shake, 0.16)
    end
    return hits
end

return Combat
