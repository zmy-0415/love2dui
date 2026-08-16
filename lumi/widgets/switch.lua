--[[
    switch.lua —— 开关
    拇指滑动动画、label、onChanged(checked)。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local Switch = setmetatable({}, { __index = Widget })
Switch.__index = Switch

local TRACK_W, TRACK_H = 44, 24
local THUMB = 20
local PAD = 2

function Switch.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Switch)
    self.checked = props.checked and true or false
    self._anim = self.checked and 1 or 0
    return self
end

function Switch:isFocusable()
    return not self.state.disabled
end

function Switch:measureContent(availW, availH)
    local f = font.get(theme.font.body)
    local w = TRACK_W
    if self.props.label then w = w + 8 + f:getWidth(self.props.label) end
    return w, math.max(TRACK_H, f:getHeight())
end

function Switch:onUpdate(dt)
    local target = self.checked and 1 or 0
    if self._anim ~= target then
        self._anim = self._anim + (target - self._anim) * math.min(1, dt * 14)
        if math.abs(self._anim - target) < 0.01 then self._anim = target end
    end
end

function Switch:mousereleased(x, y, button, ctx, hit)
    if button ~= 1 or self.state.disabled then return end
    if self.state.pressed and hit == self then
        self.checked = not self.checked
        self:emit("onChanged", self.checked)
    end
end

function Switch:drawContent()
    local p = self.props
    local base = self:resolveColor(p.color or "primary")
    local by = self.y + (self.h - TRACK_H) / 2

    -- 轨道
    local off = theme.color("surface2")
    local on = base
    local track = draw.lerpColor(off, on, self._anim)
    if self.state.disabled then track = theme.color("border") end
    draw.roundRect(self.x, by, TRACK_W, TRACK_H, TRACK_H / 2, track)

    -- 拇指
    local thumbX = self.x + PAD + (TRACK_W - THUMB - PAD * 2) * self._anim
    local thumbY = by + (TRACK_H - THUMB) / 2
    draw.shadow(thumbX, thumbY, THUMB, THUMB, THUMB / 2, 1)
    love.graphics.setColor(theme.color("surface"))
    love.graphics.circle("fill", thumbX + THUMB / 2, thumbY + THUMB / 2, THUMB / 2)

    if p.label then
        local f = font.get(theme.font.body)
        draw.text(p.label, self.x + TRACK_W + 8, self.y + (self.h - f:getHeight()) / 2, 0, { font = f, color = theme.color("text") })
    end

    if self.state.focused then
        draw.roundRectLine(self.x - 3, by - 3, TRACK_W + 6, TRACK_H + 6, TRACK_H / 2 + 2, theme.alpha("primary", 0.6), 1.5)
    end
end

return Switch
