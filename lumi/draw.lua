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

--[[
    绘制状态去重
    LÖVE 的 setColor/setFont 每次调用都要跨 Lua/C 边界并写入渲染状态，
    而界面里大量连续绘制使用同一颜色/字体。这里记录当前值，相同则直接跳过。
    注意：love.graphics.push("all") / pop() 会保存并恢复渲染状态，
    跨越这类栈操作后必须调用 draw.resetState()，否则缓存与真实状态不一致。
]]
local lastColorR, lastColorG, lastColorB, lastColorA
local hasColor = false
local lastFont

-- 接受 {r,g,b[,a]} 或 r,g,b[,a] 两种形式
function draw.setColor(c, g, b, a)
    local r, gg, bb, aa
    if type(c) == "table" then
        r, gg, bb, aa = c[1], c[2], c[3], c[4]
    else
        r, gg, bb, aa = c, g, b, a
    end
    r, gg, bb = r or 0, gg or 0, bb or 0
    aa = aa or 1
    if hasColor and r == lastColorR and gg == lastColorG and bb == lastColorB and aa == lastColorA then
        return
    end
    love.graphics.setColor(r, gg, bb, aa)
    lastColorR, lastColorG, lastColorB, lastColorA = r, gg, bb, aa
    hasColor = true
end

function draw.setFont(f)
    if f ~= nil and f ~= lastFont then
        love.graphics.setFont(f)
        lastFont = f
    end
end

-- 状态栈（push/pop、切换 Canvas 等）之后调用，丢弃缓存
function draw.resetState()
    hasColor = false
    lastFont = nil
end

-- 常用常量，避免每次绘制新建颜色/空表
local WHITE = { 1, 1, 1, 1 }
local WHITE3 = { 1, 1, 1 }
local EMPTY_OPTS = {}

-- 文本测宽缓存：按字体分表，超过上限整体清空（简单且没有 LRU 记账开销）
local widthCaches = setmetatable({}, { __mode = "k" })
local WIDTH_CACHE_MAX = 512

function draw.textWidth(f, text)
    if not text or text == "" or not f then return 0 end
    local cache = widthCaches[f]
    if not cache then
        cache = { n = 0 }
        widthCaches[f] = cache
    end
    local w = cache[text]
    if w ~= nil then return w end
    w = f:getWidth(text)
    if w == nil then return 0 end
    if cache.n >= WIDTH_CACHE_MAX then
        for k in pairs(cache) do cache[k] = nil end
        cache.n = 0
    end
    cache[text] = w
    cache.n = cache.n + 1
    return w
end

-- 圆角弧单位坐标（模块加载时算一次，绘制时不再做三角函数）
local SEG = 6
local CORNER = {}
do
    local modes = { {}, {}, {}, {} }
    for i = 0, SEG do
        local a = (math.pi / 2) * (i / SEG)
        local c, s = math.cos(a), math.sin(a)
        modes[1][#modes[1] + 1] = { s, -c }    -- 右上
        modes[2][#modes[2] + 1] = { c, s }     -- 右下
        modes[3][#modes[3] + 1] = { -s, c }    -- 左下
        modes[4][#modes[4] + 1] = { -c, -s }   -- 左上
    end
    CORNER = modes
end

-- 顶点缓冲复用：每条圆角矩形固定 4 角 × (SEG+1) 点 × 2 分量 = 56 个数字，
-- 每次写入同一张表（polygon 立即消费，不存在跨调用持有）。填充/描边各一份，避免嵌套覆盖。
local fillVerts, lineVerts = {}, {}

local function writeRoundRect(pts, x, y, w, h, r)
    local n = 0
    for m = 1, 4 do
        local unit = CORNER[m]
        local cx, cy
        if m == 1 then cx, cy = x + w - r, y + r
        elseif m == 2 then cx, cy = x + w - r, y + h - r
        elseif m == 3 then cx, cy = x + r, y + h - r
        else cx, cy = x + r, y + r end
        for i = 1, #unit do
            local p = unit[i]
            n = n + 1; pts[n] = cx + p[1] * r
            n = n + 1; pts[n] = cy + p[2] * r
        end
    end
    return n
end

-- 填充圆角矩形（不做颜色处理，供 stencil 遮罩等内部复用）
local function fillRounded(x, y, w, h, r)
    r = clamp(r or 0, 0, math.min(w, h) / 2)
    if r <= 0 then
        love.graphics.rectangle("fill", x, y, w, h)
        return
    end
    writeRoundRect(fillVerts, x, y, w, h, r)
    love.graphics.polygon("fill", fillVerts)
end

-- 填充圆角矩形
function draw.roundRect(x, y, w, h, r, color)
    if w <= 0 or h <= 0 then return end
    draw.setColor(color)
    fillRounded(x, y, w, h, r)
end

-- 描边圆角矩形
function draw.roundRectLine(x, y, w, h, r, color, lineWidth)
    if w <= 0 or h <= 0 then return end
    local lw = lineWidth or 1
    draw.setColor(color)
    love.graphics.setLineWidth(lw)
    local ix, iy = x + lw / 2, y + lw / 2
    local iw, ih = w - lw, h - lw
    local rr = clamp(r or 0, 0, math.min(iw, ih) / 2)
    if rr <= 0 then
        love.graphics.rectangle("line", ix, iy, iw, ih)
        return
    end
    writeRoundRect(lineVerts, ix, iy, iw, ih, rr)
    love.graphics.polygon("line", lineVerts)
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
            local a = intensity * (1 - t) * (1 - t)
            layers[i] = {
                a = a,
                color = { 0, 0, 0, a },   -- 颜色表随分层缓存，绘制时不再每层新建
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
        draw.roundRect(x - L.spread, y + L.dy, w + L.spread * 2, h + L.spread * 2, r + L.spread, L.color)
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

-- 把任意字节位置对齐到合法字符边界（超过串长返回串长）
-- 用于外部设置的光标/偏移：直接 clamp 字节数可能落进多字节字符内部，绘制与删除都会错位
function draw.utf8Align(s, i)
    local n = #s
    if not i or i <= 0 then return 0 end
    if i > n then return n end
    -- 若该位置正好是续字节（10xxxxxx），向前回退到字符起始字节
    while i > 0 do
        local b = s:byte(i + 1)
        if b and b >= 0x80 and b < 0xC0 then
            i = i - 1
        else
            break
        end
    end
    return i
end

-- 单行文本（可选省略号截断，按字符边界二分避免截断多字节字符）
function draw.truncate(font, text, maxWidth)
    if draw.textWidth(font, text) <= maxWidth then return text end
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
        if draw.textWidth(font, s) <= maxWidth then
            lo = mid
        else
            hi = mid - 1
        end
    end
    return text:sub(1, chars[lo + 1]) .. ell
end

-- 绘制文本，opts: font/color/align/limit(换行宽度)/ellipsis/valign
function draw.text(str, x, y, w, opts)
    opts = opts or EMPTY_OPTS
    str = str or ""
    local font = opts.font
    local color = opts.color or WHITE
    local align = opts.align or "left"

    draw.setFont(font)
    draw.setColor(color)

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
    opts = opts or EMPTY_OPTS
    local iw, ih = img:getDimensions()
    if iw <= 0 or ih <= 0 then return end
    local dx, dy, dw, dh = draw.calcFit(iw, ih, w, h, opts.fit)
    draw.setColor(opts.tint or WHITE3)
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
        fillRounded(x, y, w, h, r)
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
        draw.setColor(0, 0, 0, 0)
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
