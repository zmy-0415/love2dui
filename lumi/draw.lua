--[[
    draw.lua —— 底层绘制工具
    圆角矩形 / 阴影 / 文本 / 裁剪（scissor 栈）/ 颜色插值
]]

local draw = {}

local function clamp(v, lo, hi)
    if lo ~= nil and v < lo then return lo end
    if hi ~= nil and v > hi then return hi end
    return v
end

-- 颜色插值（a、b 为 {r,g,b} 或 {r,g,b,a}）
function draw.lerpColor(a, b, t)
    local n = math.max(#a, #b)
    local out = {}
    for i = 1, n do
        out[i] = (a[i] or 0) + ((b[i] or 0) - (a[i] or 0)) * t
    end
    return out
end

-- 圆角弧顶点缓存（按分段数缓存，避免每帧重复三角函数运算）
local cornerArcCache = {}
local function cornerArc(seg)
    local arc = cornerArcCache[seg]
    if not arc then
        arc = {}
        for i = 0, seg do
            local a = (math.pi / 2) * (i / seg)
            arc[#arc + 1] = { c = math.cos(a), s = math.sin(a) }
        end
        cornerArcCache[seg] = arc
    end
    return arc
end

-- 生成圆角矩形多边形顶点（用于填充）
local function roundRectPoints(x, y, w, h, r)
    r = clamp(r or 0, 0, math.min(w, h) / 2)
    if r <= 0 then
        return { x, y, x + w, y, x + w, y + h, x, y + h }
    end
    local seg = 6
    local arc = cornerArc(seg)
    local pts = {}
    local function corner(cx, cy, mode)
        for i = 1, #arc do
            local c, s = arc[i].c, arc[i].s
            local dx, dy
            if mode == 1 then          -- -90..0: (sin, -cos)
                dx, dy = s, -c
            elseif mode == 2 then      -- 0..90: (cos, sin)
                dx, dy = c, s
            elseif mode == 3 then      -- 90..180: (-sin, cos)
                dx, dy = -s, c
            else                       -- 180..270: (-cos, -sin)
                dx, dy = -c, -s
            end
            pts[#pts + 1] = cx + dx * r
            pts[#pts + 1] = cy + dy * r
        end
    end
    corner(x + w - r, y + r, 1)        -- 右上
    corner(x + w - r, y + h - r, 2)    -- 右下
    corner(x + r, y + h - r, 3)        -- 左下
    corner(x + r, y + r, 4)            -- 左上
    return pts
end

-- 填充圆角矩形
function draw.roundRect(x, y, w, h, r, color)
    if w <= 0 or h <= 0 then return end
    love.graphics.setColor(color)
    love.graphics.polygon("fill", roundRectPoints(x, y, w, h, r))
end

-- 描边圆角矩形
function draw.roundRectLine(x, y, w, h, r, color, lineWidth)
    if w <= 0 or h <= 0 then return end
    love.graphics.setColor(color)
    love.graphics.setLineWidth(lineWidth or 1)
    love.graphics.polygon("line", roundRectPoints(x + (lineWidth or 1) / 2, y + (lineWidth or 1) / 2, w - (lineWidth or 1), h - (lineWidth or 1), r))
end

-- 阴影分层参数缓存（按 elevation 缓存）
local shadowCache = {}
local function shadowLayers(elevation)
    local layers = shadowCache[elevation]
    if not layers then
        layers = {}
        local n = 3 + elevation * 2
        local intensity = math.min(0.22, 0.08 + elevation * 0.04)
        for i = 1, n do
            local t = i / n
            layers[i] = {
                a = intensity * (1 - t) * (1 - t),
                spread = t * elevation * 1.5,
                dy = t * elevation * 1.1,
            }
        end
        shadowCache[elevation] = layers
    end
    return layers
end

-- 绘制柔和阴影（多层半透明圆角叠加，模拟高斯模糊）
function draw.shadow(x, y, w, h, r, elevation)
    elevation = elevation or 0
    if elevation <= 0 then return end
    local layers = shadowLayers(elevation)
    for i = 1, #layers do
        local L = layers[i]
        draw.roundRect(x - L.spread, y + L.dy, w + L.spread * 2, h + L.spread * 2, r + L.spread, { 0, 0, 0, L.a })
    end
end

-- ---------------- UTF-8 工具（Lua 5.1 无内置 utf8 库） ----------------

-- 从字节位置 i 返回下一个字符的结束边界（i 为当前字符起点/光标 0 基位置）；无则返回 nil
function draw.utf8Next(s, i)
    local b = s:byte(i + 1)
    if not b then return nil end
    local len = 1
    if b >= 0xC0 and b < 0xE0 then len = 2
    elseif b >= 0xE0 and b < 0xF0 then len = 3
    elseif b >= 0xF0 and b < 0xF8 then len = 4 end
    return i + len
end

-- 返回光标位置 i（0..len 字节位）之前一个字符边界；无则返回 0
function draw.utf8Prev(s, i)
    if i <= 0 then return 0 end
    local j = i
    while j >= 1 do
        local b = s:byte(j)
        if b >= 0x80 and b < 0xC0 then
            j = j - 1
        else
            break
        end
    end
    return j - 1
end

-- 字符数量
function draw.utf8Len(s)
    local n = 0
    local i = 0
    while true do
        i = draw.utf8Next(s, i)
        if not i then break end
        n = n + 1
    end
    return n
end

-- 单行文本（可选省略号截断，按字符边界二分避免截断多字节字符）
function draw.truncate(font, text, maxWidth)
    if font:getWidth(text) <= maxWidth then return text end
    local ell = "…"
    local chars = { 0 }
    local i = 0
    while true do
        i = draw.utf8Next(text, i)
        if not i then break end
        chars[#chars + 1] = i
    end
    local lo, hi = 0, #chars - 1
    while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        local s = text:sub(1, chars[mid + 1]) .. ell
        if font:getWidth(s) <= maxWidth then
            lo = mid
        else
            hi = mid - 1
        end
    end
    return text:sub(1, chars[lo + 1]) .. ell
end

-- 绘制文本，opts: font/color/align/limit(换行宽度)/ellipsis/valign
function draw.text(str, x, y, w, opts)
    opts = opts or {}
    str = str or ""
    local font = opts.font
    local color = opts.color or { 1, 1, 1, 1 }
    local align = opts.align or "left"

    love.graphics.setFont(font)
    love.graphics.setColor(color)

    if opts.limit and opts.limit > 0 then
        love.graphics.printf(str, x, y, opts.limit, align)
    else
        local text = str
        if opts.ellipsis and w and w > 0 then
            text = draw.truncate(font, str, w)
        end
        love.graphics.print(text, x, y)
    end
end

-- ---------------- 图片绘制 ----------------

-- 计算 fit 布局：返回 dx, dy, dw, dh（绘制区域，相对 x/y 的偏移与尺寸）
-- fit: contain（完整放入）/ cover（铺满裁剪，需配合裁剪使用）/ stretch（拉伸变形）/ center（原始尺寸居中）
function draw.calcFit(iw, ih, w, h, fit)
    fit = fit or "stretch"
    if fit == "stretch" or fit == "fill" then
        return 0, 0, w, h
    elseif fit == "center" then
        return (w - iw) / 2, (h - ih) / 2, iw, ih
    end
    local s
    if fit == "cover" then
        s = math.max(w / iw, h / ih)
    else -- contain
        s = math.min(w / iw, h / ih)
    end
    local dw, dh = iw * s, ih * s
    return (w - dw) / 2, (h - dh) / 2, dw, dh
end

-- 绘制图片（自动 fit）。opts: fit / tint（{r,g,b[,a]} 染色）
-- 注意 fit="cover" 时超出 w/h 的部分不会被裁剪，调用方需自行 clip
function draw.image(img, x, y, w, h, opts)
    if not img or w <= 0 or h <= 0 then return end
    opts = opts or {}
    local iw, ih = img:getDimensions()
    if iw <= 0 or ih <= 0 then return end
    local dx, dy, dw, dh = draw.calcFit(iw, ih, w, h, opts.fit)
    love.graphics.setColor(opts.tint or { 1, 1, 1 })
    if opts.fit == "stretch" or opts.fit == "fill" then
        love.graphics.draw(img, x, y, 0, w / iw, h / ih)
    elseif opts.fit == "center" then
        love.graphics.draw(img, x + dx, y + dy)
    else
        love.graphics.draw(img, x + dx, y + dy, 0, dw / iw, dh / ih)
    end
end

-- 在圆角矩形遮罩内绘制（fn 为绘制回调，基于 stencil 实现，兼容 LÖVE 11/12）
function draw.inRound(x, y, w, h, r, fn)
    draw.stencilMask(function()
        love.graphics.polygon("fill", roundRectPoints(x, y, w, h, r))
    end, fn)
end

-- 在圆形遮罩内绘制（fn 为绘制回调）
function draw.inCircle(cx, cy, r, fn)
    draw.stencilMask(function()
        love.graphics.circle("fill", cx, cy, r)
    end, fn)
end

-- 通用模板裁剪：maskFn 绘制遮罩形状（不可见），随后仅遮罩内可见地执行 fn
function draw.stencilMask(maskFn, fn)
    if love.graphics.setStencilMode then
        -- LÖVE 12：状态式 API；draw 模式不屏蔽颜色写入，遮罩需以全透明色绘制
        love.graphics.setStencilMode("draw", 1)
        love.graphics.setColor(0, 0, 0, 0)
        maskFn()
        love.graphics.setStencilMode("test", 1)
        fn()
        love.graphics.setStencilMode()
    else
        -- LÖVE 11：回调式 API
        love.graphics.stencil(maskFn, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
        fn()
        love.graphics.setStencilTest()
    end
end

-- scissor 裁剪栈
draw.scissors = {}

-- scissor 坐标偏移（Canvas 缓存渲染时非零：世界坐标 → 缓存纹理局部坐标）
draw.clipOffsetX = 0
draw.clipOffsetY = 0

-- 当前 scissor 栈顶矩形（即当前生效的裁剪区）内是否可见；无裁剪时恒可见
function draw.rectVisible(x, y, w, h)
    local top = draw.scissors[#draw.scissors]
    if not top then return true end
    local px, py, pw, ph = top[6], top[7], top[8], top[9]
    if pw <= 0 or ph <= 0 then return false end -- 裁剪区为空，全部不可见
    return x < px + pw and x + w > px and y < py + ph and y + h > py
end

function draw.pushClip(x, y, w, h)
    x = x + draw.clipOffsetX
    y = y + draw.clipOffsetY
    local px, py, pw, ph = love.graphics.getScissor()
    local has = (px ~= nil)
    local nx, ny, nw, nh
    if has then
        nx = math.max(x, px)
        ny = math.max(y, py)
        local rx = math.min(x + w, px + pw)
        local ry = math.min(y + h, py + ph)
        nw = math.max(0, rx - nx)
        nh = math.max(0, ry - ny)
    else
        nx, ny, nw, nh = x, y, w, h
    end
    -- 保存 push 前状态（1..5）与 push 后生效矩形（6..9，供 rectVisible 快速剔除）
    table.insert(draw.scissors, { px, py, pw, ph, has, nx, ny, nw, nh })
    love.graphics.setScissor(nx, ny, nw, nh)
end

function draw.popClip()
    local prev = table.remove(draw.scissors)
    if not prev then return end
    if prev[5] then
        love.graphics.setScissor(prev[1], prev[2], prev[3], prev[4])
    else
        love.graphics.setScissor()
    end
end

return draw
