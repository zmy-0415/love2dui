--[[
    slider.lua —— 滑块
    拖拽调整、step 步进、showValue、onChanged(value)。
]]

local platform = require("lumi.platform")
local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local Slider = setmetatable({}, { __index = Widget })
Slider.__index = Slider

local THUMB = 16

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Slider.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Slider)
    self.min = props.min or 0
    self.max = props.max or 100
    self.value = clamp(props.value or self.min, self.min, self.max)
    self._dragging = false
    return self
end

function Slider:isFocusable()
    return not self.state.disabled
end

function Slider:measureContent(availW, availH)
    local f = font.get(theme.font.caption)
    local h = math.max(THUMB + 8, f:getHeight() + 8)
    local w = self.props.w or 160
    if self.props.showValue then w = w + 44 end
    return w, h
end

function Slider:getTrackX()
    local valueSpace = 0
    if self.props.showValue then valueSpace = 44 end
    return self.x + THUMB / 2, self.w - THUMB - valueSpace
end

function Slider:valueFromX(x)
    local tx, tw = self:getTrackX()
    local t = (x - tx) / tw
    t = clamp(t, 0, 1)
    local v = self.min + t * (self.max - self.min)
    if self.props.step then
        v = math.floor(v / self.props.step + 0.5) * self.props.step
    end
    return clamp(v, self.min, self.max)
end

function Slider:setValue(v)
    v = clamp(v, self.min, self.max)
    if v ~= self.value then
        self.value = v
        self:emit("onChanged", v)
    end
end

function Slider:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    self._dragging = true
    self:setValue(self:valueFromX(x))
end

function Slider:mousemoved(x, y, ctx)
    if self._dragging then
        self:setValue(self:valueFromX(x))
    end
end

function Slider:mousereleased(x, y, button, ctx, hit)
    self._dragging = false
end

-- 键盘：左右/上下方向键调整（step 优先，否则取范围的 5%）
function Slider:keypressed(key, ctx)
    if self.state.disabled then return end
    if key ~= "left" and key ~= "right" and key ~= "up" and key ~= "down" then return end
    local dir = (key == "left" or key == "down") and -1 or 1
    local step = self.props.step or (self.max - self.min) / 20
    self:setValue(self.value + dir * step)
end

function Slider:drawContent()
    local p = self.props
    local base = self:resolveColor(p.color or "primary")
    local tx, tw = self:getTrackX()
    local cy = self.y + self.h / 2
    local trackH = 4

    -- 轨道
    draw.roundRect(tx, cy - trackH / 2, tw, trackH, trackH / 2, theme.color("surface2"))
    -- 已填充
    local frac = (self.value - self.min) / (self.max - self.min)
    if frac > 0 then
        draw.roundRect(tx, cy - trackH / 2, tw * frac, trackH, trackH / 2, base)
    end
    -- 拇指
    local thumbX = tx + tw * frac
    local thumbR = THUMB / 2
    if self.state.hovered or self._dragging then thumbR = thumbR + 1.5 end
    draw.shadow(thumbX - thumbR, cy - thumbR, thumbR * 2, thumbR * 2, thumbR, self._dragging and 2 or 1)
    draw.setColor(theme.color("surface"))
    platform.graphics.circle("fill", thumbX, cy, thumbR)

    -- 数值
    if p.showValue then
        local f = font.get(theme.font.caption)
        local text = tostring(self.value)
        draw.text(text, self.x + self.w - draw.textWidth(f, text), self.y + (self.h - f:getHeight()) / 2, 0, { font = f, color = theme.color("muted") })
    end

    -- 键盘焦点环
    if self.state.focused then
        local tx, tw = self:getTrackX()
        draw.roundRectLine(tx - 6, self.y, tw + 12, self.h, self.h / 2, theme.alpha("primary", 0.5), 1.5)
    end
end

return Slider
