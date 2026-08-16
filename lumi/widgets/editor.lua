--[[
    editor.lua —— 多行文本编辑器
    支持多行文本、光标/选区（跨行）、UTF-8 与中文 IME、剪贴板、纵向/横向滚动、
    行号栏（lineNumbers）、onChange/onSubmit。

    为后续扩展预留的接口：
      - 语法高亮：覆写 renderLine(font, lineText, lineIdx, x, y, color) 按片段着色
      - 撤销/重做：所有文本修改统一走 _replace(a, b, text)，配合 snapshot()/restore()
      - 行号显示：props.lineNumbers + drawLineNumbers()/gutterW()
      - 查找/替换：find(text, from) 返回字节区间，scrollToOffset()/selectRange() 定位
      - 软换行（word wrap）：渲染已按「可见行」循环，未来可在此引入视觉行迭代
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local Editor = setmetatable({}, { __index = Widget })
Editor.__index = Editor

local function isShift()
    return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
end

local function isCtrl()
    return love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
end

local function inRect(x, y, rx, ry, rw, rh)
    return x >= rx and x < rx + rw and y >= ry and y < ry + rh
end

function Editor.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Editor)
    self._text = props.text or ""
    self.cursor = #self._text
    self._selAnchor = nil
    self._prefCol = nil
    self._imeText = nil
    self._lineStarts = { 0 }
    self._maxLineW = 0
    self._linesDirty = true
    self.isScroll = true -- 参与滚轮路由：让滚轮命中本编辑器，而非冒泡到外层滚动容器
    self.scrollX = 0
    self.scrollY = 0
    self._dragScroll = nil
    return self
end

-- ---------------- 文本模型（字节偏移 0..len，与 Input 一致） ----------------

function Editor:getText()
    return self._text
end

function Editor:setText(text)
    self._text = text or ""
    self.cursor = #self._text
    self._selAnchor = nil
    self._prefCol = nil
    self._linesDirty = true
    self.scrollX = 0
    self.scrollY = 0
    self:invalidate()
    self:emit("onChange", self._text)
end

-- 统一变更入口：删除 [a,b] 字节区间（0-based，半开），插入 newText。
-- 所有文本修改（插入/退格/删除/粘贴/剪切/回车）都汇聚于此，
-- 后续撤销/重做只需在此前后记录快照入命令栈。
function Editor:_replace(a, b, newText)
    a = math.max(0, math.min(#self._text, a))
    b = math.max(a, math.min(#self._text, b))
    self._text = self._text:sub(1, a) .. (newText or "") .. self._text:sub(b + 1)
    self.cursor = a + #(newText or "")
    self._selAnchor = nil
    self._prefCol = nil
    self._linesDirty = true
    self:invalidate()
    self:emit("onChange", self._text)
end

-- 行索引缓存：行起始字节偏移数组（1-based 行号 → 0-based 字节偏移）
function Editor:rebuildLines()
    local starts = { 0 }
    local text = self._text
    local f = font.get(theme.font.body)
    local maxW = 0
    local pos = 0
    while true do
        local n = text:find("\n", pos + 1, true)
        local lineEnd = n and (n - 1) or #text
        local w = f:getWidth(text:sub(pos + 1, lineEnd))
        if w > maxW then maxW = w end
        if not n then break end
        starts[#starts + 1] = n
        pos = n
    end
    self._lineStarts = starts
    self._maxLineW = maxW
    self._linesDirty = false
end

function Editor:getLineStarts()
    if self._linesDirty then self:rebuildLines() end
    return self._lineStarts
end

function Editor:lineCount()
    return #self:getLineStarts()
end

-- 第 i 行（1-based）起始字节偏移
function Editor:lineStart(i)
    local starts = self:getLineStarts()
    return starts[i] or #self._text
end

-- 第 i 行（1-based）结束字节偏移（不含换行符）
function Editor:lineEnd(i)
    local starts = self:getLineStarts()
    if i < #starts then
        return starts[i + 1] - 1
    end
    return #self._text
end

function Editor:getLineText(i)
    local a = self:lineStart(i)
    return self._text:sub(a + 1, self:lineEnd(i))
end

-- 字节偏移 → (行号, 字符列)
function Editor:offsetToRowCol(offset)
    local starts = self:getLineStarts()
    local row = 1
    for i = #starts, 1, -1 do
        if starts[i] <= offset then row = i; break end
    end
    local col = draw.utf8Len(self._text:sub(starts[row] + 1, offset))
    return row, col
end

-- (行号, 字符列) → 字节偏移（列超出该行长度时 clamp 到行尾）
function Editor:rowColToOffset(row, col)
    local starts = self:getLineStarts()
    row = math.max(1, math.min(#starts, row))
    local a = starts[row]
    local lineText = self._text:sub(a + 1, self:lineEnd(row))
    local i = 0
    for _ = 1, col do
        local n = draw.utf8Next(lineText, i)
        if not n then break end
        i = n
    end
    return a + i
end

function Editor:getCursorRowCol()
    return self:offsetToRowCol(self.cursor)
end

function Editor:setCursorRowCol(row, col)
    self.cursor = self:rowColToOffset(row, col)
    self._prefCol = col
    self._selAnchor = nil
end

-- ---------------- 选区（字节区间，语义同 Input） ----------------

function Editor:selectionRange()
    if self._selAnchor == nil then return nil end
    local a, b = self.cursor, self._selAnchor
    if a > b then a, b = b, a end
    return a, b
end

function Editor:hasSelection()
    local a, b = self:selectionRange()
    return a ~= nil and b > a
end

function Editor:selectRange(a, b)
    self._selAnchor = a
    self.cursor = b
    self._prefCol = nil
end

function Editor:copy()
    local a, b = self:selectionRange()
    if a and b > a then
        love.system.setClipboardText(self._text:sub(a + 1, b))
    end
end

function Editor:cut()
    local a, b = self:selectionRange()
    if a and b > a then
        love.system.setClipboardText(self._text:sub(a + 1, b))
        self:_replace(a, b, "")
    end
end

function Editor:paste()
    local text = love.system.getClipboardText()
    if text and #text > 0 then
        self:textinput(text, nil)
    end
end

-- 查找子串（0-based 字节区间 [start, finish)），供查找/替换扩展使用
function Editor:find(text, from)
    from = from or 0
    local s = self._text:find(text, from + 1, true)
    if not s then return nil end
    return s - 1, s - 1 + #text
end

-- 撤销/重做扩展的接口：快照与恢复
function Editor:snapshot()
    return {
        text = self._text,
        cursor = self.cursor,
        anchor = self._selAnchor,
        scrollX = self.scrollX,
        scrollY = self.scrollY,
    }
end

function Editor:restore(snap)
    if not snap then return end
    self._text = snap.text
    self.cursor = snap.cursor
    self._selAnchor = snap.anchor
    self.scrollX = snap.scrollX or 0
    self.scrollY = snap.scrollY or 0
    self._prefCol = nil
    self._linesDirty = true
    self:invalidate()
end

-- ---------------- 尺寸与滚动 ----------------

function Editor:padding()
    return 12, 8
end

function Editor:lineHeight()
    return font.get(theme.font.body):getHeight()
end

-- 滚动条预留宽度（纵向/横向滚动条占用，避免文本被遮挡）
function Editor:scrollbarReserve()
    return 8
end

function Editor:gutterW()
    if not self.props.lineNumbers then return 0 end
    local n = self:lineCount()
    local digits = 1
    while n >= 10 do n = math.floor(n / 10); digits = digits + 1 end
    local cf = font.get(theme.font.caption)
    return 10 + digits * cf:getWidth("0") + 10
end

function Editor:viewWidth()
    return self.w - self:padding() * 2 - self:gutterW() - self:scrollbarReserve()
end

function Editor:viewHeight()
    return self.h - self:padding() * 2 - self:scrollbarReserve()
end

function Editor:contentWidth()
    self:getLineStarts()
    return self._maxLineW
end

function Editor:contentHeight()
    return self:lineCount() * self:lineHeight()
end

function Editor:clampScroll()
    local maxY = math.max(0, self:contentHeight() - self:viewHeight())
    local maxX = math.max(0, self:contentWidth() - self:viewWidth())
    self.scrollY = math.max(0, math.min(maxY, self.scrollY))
    self.scrollX = math.max(0, math.min(maxX, self.scrollX))
end

-- ---------------- 滚动条交互 ----------------

function Editor:hasVScrollbar()
    return self:contentHeight() - self:viewHeight() > 0
end

function Editor:hasHScrollbar()
    return self:contentWidth() - self:viewWidth() > 0
end

-- 纵向/横向滚动条轨道矩形（两者同时存在时互不重叠）
function Editor:vScrollbarRect()
    local trackW = 6
    local x = self.x + self.w - trackW - 3
    local y = self.y + 3
    local h = self.h - 6
    if self:hasHScrollbar() then h = h - trackW - 6 end
    return x, y, trackW, h
end

function Editor:hScrollbarRect()
    local trackW = 6
    local x = self.x + 3
    local y = self.y + self.h - trackW - 3
    local w = self.w - 6
    if self:hasVScrollbar() then w = w - trackW - 6 end
    return x, y, w, trackW
end

-- 拖动纵向滚动条：thumb 中心跟随鼠标 y
function Editor:scrollFromVY(y)
    local maxScroll = self:contentHeight() - self:viewHeight()
    if maxScroll <= 0 then return end
    local _, trackY, trackW, trackH = self:vScrollbarRect()
    local thumbH = math.max(24, trackH * (self:viewHeight() / self:contentHeight()))
    local usable = math.max(1, trackH - thumbH)
    local ratio = (y - trackY - thumbH / 2) / usable
    self.scrollY = math.max(0, math.min(1, ratio)) * maxScroll
end

-- 拖动横向滚动条：thumb 中心跟随鼠标 x
function Editor:scrollFromHX(x)
    local maxScroll = self:contentWidth() - self:viewWidth()
    if maxScroll <= 0 then return end
    local trackX, _, trackW, _ = self:hScrollbarRect()
    local thumbW = math.max(24, trackW * (self:viewWidth() / self:contentWidth()))
    local usable = math.max(1, trackW - thumbW)
    local ratio = (x - trackX - thumbW / 2) / usable
    self.scrollX = math.max(0, math.min(1, ratio)) * maxScroll
end

function Editor:measureContent(availW, availH)
    local lh = self:lineHeight()
    local _, padY = self:padding()
    local lines = math.max(1, self:lineCount())
    if self.props.minLines then lines = math.max(lines, self.props.minLines) end
    if self.props.maxLines then lines = math.min(lines, self.props.maxLines) end
    return self.props.w or 280, lines * lh + padY * 2
end

function Editor:onUpdate(dt)
    self:clampScroll()
end

-- 使光标所在位置滚动到可视区
function Editor:scrollToCursor()
    self:scrollToOffset(self.cursor)
end

function Editor:scrollToOffset(offset)
    local row = self:offsetToRowCol(offset)
    local lh = self:lineHeight()
    local f = font.get(theme.font.body)
    local rowTop = (row - 1) * lh
    local viewH = self:viewHeight()
    if rowTop < self.scrollY then
        self.scrollY = rowTop
    elseif rowTop + lh > self.scrollY + viewH then
        self.scrollY = rowTop + lh - viewH
    end
    local x = f:getWidth(self._text:sub(self:lineStart(row) + 1, offset))
    local viewW = self:viewWidth()
    if x < self.scrollX then
        self.scrollX = x
    elseif x > self.scrollX + viewW then
        self.scrollX = x - viewW
    end
    self:clampScroll()
end

-- ---------------- 光标移动（键控） ----------------

function Editor:moveHorizontal(dir, shift)
    if shift and self._selAnchor == nil then self._selAnchor = self.cursor end
    if dir < 0 then
        self.cursor = draw.utf8Prev(self._text, self.cursor)
    else
        self.cursor = draw.utf8Next(self._text, self.cursor) or #self._text
    end
    if not shift then self._selAnchor = nil end
    self._prefCol = nil
    self:scrollToCursor()
end

function Editor:moveVertical(dir, shift)
    if shift and self._selAnchor == nil then self._selAnchor = self.cursor end
    local row, col = self:offsetToRowCol(self.cursor)
    local targetRow = row + dir
    if targetRow < 1 then
        targetRow = 1
        col = 0
    elseif targetRow > self:lineCount() then
        targetRow = self:lineCount()
        col = draw.utf8Len(self:getLineText(targetRow))
    elseif self._prefCol then
        col = self._prefCol
    else
        self._prefCol = col
    end
    self.cursor = self:rowColToOffset(targetRow, col)
    if not shift then self._selAnchor = nil end
    self:scrollToCursor()
end

function Editor:moveHome(shift)
    if shift and self._selAnchor == nil then self._selAnchor = self.cursor end
    self.cursor = self:lineStart(self:offsetToRowCol(self.cursor))
    if not shift then self._selAnchor = nil end
    self._prefCol = nil
    self:scrollToCursor()
end

function Editor:moveEnd(shift)
    if shift and self._selAnchor == nil then self._selAnchor = self.cursor end
    self.cursor = self:lineEnd(self:offsetToRowCol(self.cursor))
    if not shift then self._selAnchor = nil end
    self._prefCol = nil
    self:scrollToCursor()
end

function Editor:backspace()
    local a, b = self:selectionRange()
    if a and b > a then
        self:_replace(a, b, "")
    else
        local prev = draw.utf8Prev(self._text, self.cursor)
        if prev < self.cursor then
            self:_replace(prev, self.cursor, "")
        end
    end
    self:scrollToCursor()
end

function Editor:deleteForward()
    local a, b = self:selectionRange()
    if a and b > a then
        self:_replace(a, b, "")
    else
        local nxt = draw.utf8Next(self._text, self.cursor)
        if nxt then
            self:_replace(self.cursor, nxt, "")
        end
    end
    self:scrollToCursor()
end

function Editor:pageScroll(dir)
    self.scrollY = self.scrollY + dir * self:viewHeight()
    self:clampScroll()
end

-- ---------------- 焦点与输入法 ----------------

function Editor:isFocusable()
    return not self.state.disabled
end

function Editor:focus()
    self.state.focused = true
    self:updateTextInput()
end

function Editor:blur()
    self.state.focused = false
    self._imeText = nil
    love.keyboard.setTextInput(false)
end

-- 更新系统文本输入区域，让输入法候选窗定位到本编辑器（每帧调用保持位置最新）
function Editor:updateTextInput()
    if not self.state.focused or self.state.disabled then return end
    love.keyboard.setTextInput(true, self.x, self.y, self.w, self.h)
end

-- ---------------- 事件 ----------------

function Editor:keypressed(key, ctx)
    if self.state.disabled then return end

    if isCtrl() then
        if key == "a" then
            self._selAnchor = 0
            self.cursor = #self._text
        elseif key == "c" then
            self:copy()
        elseif key == "x" then
            self:cut()
        elseif key == "v" then
            self:paste()
        elseif key == "home" then
            self._selAnchor = nil
            self.cursor = 0
        elseif key == "end" then
            self._selAnchor = nil
            self.cursor = #self._text
        end
        self:scrollToCursor()
        return
    end

    local shift = isShift()

    if key == "backspace" then
        self:backspace()
    elseif key == "delete" then
        self:deleteForward()
    elseif key == "left" then
        self:moveHorizontal(-1, shift)
    elseif key == "right" then
        self:moveHorizontal(1, shift)
    elseif key == "up" then
        self:moveVertical(-1, shift)
    elseif key == "down" then
        self:moveVertical(1, shift)
    elseif key == "home" then
        self:moveHome(shift)
    elseif key == "end" then
        self:moveEnd(shift)
    elseif key == "return" or key == "kpenter" then
        local a, b = self:selectionRange()
        if a and b > a then
            self:_replace(a, b, "\n")
        else
            self:_replace(self.cursor, self.cursor, "\n")
        end
        self:scrollToCursor()
    elseif key == "pageup" then
        self:pageScroll(-1)
    elseif key == "pagedown" then
        self:pageScroll(1)
    end
end

function Editor:textinput(t, ctx)
    if self.state.disabled then return end
    -- 统一换行符（粘贴的 Windows 文本可能带 \r\n）
    t = t:gsub("\r\n", "\n"):gsub("\r", "\n")
    self._imeText = nil
    local a, b = self:selectionRange()
    if a and b > a then
        self:_replace(a, b, t)
    else
        self:_replace(self.cursor, self.cursor, t)
    end
    self:scrollToCursor()
end

-- 输入法组合中（打字预览）：仅用于显示，不写入 _text
function Editor:textedited(text, start, length, ctx)
    if self.state.disabled then return end
    self._imeText = (text and #text > 0) and text or nil
end

function Editor:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    if self:hasVScrollbar() and inRect(x, y, self:vScrollbarRect()) then
        self._dragScroll = "v"
        self:scrollFromVY(y)
        return
    end
    if self:hasHScrollbar() and inRect(x, y, self:hScrollbarRect()) then
        self._dragScroll = "h"
        self:scrollFromHX(x)
        return
    end
    self._selAnchor = nil
    self._prefCol = nil
    self:setCursorFromXY(x, y)
end

-- 拖拽选择 / 拖拽滚动条
function Editor:mousemoved(x, y, ctx)
    if self._dragScroll == "v" then
        self:scrollFromVY(y)
        return
    elseif self._dragScroll == "h" then
        self:scrollFromHX(x)
        return
    end
    if self.state.pressed then
        if self._selAnchor == nil then self._selAnchor = self.cursor end
        self._prefCol = nil
        self:setCursorFromXY(x, y)
    end
end

function Editor:mousereleased(x, y, button, ctx, hit)
    self._dragScroll = nil
end

function Editor:wheelmoved(x, y, ctx)
    if isShift() then
        self.scrollX = self.scrollX - y * 40
    else
        self.scrollY = self.scrollY - y * 40
    end
    self:clampScroll()
end

-- 按 (x, y) 定位光标（屏幕坐标 → 行/列 → 字节偏移）
function Editor:setCursorFromXY(x, y)
    local padX, padY = self:padding()
    local lh = self:lineHeight()
    local textX = self.x + padX + self:gutterW() - self.scrollX
    local textY = self.y + padY - self.scrollY
    local row = math.floor((y - textY) / lh) + 1
    row = math.max(1, math.min(self:lineCount(), row))
    self.cursor = self:lineStart(row) + self:colFromX(self:getLineText(row), x - textX)
end

-- 按行内 x 坐标定位列（沿字符边界遍历，返回字节偏移）
function Editor:colFromX(lineText, tx)
    local f = font.get(theme.font.body)
    local best, bestDist = 0, math.huge
    local i = 0
    while true do
        local d = math.abs(f:getWidth(lineText:sub(1, i)) - tx)
        if d < bestDist then bestDist = d; best = i end
        i = draw.utf8Next(lineText, i)
        if not i then break end
    end
    return best
end

-- ---------------- 绘制 ----------------

-- 单行渲染（语法高亮扩展点：覆写本方法按 token 分段着色）
function Editor:renderLine(fontObj, lineText, lineIdx, x, y, color)
    love.graphics.setFont(fontObj)
    love.graphics.setColor(color)
    love.graphics.print(lineText, x, y)
end

function Editor:drawLineNumbers(firstRow, lastRow, ty, viewH)
    local gutter = self:gutterW()
    if gutter <= 0 then return end
    local cf = font.get(theme.font.caption)
    local lh = self:lineHeight()
    love.graphics.setColor(theme.color("border"))
    love.graphics.rectangle("fill", self.x + self:padding() + gutter - 5, ty, 1, viewH)
    for row = firstRow, lastRow do
        local rowY = ty + (row - 1) * lh - self.scrollY
        local num = tostring(row)
        local nx = self.x + self:padding() + gutter - 5 - 8 - cf:getWidth(num)
        love.graphics.setFont(cf)
        love.graphics.setColor(theme.color("muted"))
        love.graphics.print(num, nx, rowY + (lh - cf:getHeight()) / 2)
    end
end

function Editor:drawContent()
    local p = self.props
    local f = font.get(theme.font.body)
    local lh = self:lineHeight()
    local padX, padY = self:padding()
    local gutter = self:gutterW()
    local radius = self:resolveRadius(p.radius, theme.shape.medium)

    draw.roundRect(self.x, self.y, self.w, self.h, radius, theme.color("surface2"))

    local borderColor = theme.color("border")
    local borderW = 1
    if self.state.focused then
        borderColor = theme.color("primary")
        borderW = 2
    end
    draw.roundRectLine(self.x, self.y, self.w, self.h, radius, borderColor, borderW)

    local tx = self.x + padX + gutter
    local ty = self.y + padY
    local viewW = self:viewWidth()
    local viewH = self:viewHeight()

    draw.pushClip(tx, ty, viewW, viewH)

    local firstRow = math.floor(self.scrollY / lh) + 1
    local lastRow = math.floor((self.scrollY + viewH) / lh) + 1
    local total = self:lineCount()
    if lastRow > total then lastRow = total end
    if firstRow > lastRow then firstRow = lastRow end

    local selA, selB
    if self.state.focused then
        selA, selB = self:selectionRange()
    end

    for row = firstRow, lastRow do
        local rowY = ty + (row - 1) * lh - self.scrollY
        local ls = self:lineStart(row)
        local le = self:lineEnd(row)
        local lineText = self._text:sub(ls + 1, le)
        local textX = tx - self.scrollX

        -- 选区高亮（跨行选区在每一行分别绘制交集片段）
        if selA and selB and selB > selA then
            local a = math.max(selA, ls)
            local b = math.min(selB, le)
            if b > a then
                local x0 = textX + f:getWidth(self._text:sub(ls + 1, a))
                local x1 = textX + f:getWidth(self._text:sub(ls + 1, b))
                love.graphics.setColor(theme.alpha("primary", 0.28))
                love.graphics.rectangle("fill", x0, rowY, x1 - x0, lh)
            end
        end

        self:renderLine(f, lineText, row, textX, rowY, theme.color("text"))
    end

    -- placeholder
    if #self._text == 0 and not self._imeText and p.placeholder then
        draw.text(p.placeholder, tx, ty, 0, { font = f, color = theme.color("muted") })
    end

    -- 输入法组合文本（带下划线）
    if self._imeText and #self._imeText > 0 then
        local row = self:offsetToRowCol(self.cursor)
        local px = tx + f:getWidth(self._text:sub(self:lineStart(row) + 1, self.cursor)) - self.scrollX
        local py = ty + (row - 1) * lh - self.scrollY
        love.graphics.setFont(f)
        love.graphics.setColor(theme.color("primary"))
        love.graphics.print(self._imeText, px, py)
        love.graphics.setLineWidth(1.5)
        love.graphics.line(px, py + f:getHeight() + 1, px + f:getWidth(self._imeText), py + f:getHeight() + 1)
    end

    -- 光标
    if self.state.focused and not self.state.disabled and not self:hasSelection() then
        if (love.timer.getTime() % 1) < 0.55 then
            local row = self:offsetToRowCol(self.cursor)
            local cx = tx + f:getWidth(self._text:sub(self:lineStart(row) + 1, self.cursor)) - self.scrollX
            local cy = ty + (row - 1) * lh - self.scrollY
            love.graphics.setColor(theme.color("primary"))
            love.graphics.rectangle("fill", cx, cy, 1.5, lh)
        end
    end

    draw.popClip()

    self:drawLineNumbers(firstRow, lastRow, ty, viewH)
    self:drawScrollbars()
end

function Editor:drawScrollbars()
    if self:hasVScrollbar() then
        local x, y, w, h = self:vScrollbarRect()
        draw.roundRect(x, y, w, h, w / 2, theme.alpha("text", 0.06))
        local thumbH = math.max(24, h * (self:viewHeight() / self:contentHeight()))
        local thumbY = y + (h - thumbH) * (self.scrollY / (self:contentHeight() - self:viewHeight()))
        draw.roundRect(x, thumbY, w, thumbH, w / 2, theme.alpha("text", 0.28))
    end
    if self:hasHScrollbar() then
        local x, y, w, h = self:hScrollbarRect()
        draw.roundRect(x, y, w, h, h / 2, theme.alpha("text", 0.06))
        local thumbW = math.max(24, w * (self:viewWidth() / self:contentWidth()))
        local thumbX = x + (w - thumbW) * (self.scrollX / (self:contentWidth() - self:viewWidth()))
        draw.roundRect(thumbX, y, thumbW, h, h / 2, theme.alpha("text", 0.28))
    end
end

return Editor
