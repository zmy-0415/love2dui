--[[
    icon.lua —— 矢量图标
    内置 30+ 线条风格图标（24×24 网格，随尺寸等比缩放），无需图片资源。
    用法：ui:icon("home", { size = 24, color = "primary" })
    未知图标名安全降级为方块占位。
]]

local platform = require("lumi.platform")
local draw = require("lumi.draw")
local Widget = require("lumi.widget")
local theme = require("lumi.theme")

local Icon = setmetatable({}, { __index = Widget })
Icon.__index = Icon

-- ---------------- 24×24 网格图标定义 ----------------
-- 每个 g.xxx 均在 0..24 坐标空间绘制，线宽 2，随外部 scale 等比缩放

local icons = {}

icons.home = function(g)
    g.poly({ 12, 3, 21, 11, 18, 11, 18, 21, 14, 21, 14, 14, 10, 14, 10, 21, 6, 21, 6, 11, 3, 11 })
end

icons.user = function(g)
    g.circle(12, 8, 4)
    g.arc(12, 20, 7, math.pi, math.pi * 2)
end

icons.settings = function(g)
    g.circle(12, 12, 3.5)
    for k = 0, 7 do
        local a = k * math.pi / 4
        local c, s = math.cos(a), math.sin(a)
        g.line(12 + c * 6.5, 12 + s * 6.5, 12 + c * 9.5, 12 + s * 9.5)
    end
end

icons.search = function(g)
    g.circle(10.5, 10.5, 6)
    g.line(15, 15, 20, 20)
end

icons.close = function(g)
    g.line(6, 6, 18, 18)
    g.line(18, 6, 6, 18)
end

icons.check = function(g)
    g.line(4, 13, 9, 18, 20, 7)
end

icons.plus = function(g)
    g.line(12, 5, 12, 19)
    g.line(5, 12, 19, 12)
end

icons.minus = function(g)
    g.line(5, 12, 19, 12)
end

icons.heart = function(g)
    g.poly({ 12, 20, 3.5, 11, 3, 7, 5.5, 4.5, 8.5, 5, 10.5, 7, 12, 9, 13.5, 7, 15.5, 5, 18.5, 4.5, 21, 7, 20.5, 11 })
end

icons.star = function(g)
    g.poly({ 12, 3.5, 14.2, 9.4, 20.6, 9.7, 15.6, 13.7, 17.3, 19.8, 12, 16.3, 6.7, 19.8, 8.4, 13.7, 3.4, 9.7, 9.8, 9.4 })
end

icons.trash = function(g)
    g.rect(6, 8, 12, 12)
    g.line(4, 5, 20, 5)
    g.line(9, 5, 9, 3, 15, 3, 15, 5)
    g.line(10, 11, 10, 17)
    g.line(14, 11, 14, 17)
end

icons.edit = function(g)
    g.poly({ 4, 20, 5, 15, 16, 4, 20, 8, 9, 19 })
    g.line(14, 6, 18, 10)
end

icons.play = function(g)
    g.fillPoly({ 9, 6, 19, 12, 9, 18 })
end

icons.pause = function(g)
    g.line(9, 6, 9, 18)
    g.line(15, 6, 15, 18)
end

icons.folder = function(g)
    g.poly({ 3, 6, 9, 6, 11, 8, 21, 8, 21, 19, 3, 19 })
end

icons.file = function(g)
    g.poly({ 6, 3, 15, 3, 19, 7, 19, 21, 6, 21 })
    g.line(15, 3, 15, 7, 19, 7)
end

icons.image = function(g)
    g.rect(3.5, 5, 17, 14)
    g.circle(8.5, 9.5, 1.6)
    g.line(6, 16, 11, 11, 14, 14, 16, 12, 20, 16)
end

icons.download = function(g)
    g.line(12, 4, 12, 14)
    g.line(7, 9, 12, 14, 17, 9)
    g.line(5, 19, 19, 19)
end

icons.upload = function(g)
    g.line(12, 14, 12, 4)
    g.line(7, 9, 12, 4, 17, 9)
    g.line(5, 19, 19, 19)
end

icons.refresh = function(g)
    g.arc(12, 12, 8, -1.2, 4.0)
    g.fillPoly({ 16.5, 3.2, 21, 6.5, 16, 9.5 })
    g.fillPoly({ 7.5, 20.8, 3, 17.5, 8, 14.5 })
end

icons.menu = function(g)
    g.line(4, 6, 20, 6)
    g.line(4, 12, 20, 12)
    g.line(4, 18, 20, 18)
end

icons.warning = function(g)
    g.poly({ 12, 4, 22, 20, 2, 20 })
    g.line(12, 10, 12, 15)
    g.fillCircle(12, 17.4, 0.9)
end

icons.info = function(g)
    g.circle(12, 12, 9)
    g.line(12, 11, 12, 16)
    g.fillCircle(12, 7.8, 0.9)
end

icons.mail = function(g)
    g.rect(3, 5, 18, 14)
    g.line(4, 6, 12, 13, 20, 6)
end

icons.lock = function(g)
    g.rect(5, 11, 14, 9)
    g.arc(12, 11, 4, math.pi, math.pi * 2)
end

icons.calendar = function(g)
    g.rect(3.5, 5, 17, 15)
    g.line(3.5, 9.5, 20.5, 9.5)
    g.line(8, 3, 8, 6)
    g.line(16, 3, 16, 6)
end

icons["arrow-left"] = function(g)
    g.line(20, 12, 5, 12)
    g.line(11, 6, 5, 12, 11, 18)
end

icons["arrow-right"] = function(g)
    g.line(4, 12, 19, 12)
    g.line(13, 6, 19, 12, 13, 18)
end

icons["arrow-up"] = function(g)
    g.line(12, 20, 12, 5)
    g.line(6, 11, 12, 5, 18, 11)
end

icons["arrow-down"] = function(g)
    g.line(12, 4, 12, 19)
    g.line(6, 13, 12, 19, 18, 13)
end

icons["chevron-left"] = function(g)
    g.line(14, 6, 8, 12, 14, 18)
end

icons["chevron-right"] = function(g)
    g.line(10, 6, 16, 12, 10, 18)
end

icons["chevron-up"] = function(g)
    g.line(6, 14, 12, 8, 18, 14)
end

icons["chevron-down"] = function(g)
    g.line(6, 10, 12, 16, 18, 10)
end

icons.more = function(g)
    g.fillCircle(5, 12, 1.4)
    g.fillCircle(12, 12, 1.4)
    g.fillCircle(19, 12, 1.4)
end

Icon.icons = icons

-- ---------------- 组件 ----------------

function Icon.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Icon)
    return self
end

function Icon:getName()
    return self.props.name or self.props.text
end

function Icon:getSize()
    return self.props.size or 24
end

function Icon:measureContent()
    local s = self:getSize()
    return s, s
end

-- 图标绘制指令集：模块级常量，避免每次绘制都新建 8 个转发闭包
local WHITE = { 1, 1, 1, 1 }

local ICON_GFX = {
    line = function(...) platform.graphics.line(...) end,
    rect = function(rx, ry, rw, rh) platform.graphics.rectangle("line", rx, ry, rw, rh) end,
    circle = function(cx, cy, r) platform.graphics.circle("line", cx, cy, r) end,
    arc = function(cx, cy, r, a1, a2) platform.graphics.arc("line", "open", cx, cy, r, a1, a2) end,
    poly = function(pts) platform.graphics.polygon("line", pts) end,
    fillPoly = function(pts) platform.graphics.polygon("fill", pts) end,
    fillCircle = function(cx, cy, r) platform.graphics.circle("fill", cx, cy, r) end,
}

-- 静态绘制：在 (x,y) 绘制 size 大小的图标（供其他控件复用）
function Icon.drawIcon(name, x, y, size, color)
    local fn = icons[name]
    platform.graphics.push()
    platform.graphics.translate(x, y)
    platform.graphics.scale(size / 24, size / 24)
    platform.graphics.setLineWidth(2)
    platform.graphics.setLineJoin("miter")
    platform.graphics.setLineStyle("smooth")
    draw.setColor(color or WHITE)
    if fn then
        fn(ICON_GFX)
    else
        -- 未知图标：虚线方块占位
        platform.graphics.setLineWidth(1.5)
        platform.graphics.rectangle("line", 4, 4, 16, 16)
        platform.graphics.line(4, 4, 20, 20)
    end
    platform.graphics.pop()
    draw.resetState()   -- pop 恢复渲染状态，缓存作废
end

function Icon:drawContent()
    local color = self.props.color and self:resolveColor(self.props.color) or theme.color("text")
    if self.state.disabled then
        color = theme.color("muted")
    end
    Icon.drawIcon(self:getName(), self.x, self.y, self:getSize(), color)
end

return Icon
