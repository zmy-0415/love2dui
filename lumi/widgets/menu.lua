--[[
    menu.lua —— 菜单栏
    props.items = {
        { label="文件", items={ {label="新建", onClick=fn}, {divider=true}, {label="退出", onClick=fn} } },
        { label="帮助", onClick=fn },   -- 无子项的顶层动作
    }
    点击展开下拉菜单，悬停切换，点击项触发 onClick。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")
local Overlay = require("lumi.widgets.overlay")
local Button = require("lumi.widgets.button")
local Divider = require("lumi.widgets.divider")

local Menu = setmetatable({}, { __index = Widget })
Menu.__index = Menu

function Menu.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Menu)
    self._open = nil
    self._panel = nil
    return self
end

function Menu:getTops()
    local f = font.get(theme.font.body)
    local tops = {}
    local x = self.x
    for _, it in ipairs(self.props.items or {}) do
        local label = it.label or it.text or ""
        local w = draw.textWidth(f, label) + 24
        tops[#tops + 1] = { x = x, w = w, item = it, label = label }
        x = x + w
    end
    return tops
end

function Menu:measureContent(availW, availH)
    local totalW = 0
    local f = font.get(theme.font.body)
    for _, it in ipairs(self.props.items or {}) do
        totalW = totalW + draw.textWidth(f, it.label or "") + 24
    end
    return totalW, 40
end

function Menu:close(ctx)
    if self._panel and ctx then ctx:closeOverlay(self._panel) end
    self._open = nil
    self._panel = nil
end

function Menu:buildPanel(items, ctx)
    local f = font.get(theme.font.body)
    local panel = Overlay.new({ bg = "surface", elevation = 3, radius = theme.shape.medium, padding = 4, direction = "column" })
    panel.acceptsChildren = true
    local maxW = 120
    for _, it in ipairs(items or {}) do
        local label = it.label or ""
        maxW = math.max(maxW, draw.textWidth(f, label) + 48)
        if it.divider then
            panel:addChild(Divider.new({ margin = { x = 8, y = 4 } }))
        else
            panel:addChild(Button.new({
                text = label,
                variant = "text",
                align = "left",
                padX = 12,
                radius = theme.shape.small,
                h = 34,
                onClick = function()
                    if it.onClick then it.onClick() end
                    self:close(ctx)
                end,
            }))
        end
    end
    panel.w = maxW
    panel.h = #(items or {}) * 34 + 8
    return panel
end

function Menu:openTop(i, ctx)
    self:close(ctx)
    local tops = self:getTops()
    local t = tops[i]
    if not t then return end
    local panel = self:buildPanel(t.item.items, ctx)
    panel.x = t.x
    panel.y = self.y + self.h + 2
    self._open = i
    self._panel = panel
    ctx:openOverlay(panel, {
        closeOnOutside = true,
        onClose = function()
            -- 退场动画结束后才回调：若期间已切到新面板，勿误清
            if self._panel == panel then
                self._open = nil
                self._panel = nil
            end
        end,
    })
end

function Menu:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    local tops = self:getTops()
    for i, t in ipairs(tops) do
        if x >= t.x and x < t.x + t.w then
            if t.item.items and #t.item.items > 0 then
                if self._open == i then
                    self:close(ctx)
                else
                    self:openTop(i, ctx)
                end
            elseif t.item.onClick then
                t.item.onClick()
            end
            return
        end
    end
end

function Menu:onUpdate(dt)
    if not self._open or not self._ctx then return end
    local x, y = self._ctx._mouseX, self._ctx._mouseY
    if y < self.y or y >= self.y + self.h then return end
    local tops = self:getTops()
    for i, t in ipairs(tops) do
        if x >= t.x and x < t.x + t.w then
            if i ~= self._open then self:openTop(i, self._ctx) end
            return
        end
    end
end

function Menu:drawContent()
    local f = font.get(theme.font.body)
    local tops = self:getTops()
    for i, t in ipairs(tops) do
        if i == self._open then
            draw.roundRect(t.x + 2, self.y + 4, t.w - 4, self.h - 8, theme.shape.small, theme.alpha("primary", 0.14))
        end
        local color = (i == self._open) and theme.color("primary") or theme.color("text")
        local tw = draw.textWidth(f, t.label)
        draw.text(t.label, t.x + (t.w - tw) / 2, self.y + (self.h - f:getHeight()) / 2, 0, { font = f, color = color })
    end
end

return Menu
