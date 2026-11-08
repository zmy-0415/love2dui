--[[
    game/core/combat.lua —— 玩家攻击结算

    只在 active 窗口里做一次判定，每个敌人每次挥砍只吃一次伤害。
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
]]

local Weapons = require("game.data.weapons")

local Combat = {}

-- 玩家发起一次攻击。后摇内不能再次发起（M1 不做取消）
function Combat.start(p, kind, material)
    if p.dead then return false end
    if p.attackT and p.attackT > 0 then return false end
    local def = Weapons.get(kind)
    if not def then return false end
    p.attackKind = kind
    p.attackMat = material or "copper"
    p.attackDur = Weapons.total(kind)
    p.attackT = p.attackDur
    p.hitSet = {}
    -- 出刀瞬间把横向速度压一下：不然玩家会一边冲刺一边挥砍，
    -- 判定框跟着人飞，看起来像"滑铲攻击"
    p.vx = p.vx * 0.35
    return true
end

-- 当前是否处在判定窗口
function Combat.inActive(p)
    if not p.attackT or p.attackT <= 0 then return false end
    local def = Weapons.get(p.attackKind)
    if not def then return false end
    local elapsed = p.attackDur - p.attackT
    return elapsed >= def.windup and elapsed <= def.windup + def.active
end

-- 判定矩形（世界坐标）
function Combat.hitbox(p)
    local def = Weapons.get(p.attackKind)
    if not def then return nil end
    local cy = p.y - p.h * 0.5
    local x0, x1
    if p.facing > 0 then
        x0 = p.x - def.back
        x1 = p.x + def.reach
    else
        x0 = p.x - def.reach
        x1 = p.x + def.back
    end
    return x0, cy - def.halfH, x1, cy + def.halfH
end

local function overlapsMob(hx0, hy0, hx1, hy1, m)
    local l, r = m.x - m.w * 0.5, m.x + m.w * 0.5
    local t, b = m.y - m.h, m.y
    return hx0 < r and hx1 > l and hy0 < b and hy1 > t
end

-- 推进攻击并结算。返回本帧命中的怪物数量
function Combat.update(game, dt)
    local p = game.player
    if not p.attackT or p.attackT <= 0 then return 0 end

    local prev = p.attackT
    p.attackT = math.max(0, p.attackT - dt)
    local def = Weapons.get(p.attackKind)
    if not def then return 0 end

    local elapsed0 = p.attackDur - prev
    local elapsed1 = p.attackDur - p.attackT
    local a0 = def.windup
    local a1 = def.windup + def.active
    -- 判定窗口与这一帧的时间区间有交集才算
    if elapsed1 < a0 or elapsed0 > a1 then return 0 end

    local hx0, hy0, hx1, hy1 = Combat.hitbox(p)
    p.hitSet = p.hitSet or {}
    local hits = 0
    local dmg = Weapons.damage(p.attackKind, p.attackMat)

    for i = 1, #game.mobs do
        local m = game.mobs[i]
        if m:alive() and not p.hitSet[m] and overlapsMob(hx0, hy0, hx1, hy1, m) then
            p.hitSet[m] = true
            local dir = (m.x >= p.x) and 1 or -1
            m:hurt(dmg, dir, def.poise)
            hits = hits + 1
            game:onHit(m, dmg, dir, def)
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
                end
            end
            local res = b:hurt(dmg * mult, (b.x >= p.x) and 1 or -1, def.poise, weak)
            hits = hits + 1
            game:onBossHit(b, dmg * mult, res, weak)
        end
    end

    if hits > 0 then
        game:hitStop(def.hitstop)
        game.cam:kick(def.shake, 0.16)
    end
    return hits
end

return Combat
