--[[
    game/render/entities.lua —— 实体绘制

    把「游戏状态」翻译成 game/art 的骨架绘制调用。
    这一层刻意很薄：状态里没有姿势，姿势全在 art/creature 的动作曲线里，
    这样改动作不会碰到游戏逻辑，改逻辑也不会碰坏动画。

    动画时间在这里归一化。游戏状态里存的是「还剩多少秒」
    （攻击剩余、受击剩余），到这里才换算成 0~1 的进度，
    因为逻辑关心剩余时间，而动画关心进度。
]]

local C = require("game.art.creature")
local World = require("game.core.world")

local E = {}

local T = World.TILE

-- 骨架只建一次。每帧新建骨架等于每帧重建几十个 table，
-- 而且骨架里带颜色表，扔给 GC 纯属浪费
local SKEL = {
    player = C.humanoid({ hair = "leather", cloth = "cloth", boot = "leather", metal = "iron" }),
    crawler = C.crawler({ shell = "chitin", leg = "leather", size = 0.85 }),
    flyer = C.flyer({ body = "void", wing = "ice" }),
    blob = C.blob({ body = "rot" }),
    golem = C.humanoid({ skin = "stone", cloth = "stone", boot = "stone", metal = "iron", bulk = 1.55, headR = 4.2 }),
}

E.SKEL = SKEL

-- 把玩家的剩余时间换算成 (动作名, 0~1 进度)
function E.playerAnim(p)
    if p.dead then
        return "dead", math.min(1, p.stateTime / 0.7)
    end
    if p.attackT > 0 and p.attackDur and p.attackDur > 0 then
        local u = 1 - p.attackT / p.attackDur
        if u < 0 then u = 0 elseif u > 1 then u = 1 end
        return "attack", u
    end
    if p.hurtAnim and p.hurtAnim > 0 then
        return "hurt", 1 - p.hurtAnim / 0.26
    end
    local s = p.state
    if s == "jump" or s == "fall" or s == "dig" or s == "run" then
        -- 跑步用位移驱动相位，速度慢时腿也慢，不会出现「原地快跑」
        if s == "run" then
            return s, p.animT
        end
        return s, p.animT
    end
    return "idle", p.animT
end

function E.player(g, p, cam)
    local sx = p.x - cam.x
    local sy = p.y - cam.y
    -- 完全移出视野就不画，省下骨架遍历
    if sx < -80 or sx > cam.w + 80 or sy < -80 or sy > cam.h + 80 then return end

    local anim, t = E.playerAnim(p)
    local opts = {
        scale = 0.95,
        outline = 1.0,
        weapon = p.weapon,
        weaponAngle = -0.35,
    }
    -- 受击闪白：整副骨架统一染一次色，比逐节点改色省事且不会漏
    if p.hurtFlash > 0 then
        opts.tint = { 0.95, 0.42, 0.40 }
    end
    -- 无敌帧闪烁：画一半的帧，让玩家知道自己在无敌
    if p.invuln > 0 and p.hurtFlash <= 0 and math.floor(p.invuln * 24) % 2 == 0 then
        opts.alpha = 0.55
    end

    -- 落地阴影：一小片椭圆。没有它角色看起来是「贴」在背景上，是浮着的
    if p.onGround then
        g.setColor(0, 0, 0, 0.28)
        g.ellipse("fill", sx, sy - 1, 7, 2.5)
    end

    C.draw(g, SKEL.player, sx, sy, p.facing, anim, t, opts)
end

-- 怪物通用绘制。mob 需要字段：x(中心) y(脚底) facing kind state animT hurtFlash hp maxHp
function E.mob(g, m, cam)
    local sx = m.x - cam.x
    local sy = m.y - cam.y
    if sx < -100 or sx > cam.w + 100 or sy < -100 or sy > cam.h + 100 then return end

    local skel = SKEL[m.kind] or SKEL.crawler
    local anim = m.anim or "idle"
    local opts = {
        scale = (m.scale or 1) * 0.95,
        outline = 1.0,
    }
    if m.hurtFlash and m.hurtFlash > 0 then
        opts.tint = { 0.95, 0.45, 0.42 }
    end
    if m.dead then
        anim = "dead"
        opts.alpha = math.max(0, 1 - (m.deadT or 0) / 0.5)
    end
    C.draw(g, skel, sx, sy, m.facing or 1, anim, m.animT or 0, opts)

    -- 血条：只在受过伤之后显示，满血时不画，避免屏幕上全是条
    if not m.dead and m.hp and m.hp < m.maxHp then
        local w = (m.barW or 22)
        local bx = sx - w * 0.5
        -- 按碰撞盒高度往上让 12px，而不是写死一个数：
        -- 写死的话体型一变，血条就会飘在怪头顶十几像素之外
        local by = sy - m.h * 1.35 - 10
        g.setColor(0.05, 0.06, 0.08, 0.75)
        g.rectangle("fill", bx - 1, by - 1, w + 2, 4)
        local frac = math.max(0, m.hp / m.maxHp)
        g.setColor(0.85, 0.25, 0.22, 1)
        g.rectangle("fill", bx, by, w * frac, 2)
    end
end

-- 掉落物：小方块 + 上下浮动。不做吸附动画，M1 先保证「看得见、捡得到」
function E.drop(g, d, cam)
    local sx = d.x - cam.x
    local sy = d.y - cam.y + math.sin((d.t or 0) * 4) * 1.5
    if sx < -20 or sx > cam.w + 20 or sy < -20 or sy > cam.h + 20 then return end
    local c = d.col or { 0.8, 0.8, 0.85 }
    g.setColor(0, 0, 0, 0.35)
    g.rectangle("fill", sx - 3, sy + 3, 6, 2)
    g.setColor(c[1], c[2], c[3], 1)
    g.rectangle("fill", sx - 2.5, sy - 2.5, 5, 5)
    g.setColor(math.min(1, c[1] * 1.3), math.min(1, c[2] * 1.3), math.min(1, c[3] * 1.3), 1)
    g.rectangle("fill", sx - 2.5, sy - 2.5, 5, 1)
end

-- 挖掘准星：框住目标格，并按进度从下往上填充
function E.digCursor(g, p, world, cam)
    if not p.digTarget then return end
    local tx, ty = p.digTarget.x, p.digTarget.y
    local sx = tx * T - cam.x
    local sy = ty * T - cam.y
    g.setColor(1, 1, 1, 0.55)
    g.setLineWidth(1)
    g.rectangle("line", sx + 0.5, sy + 0.5, T - 1, T - 1)
    local d = world:damageAt(tx, ty)
    if d and d > 0 then
        g.setColor(1, 1, 1, 0.18)
        g.rectangle("fill", sx + 2, sy + T - 2 - (T - 4) * d, T - 4, (T - 4) * d)
    end
end

-- 投射物：毒液球。画一个深色芯 + 亮边，暗背景上才看得见
function E.projectiles(g, list, cam)
    for i = 1, #list do
        local pr = list[i]
        local sx = pr.x - cam.x
        local sy = pr.y - cam.y
        -- 拖尾：沿速度反方向拉一小段，速度越快尾巴越长
        g.setColor(0.35, 0.55, 0.20, 0.35)
        g.circle("fill", sx - pr.vx * 0.012, sy - pr.vy * 0.012, 4.5)
        g.setColor(0.52, 0.76, 0.28, 0.95)
        g.circle("fill", sx, sy, 3.6)
        g.setColor(0.80, 0.95, 0.52, 0.9)
        g.circle("fill", sx - pr.vx * 0.004 - 1, sy - pr.vy * 0.004 - 1, 1.6)
    end
end

-- 粒子：方块状火花，按剩余寿命淡出
function E.particles(g, list, cam)
    for i = 1, #list do
        local q = list[i]
        local a = 1 - q.t / q.life
        if a > 0 then
            local c = q.col
            local s = (q.size or 2) * (0.35 + a * 0.65)
            g.setColor(c[1], c[2], c[3], a)
            g.rectangle("fill", q.x - cam.x - s, q.y - cam.y - s, s * 2, s * 2)
        end
    end
end

-- ---------------- 石喉 ----------------

local B = require("game.art.boss")

-- AOE 半径。渲染和判定共用这一个数：两边各写一个值一定会漂，
-- 玩家就会遇到「明明在圈外却被打到」
local BOSS_AOE_R = 150
E.BOSS_AOE_R = BOSS_AOE_R
local bossSkel

-- 钻地时的地面裂纹：Boss 大部分时间在地下，玩家唯一的线索就是它
function E.bossTracks(g, b, cam)
    local gx = (b.state == "telegraph") and b.targetX or b.x
    local sy = b.y - cam.y
    local sx = gx - cam.x
    local prog = 1
    if b.state == "telegraph" then
        -- 预警期间裂纹逐渐张开并变红，让步进感清楚
        local t = 1 - math.max(0, b.timer) / 0.75
        prog = math.max(0.15, t)
        g.setColor(0.85, 0.28, 0.22, 0.35 * prog)
        g.circle("fill", sx, sy - 2, 26 * prog + 8)
    end

    g.setColor(0.12, 0.10, 0.09, 0.85)
    for i = -3, 3 do
        local lx = sx + i * 7 * prog
        local len = 6 + (i % 3 + 3) * 3
        g.rectangle("fill", lx, sy - 3, 2, len * prog)
    end
    -- 地上的碎石，暗示下面有东西在动
    g.setColor(0.42, 0.34, 0.26, 0.9)
    g.rectangle("fill", sx - 14, sy - 4, 5, 3)
    g.rectangle("fill", sx + 9, sy - 4, 6, 3)
end

function E.boss(g, b, cam)
    if b.underground then
        E.bossTracks(g, b, cam)
        return
    end
    if not bossSkel then bossSkel = B.stoneMaw({}) end

    local sx = b.x - cam.x
    local sy = b.y - cam.y
    if sx < -220 or sx > cam.w + 220 then return end

    local anim = "idle"
    local t = b.animT
    if b.dead then
        anim = "idle"
        t = b.animT
    elseif b.phase == 3 and b.aoeWind then
        anim = "roar"
        t = 1 - b.aoeWind / 2.6
    end

    local opts = {
        scale = 1.7,
        outline = 1.5,
        -- 骨架原点大致在身体中线，往上一格多才能坐在地面上
        y = sy - 10,
    }
    if b.flash > 0 then
        opts.tint = { 1.0, 0.55, 0.45 }
    end
    if b.dead then
        opts.alpha = math.max(0, 1 - b.deadT / 1.4)
        opts.tint = { 0.55, 0.50, 0.48 }
    end

    B.draw(g, bossSkel, sx, sy - 10, b.facing, anim, t, opts)

    -- 阶段 3 的弱点：尾节发光。玩家得知道该打哪儿，不然「打弱点」变成猜谜
    if b.phase == 3 and not b.dead then
        local wx = b.x - b.w + 10 - cam.x
        local wy = b.y - b.h * 0.45 - cam.y
        local pulse = 0.55 + math.sin(b.animT * 6) * 0.25
        g.setColor(1.0, 0.55, 0.35, 0.18 * pulse)
        g.circle("fill", wx, wy, 16)
        g.setColor(1.0, 0.72, 0.45, 0.55 * pulse)
        g.circle("fill", wx, wy, 7)
        g.setColor(1.0, 0.92, 0.75, 0.9)
        g.circle("fill", wx, wy, 3)
    end

    -- 阶段 3 蓄力：同心圆表示「伤害范围 + 还剩多久」。
    -- 一开始画成实心大红圈，结果半屏都被染红、Boss 自己看不清了。
    -- 现在只用很低的 alpha 叠三层，视觉上像「热浪」而不是「一块红布」
    if b.aoeWind then
        local k = 1 - b.aoeWind / 2.6
        local cx, cy = b:center()
        local r = BOSS_AOE_R
        local px, py = cx - cam.x, cy - cam.y
        g.setColor(1.0, 0.32, 0.22, 0.05 + k * 0.07)
        g.circle("fill", px, py, r)
        g.setColor(1.0, 0.28, 0.18, 0.08 + k * 0.10)
        g.circle("fill", px, py, r * 0.70)
        g.setColor(1.0, 0.55, 0.32, 0.10 + k * 0.14)
        g.circle("fill", px, py, r * 0.34)
        -- 核心亮点，随蓄力变大
        g.setColor(1.0, 0.80, 0.55, 0.45 + k * 0.4)
        g.circle("fill", px, py, 6 + k * 10)
    end
end

-- 顶部 Boss 血条。放屏幕顶端而不是怪头上：
-- Boss 会跑出画面，血条飘走了玩家就不知道打了多少
function E.bossBar(g, game)
    local b = game.boss
    if not b then return end
    local w = game.vw * 0.52
    local x = (game.vw - w) * 0.5
    local y = 18
    local frac = math.max(0, b.hp / b.maxHp)
    local alpha = b.dead and math.max(0, 1 - b.deadT / 1.2) or 1

    g.setColor(0.04, 0.04, 0.06, 0.82 * alpha)
    g.rectangle("fill", x - 3, y - 3, w + 6, 13)
    g.setColor(0.18, 0.10, 0.10, 0.9 * alpha)
    g.rectangle("fill", x, y, w, 7)
    g.setColor(0.78, 0.24, 0.20, alpha)
    g.rectangle("fill", x, y, w * frac, 7)
    g.setColor(1.0, 0.55, 0.45, 0.55 * alpha)
    g.rectangle("fill", x, y, w * frac, 2)

    -- 阶段分界线：70% / 35%，让玩家知道还有几个阶段
    g.setColor(1, 1, 1, 0.35 * alpha)
    g.rectangle("fill", x + w * 0.70, y, 1, 7)
    g.rectangle("fill", x + w * 0.35, y, 1, 7)
end

return E
