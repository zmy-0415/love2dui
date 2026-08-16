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

-- scissor 裁剪栈
draw.scissors = {}

function draw.pushClip(x, y, w, h)
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
    table.insert(draw.scissors, { px, py, pw, ph, has })
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
