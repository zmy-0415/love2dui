--[[
    tools/softraster.lua —— 纯 Lua 软件光栅器（离线出图，不需要显卡）

    存在的理由很简单：CI 和这台机器都没有 OpenGL，但美术效果必须能被看到、
    被比对、被回归。所以这里实现 love.graphics 的一个子集，把绘制调用直接
    光栅化到内存位图，再存成 BMP。

    覆盖的 API（签名与 LÖVE 一致，便于同一份绘制代码两边跑）：
        setColor / push / pop / translate / rotate / scale / origin
        polygon(fill|line) / circle(fill|line) / ellipse(fill|line)
        line (折线) / rectangle(fill|line[, rx, ry]) / points
        setLineWidth / setScissor / setCanvas / clear / print / printf / draw

    不做的：文字（print 只占位）、纹理（draw 只占位）、混合模式、着色器。
    画不出来的东西不会报错，只会被跳过——这保证「同一份代码在真机与软栅
    上都能跑」，软栅只负责几何与配色这两件最需要回归的事。

    用法：
        local sr = require("tools.softraster")
        local g = sr.new(640, 360)
        g.setColor(0.2, 0.3, 0.9, 1)
        g.circle("fill", 320, 180, 80)
        g:saveBMP("out.bmp")
]]

local ffi = require("ffi")

local M = {}

local floor, sin, cos, sqrt = math.floor, math.sin, math.cos, math.sqrt
local unpack = table.unpack or unpack   -- LÖVE 用 LuaJIT（5.1），没有 table.unpack
local huge = math.huge

-- ---------------------------------------------------------------- 位图

local Canvas = {}
Canvas.__index = Canvas

function M.new(w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Canvas)
    self.w, self.h = w, h
    self.buf = ffi.new("uint8_t[?]", w * h * 4)
    self.depth = 0
    self.lw = 1
    self.tx, self.ty = 0, 0            -- origin 偏移（LÖVE 的 graphics.origin）
    self.color = { 1, 1, 1, 1 }
    self.stack = {}
    self.calls = {}                    -- 与 fake_backend 同构的调用计数
    self.scissor = nil
    self.m = { 1, 0, 0, 1, 0, 0 }

    -- 把每个方法绑定到实例，制成 g.setColor(...) 这种 LÖVE 风格的 API。
    -- 同一份绘制代码要能在真机（love.graphics，模块级函数）和这里跑，
    -- 所以调用风格必须一致：一律点号，不走冒号。
    for name, fn in pairs(Canvas) do
        if type(fn) == "function" then
            self[name] = function(...) return fn(self, ...) end
        end
    end

    self.clear(opts.r or 0, opts.g or 0, opts.b or 0, opts.a or 1)
    return self
end

function Canvas:rec(name)
    self.calls[name] = (self.calls[name] or 0) + 1
end

-- 变换用一个 6 元组：x' = a*x + c*y + e, y' = b*x + d*y + f
local function matIdentity()
    return { 1, 0, 0, 1, 0, 0 }
end

function Canvas:resetTransform()
    self.m = { 1, 0, 0, 1, 0, 0 }
    self.tx, self.ty = 0, 0
end

function Canvas:push()
    self.rec("push")
    local m = self.m
    self.depth = self.depth + 1
    self.stack[self.depth] = { m[1], m[2], m[3], m[4], m[5], m[6], self.lw, self.tx, self.ty }
end

function Canvas:pop()
    self.rec("pop")
    if self.depth <= 0 then return end
    local s = self.stack[self.depth]
    self.stack[self.depth] = nil
    self.depth = self.depth - 1
    self.m = { s[1], s[2], s[3], s[4], s[5], s[6] }
    self.lw, self.tx, self.ty = s[7], s[8], s[9]
end

function Canvas:translate(x, y)
    self.rec("translate")
    self.m[5] = self.m[5] + self.m[1] * x + self.m[3] * y
    self.m[6] = self.m[6] + self.m[2] * x + self.m[4] * y
end

function Canvas:rotate(r)
    self.rec("rotate")
    local c, s = cos(r), sin(r)
    local m = self.m
    local a, b, cc, d = m[1], m[2], m[3], m[4]
    m[1] = a * c + cc * s
    m[2] = b * c + d * s
    m[3] = cc * c - a * s
    m[4] = d * c - b * s
end

function Canvas:scale(sx, sy)
    self.rec("scale")
    sy = sy or sx
    local m = self.m
    m[1], m[2], m[3], m[4] = m[1] * sx, m[2] * sx, m[3] * sy, m[4] * sy
end

function Canvas:origin()
    self.rec("origin")
end

function Canvas:setColor(r, g, b, a)
    self.rec("setColor")
    -- 允许调色板直接给 0~255 的整数，省掉调用侧反复除 255
    if r and r > 1 then r = r / 255 end
    if g and g > 1 then g = g / 255 end
    if b and b > 1 then b = b / 255 end
    self.color[1] = r or 1
    self.color[2] = g or r or 1
    self.color[3] = b or r or 1
    self.color[4] = a or 1
end

function Canvas:setLineWidth(w) self.rec("setLineWidth") self.lw = w or 1 end
function Canvas:setLineStyle() self.rec("setLineStyle") end
function Canvas:setLineJoin() self.rec("setLineJoin") end
function Canvas:setFont() self.rec("setFont") end
function Canvas:setStencilTest() end
function Canvas:setCanvas() self.rec("setCanvas") end
function Canvas:setBlendMode() end
function Canvas:setShader() end

function Canvas:setScissor(x, y, w, h)
    self.rec("setScissor")
    if x == nil then self.scissor = nil
    else self.scissor = { x, y, w, h } end
end

function Canvas:getScissor() return nil end

function Canvas:clear(r, g, b, a)
    self.rec("clear")
    r, g, b, a = r or 0, g or 0, b or 0, a or 1
    local buf = self.buf
    local R, G, B = floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5)
    local A = floor(a * 255 + 0.5)
    for i = 0, self.w * self.h - 1 do
        local o = i * 4
        buf[o] = R
        buf[o + 1] = G
        buf[o + 2] = B
        buf[o + 3] = A
    end
end

-- ---------------------------------------------------------------- 像素

function Canvas:px(x, y)
    if x < 0 or y < 0 or x >= self.w or y >= self.h then return end
    local sc = self.scissor
    if sc and (x < sc[1] or y < sc[2] or x >= sc[1] + sc[3] or y >= sc[2] + sc[4]) then return end
    local c = self.color
    local a = c[4]
    if a <= 0 then return end
    local o = (y * self.w + x) * 4
    local buf = self.buf
    if a >= 1 then
        buf[o] = floor(c[1] * 255 + 0.5)
        buf[o + 1] = floor(c[2] * 255 + 0.5)
        buf[o + 2] = floor(c[3] * 255 + 0.5)
        buf[o + 3] = 255
        return
    end
    local ia = 1 - a
    buf[o] = floor(c[1] * 255 * a + buf[o] * ia + 0.5)
    buf[o + 1] = floor(c[2] * 255 * a + buf[o + 1] * ia + 0.5)
    buf[o + 2] = floor(c[3] * 255 * a + buf[o + 2] * ia + 0.5)
    buf[o + 3] = floor(255 * a + buf[o + 3] * ia + 0.5)
end

-- ---------------------------------------------------------------- 多边形填充

-- 就近取整的扫描线填充（奇偶规则）。屏幕空间的点是奇偶交替的 x 交点对。
function Canvas:fillPolys(pts, n)
    if n < 3 then return end
    local minY, maxY = huge, -huge
    for i = 1, n do
        local y = pts[i * 2]
        if y < minY then minY = y end
        if y > maxY then maxY = y end
    end
    local y0 = floor(minY)
    local y1 = floor(maxY)
    if y1 < y0 then return end
    if y0 < 0 then y0 = 0 end
    if y1 > self.h - 1 then y1 = self.h - 1 end

    local xs = {}
    for py = y0, y1 do
        local sy = py + 0.5
        local count = 0
        for i = 1, n do
            local j = i % n + 1
            local x1, y1v = pts[i * 2 - 1], pts[i * 2]
            local x2, y2v = pts[j * 2 - 1], pts[j * 2]
            if (y1v <= sy and y2v > sy) or (y2v <= sy and y1v > sy) then
                count = count + 1
                xs[count] = x1 + (sy - y1v) / (y2v - y1v) * (x2 - x1)
            end
        end
        if count >= 2 then
            -- 交点一般很少，插入排序比 table.sort 省
            for i = 2, count do
                local v = xs[i]
                local k = i - 1
                while k >= 1 and xs[k] > v do
                    xs[k + 1] = xs[k]
                    k = k - 1
                end
                xs[k + 1] = v
            end
            for i = 1, count - 1, 2 do
                local xa = floor(xs[i] + 0.5)
                local xb = floor(xs[i + 1] - 0.5)
                for px = xa, xb do self.px(px, py) end
            end
        end
    end
end

-- 把可变参数形式的顶点收集成屏幕空间数组，返回 (pts, n)
function Canvas:xform(...)
    local m = self.m
    local n = select("#", ...)
    local pts = {}
    local k = 0
    for i = 1, n, 2 do
        local x, y = select(i, ...), select(i + 1, ...)
        k = k + 1
        pts[k] = m[1] * x + m[3] * y + m[5] + self.tx
        pts[k + 1] = m[2] * x + m[4] * y + m[6] + self.ty
        k = k + 1
    end
    return pts, k / 2
end

function Canvas:polygon(mode, ...)
    self.rec("polygon")
    local pts, n = self.xform(...)
    if mode == "fill" then
        self.fillPolys(pts, n)
    else
        for i = 1, n do
            local j = i % n + 1
            self.seg(pts[i * 2 - 1], pts[i * 2], pts[j * 2 - 1], pts[j * 2])
        end
    end
end

function Canvas:points(...)
    self.rec("points")
    local pts, n = self.xform(...)
    for i = 1, n do
        self.disc(pts[i * 2 - 1], pts[i * 2], 1)
    end
end

-- 粗线段：用矩形近似，宽度取当前变换缩放后的 lineWidth
function Canvas:seg(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local len = sqrt(dx * dx + dy * dy)
    if len < 1e-6 then return end
    local m = self.m
    local s = sqrt(math.abs(m[1] * m[4] - m[2] * m[3]))
    if s < 1e-6 then s = 1 end
    local hw = (self.lw * s) / 2
    if hw < 0.5 then hw = 0.5 end
    local nx, ny = -dy / len * hw, dx / len * hw
    self.fillPolys({
        x1 + nx, y1 + ny,
        x2 + nx, y2 + ny,
        x2 - nx, y2 - ny,
        x1 - nx, y1 - ny,
    }, 4)
    -- 端点补圆：否则折线在拐角处会缺一个扇形的口子
    if hw > 0.6 then
        self.disc(x1, y1, hw)
        self.disc(x2, y2, hw)
    end
end

function Canvas:line(...)
    self.rec("line")
    local pts, n = self.xform(...)
    if n == 1 then return end
    for i = 1, n - 1 do
        self.seg(pts[i * 2 - 1], pts[i * 2], pts[i * 2 + 1], pts[i * 2 + 2])
    end
end

-- 实心圆（扫描线求交，避免多边形近似出现棱角）
function Canvas:disc(cx, cy, r)
    if r <= 0 then return end
    local y0 = floor(cy - r)
    local y1 = floor(cy + r)
    if y0 < 0 then y0 = 0 end
    if y1 > self.h - 1 then y1 = self.h - 1 end
    for py = y0, y1 do
        local dy = (py + 0.5) - cy
        local d2 = r * r - dy * dy
        if d2 > 0 then
            local dx = sqrt(d2)
            local xa = floor(cx - dx + 0.5)
            local xb = floor(cx + dx - 0.5)
            for px = xa, xb do self.px(px, py) end
        end
    end
end

local SEGS = 48

function Canvas:circle(mode, x, y, r)
    self.rec("circle")
    local m = self.m
    local sx = sqrt(math.abs(m[1] * m[4] - m[2] * m[3]))
    local cx = m[1] * x + m[3] * y + m[5] + self.tx
    local cy = m[2] * x + m[4] * y + m[6] + self.ty
    local rr = r * (sx > 1e-6 and sx or 1)
    if mode == "fill" then
        self.disc(cx, cy, rr)
    else
        local pts = {}
        for i = 0, SEGS - 1 do
            local a = i / SEGS * math.pi * 2
            pts[i * 2 + 1] = cx + cos(a) * rr
            pts[i * 2 + 2] = cy + sin(a) * rr
        end
        for i = 1, SEGS do
            local j = i % SEGS + 1
            self.seg(pts[i * 2 - 1], pts[i * 2], pts[j * 2 - 1], pts[j * 2])
        end
    end
end

function Canvas:ellipse(mode, x, y, rx, ry)
    self.rec("ellipse")
    local pts = {}
    for i = 1, SEGS do
        local a = (i - 1) / SEGS * math.pi * 2
        pts[i * 2 - 1] = x + cos(a) * rx
        pts[i * 2] = y + sin(a) * ry
    end
    local sp, n = self.xform(unpack(pts))
    if mode == "fill" then
        self.fillPolys(sp, n)
    else
        for i = 1, n do
            local j = i % n + 1
            self.seg(sp[i * 2 - 1], sp[i * 2], sp[j * 2 - 1], sp[j * 2])
        end
    end
end

-- 圆角矩形：LÖVE 的 rx/ry 是圆角半径（rx 为 nil 时是普通矩形）
function Canvas:rectangle(mode, x, y, w, h, rx, ry)
    self.rec("rectangle")
    if not rx or rx <= 0 then
        local pts, n = self.xform(x, y, x + w, y, x + w, y + h, x, y + h)
        if mode == "fill" then
            self.fillPolys(pts, n)
        else
            for i = 1, n do
                local j = i % n + 1
                self.seg(pts[i * 2 - 1], pts[i * 2], pts[j * 2 - 1], pts[j * 2])
            end
        end
        return
    end
    rx = math.min(rx, w / 2)
    ry = math.min(ry or rx, h / 2)
    local pts = {}
    local k = 0
    local corners = {
        { x + w - rx, y + ry, -math.pi / 2 },
        { x + w - rx, y + h - ry, 0 },
        { x + rx, y + h - ry, math.pi / 2 },
        { x + rx, y + ry, math.pi },
    }
    for _, c in ipairs(corners) do
        for i = 0, 7 do
            local a = c[3] + i / 7 * (math.pi / 2)
            k = k + 1
            pts[k] = c[1] + cos(a) * rx
            pts[k + 1] = c[2] + sin(a) * ry
            k = k + 1
        end
    end
    local sp, n = self.xform(unpack(pts))
    if mode == "fill" then
        self.fillPolys(sp, n)
    else
        for i = 1, n do
            local j = i % n + 1
            self.seg(sp[i * 2 - 1], sp[i * 2], sp[j * 2 - 1], sp[j * 2])
        end
    end
end

-- 文字与纹理：软栅画不了，占位即可（真机上的观感另行目测）
function Canvas:print() self.rec("print") end
function Canvas:printf() self.rec("printf") end
function Canvas:draw() self.rec("draw") end
function Canvas:newText() return { set = function() end } end
function Canvas:newFont() return { getHeight = function() return 12 end, getWidth = function() return 6 end } end
function Canvas:newCanvas() return self end
function Canvas:newImageData() return { encode = function() return { getString = function() return "" end } end } end

-- ---------------------------------------------------------------- 输出

-- BMP 32 位（BGRA，自下而上）。不压缩，纯手写头部，
-- 好处是零依赖：Python 的 PIL 打不开的机器上也能直接看。
function Canvas:saveBMP(path)
    local w, h = self.w, self.h
    local dataSize = w * 4 * h
    local f = assert(io.open(path, "wb"))
    local function u16(v) f:write(string.char(v % 256, floor(v / 256) % 256)) end
    local function u32(v)
        f:write(string.char(v % 256, floor(v / 256) % 256, floor(v / 65536) % 256, floor(v / 16777216) % 256))
    end
    f:write("BM")
    u32(54 + dataSize)
    u16(0)
    u16(0)
    u32(54)
    u32(40)
    u32(w)
    u32(h)
    u16(1)
    u16(32)
    u32(0)
    u32(dataSize)
    u32(2835)
    u32(2835)
    u32(0)
    u32(0)

    local buf = self.buf
    local row = ffi.new("uint8_t[?]", w * 4)
    for y = h - 1, 0, -1 do
        local base = y * w * 4
        for x = 0, w - 1 do
            local i = base + x * 4
            local o = x * 4
            row[o] = buf[i + 2]
            row[o + 1] = buf[i + 1]
            row[o + 2] = buf[i]
            row[o + 3] = 255
        end
        f:write(ffi.string(row, w * 4))
    end
    f:close()
    return path
end

-- 截图对比用：返回像素的 32 位校验和（位图回归测试只需要一个数）
function Canvas:checksum()
    local buf = self.buf
    local n = self.w * self.h * 4
    local hsh = 2166136261
    for i = 0, n - 1 do
        hsh = hsh ~ buf[i]
        hsh = (hsh * 16777619) % 4294967296
    end
    return hsh
end

function Canvas:getPixel(x, y)
    local o = (y * self.w + x) * 4
    return self.buf[o], self.buf[o + 1], self.buf[o + 2], self.buf[o + 3]
end

return M
