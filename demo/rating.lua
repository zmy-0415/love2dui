--[[
    rating.lua —— 自定义控件示例：星级评分
    演示如何基于 Widget 基类实现一个完整控件：
    子类化、measureContent、drawContent、mousepressed、emit 回调。
    用法（先注册）：ui:rating({ max = 5, value = 3, onChanged = function(v) ... end })
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")

local Rating = setmetatable({}, { __index = Widget })
Rating.__index = Rating

function Rating.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Rating)
    self.max = props.max or 5
    self.value = props.value or 0
    return self
end

function Rating:isFocusable()
    return not self.state.disabled
end

function Rating:measureContent(availW, availH)
    local size = self.props.size or 24
    local gap = self.props.gap or 6
    return self.max * size + (self.max - 1) * gap, size
end

function Rating:setValue(v)
    v = math.max(0, math.min(self.max, v))
    if v ~= self.value then
        self.value = v
        self:emit("onChanged", v)
    end
end

function Rating:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    local size = self.props.size or 24
    local gap = self.props.gap or 6
    local idx = math.floor((x - self.x) / (size + gap)) + 1
    self:setValue(idx)
end

function Rating:drawContent()
    local size = self.props.size or 24
    local gap = self.props.gap or 6
    local base = self:resolveColor(self.props.color or "primary")
    for i = 1, self.max do
        local cx = self.x + (i - 1) * (size + gap) + size / 2
        local cy = self.y + self.h / 2
        local r = size / 2 - 2
        if i <= self.value then
            love.graphics.setColor(base)
            love.graphics.circle("fill", cx, cy, r)
        else
            love.graphics.setLineWidth(1.5)
            love.graphics.setColor(theme.color("border"))
            love.graphics.circle("line", cx, cy, r)
        end
    end
end

return Rating
