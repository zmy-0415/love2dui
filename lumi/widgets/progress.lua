--[[
    progress.lua —— 进度条
    mode: linear（线性）/ circular（环形），value 0..max（默认 1）。
]]

local platform = require("lumi.platform")
local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local Progress = setmetatable({}, { __index = Widget })
Progress.__index = Progress

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Progress.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Progress)
    self.mode = props.mode or "linear"
    self.max = props.max or 1
    self._fraction = clamp((props.value or 0) / self.max, 0, 1)
    return self
end

function Progress:setValue(v)
    self._fraction = clamp(v / self.max, 0, 1)
end

function Progress:getFraction()
    if self.props.value ~= nil then
        return clamp(self.props.value / self.max, 0, 1)
    end
    return self._fraction
end

function Progress:measureContent(availW, availH)
    if self.mode == "circular" then
        local s = self.props.size or 48
        return s, s
    end
    local h = self.props.thickness or 8
    return self.props.w or 160, h
end

function Progress:drawContent()
    local p = self.props
    local base = self:resolveColor(p.color or "primary")
    local frac = self:getFraction()

    if self.mode == "circular" then
        local thickness = p.thickness or 6
        local cx = self.x + self.w / 2
        local cy = self.y + self.h / 2
        local r = math.min(self.w, self.h) / 2 - thickness / 2 - 1
        platform.graphics.setLineWidth(thickness)
        draw.setColor(theme.color("surface2"))
        platform.graphics.arc("line", "open", cx, cy, r, 0, math.pi * 2)
        draw.setColor(base)
        platform.graphics.arc("line", "open", cx, cy, r, -math.pi / 2, -math.pi / 2 + math.pi * 2 * frac)
        if p.showValue then
            local f = font.get(theme.font.caption)
            local text = math.floor(frac * 100 + 0.5) .. "%"
            draw.text(text, cx - draw.textWidth(f, text) / 2, cy - f:getHeight() / 2, 0, { font = f, color = theme.color("text") })
        end
        return
    end

    -- 线性
    local h = p.thickness or 8
    local cy = self.y + self.h / 2
    local r = p.radius or (h / 2)
    draw.roundRect(self.x, cy - h / 2, self.w, h, r, theme.color("surface2"))
    if frac > 0 then
        draw.roundRect(self.x, cy - h / 2, self.w * frac, h, r, base)
    end
end

return Progress
