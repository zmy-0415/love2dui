--[[
    tabs.lua —— 标签页
    props.tabs = { "标签1", "标签2", ... }，active 起始下标（1 基）。
    每个子节点对应一个标签页的内容，仅显示 active 对应内容。
    下划线指示器带动画，悬停切换预览。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local Tabs = setmetatable({}, { __index = Widget })
Tabs.__index = Tabs

local HEADER_H = 44

function Tabs.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Tabs)
    self.acceptsChildren = true
    self.active = props.active or 1
    self._indicatorX = 0
    self._indicatorW = 0
    self._hoverTab = nil
    return self
end

function Tabs:measureContent(availW, availH)
    local contentH = 0
    local child = self.children[self.active]
    if child and child.visible then
        local _, ch = child:measure(availW, availH)
        contentH = ch
    end
    local w = (availW and availW > 0) and availW or 300
    return w, HEADER_H + contentH
end

function Tabs:getTabRects()
    local n = #(self.props.tabs or {})
    if n == 0 then return {} end
    local tabW = self.w / n
    local rects = {}
    for i = 1, n do
        rects[i] = { x = self.x + (i - 1) * tabW, w = tabW }
    end
    return rects
end

function Tabs:arrange(x, y, w, h)
    self.x, self.y, self.w, self.h = x, y, w, h
    local child = self.children[self.active]
    if child and child.visible then
        child:arrange(x, y + HEADER_H, w, h - HEADER_H)
    end
end

-- 仅当前页参与命中、焦点与更新（非活动页停在旧坐标，不能穿透点击或抢焦点）
function Tabs:isChildActive(child)
    return child == self.children[self.active] and child.visible and not child._bpHidden
end

function Tabs:hitTest(x, y)
    if not self.visible or self._bpHidden then return nil end
    if not self:contains(x, y) then return nil end
    -- 标签头由自身处理点击
    if y < self.y + HEADER_H then return self end
    local child = self.children[self.active]
    if child then
        local hit = child:hitTest(x, y)
        if hit then return hit end
    end
    return self
end

function Tabs:update(dt)
    self:onUpdate(dt)
    local child = self.children[self.active]
    if child and child.visible then child:update(dt) end
end

function Tabs:setActive(i)
    if i ~= self.active then
        self.active = i
        self:invalidate()
        self:emit("onChanged", i)
    end
end

function Tabs:isFocusable()
    return not self.state.disabled and #(self.props.tabs or {}) > 1
end

-- 方向键在标签间循环切换（左/上回退，右/下前进）
function Tabs:keypressed(key)
    local n = #(self.props.tabs or {})
    if n < 2 then return end
    if key == "left" or key == "up" then
        self:setActive((self.active - 2) % n + 1)
    elseif key == "right" or key == "down" then
        self:setActive(self.active % n + 1)
    end
end

function Tabs:onUpdate(dt)
    -- 指示器动画
    local rects = self:getTabRects()
    if rects[self.active] then
        local targetX = rects[self.active].x
        local targetW = rects[self.active].w
        self._indicatorX = self._indicatorX + (targetX - self._indicatorX) * math.min(1, dt * 12)
        self._indicatorW = self._indicatorW + (targetW - self._indicatorW) * math.min(1, dt * 12)
    end
    -- 悬停标签预览
    if self._ctx then
        local x, y = self._ctx._mouseX, self._ctx._mouseY
        self._hoverTab = nil
        if y >= self.y and y < self.y + HEADER_H then
            for i, r in ipairs(rects) do
                if x >= r.x and x < r.x + r.w then self._hoverTab = i; break end
            end
        end
    end
end

function Tabs:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    if y < self.y + HEADER_H then
        local rects = self:getTabRects()
        for i, r in ipairs(rects) do
            if x >= r.x and x < r.x + r.w then
                self:setActive(i)
                return
            end
        end
    end
end

function Tabs:draw()
    if not self.visible then return end
    self:drawBackground()

    -- 标签头
    local rects = self:getTabRects()
    local f = font.get(theme.font.body)
    for i, label in ipairs(self.props.tabs or {}) do
        local r = rects[i]
        local color = theme.color("muted")
        if i == self.active then color = theme.color("primary") end
        if self._hoverTab == i and i ~= self.active then color = theme.color("text") end
        local tw = draw.textWidth(f, label)
        draw.text(label, r.x + (r.w - tw) / 2, self.y + (HEADER_H - f:getHeight()) / 2, 0, { font = f, color = color })
    end

    -- 下划线指示器
    if self._indicatorW > 0 then
        draw.roundRect(self._indicatorX + 16, self.y + HEADER_H - 4, self._indicatorW - 32, 3, 1.5, theme.color("primary"))
    end

    -- 键盘焦点环（画在标签头上，提示左右键可切页）
    if self.state.focusVisible then
        local r = rects[self.active]
        if r then
            draw.roundRectLine(r.x + 6, self.y + 4, r.w - 12, HEADER_H - 12, theme.shape.small, theme.alpha("primary", 0.6), 1.5)
        end
    end

    -- 内容
    local child = self.children[self.active]
    if child then child:draw() end
end

return Tabs
