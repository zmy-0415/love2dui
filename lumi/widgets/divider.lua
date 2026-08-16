--[[
    divider.lua —— 分隔线
    direction: horizontal（默认）/ vertical，可选中间标题 text。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local Divider = setmetatable({}, { __index = Widget })
Divider.__index = Divider

function Divider.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Divider)
    return self
end

function Divider:measureContent(availW, availH)
    if self.props.direction == "vertical" then
        return self.props.w or 1, self.props.h or 24
    end
    local f = font.get(theme.font.caption)
    local h = self.props.text and f:getHeight() or 1
    local w = (availW and availW > 0) and availW or 200
    return w, h
end

function Divider:drawContent()
    local p = self.props
    local color = p.color and self:resolveColor(p.color) or theme.color("border")

    if p.direction == "vertical" then
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", self.x + self.w / 2, self.y, 1, self.h)
        return
    end

    local cy = self.y + self.h / 2
    if p.text then
        local f = font.get(theme.font.caption)
        local tw = f:getWidth(p.text)
        local tx = self.x + (self.w - tw) / 2
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", self.x, cy, tx - self.x - 8, 1)
        love.graphics.rectangle("fill", tx + tw + 8, cy, self.x + self.w - (tx + tw + 8), 1)
        draw.text(p.text, tx, self.y + (self.h - f:getHeight()) / 2, 0, { font = f, color = theme.color("muted") })
    else
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", self.x, cy, self.w, 1)
    end
end

return Divider
