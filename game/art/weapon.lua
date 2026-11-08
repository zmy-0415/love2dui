--[[
    game/art/weapon.lua —— 程序化武器（刃 + 柄 + 芯）

    这是整个素材方案里唯一「必须程序化」的部分，原因不是省事：
        设计文档里武器 = 刃 + 柄 + 芯，各 5 档，还有 32 条词条。
        玩家在铁砧前把铜刃换成炎铁刃的那一刻，这把武器就是世界上
        第一次存在的形状——不可能有对应的贴图。

    所以武器是「算出来的」：
        spec   部件档位 + 材料 + 词条（存档里就这几个数字）
        build  纯函数 → 轮廓点集（可测试、可复现、可序列化）
        draw   把轮廓画出来

    同一份 build 结果既能给软栅出图，也能在真机上画，还能拿去做碰撞判定
    （武器判定框直接复用刀刃多边形，不用另外维护一套）。

    坐标：原点在握把，刀身沿 +X 伸出，柄在 -X 方向。
]]

local Palette = require("game.art.palette")
local Rng = require("game.art.rng")

local W = {}

local PI = math.pi
local sin, cos, rad = math.sin, math.cos, math.rad
local unpack = table.unpack or unpack

-- 档位 → 外观系数。1 粗制 ... 5 终焉
local TIER = {
    --          长度   宽度   弯曲   精细度
    [1] = { 13.0, 0.88, 0.10, 0.2 },
    [2] = { 15.0, 1.00, 0.16, 0.4 },
    [3] = { 17.0, 1.06, 0.26, 0.6 },
    [4] = { 19.0, 1.10, 0.40, 0.8 },
    [5] = { 21.5, 1.16, 0.55, 1.0 },
}

-- 类别 → 基础形状
local CLASS = {
    sword  = { w = 3.2, profile = "blade", guard = "cross" },
    great  = { w = 5.4, profile = "cleaver", guard = "cross" },
    axe    = { w = 6.2, profile = "axe", guard = "ring" },
    spear  = { w = 2.0, profile = "spear", guard = "ring" },
    hammer = { w = 5.0, profile = "hammer", guard = "ring" },
    dagger = { w = 2.4, profile = "blade", guard = "disc" },
}

-- 词条 → 视觉装饰。设计文档 5.3 的 32 条词条按「看得见的程度」归成 6 类
local AFFIX_LOOK = {
    fire = { glow = "ember", edge = 0.9 },
    frost = { glow = "ice", edge = 0.7 },
    void = { glow = "void", edge = 0.8 },
    blood = { glow = "blood", edge = 0.6 },
    crit = { teeth = true },
    guard = { rim = true },
}

W.AFFIX_LOOK = AFFIX_LOOK

-- ---------------------------------------------------------------- 轮廓

-- 刀身剖面：u=0 在护手，u=1 在刀尖。返回上沿半宽（负值）与下沿半宽
local function bladeProfile(kind, u, tier)
    local t = TIER[tier] or TIER[1]
    local base = 1 - u ^ 2.3          -- 向尖端收窄，指数越大收得越晚越锋利
    local wob = 0

    if kind == "cleaver" then
        -- 大剑：前段保持宽度，末端突然收成斜尖
        base = 1 - u ^ 5.5
    elseif kind == "axe" then
        -- 斧：中前段鼓出一个弧，是斧刃的典型剪影
        local bulge = math.max(0, sin((u - 0.42) / 0.5 * PI))
        base = 0.35 + bulge * 1.5
    elseif kind == "hammer" then
        -- 锤：整段等宽，末端平头
        base = u < 0.86 and 1 or 0.88
    elseif kind == "spear" then
        -- 枪：细长，只有最后 25% 才收
        base = u < 0.72 and 1 or (1 - (u - 0.72) / 0.28) ^ 1.4
    end

    -- 高阶刃口有细微波纹，暗示锻造工艺；低阶保持粗糙直线
    if t[4] > 0.6 and kind == "blade" then
        wob = sin(u * 9) * 0.03 * t[4]
    end
    return base + wob
end

-- 生成刀身多边形（含刃口高光需要的分段信息）
local function buildBlade(spec, rng)
    local kind = (CLASS[spec.class] or CLASS.sword)
    local tier = spec.bladeTier or 1
    local t = TIER[tier] or TIER[1]
    local len = t[1] * (spec.lenScale or 1)
    local halfW = kind.w * t[2] * 0.5

    local N = 11
    local top, bot = {}, {}
    local curve = t[3] * (spec.curve or 1)

    for i = 0, N do
        local u = i / N
        local p = bladeProfile(kind.profile, u, tier)
        -- 弯曲：整条刃沿 -Y 偏移，像弯刀那样
        local bend = -curve * (u ^ 1.7) * 3.0
        local y = bend
        local hw = halfW * p
        top[i + 1] = { u * len, y - hw, hw }
        bot[i + 1] = { u * len, y + hw, hw }
    end

    -- 闭合：上沿正序 + 下沿逆序
    local pts = {}
    for i = 1, N + 1 do
        pts[#pts + 1] = top[i][1]
        pts[#pts + 1] = top[i][2]
    end
    for i = N + 1, 1, -1 do
        pts[#pts + 1] = bot[i][1]
        pts[#pts + 1] = bot[i][2]
    end

    return {
        points = pts,
        len = len,
        halfW = halfW,
        top = top,
        bot = bot,
        curve = curve,
    }
end

-- ---------------------------------------------------------------- 组装

--[[
    由 spec 生成可绘制的武器描述。纯函数：同样的 spec 一定得到同样的结果。
    spec = {
        class = "sword"|"great"|"axe"|"spear"|"hammer"|"dagger",
        bladeTier = 1..5, bladeMat = "iron",
        hiltTier  = 1..5, hiltMat  = "wood",
        coreTier  = 1..5, coreMat  = "crystal",
        affixes   = { "fire", "crit" },   -- 可选，影响装饰
        seed      = 数字（不给就用部件信息算）
    }
]]
function W.build(spec)
    spec = spec or {}
    local cls = CLASS[spec.class] or CLASS.sword
    local tier = spec.bladeTier or 1
    local t = TIER[tier] or TIER[1]

    local seed = spec.seed or Rng.hash(spec.class or "sword", tier,
        spec.hiltTier or 1, spec.coreTier or 1, spec.bladeMat or "iron")
    local rng = Rng.new(seed)

    local blade = buildBlade(spec, rng)
    local hiltTier = spec.hiltTier or 1
    local gripLen = 5.4 + hiltTier * 0.5 + rng:range(-0.3, 0.3)
    local gripW = 1.5 + hiltTier * 0.1

    -- 护手：形状由类别决定，尺寸由柄的档位决定
    local guardW = (cls.guard == "cross") and (2.0 + hiltTier * 0.42) or (1.9 + hiltTier * 0.3)
    local guardT = 0.72 + hiltTier * 0.1

    -- 芯：宝石/符文，决定发光。档位越高越大越亮
    local coreTier = spec.coreTier or 1
    local gemR = 0.62 + coreTier * 0.2

    local affixGlow, affixEdge, teeth, rim = nil, 1, false, false
    for _, a in ipairs(spec.affixes or {}) do
        local look = AFFIX_LOOK[a]
        if look then
            if look.glow then affixGlow = look.glow end
            if look.teeth then teeth = true end
            if look.rim then rim = true end
            if look.edge then affixEdge = look.edge end
        end
    end

    local vis = {
        spec = spec,
        seed = seed,
        class = spec.class or "sword",
        blade = blade,
        grip = { len = gripLen, w = gripW },
        guard = { w = guardW, t = guardT, style = cls.guard },
        pommel = { r = 0.95 + hiltTier * 0.12 },
        gem = {
            r = gemR,
            at = blade.len * 0.10 + 0.9,
            mat = spec.coreMat or "crystal",
            glow = affixGlow or spec.coreMat or "crystal",
            tier = coreTier,
        },
        teeth = teeth,
        rim = rim,
        affixEdge = affixEdge,
        metalMat = spec.bladeMat or "iron",
        hiltMat = spec.hiltMat or "wood",
        -- 词条带来的额外光晕强度，画刀光时用
        glowPower = 0.35 + coreTier * 0.13 + (affixGlow and 0.35 or 0),
    }

    -- 刃口锯齿（暴击词条）：在下沿插一圈小三角
    if teeth then
        local spikes = {}
        local N = 6
        for i = 1, N do
            local u = i / (N + 1)
            local p = bladeProfile(cls.profile, u, tier)
            local hw = blade.halfW * p
            local x = u * blade.len
            local y = -blade.curve * (u ^ 1.7) * 3.0 + hw
            spikes[#spikes + 1] = { x, y, 0.55 + (i % 2) * 0.22 }
        end
        vis.spikes = spikes
    end

    return vis
end

-- ---------------------------------------------------------------- 绘制

function W.draw(g, vis, x, y, ang, scale, opts)
    opts = opts or {}
    scale = scale or 1
    g.push()
    g.translate(x or 0, y or 0)
    g.rotate(ang or 0)
    if scale ~= 1 then g.scale(scale) end

    local metal = vis.metalMat
    local hilt = vis.hiltMat

    -- 1) 刀身描边：用 line 模式沿轮廓走一圈，宽度独立于形状
    g.setColor(Palette.rgba(metal, "edge"))
    g.setLineWidth(1.15)
    g.polygon("line", unpack(vis.blade.points))

    -- 2) 刀身本体
    g.setColor(Palette.rgba(metal, "base"))
    g.polygon("fill", unpack(vis.blade.points))

    -- 3) 上沿高光：沿刃背画一条细带，金属感全靠它
    local top = vis.blade.top
    local band = {}
    for i = 1, #top - 1 do
        local a, b = top[i], top[i + 1]
        local h1 = math.max(0.35, a[3] * 0.38)
        local h2 = math.max(0.35, b[3] * 0.38)
        band[#band + 1] = a[1]
        band[#band + 1] = a[2]
        band[#band + 1] = b[1]
        band[#band + 1] = b[2]
        band[#band + 1] = b[1]
        band[#band + 1] = b[2] + h2
        band[#band + 1] = a[1]
        band[#band + 1] = a[2] + h1
    end
    if #band >= 8 then
        g.setColor(Palette.rgba(metal, "light"))
        g.polygon("fill", unpack(band))
    end

    -- 4) 刃口：下沿一条亮线（附词条时更亮，暗示元素附着）
    local bot = vis.blade.bot
    g.setColor(Palette.rgba(vis.gem.glow or metal, "glow", 0.35 + 0.3 * vis.affixEdge))
    g.setLineWidth(1.0)
    for i = 1, #bot - 1 do
        g.line(bot[i][1], bot[i][2], bot[i + 1][1], bot[i + 1][2])
    end

    -- 5) 锯齿（暴击词条）
    if vis.spikes then
        g.setColor(Palette.rgba(metal, "glow"))
        for _, s in ipairs(vis.spikes) do
            g.polygon("fill", s[1] - s[3], s[2], s[1] + s[3] * 0.2, s[2] + s[3] * 1.6,
                s[1] + s[3] * 0.4, s[2])
        end
    end

    -- 6) 护手
    local gw, gt = vis.guard.w, vis.guard.t
    g.setColor(Palette.rgba(hilt, "edge"))
    g.rectangle("fill", -gt * 0.9, -gw / 2 - 0.7, gt * 1.8 + 0.6, gw + 1.4, 1.0)
    g.setColor(Palette.rgba(vis.guard.style == "ring" and metal or hilt, "base"))
    if vis.guard.style == "disc" then
        g.circle("fill", 0, 0, gw * 0.5)
    elseif vis.guard.style == "ring" then
        g.rectangle("fill", -gt * 0.5, -gw / 2, gt, gw, gt * 0.5)
    else
        g.rectangle("fill", -gt * 0.5, -gw / 2, gt, gw, 0.8)
    end
    if vis.rim then
        g.setColor(Palette.rgba(hilt, "light", 0.9))
        g.setLineWidth(0.8)
        g.rectangle("line", -gt * 0.5, -gw / 2, gt, gw, 0.8)
    end

    -- 7) 柄：分段缠绳，段数随档位增加
    local gl, gwid = vis.grip.len, vis.grip.w
    g.setColor(Palette.rgba(hilt, "base"))
    g.rectangle("fill", -gl, -gwid / 2, gl, gwid, gwid * 0.35)
    g.setColor(Palette.rgba(hilt, "dark"))
    local wraps = 2 + (vis.spec.hiltTier or 1)
    for i = 1, wraps do
        local x0 = -gl * (i / (wraps + 1))
        g.rectangle("fill", x0 - 0.25, -gwid / 2, 0.5, gwid)
    end

    -- 8) 尾锤
    g.setColor(Palette.rgba(hilt, "edge"))
    g.circle("fill", -gl, 0, vis.pommel.r + 0.6)
    g.setColor(Palette.rgba(metal, "base"))
    g.circle("fill", -gl, 0, vis.pommel.r)

    -- 9) 芯：宝石。放在护手与刀身的交界处，最容易看见
    local gem = vis.gem
    g.setColor(Palette.rgba(gem.glow, "glow", 0.55 * (0.6 + gem.tier * 0.1)))
    g.circle("fill", gem.at - 1.4, 0, gem.r * 1.55)
    g.setColor(Palette.rgba(gem.mat, "light"))
    g.circle("fill", gem.at - 1.4, 0, gem.r)
    g.setColor(Palette.rgba(gem.mat, "glow"))
    g.circle("fill", gem.at - 1.4, 0, gem.r * 0.5)

    g.pop()
end

-- ---------------------------------------------------------------- 查询

-- 商店/背包里的图标尺寸：统一归一化，避免每把武器占不同格子
function W.bounds(vis)
    local minX, maxX = -vis.grip.len - vis.pommel.r, 0
    local minY, maxY = 0, 0
    local pts = vis.blade.points
    for i = 1, #pts, 2 do
        local x, y = pts[i], pts[i + 1]
        if x < minX then minX = x end
        if x > maxX then maxX = x end
        if y < minY then minY = y end
        if y > maxY then maxY = y end
    end
    local halfG = math.max(vis.guard.w, vis.guard.t) / 2
    if -halfG < minY then minY = -halfG end
    if halfG > maxY then maxY = halfG end
    return minX, minY, maxX, maxY
end

-- 供 UI 显示：从 spec 生成一句人类可读的描述
function W.describe(vis)
    local names = {
        sword = "剑", great = "大剑", axe = "战斧", spear = "长枪",
        hammer = "战锤", dagger = "短刃",
    }
    local parts = { "粗制", "精制", "淬火", "裂变", "终焉" }
    local s = vis.spec
    return string.format("%s%s · %s刃", parts[s.hiltTier or 1] or "粗制",
        names[vis.class] or "剑", parts[s.bladeTier or 1] or "粗制")
end

return W
