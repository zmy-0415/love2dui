--[[
    radio.lua —— 单选按钮
    支持 group 分组互斥，onChanged(checked)。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local Radio = setmetatable({}, { __index = Widget })
Radio.__index = Radio

function Radio.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Radio)
    self.checked = props.checked and true or false
    self._anim = self.checked and 1 or 0
    return self
end

function Radio:isFocusable()
    return not self.state.disabled
end

function Radio:measureContent(availW, availH)
    local f = font.get(theme.font.body)
    local size = 20
    local w = size
    if self.props.label then w = w + 8 + f:getWidth(self.props.label) end
    return w, math.max(size, f:getHeight())
end

function Radio:setChecked(v)
    if v and self.props.group and self.parent then
        for _, c in ipairs(self.parent.children) do
            if c ~= self and c.checked ~= nil and c.props and c.props.group == self.props.group then
                c.checked = false
            end
        end
    end
    if self.checked ~= v then
        self.checked = v
        self:emit("onChanged", self.checked)
    end
end

function Radio:onUpdate(dt)
    local target = self.checked and 1 or 0
    if self._anim ~= target then
        self._anim = self._anim + (target - self._anim) * math.min(1, dt * 16)
        if math.abs(self._anim - target) < 0.01 then self._anim = target end
    end
end

function Radio:mousereleased(x, y, button, ctx, hit)
    if button ~= 1 or self.state.disabled then return end
    if self.state.pressed and hit == self then
        self:setChecked(true)
    end
end

function Radio:drawContent()
    local p = self.props
    local size = 20
    local bx = self.x
    local by = self.y + (self.h - size) / 2
    local base = self:resolveColor(p.color or "primary")
    local cxb = bx + size / 2
    local cyb = by + size / 2

    love.graphics.setColor(self.state.hovered and theme.color("surface") or theme.color("surface2"))
    love.graphics.circle("fill", cxb, cyb, size / 2)

    love.graphics.setLineWidth(2)
    love.graphics.setColor(self.checked and base or theme.color("border"))
    love.graphics.circle("line", cxb, cyb, size / 2 - 1)

    if self._anim > 0 then
        love.graphics.setColor({ base[1], base[2], base[3], self._anim })
        love.graphics.circle("fill", cxb, cyb, (size / 2 - 4) * self._anim)
    end

    if p.label then
        local f = font.get(theme.font.body)
        draw.text(p.label, bx + size + 8, self.y + (self.h - f:getHeight()) / 2, 0, { font = f, color = theme.color("text") })
    end
end

return Radio
