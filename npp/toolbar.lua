--[[
    toolbar.lua —— 紧凑工具栏
    props.items = { { label = "新建", onClick = fn }, ... }
    悬停/按下状态反馈，点击触发 onClick。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local ToolBar = setmetatable({}, { __index = Widget })
ToolBar.__index = ToolBar

local H = 42

function ToolBar.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, ToolBar)
    self._pressedIndex = nil
    return self
end

function ToolBar:measureContent(availW, availH)
    return (availW and availW > 0) and availW or 400, H
end

local function inRect(x, y, rx, ry, rw, rh)
    return x >= rx and x < rx + rw and y >= ry and y < ry + rh
end

function ToolBar:itemRects()
    local f = font.get(theme.font.body)
    local rects = {}
    local x = self.x + 6
    for i, it in ipairs(self.props.items or {}) do
        local w = f:getWidth(it.label or "") + 20
        rects[i] = { x = x, w = w, it = it, i = i }
        x = x + w + 2
    end
    return rects
end

function ToolBar:drawContent()
    local f = font.get(theme.font.body)

    draw.roundRect(self.x, self.y, self.w, self.h, 0, theme.color("surface"))
    draw.roundRect(self.x, self.y + self.h - 1, self.w, 1, 0, theme.color("border"))

    local mx, my = -1, -1
    if self._ctx then mx, my = self._ctx._mouseX, self._ctx._mouseY end

    for i, r in ipairs(self:itemRects()) do
        local hovered = inRect(mx, my, r.x, self.y, r.w, self.h)
        local pressed = (self._pressedIndex == i)
        if hovered then
            draw.roundRect(r.x, self.y + 4, r.w, self.h - 8, 6,
                theme.alpha("primary", pressed and 0.22 or 0.12))
        end
        local color = hovered and theme.color("primary") or theme.color("text")
        draw.text(r.it.label or "", r.x + 10, self.y + (self.h - f:getHeight()) / 2, 0,
            { font = f, color = color })
    end
end

function ToolBar:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    for i, r in ipairs(self:itemRects()) do
        if inRect(x, y, r.x, self.y, r.w, self.h) then
            self._pressedIndex = i
            return
        end
    end
end

function ToolBar:mousereleased(x, y, button, ctx, hit)
    if button ~= 1 then return end
    local i = self._pressedIndex
    self._pressedIndex = nil
    if not i then return end
    local rects = self:itemRects()
    local r = rects[i]
    if r and inRect(x, y, r.x, self.y, r.w, self.h) then
        if r.it.onClick then r.it.onClick() end
    end
end

return ToolBar
