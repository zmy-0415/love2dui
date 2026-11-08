--[[
    game/art/creature.lua —— 角色与怪物（四类骨架 + 皮肤）

    一套骨架 + 一组颜色参数 = 一个新怪物。这不是偷懒，是因为设计文档里
    怪物种类会随层数膨胀（9 层 × 每层 4~6 种 + 精英词缀变体 + 事件波次），
    而美术人力永远追不上。所以先把「骨架族」定死：

        humanoid  人形：玩家、骷髅矿工、腐化教徒、精英人形
        crawler   爬行：矿虫、腐化蜈蚣、深渊爬兽
        blob      软体：史莱姆、腐化团、岩浆泡
        flyer     飞行：洞穴蝠、虚空浮眼、熔岩鸟

    皮肤参数只有 5 个颜色键 + 3 个尺寸系数，改完就是另一个物种。

    动作是「角度曲线」而非帧序列：run/attack 的每一帧都是 t 的函数，
    攻速词条改变的是时间轴长度，不是换一组贴图。
]]

local Palette = require("game.art.palette")
local Rig = require("game.art.rig")
local Weapon = require("game.art.weapon")

local C = {}

local PI = math.pi

-- ---------------------------------------------------------------- 工具

local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end
C.copy = copy

-- 关键帧插值：u 是 0~1 的动作进度，keys 是 { {u, 值}, ... }
-- 用 smoothstep 而不是线性——线性插值的挥砍看起来像机械臂
local function kf(u, keys)
    if u <= keys[1][1] then return keys[1][2] end
    for i = 2, #keys do
        if u <= keys[i][1] then
            local a, b = keys[i - 1], keys[i]
            local span = b[1] - a[1]
            local k = span > 1e-6 and (u - a[1]) / span or 1
            k = k * k * (3 - 2 * k)
            return a[2] + (b[2] - a[2]) * k
        end
    end
    return keys[#keys][2]
end
C.kf = kf

-- 沿圆弧生成一圈月牙形多边形，贴着头圆画头发/甲壳用
local function crescent(r, a0, a1, inner, segs)
    local pts = {}
    local n = segs or 9
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

-- ---------------------------------------------------------------- 人形

--[[
    人形骨架。总高约 28 逻辑像素（脚底 y≈+9.4，头顶 y≈-18.7）。
    skin: { cloth, skin, metal, boot }，都是 palette 的材质键。
]]
function C.humanoid(skin)
    skin = skin or {}
    local cloth = skin.cloth or "cloth"
    local flesh = skin.skin or "flesh"
    local metal = skin.metal or "iron"
    local boot = skin.boot or "leather"
    local bulk = skin.bulk or 1          -- 体型系数：精英怪调 1.15
    local headR = (skin.headR or 3.4)

    local function leg(side, step)
        return {
            name = "thigh_" .. side, at = 0, ax = (side == "near" and 2.4 or -2.4) * bulk,
            rest = PI / 2 + (side == "near" and -0.06 or 0.10), len = 5.4,
            w0 = 2.9 * bulk, w1 = 2.3 * bulk, col = cloth, step = step,
            children = {
                {
                    name = "shin_" .. side, at = 1, rest = PI / 2 - 0.03, len = 5.2,
                    w0 = 2.2 * bulk, w1 = 1.8 * bulk, col = cloth, step = step,
                    children = {
                        {
                            name = "foot_" .. side, at = 1, rest = 0, len = 2.6,
                            w0 = 2.0 * bulk, w1 = 1.5 * bulk, col = boot, step = step,
                        },
                    },
                },
            },
        }
    end

    local function arm(side, step)
        return {
            name = "arm_" .. side, at = 0.94, off = (side == "near" and 4.2 or -4.2) * bulk,
            rest = PI / 2 + (side == "near" and 0.16 or -0.20), len = 4.2,
            w0 = 2.2 * bulk, w1 = 1.9 * bulk, col = cloth, step = step,
            children = {
                {
                    name = "fore_" .. side, at = 1, rest = PI / 2, len = 4.0,
                    w0 = 1.8 * bulk, w1 = 1.5 * bulk, col = skin.shade or step, step = step,
                    children = {
                        {
                            name = "hand_" .. side, at = 1, rest = PI / 2, shape = "circle",
                            radius = 1.4 * bulk, col = flesh, step = step,
                        },
                    },
                },
            },
        }
    end

    local head = {
        name = "head", at = 1, ax = headR * 1.05 + 0.9, rest = -PI / 2,
        shape = "circle", radius = headR, col = flesh,
        children = {
            {
                name = "hair", shape = "poly", col = skin.hair or "leather",
                step = "dark", outline = 0, shade = false,
                points = crescent(headR * 1.04, 34, -160, headR * 0.58),
            },
            -- 眼睛：本地 +X 是世界向上、本地 +Y 是世界向右，
            -- 所以 ax 控制高低、off 控制前后
            {
                name = "eye", ax = -headR * 0.12, off = headR * 0.50, shape = "circle",
                radius = 0.62, col = "ink", outline = 0, shade = false,
            },

        },
    }
    if skin.helmet then
        table.insert(head.children, 1, {
            name = "helmet", ax = headR * 0.55, shape = "poly", col = metal,
            points = {
                -headR * 1.05, -headR * 0.2,
                -headR * 0.55, -headR * 0.95,
                headR * 0.7, -headR * 0.85,
                headR * 0.95, headR * 0.1,
                -headR * 0.2, headR * 0.35,
            },
        })
    end

    local torso = {
        name = "torso", at = 0, rest = -PI / 2, len = 8.5,
        w0 = 5.2 * bulk, w1 = 7.6 * bulk, col = cloth,
        children = {
            arm("far", "dark"),
            head,
            arm("near", "base"),
        },
    }

    return {
        name = "humanoid",
        kind = "humanoid",
        scale = 1,
        len = 0, rest = 0,
        children = { leg("far", "dark"), leg("near", "base"), torso },
    }
end

-- ---------------------------------------------------------------- 爬行

--[[ 爬行类：一节身体 + 3 对腿。矿虫、蜈蚣、深渊爬兽共用。
    skin: { shell, leg, eye }
]]
function C.crawler(skin)
    skin = skin or {}
    local shell = skin.shell or "chitin"
    local legCol = skin.leg or "iron"
    local segs = skin.segs or 3
    local unit = skin.size or 1

    local body = {
        name = "seg1", at = 0, shape = "circle", radius = 4.6 * unit, col = shell,
        children = {
            { name = "eye", ax = 1.6 * unit, off = 2.2 * unit, shape = "circle",
              radius = 1.0 * unit, col = "ink", outline = 0, shade = false,
              glow = skin.glow or "blood", glowAlpha = 0.9, glowAt = 0, glowRadius = 0.7 * unit },
            { name = "jaw_l", ax = -1.5 * unit, off = 2.6 * unit, shape = "poly", col = "bone",
              points = { 0, 0, 3.6 * unit, 1.2 * unit, 3.0 * unit, 2.6 * unit } },
            { name = "jaw_r", ax = -1.5 * unit, off = -2.6 * unit, shape = "poly", col = "bone",
              points = { 0, 0, 3.6 * unit, -1.2 * unit, 3.0 * unit, -2.6 * unit } },
        },
    }

    -- 身体往后串：每节挂在上一节尾部，同时记下每节的节点引用，供挂腿用
    -- 身体链：所有节都保持 rest = 0（本地轴 = 世界轴），靠负的 ax 往身后排。
    --
    -- 踩过两个坑，记在这里：
    -- 1) 圆形节点没有 len，子节点写 at = 1 会落在原点，三节全糊成一团。
    --    所以这里明确给每节 len，并且用 ax 而不是 at 排布。
    -- 2) 如果节写成 rest = PI（朝后），它的本地 X 轴会翻向左、Y 轴翻向上，
    --    挂在它身上的腿再用 ax/off 就会长到身体上方去。保持 rest = 0，
    --    整条链的坐标系一致，挂点才好算。
    local prevR = 4.6 * unit
    local segNodes = { body }
    local tail = body
    for i = 2, segs do
        local r = (4.6 - (i - 1) * 0.55) * unit
        local s = {
            name = "seg" .. i, at = 0, ax = -(prevR + r * 0.92),
            rest = 0, len = r * 2, shape = "circle", radius = r, col = shell,
            step = i % 2 == 0 and "dark" or "base",
        }
        tail.children = tail.children or {}
        table.insert(tail.children, s)
        segNodes[i] = s
        tail = s
        prevR = r
    end

    -- 腿：每节一对，从身体下缘伸出。左右明度不同，一眼能看出前后
    for i = 1, math.min(segs, 3) do
        local host = segNodes[i]
        if host then
            host.children = host.children or {}
            local r = host.radius
            for _, side in ipairs({ { "l", 1 }, { "r", -1 } }) do
                local legNode = {
                    -- 挂点必须在身体边缘：ax 用半径 + 一点余量
                    name = "leg_" .. i .. side[1], at = 0,
                    ax = side[2] * (r + 0.6), off = r * 0.35,
                    rest = PI / 2 + side[2] * 0.55, len = 5.4 * unit,
                    w0 = 1.5 * unit, w1 = 0.9 * unit, col = legCol,
                    step = side[2] > 0 and "dark" or "base",
                    children = {
                        { name = "foot_" .. i .. side[1], at = 1, rest = PI / 2 + side[2] * 0.2,
                          len = 2.6 * unit, w0 = 1.0 * unit, w1 = 0.6 * unit,
                          col = legCol, step = side[2] > 0 and "dark" or "base" },
                    },
                }
                table.insert(host.children, legNode)
            end
        end
    end

    return { name = "crawler", kind = "crawler", len = 0, rest = 0, children = { body } }
end

-- ---------------------------------------------------------------- 软体

--[[ 软体：一个主体 + 三只伪足。靠整体挤压变形表现动作，没有关节。 ]]
function C.blob(skin)
    skin = skin or {}
    local body = skin.body or "slime"
    local r = skin.size or 6.0

    return {
        name = "blob",
        kind = "blob",
        len = 0, rest = 0,
        children = {
            {
                name = "body", at = 0, shape = "circle", radius = r, col = body,
                children = {
                    { name = "eye_l", ax = r * 0.42, off = r * 0.30, shape = "circle",
                      radius = 1.15, col = "ink", outline = 0, shade = false },
                    { name = "eye_r", ax = r * 0.42, off = -r * 0.34, shape = "circle",
                      radius = 1.15, col = "ink", outline = 0, shade = false },
                    { name = "maw", ax = -r * 0.35, off = 0, shape = "poly", col = "ink",
                      points = { 0, -2.4, 2.6, 0, 0, 2.4 }, outline = 0, shade = false },
                },
            },
            { name = "foot_l", at = 0, ax = r * 0.42, off = r * 0.5, shape = "poly",
              col = body, step = "dark", points = { 0, -2.4, 4.0, -1.6, 4.4, 2.0, 0, 2.6 } },
            { name = "foot_r", at = 0, ax = -r * 0.46, off = r * 0.52, shape = "poly",
              col = body, step = "dark", points = { 0, -2.2, 3.8, -1.8, 4.2, 1.8, 0, 2.4 } },
        },
    }
end

-- ---------------------------------------------------------------- 飞行

--[[ 飞行类：躯干 + 双翼。翼是独立节点，扇动靠 pose 驱动。 ]]
function C.flyer(skin)
    skin = skin or {}
    local body = skin.body or "void"
    -- 翼膜单独给个颜色。和身体同色时整只蝙蝠会糊成一个椭圆，
    -- 完全看不出有翅膀；浅色膜 + 深色身体才有剪影
    local membrane = skin.wing or "ice"
    local r = skin.size or 4.0

    local function wing(side, step)
        return {
            name = "wing_" .. side, ax = 0.6, off = (side == "far" and -2.2 or 2.2),
            rest = 0, shape = "poly", col = membrane, step = step,
            -- 翼膜朝身后展开。朝前的版本在侧视图里就是一根尖刺，
            -- 完全读不出「翅膀」；朝后张开的三角才有翼膜的感觉
            points = {
                0, 0,
                -5.0, -4.6,
                -10.5, -2.0,
                -8.0, 1.6,
                -3.0, 2.2,
            },
        }
    end

    return {
        name = "flyer", kind = "flyer", len = 0, rest = 0,
        children = {
            {
                name = "body", at = 0, shape = "circle", radius = r, col = body,
                children = {
                    { name = "eye", ax = r * 0.4, off = r * 0.3, shape = "circle",
                      radius = 1.0, col = "ember", outline = 0, shade = false,
                      glow = "ember", glowAlpha = 0.9 },
                    { name = "tail", at = 0, ax = -r * 0.8, off = 0, rest = PI, len = 5.0,
                      w0 = 1.8, w1 = 0.6, col = body, step = "dark" },
                    wing("far", "dark"),
                    wing("near", "base"),
                },
            },
        },
    }
end

-- ---------------------------------------------------------------- 动作

--[[
    产生 pose 表。
    anim: "idle" | "run" | "attack" | "hurt" | "dead"
    t:    秒（idle/run），或 0~1 的动作进度（attack/hurt）
    返回 pose, extra（extra 里有 bob 垂直位移、lean 等给绘制用的量）
]]
function C.pose(kind, anim, t, opt)
    opt = opt or {}
    local pose, extra = {}, { bob = 0 }

    if kind == "humanoid" then
        if anim == "run" then
            local ph = t * 2 * PI
            local s, c = math.sin(ph), math.cos(ph)
            pose.thigh_near = s * 0.78
            pose.thigh_far = -s * 0.78
            pose.shin_near = math.max(0, -s) * 1.15
            pose.shin_far = math.max(0, s) * 1.15
            pose.foot_near = -s * 0.25
            pose.foot_far = s * 0.25
            pose.arm_near = -s * 0.62
            pose.arm_far = s * 0.62
            pose.fore_near = 0.35 + math.max(0, s) * 0.3
            pose.fore_far = 0.35
            pose.torso = 0.14
            pose.head = -0.10
            extra.bob = math.abs(math.sin(ph)) * 1.3 - 0.6
        elseif anim == "attack" then
            -- 三段：前摇（抬刀蓄力）→ 判定（挥出，最快的一段）→ 后摇（收势）
            local u = t
            pose.arm_near = kf(u, { { 0, 0.16 }, { 0.38, -2.05 }, { 0.52, 1.35 }, { 0.72, 0.55 }, { 1, 0.16 } })
            pose.fore_near = kf(u, { { 0, 0 }, { 0.38, -0.95 }, { 0.52, 0.15 }, { 1, 0 } })
            pose.arm_far = kf(u, { { 0, -0.2 }, { 0.38, 0.45 }, { 0.52, -0.35 }, { 1, -0.2 } })
            pose.torso = kf(u, { { 0, 0 }, { 0.38, -0.20 }, { 0.52, 0.30 }, { 0.72, 0.12 }, { 1, 0 } })
            pose.head = kf(u, { { 0, 0 }, { 0.38, 0.10 }, { 0.52, -0.14 }, { 1, 0 } })
            pose.thigh_near = kf(u, { { 0, 0 }, { 0.38, -0.16 }, { 0.52, 0.22 }, { 1, 0 } })
            pose.thigh_far = -pose.thigh_near * 0.7
            extra.bob = kf(u, { { 0, 0 }, { 0.38, -1.1 }, { 0.52, 1.4 }, { 0.72, 0.2 }, { 1, 0 } })
            extra.lean = pose.torso
        elseif anim == "hurt" then
            local u = t
            pose.torso = kf(u, { { 0, -0.34 }, { 0.35, -0.18 }, { 1, 0 } })
            pose.head = kf(u, { { 0, 0.26 }, { 1, 0 } })
            pose.arm_near = kf(u, { { 0, -0.55 }, { 1, 0.16 } })
            pose.arm_far = kf(u, { { 0, 0.5 }, { 1, -0.2 } })
            extra.bob = kf(u, { { 0, 1.2 }, { 1, 0 } })
        elseif anim == "dead" then
            local u = t
            pose.torso = 1.45 * u
            pose.head = 0.5 * u
            pose.arm_near = -0.9 * u
            pose.arm_far = 0.8 * u
            pose.thigh_near = -0.5 * u
            pose.thigh_far = -0.3 * u
            extra.bob = 3 * u
        elseif anim == "jump" then
            -- 起跳：双腿收起、手臂上举。剪影要一眼能和跑区分开
            pose.thigh_near = -0.62
            pose.shin_near = 0.95
            pose.thigh_far = -0.22
            pose.shin_far = 0.55
            pose.arm_near = -1.85
            pose.arm_far = -1.35
            pose.fore_near = -0.45
            pose.torso = -0.10
            extra.bob = -1.4
        elseif anim == "fall" then
            -- 下落：腿分开、手臂张开，靠剪影判断「正在掉」
            pose.thigh_near = 0.38
            pose.shin_near = -0.28
            pose.thigh_far = -0.34
            pose.shin_far = 0.18
            pose.arm_near = -1.15
            pose.arm_far = -0.95
            pose.torso = 0.06
            pose.head = -0.08
        elseif anim == "dig" then
            -- 挖掘：前下方短促上下摆。频率高一些，否则挖起来像在打太极
            local ph = t * 13
            pose.arm_near = -0.95 + math.sin(ph) * 0.55
            pose.fore_near = -0.35 + math.sin(ph + 0.9) * 0.45
            pose.arm_far = -0.55 + math.sin(ph + PI) * 0.30
            pose.torso = 0.20 + math.sin(ph) * 0.06
            pose.head = 0.16
            pose.thigh_near = 0.10
            pose.thigh_far = -0.10
            pose.shin_near = 0.12
            extra.bob = math.abs(math.sin(ph)) * 0.6
        else -- idle
            local ph = t * 2.1
            local s = math.sin(ph)
            pose.torso = s * 0.022
            pose.head = -s * 0.03
            pose.arm_near = s * 0.075
            pose.arm_far = -s * 0.06
            pose.fore_near = 0.08 + s * 0.03
            pose.shin_near = 0.04
            extra.bob = s * 0.35
        end
    elseif kind == "crawler" then
        local ph = t * 6.5
        for i = 1, 3 do
            local o = (i - 1) * 1.9
            for _, s in ipairs({ "l", "r" }) do
                local sign = s == "l" and 1 or -1
                local seg = o + (sign > 0 and 0 or PI)
                pose["leg_" .. i .. s] = math.sin(ph + seg) * 0.42
                pose["foot_" .. i .. s] = math.sin(ph + seg + 0.9) * 0.3
            end
        end
        pose.seg1 = math.sin(ph * 0.5) * 0.05
        extra.bob = math.sin(ph) * 0.5
    elseif kind == "blob" then
        local ph = t * 3.4
        extra.bob = math.sin(ph) * 0.9
        extra.squash = math.sin(ph) * 0.10   -- 由绘制端做整体缩放
    elseif kind == "flyer" then
        local ph = t * 9
        pose.wing_near = math.sin(ph) * 0.55
        pose.wing_far = -math.sin(ph) * 0.55
        pose.tail = math.sin(ph * 0.4) * 0.18
        extra.bob = math.sin(t * 2.6) * 1.6
    end

    return pose, extra
end

-- ---------------------------------------------------------------- 绘制

--[[
    一站式绘制：选动作、算姿势、画骨架。
    facing: 1 朝右，-1 朝左
    opts 额外项透传给 Rig.draw（outline / tint / alpha / scale）
    返回 pose，便于调用方算武器锚点。
]]
function C.draw(g, skel, x, y, facing, anim, t, opts)
    opts = opts or {}
    local pose, extra = C.pose(skel.kind, anim, t, opts)

    local sx = opts.scale or 1
    local sy = sx
    local bob = (extra.bob or 0) * sx
    if extra.squash then
        -- 软体挤压：横向变胖时纵向变矮，体积感守恒
        sx = sx * (1 + extra.squash)
        sy = sy * (1 - extra.squash)
    end

    g.push()
    g.translate(x, y + bob)
    if facing < 0 then g.scale(-1, 1) end
    if sx ~= 1 or sy ~= 1 then g.scale(sx, sy) end
    Rig.draw(g, skel, pose, {
        x = 0, y = 0,
        outline = opts.outline,
        alpha = opts.alpha,
        shade = opts.shade,
        tint = opts.tint,
    })

    -- 武器挂在近侧手上。此时坐标系是角色本地（面朝 +X），
    -- 所以直接取 hand 的末端就能握住，flip 由外层 scale(-1,1) 处理
    if opts.weapon then
        local hx, hy, ha = Rig.tip(skel, pose, "hand_near")
        Weapon.draw(g, opts.weapon, hx, hy, ha + (opts.weaponAngle or 0), 1, opts)
    end

    g.pop()

    return pose, extra
end

C.PI = PI

return C
