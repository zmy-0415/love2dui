--[[
    game/art/boss.lua —— Boss（多节躯体）

    Boss 和普通怪的区别不在贴图精细度，而在「能不能一眼看懂要打哪里」。
    设计文档里石喉的三个阶段分别要求玩家：预判钻地、优先清虫、打尾节弱点——
    这三件事都必须从剪影上直接读出来，所以 Boss 用「节」组织：

        头节   最大、有颚、有眼睛（玩家会本能地认为这是要害）
        中节   甲片，负责「这怪物很长」的体量感
        尾节   唯一发光的部分（真弱点在这里，与直觉相反——这正是设计意图）

    每个节都是独立节点，可以单独摆动、断开、发光，不用画第二套图。
]]

local Palette = require("game.art.palette")
local Rig = require("game.art.rig")

local B = {}

local PI = math.pi

-- 沿圆弧生成月牙，用来做甲壳
local function crescent(r, a0, a1, inner, segs)
    local pts = {}
    local n = segs or 10
    for i = 0, n do
        local a = math.rad(a0 + (a1 - a0) * i / n)
        pts[#pts + 1] = math.cos(a) * r
        pts[#pts + 1] = math.sin(a) * r
    end
    for i = n, 0, -1 do
        local a = math.rad(a0 + (a1 - a0) * i / n)
        pts[#pts + 1] = math.cos(a) * inner
        pts[#pts + 1] = math.sin(a) * inner
    end
    return pts
end

-- 背刺：沿节体上缘排一圈三角
local function spikes(r, count, len, from, to)
    local out = {}
    for i = 1, count do
        local a = math.rad(from + (to - from) * (i - 0.5) / count)
        local cx, cy = math.cos(a) * r, math.sin(a) * r
        local nx, ny = math.cos(a), math.sin(a)
        out[#out + 1] = {
            name = "spike" .. i, ax = cx, off = cy, rest = a + PI / 2,
            shape = "poly", col = "stone", step = "dark", outline = 0,
            points = { 0, -len * 0.45, len, 0, 0, len * 0.45 },
        }
    end
    return out
end

--[[
    石喉：3,200 血的第一个 Boss。
    朝右，身体向左延伸；尾部是弱点（发光）。
]]
function C_stoneMaw(skin)
    skin = skin or {}
    local shell = skin.shell or "stone"
    local ore = skin.ore or "ember"
    local headR = skin.headR or 11

    -- ---- 尾节：弱点
    local tail = {
        name = "tail", at = 1, rest = PI, shape = "circle", radius = 5.8, col = shell,
        step = "dark",
        children = {
            -- 弱点：整只 Boss 唯一强发光的地方，玩家会先打这里（错的），
            -- 但打断尾节才能真正停止 AOE（对的）——引导与反转都靠这一处光
            { name = "core", ax = -1.5, shape = "circle", radius = 3.2, col = ore,
              step = "glow", glow = ore, glowAlpha = 1.0, glowRadius = 7.0,
              outline = 0.8 },
            { name = "core_rim", shape = "poly", col = "stone", step = "dark", outline = 0,
              points = crescent(7.0, 30, 150, 4.4, 8) },
        },
    }

    -- ---- 中节 ×2
    local seg2 = {
        name = "seg2", at = 1, rest = PI, len = 14, shape = "circle", radius = 7.0, col = shell,
        step = "dark",
        children = {
            { name = "seg2_plate", shape = "poly", col = shell, step = "base", outline = 0.7,
              points = crescent(8.0, 190, 350, 5.6, 9) },
            tail,
        },
    }
    for _, s in ipairs(spikes(7.3, 3, 3.6, 200, 340)) do
        table.insert(seg2.children, s)
    end

    local seg1 = {
        name = "seg1", at = 0, ax = -headR * 1.05, rest = PI, len = 16, shape = "circle", radius = 8.0, col = shell,
        children = {
            { name = "seg1_plate", shape = "poly", col = shell, step = "light", outline = 0.8,
              points = crescent(9.2, 190, 350, 6.4, 9) },
            seg2,
        },
    }
    for _, s in ipairs(spikes(8.2, 3, 4.2, 200, 340)) do
        table.insert(seg1.children, s)
    end

    -- ---- 头节
    local head = {
        name = "head", at = 0, len = 13, rest = 0, shape = "circle", radius = headR,
        col = shell,
        children = {
            -- 甲壳盖住上半个头，留出下缘给颚
            { name = "skull", shape = "poly", col = shell, step = "light", outline = 0.9,
              points = crescent(headR * 1.05, 186, 354, headR * 0.72, 11) },
            -- 三只眼：不偶数，看起来更不像"动物"，更危险
            { name = "eye1", ax = headR * 0.42, off = -headR * 0.42, shape = "circle",
              radius = 1.8, col = ore, step = "glow", outline = 0, shade = false,
              glow = ore, glowAlpha = 1.0, glowRadius = 3.2 },
            { name = "eye2", ax = headR * 0.42, off = headR * 0.34, shape = "circle",
              radius = 1.8, col = ore, step = "glow", outline = 0, shade = false,
              glow = ore, glowAlpha = 1.0, glowRadius = 3.2 },
            { name = "eye3", ax = headR * 0.02, off = -headR * 0.02, shape = "circle",
              radius = 1.3, col = ore, step = "glow", outline = 0, shade = false,
              glow = ore, glowAlpha = 0.85, glowRadius = 2.2 },
            -- 上下颚：一对钳子，张开时威胁感翻倍，而且直接提示「嘴是攻击源」
            { name = "jaw_top", ax = headR * 0.55, off = -headR * 0.52, rest = -0.35,
              shape = "poly", col = "bone", step = "dark",
              points = { 0, -2.8, headR * 0.52, -4.6, headR * 0.86, -2.6,
                         headR * 0.78, 0.4, 0, 1.8 } },
            { name = "jaw_bot", ax = headR * 0.55, off = headR * 0.52, rest = 0.35,
              shape = "poly", col = "bone", step = "dark",
              points = { 0, 2.8, headR * 0.52, 4.6, headR * 0.86, 2.6,
                         headR * 0.78, -0.4, 0, -1.8 } },
            -- 颈部甲环，遮住头与身之间的接缝
            { name = "collar", ax = -headR * 0.8, shape = "poly", col = shell, step = "dark",
              outline = 0.6, points = crescent(headR * 1.02, -170, -10, headR * 0.66, 9) },
        },
    }
    for _, s in ipairs(spikes(headR * 1.02, 4, 4.6, 200, 340)) do
        table.insert(head.children, s)
    end

    -- 注意顺序：身体先画、头后画。若把头挂在身体之后（作为父节点），
    -- 后画的身体节会盖住头，Boss 就变成一根没有脸的香肠了。
    seg1.at = 0
    seg1.ax = -headR * 1.05

    return {
        name = "stoneMaw",
        kind = "boss",
        bossKind = "stoneMaw",
        len = 0, rest = 0,
        children = { seg1, head },
    }
end

--[[
    Boss 姿态：整条身体做 S 形摆动，每节相位递增，
    这是「分节生物」看起来活着的关键——所有节同相位摆动会像一根棍子。
]]
function B.pose(bossKind, anim, t)
    local pose, extra = {}, { bob = 0 }

    if bossKind == "stoneMaw" then
        local ph = t * 1.6
        local phase = { head = 0, seg1 = 0.7, seg2 = 1.5, tail = 2.2 }
        local amp = { head = 0.10, seg1 = 0.16, seg2 = 0.22, tail = 0.30 }

        if anim == "lunge" then
            -- 突袭：头压低向前，身体绷直，尾节甩起
            pose.head = -0.28
            pose.seg1 = 0.10
            pose.seg2 = -0.14
            pose.tail = -0.30
            extra.bob = -1.5
        elseif anim == "roar" then
            -- 咆哮：抬头、张颚
            pose.head = 0.34
            pose.jaw_top = -0.75
            pose.jaw_bot = 0.75
            pose.seg1 = 0.18
            pose.seg2 = -0.22
            pose.tail = 0.34
            extra.bob = 1.6
        elseif anim == "hurt" then
            pose.head = 0.22
            pose.seg1 = -0.10
            pose.seg2 = 0.16
            pose.tail = -0.22
        else -- idle / burrow
            local s = math.sin(ph)
            pose.head = s * amp.head
            pose.seg1 = math.sin(ph - 0.7) * amp.seg1
            pose.seg2 = math.sin(ph - 1.5) * amp.seg2
            pose.tail = math.sin(ph - 2.2) * amp.tail
            if anim == "burrow" then
                -- 钻地：身体沉下去，只露甲壳
                extra.bob = 9
                extra.clip = true
            end
        end
        extra.bob = (extra.bob or 0) + math.sin(ph * 0.8) * 0.6
    end

    return pose, extra
end

function B.draw(g, skel, x, y, facing, anim, t, opts)
    opts = opts or {}
    local pose, extra = B.pose(skel.bossKind, anim, t)

    g.push()
    g.translate(x, y + (extra.bob or 0))
    if facing < 0 then g.scale(-1, 1) end
    if opts.scale and opts.scale ~= 1 then g.scale(opts.scale) end
    Rig.draw(g, skel, pose, {
        x = 0, y = 0,
        outline = opts.outline == nil and 1.5 or opts.outline,
        alpha = opts.alpha,
        tint = opts.tint,
    })
    g.pop()

    return pose, extra
end

-- 阶段切换：血量 70% / 35% 时改变甲壳与弱点亮度，
-- 不换贴图，只换明度与发光强度，够玩家看出「它变了」
function B.applyPhase(skel, phase)
    local t = ({ 1.0, 0.92, 0.82 })[math.max(1, math.min(3, phase))] or 1
    local function walk(n)
        if n.glow then
            n.glowAlpha = (n.glowAlpha or 0.8) * t
        end
        if n.children then
            for i = 1, #n.children do walk(n.children[i]) end
        end
    end
    walk(skel)
    return skel
end

B.stoneMaw = C_stoneMaw
B.crescent = crescent

return B
