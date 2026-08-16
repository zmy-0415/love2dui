--[[
    input.lua —— 文本输入框
    支持 label、placeholder、password 掩码、光标、中文 IME 输入、onChange/onSubmit。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local Input = setmetatable({}, { __index = Widget })
Input.__index = Input

local function isShift()
    return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
end

local function isCtrl()
    return love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
end

function Input.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Input)
    self._text = props.text or ""
    self.cursor = #self._text
    self._imeText = nil
    self._selAnchor = nil
    return self
end

function Input:isFocusable()
    return not self.state.disabled
end

function Input:focus()
    self.state.focused = true
    self:updateTextInput()
end

function Input:blur()
    self.state.focused = false
    self._imeText = nil
    love.keyboard.setTextInput(false)
end

-- 更新系统文本输入区域，让输入法候选窗定位到本输入框（每帧调用保持位置最新）
function Input:updateTextInput()
    if not self.state.focused or self.state.disabled then return end
    local labelH = self:getLabelHeight()
    love.keyboard.setTextInput(true, self.x, self.y + labelH, self.w, self.h - labelH)
end

function Input:getText()
    return self._text
end

function Input:setText(text)
    self._text = text or ""
    self.cursor = #self._text
    self._selAnchor = nil
    self:invalidate()
    self:emit("onChange", self._text)
end

-- 返回选区 [start, finish]（字节下标，start<=finish），无选区返回 nil
function Input:selectionRange()
    if self._selAnchor == nil then return nil end
    local a, b = self.cursor, self._selAnchor
    if a > b then a, b = b, a end
    return a, b
end

function Input:hasSelection()
    local a, b = self:selectionRange()
    return a ~= nil and b > a
end

-- 删除 [a, b] 字节区间的选区
function Input:deleteRange(a, b)
    self._text = self._text:sub(1, a) .. self._text:sub(b + 1)
    self.cursor = a
    self._selAnchor = nil
end

function Input:copy()
    local a, b = self:selectionRange()
    if a and b > a then
        love.system.setClipboardText(self._text:sub(a + 1, b))
    end
end

function Input:cut()
    local a, b = self:selectionRange()
    if a and b > a then
        love.system.setClipboardText(self._text:sub(a + 1, b))
        self:deleteRange(a, b)
        self:emit("onChange", self._text)
    end
end

function Input:paste()
    local text = love.system.getClipboardText()
    if text and #text > 0 then
        self:textinput(text, nil)
    end
end

-- 将「前 n 个字符」换算为字节下标
function Input:charToByte(n)
    local i = 0
    for _ = 1, n do
        i = draw.utf8Next(self._text, i)
        if not i then break end
    end
    return i
end

function Input:getLabelHeight()
    if not self.props.label then return 0 end
    return font.get(theme.font.caption):getHeight() + 6
end

function Input:measureContent(availW, availH)
    local fieldH = self.props.height or theme.control.height
    return self.props.w or 240, fieldH + self:getLabelHeight()
end

-- 按 x 坐标定位光标（沿字符边界遍历）
function Input:setCursorFromX(x)
    local f = font.get(theme.font.body)
    local padX = 12
    local masked = self.props.password and true or false
    local display = masked and string.rep("•", draw.utf8Len(self._text)) or self._text
    local tx = x - (self.x + padX)
    local best, bestDist = 0, math.huge
    local i = 0
    while true do
        local d = math.abs(f:getWidth(display:sub(1, i)) - tx)
        if d < bestDist then bestDist = d; best = i end
        i = draw.utf8Next(display, i)
        if not i then break end
    end
    if masked then
        self.cursor = self:charToByte(best)
    else
        self.cursor = best
    end
end

function Input:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    self._selAnchor = nil
    self:setCursorFromX(x)
end

-- 拖拽选择
function Input:mousemoved(x, y, ctx)
    if self.state.pressed then
        if self._selAnchor == nil then self._selAnchor = self.cursor end
        self:setCursorFromX(x)
    end
end

function Input:textinput(t, ctx)
    if self.state.disabled then return end
    self._imeText = nil
    local a, b = self:selectionRange()
    if a and b > a then
        self:deleteRange(a, b)
    end
    self._text = self._text:sub(1, self.cursor) .. t .. self._text:sub(self.cursor + 1)
    self.cursor = self.cursor + #t
    self:emit("onChange", self._text)
end

-- 输入法组合中（打字预览）：text 为当前候选/拼音，仅用于显示，不写入 _text
function Input:textedited(text, start, length, ctx)
    if self.state.disabled then return end
    self._imeText = (text and #text > 0) and text or nil
end

function Input:keypressed(key, ctx)
    if self.state.disabled then return end

    -- 剪贴板快捷键
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
        end
        return
    end

    local shift = isShift()

    if key == "backspace" then
        local a, b = self:selectionRange()
        if a and b > a then
            self:deleteRange(a, b)
            self:emit("onChange", self._text)
        else
            local prev = draw.utf8Prev(self._text, self.cursor)
            if prev < self.cursor then
                self._text = self._text:sub(1, prev) .. self._text:sub(self.cursor + 1)
                self.cursor = prev
                self:emit("onChange", self._text)
            end
        end
    elseif key == "delete" then
        local a, b = self:selectionRange()
        if a and b > a then
            self:deleteRange(a, b)
            self:emit("onChange", self._text)
        else
            local nxt = draw.utf8Next(self._text, self.cursor)
            if nxt then
                self._text = self._text:sub(1, self.cursor) .. self._text:sub(nxt + 1)
                self:emit("onChange", self._text)
            end
        end
    elseif key == "left" then
        if shift and self._selAnchor == nil then self._selAnchor = self.cursor end
        if not shift then self._selAnchor = nil end
        self.cursor = draw.utf8Prev(self._text, self.cursor)
    elseif key == "right" then
        if shift and self._selAnchor == nil then self._selAnchor = self.cursor end
        if not shift then self._selAnchor = nil end
        self.cursor = draw.utf8Next(self._text, self.cursor) or #self._text
    elseif key == "home" then
        if shift and self._selAnchor == nil then self._selAnchor = self.cursor end
        if not shift then self._selAnchor = nil end
        self.cursor = 0
    elseif key == "end" then
        if shift and self._selAnchor == nil then self._selAnchor = self.cursor end
        if not shift then self._selAnchor = nil end
        self.cursor = #self._text
    elseif key == "return" or key == "kpenter" then
        self:emit("onSubmit", self._text)
        if ctx then ctx:setFocus(nil) end
    end
end

function Input:drawContent()
    local p = self.props
    local caption = font.get(theme.font.caption)
    local labelH = self:getLabelHeight()

    if p.label then
        draw.text(p.label, self.x, self.y, 0, { font = caption, color = theme.color("muted") })
    end

    local fx, fy = self.x, self.y + labelH
    local fw, fh = self.w, self.h - labelH
    local radius = self:resolveRadius(p.radius, theme.shape.medium)

    draw.roundRect(fx, fy, fw, fh, radius, theme.color("surface2"))

    local borderColor = theme.color("border")
    local borderW = 1
    if self.state.focused then
        borderColor = theme.color("primary")
        borderW = 2
    end
    draw.roundRectLine(fx, fy, fw, fh, radius, borderColor, borderW)

    local f = font.get(theme.font.body)
    local display = self._text
    local cursorByte = self.cursor
    if p.password then
        display = string.rep("•", draw.utf8Len(self._text))
        -- 掩码字符是多字节的，需把「光标前字符数」换算为 display 的字节位置，
        -- 否则 display:sub(1, cursorByte) 会截断多字节字符导致解码错误
        cursorByte = draw.utf8Len(self._text:sub(1, self.cursor)) * #"•"
    end
    local imeText = self._imeText
    local padX = 12
    local textY = fy + (fh - f:getHeight()) / 2

    -- 选区（仅非密码、聚焦时显示）
    local selA, selB
    if not p.password and self.state.focused then
        selA, selB = self:selectionRange()
    end

    draw.pushClip(fx + padX, fy, fw - padX * 2, fh)
    if selA and selB and selB > selA then
        local preW = f:getWidth(display:sub(1, selA))
        local selW = f:getWidth(display:sub(selA + 1, selB))
        love.graphics.setColor(theme.alpha("primary", 0.28))
        love.graphics.rectangle("fill", fx + padX + preW, textY, selW, f:getHeight())
    end
    if #display == 0 and not imeText and p.placeholder then
        draw.text(p.placeholder, fx + padX, textY, 0, { font = f, color = theme.color("muted") })
    else
        self:drawTextField(f, display, cursorByte, imeText, fx + padX, textY, theme.color("text"))
    end

    if self.state.focused and not self.state.disabled and not self:hasSelection() then
        if (love.timer.getTime() % 1) < 0.55 then
            local cursorText = display:sub(1, cursorByte) .. (imeText or "")
            local cursorX = fx + padX + f:getWidth(cursorText)
            love.graphics.setColor(theme.color("primary"))
            love.graphics.rectangle("fill", cursorX, textY, 1.5, f:getHeight())
        end
    end
    draw.popClip()
end

-- 绘制已提交文本 + 输入法组合文本（组合部分加下划线）
function Input:drawTextField(f, display, cursorByte, imeText, x, y, color)
    -- 显式使用正文字体：上游 label 用 caption 字体绘制过，若不重置会导致
    -- 渲染字体与 getWidth 计算字体不一致，光标位置错位、文本后出现空白
    love.graphics.setFont(f)
    if not imeText or #imeText == 0 then
        love.graphics.setColor(color)
        love.graphics.print(display, x, y)
        return
    end
    local prefix = display:sub(1, cursorByte)
    local suffix = display:sub(cursorByte + 1)
    local prefixW = f:getWidth(prefix)
    local imeW = f:getWidth(imeText)

    love.graphics.setColor(color)
    love.graphics.print(prefix, x, y)

    love.graphics.setColor(theme.color("primary"))
    love.graphics.print(imeText, x + prefixW, y)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(x + prefixW, y + f:getHeight() + 1, x + prefixW + imeW, y + f:getHeight() + 1)

    love.graphics.setColor(color)
    love.graphics.print(suffix, x + prefixW + imeW, y)
end

return Input
