--[[
    tabbar.lua —— 多标签页条
    读取 props.app 的 docs / active 动态绘制标签：未保存标记、关闭按钮、末尾“+”。
    点击标签切换文档，点击 × 关闭文档，点击 + 新建文档。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local TabBar = setmetatable({}, { __index = Widget })
TabBar.__index = TabBar

local H = 38
local CLOSE_W = 22

function TabBar.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, TabBar)
    return self
end

function TabBar:measureContent(availW, availH)
    return (availW and availW > 0) and availW or 400, H
end

local function inRect(x, y, rx, ry, rw, rh)
    return x >= rx and x < rx + rw and y >= ry and y < ry + rh
end

function TabBar:tabRects()
    local app = self.props.app
    local f = font.get(theme.font.body)
    local rects = {}
    local x = self.x + 6
    for i, doc in ipairs(app.docs) do
        local label = (doc.name or "未命名") .. (doc.dirty and " ●" or "")
        local w = f:getWidth(label) + 30 + CLOSE_W
        rects[i] = { x = x, w = w, label = label, i = i }
        x = x + w + 2
    end
    return rects
end

function TabBar:addRect()
    local rects = self:tabRects()
    local last = rects[#rects]
    local x = last and (last.x + last.w + 2) or (self.x + 6)
    return { x = x, w = 30 }
end

function TabBar:drawContent()
    local app = self.props.app
    local f = font.get(theme.font.body)
    local cf = font.get(theme.font.caption)

    draw.roundRect(self.x, self.y, self.w, self.h, 0, theme.color("surface"))
    draw.roundRect(self.x, self.y + self.h - 1, self.w, 1, 0, theme.color("border"))

    local mx, my = -1, -1
    if self._ctx then mx, my = self._ctx._mouseX, self._ctx._mouseY end

    for i, r in ipairs(self:tabRects()) do
        local active = (i == app.active)
        local hovered = inRect(mx, my, r.x, self.y, r.w, self.h)

        if active then
            draw.roundRect(r.x, self.y, r.w, self.h, 0, theme.color("background"))
            draw.roundRect(r.x, self.y, r.w, 3, 1.5, theme.color("primary"))
        elseif hovered then
            draw.roundRect(r.x, self.y, r.w, self.h, 0, theme.alpha("text", 0.06))
        end

        local color = active and theme.color("text") or theme.color("muted")
        draw.text(r.label, r.x + 8, self.y + (self.h - f:getHeight()) / 2, 0, { font = f, color = color })

        -- 关闭按钮 ×
        local closeX = r.x + r.w - CLOSE_W + 5
        local ch = cf:getHeight()
        draw.text("×", closeX, self.y + (self.h - ch) / 2, 0, { font = cf, color = theme.color("muted") })
    end

    -- 新增按钮 +
    local add = self:addRect()
    local hovered = inRect(mx, my, add.x, self.y, add.w, self.h)
    local color = hovered and theme.color("primary") or theme.color("muted")
    draw.text("+", add.x + 7, self.y + (self.h - f:getHeight()) / 2 - 1, 0, { font = f, color = color })
end

function TabBar:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    local app = self.props.app

    local add = self:addRect()
    if inRect(x, y, add.x, self.y, add.w, self.h) then
        app:newFile()
        return
    end

    for _, r in ipairs(self:tabRects()) do
        if inRect(x, y, r.x, self.y, r.w, self.h) then
            if x >= r.x + r.w - CLOSE_W then
                app:closeTab(r.i)
            else
                app:switchTo(r.i)
            end
            return
        end
    end
end

return TabBar
