--[[
    checkbox.lua —— 复选框
    勾选动画、label、onChanged(checked)。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local Checkbox = setmetatable({}, { __index = Widget })
Checkbox.__index = Checkbox

function Checkbox.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Checkbox)
    self.checked = props.checked and true or false
    self._anim = self.checked and 1 or 0
    return self
end

function Checkbox:isFocusable()
    return not self.state.disabled
end

function Checkbox:measureContent(availW, availH)
    local f = font.get(theme.font.body)
    local size = 20
    local w = size
    if self.props.label then w = w + 8 + draw.textWidth(f, self.props.label) end
    return w, math.max(size, f:getHeight())
end

function Checkbox:onUpdate(dt)
    local target = self.checked and 1 or 0
    if self._anim ~= target then
        self._anim = self._anim + (target - self._anim) * math.min(1, dt * 16)
        if math.abs(self._anim - target) < 0.01 then self._anim = target end
    end
end

function Checkbox:mousereleased(x, y, button, ctx, hit)
    if button ~= 1 or self.state.disabled then return end
    if self.state.pressed and hit == self then
        self.checked = not self.checked
        self:emit("onChanged", self.checked)
    end
end

function Checkbox:drawContent()
    local p = self.props
    local size = 20
    local bx = self.x
    local by = self.y + (self.h - size) / 2
    local radius = theme.shape.small
    local base = self:resolveColor(p.color or "primary")

    local bg = self.state.hovered and theme.color("surface") or theme.color("surface2")
    draw.roundRect(bx, by, size, size, radius, bg)

    local border = self.checked and base or theme.color("border")
    draw.roundRectLine(bx, by, size, size, radius, border, 2)

    if self._anim > 0 then
        draw.roundRect(bx, by, size, size, radius, { base[1], base[2], base[3], self._anim })
        draw.setColor({ theme.color("onPrimary")[1], theme.color("onPrimary")[2], theme.color("onPrimary")[3], self._anim })
        love.graphics.setLineWidth(2.5)
        local x1, y1 = bx + 5, by + size / 2
        local x2, y2 = bx + size / 2, by + size - 5
        local x3, y3 = bx + size - 4, by + 4.5
        love.graphics.line(x1, y1, x1 + (x2 - x1) * self._anim, y1 + (y2 - y1) * self._anim)
        if self._anim > 0.5 then
            local t2 = (self._anim - 0.5) / 0.5
            love.graphics.line(x2, y2, x2 + (x3 - x2) * t2, y2 + (y3 - y2) * t2)
        end
    end

    if p.label then
        local f = font.get(theme.font.body)
        draw.text(p.label, bx + size + 8, self.y + (self.h - f:getHeight()) / 2, 0, { font = f, color = theme.color("text") })
    end

    if self.state.focused then
        draw.roundRectLine(bx - 3, by - 3, size + 6, size + 6, radius + 2, theme.alpha("primary", 0.6), 1.5)
    end
end

return Checkbox
