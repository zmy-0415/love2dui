--[[
    game/art/rig.lua —— 骨架（分部件刚性骨骼）

    为什么不做逐帧贴图：
        帧数据战斗要求同一个人在任意时刻有任意角度——前摇 6 帧、判定 3 帧、
        后摇 10 帧，每个动作还要能被「攻速词条」临时加速。手绘动画无法在
        运行时改节奏，而骨骼可以：姿势是关节角度的函数，改一帧的插值曲线
        就等于改了手感。

    节点的角度约定（重要，读代码前先记这三条）：
        1. 每个节点的 rest 是「世界角」，0 = 朝右，π/2 = 朝下。
           写骨架时用世界角，直观；绘制时自动换算成相对父节点的角。
        2. 节点沿本地 +X 延伸 len，宽度从 w0 收到 w1。
        3. 子节点挂在父节点 at*len 处（默认末端），可加 off 沿本地 Y 偏移。

    pose 是 { [节点名] = 相对 rest 的角度偏移 }。所以「手臂自然下垂」
    就是 pose 里不写它；「抬起 30°」写 -0.52。

    颜色走 palette 的材质键，节点上写 col = "cloth"、step = "dark"。
]]

local Palette = require("game.art.palette")

local Rig = {}

local unpack = table.unpack or unpack

-- ---------------------------------------------------------------- 绘制

-- 取色统一入口：受击闪白（tint）不用改节点表，只在这里偏置一次
local function colOf(node, step, opt)
    if opt.tint then
        local t = opt.tint
        local f = (step == "edge") and 0.45 or (step == "light" and 1.0 or 0.92)
        return t[1] * f, t[2] * f, t[3] * f
    end
    return Palette.rgba(node.col or "stone", step, opt.alpha)
end

local function paintTaper(g, node, opt)
    local len = node.len or 0
    local w0 = (node.w0 or 4) / 2
    local w1 = (node.w1 or w0 * 2) / 2
    local ow = node.outline ~= nil and node.outline or (opt.outline or 0)

    if ow > 0 then
        g.setColor(colOf(node, "edge", opt))
        g.polygon("fill",
            0, -w0 - ow,
            len + ow, -w1 - ow,
            len + ow, w1 + ow,
            0, w0 + ow)
    end

    local r, gg, b = colOf(node, node.step or "base", opt)
    g.setColor(r, gg, b, opt.alpha)
    g.polygon("fill", 0, -w0, len, -w1, len, w1, 0, w0)

    -- 顶光：沿上沿画一条细亮带，色块立刻有体积感（比加渐变便宜得多）
    if (node.shade ~= false) and opt.shade ~= false and len > 2 then
        local lr, lg, lb = colOf(node, "light", opt)
        g.setColor(lr, lg, lb, (opt.alpha or 1) * 0.75)
        local hw = math.min(w0, w1) * 0.34
        g.polygon("fill", 0, -w0, len, -w1, len, -w1 + hw * 2, 0, -w0 + hw * 2)
    end
end

local function paintCircle(g, node, opt)
    local r = node.radius or 4
    local ow = node.outline ~= nil and node.outline or (opt.outline or 0)
    if ow > 0 then
        g.setColor(colOf(node, "edge", opt))
        g.circle("fill", 0, 0, r + ow)
    end
    local cr, cg, cb = colOf(node, node.step or "base", opt)
    g.setColor(cr, cg, cb, opt.alpha)
    g.circle("fill", 0, 0, r)
    if (node.shade ~= false) and opt.shade ~= false then
        local lr, lg, lb = colOf(node, "light", opt)
        g.setColor(lr, lg, lb, (opt.alpha or 1) * 0.7)
        g.circle("fill", -r * 0.28, -r * 0.3, r * 0.45)
    end
end

local function paintPoly(g, node, opt)
    local pts = node.points
    if not pts then return end
    local ow = node.outline ~= nil and node.outline or (opt.outline or 0)
    if ow > 0 then
        g.setColor(colOf(node, "edge", opt))
        g.push()
        g.scale(1 + ow / 6, 1 + ow / 6)
        g.polygon("fill", unpack(pts))
        g.pop()
    end
    local r, gg, b = colOf(node, node.step or "base", opt)
    g.setColor(r, gg, b, opt.alpha)
    g.polygon("fill", unpack(pts))
end

local function paint(g, node, opt)
    local shape = node.shape or "taper"
    if shape == "taper" then
        paintTaper(g, node, opt)
    elseif shape == "circle" then
        paintCircle(g, node, opt)
    elseif shape == "poly" then
        paintPoly(g, node, opt)
    end

    -- 自发光：宝石、眼睛、弱点。单独一层，命中/阶段变化时只改这里
    if node.glow then
        local gr, gg, gb = Palette.rgba(node.glow, "glow", (opt.alpha or 1) * (node.glowAlpha or 0.85))
        g.setColor(gr, gg, gb, (opt.alpha or 1) * (node.glowAlpha or 0.85))
        local gr2 = node.glowRadius or math.max(1.5, (node.radius or 3) * 0.5)
        g.circle("fill", node.glowAt or 0, node.glowY or 0, gr2)
    end
end

local function drawNode(g, node, pose, parentRest, opt)
    local rest = node.rest or 0
    local localAng = rest - (parentRest or 0)
    local p = pose and pose[node.name]

    g.push()
    g.rotate(localAng + (p or 0))
    paint(g, node, opt)
    local kids = node.children
    if kids then
        for i = 1, #kids do
            local ch = kids[i]
            g.push()
            -- ax：沿父节点轴线的额外偏移（眼睛、甲片这类不长在关节上的东西要用）
            g.translate((node.len or 0) * (ch.at or 1) + (ch.ax or 0), ch.off or 0)
            drawNode(g, ch, pose, rest, opt)
            g.pop()
        end
    end
    g.pop()
end

--[[
    绘制一棵骨架。
    opts:
        x, y      根节点位置
        scale     整体缩放
        flip      水平镜像（朝左）
        outline   描边宽度，0 关闭
        alpha     整体透明度
        shade     关掉顶光
        tint      覆盖全部颜色，受击闪白用
]]
function Rig.draw(g, skel, pose, opts)
    opts = opts or {}
    g.push()
    g.translate(opts.x or 0, opts.y or 0)
    if opts.scale and opts.scale ~= 1 then g.scale(opts.scale) end
    if opts.flip then g.scale(-1, 1) end

    local opt = {
        outline = opts.outline == nil and 1.1 or opts.outline,
        alpha = opts.alpha or 1,
        shade = opts.shade,
        tint = opts.tint,
    }
    drawNode(g, skel, pose, nil, opt)

    g.pop()
end

-- ---------------------------------------------------------------- 查询

-- 深度优先找节点
function Rig.find(skel, name)
    if skel.name == name then return skel end
    local kids = skel.children
    if not kids then return nil end
    for i = 1, #kids do
        local hit = Rig.find(kids[i], name)
        if hit then return hit end
    end
    return nil
end

-- 统计节点数：性能预算与「怪物复杂度」冒烟测试都用得上
function Rig.count(skel)
    local n = 1
    local kids = skel.children
    if kids then
        for i = 1, #kids do n = n + Rig.count(kids[i]) end
    end
    return n
end

--[[
    求某节点末端的局部坐标与朝向（相对骨架根）。
    武器要握在手上、粒子要从刀尖出，都得先知道手在哪。
    返回 x, y, angle
]]
function Rig.tip(skel, pose, name)
    local path = {}
    local function walk(n, chain)
        chain[#chain + 1] = n
        if n.name == name then
            for i = 1, #chain do path[i] = chain[i] end
            return true
        end
        local kids = n.children
        if kids then
            for i = 1, #kids do
                if walk(kids[i], chain) then return true end
            end
        end
        chain[#chain] = nil
        return false
    end
    if not walk(skel, {}) then return 0, 0, 0 end
    return Rig.tipOfPath(path, pose)
end

-- 沿一条链累加变换，返回末端位置与角度
function Rig.tipOfPath(path, pose)
    local x, y, ang = 0, 0, 0
    for i = 1, #path do
        local n = path[i]
        local rest = n.rest or 0
        local parentRest = i > 1 and (path[i - 1].rest or 0) or 0
        local a = ang + (rest - parentRest) + ((pose and pose[n.name]) or 0)
        local len = (n.len or 0) * ((n.children and 1) or 1)
        -- 节点自身沿本地 +X 走满 len
        x = x + math.cos(a) * len
        y = y + math.sin(a) * len
        ang = a
    end
    return x, y, ang
end

-- 节点根位置（腕/肩），arm 抬起时武器要挂在这里
function Rig.joint(skel, pose, name)
    local x, y, a = Rig.tip(skel, pose, name)
    local node = Rig.find(skel, name)
    if node then
        local len = node.len or 0
        return x - math.cos(a) * len, y - math.sin(a) * len, a
    end
    return x, y, a
end

return Rig
