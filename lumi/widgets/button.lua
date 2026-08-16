--[[
    button.lua —— 按钮
    variant: filled / tonal / outlined / text（Material Design 3 风格）
    特性：状态过渡动画、点击波纹、禁用态、onClick 回调。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")
local animate = require("lumi.animate")

local Button = setmetatable({}, { __index = Widget })
Button.__index = Button

local function lighten(c, t)
    return { c[1] + (1 - c[1]) * t, c[2] + (1 - c[2]) * t, c[3] + (1 - c[3]) * t, c[4] or 1 }
end

local function darken(c, t)
    return { c[1] * (1 - t), c[2] * (1 - t), c[3] * (1 - t), c[4] or 1 }
end

function Button.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Button)
    self.ripples = {}
    self._bgColor = self:targetBg()
    self._textColor = self:targetText()
    self._lastHovered = false
    self._lastPressed = false
    self._lastDisabled = false
    self:init(props)
    return self
end

function Button:init(props)
    self.ripples = self.ripples or {}
end

-- 计算当前状态的目标背景色
function Button:targetBg()
    local p = self.props
    local variant = p.variant or "filled"
    local base = self:resolveColor(p.color or "primary")
    if self.state.disabled then
        return theme.color("surface2")
    end
    if variant == "filled" then
        if self.state.pressed then return darken(base, 0.14) end
        if self.state.hovered then return lighten(base, 0.08) end
        return base
    elseif variant == "tonal" then
        if self.state.pressed then return theme.alpha("primary", 0.30) end
        if self.state.hovered then return theme.alpha("primary", 0.24) end
        return theme.alpha("primary", 0.16)
    else -- outlined / text
        if self.state.pressed then return theme.alpha("primary", 0.22) end
        if self.state.hovered then return theme.alpha("primary", 0.12) end
        return theme.alpha("primary", 0)
    end
end

function Button:targetText()
    local variant = self.props.variant or "filled"
    if self.state.disabled then
        return theme.color("muted")
    end
    if self.props.textColor then
        return self:resolveColor(self.props.textColor)
    end
    if variant == "filled" then
        return theme.color("onPrimary")
    end
    return self:resolveColor(self.props.color or "primary")
end

function Button:isFocusable()
    return not self.state.disabled
end

function Button:measureContent(availW, availH)
    local f = font.get(theme.font.body)
    local text = self.props.text or ""
    local h = self.props.height or theme.control.height
    local w = f:getWidth(text) + theme.control.padX * 2
    w = math.max(w, theme.control.minWidth)
    return w, h
end

function Button:onUpdate(dt)
    -- 状态变化时触发颜色过渡
    if self.state.hovered ~= self._lastHovered or self.state.pressed ~= self._lastPressed or self.state.disabled ~= self._lastDisabled then
        self._lastHovered = self.state.hovered
        self._lastPressed = self.state.pressed
        self._lastDisabled = self.state.disabled
        animate.stop(self)
        animate.to(self, { _bgColor = self:targetBg() }, { duration = theme.motion.fast })
        animate.to(self, { _textColor = self:targetText() }, { duration = theme.motion.fast })
    end
    -- 推进波纹
    for i = #self.ripples, 1, -1 do
        local r = self.ripples[i]
        r.t = (love.timer.getTime() - r.start) / r.duration
        if r.t >= 1 then
            table.remove(self.ripples, i)
        end
    end
end

function Button:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    -- 创建波纹
    local maxR = math.max(
        math.sqrt((x - self.x) ^ 2 + (y - self.y) ^ 2),
        math.sqrt((self.x + self.w - x) ^ 2 + (y - self.y) ^ 2),
        math.sqrt((x - self.x) ^ 2 + (self.y + self.h - y) ^ 2),
        math.sqrt((self.x + self.w - x) ^ 2 + (self.y + self.h - y) ^ 2)
    )
    table.insert(self.ripples, {
        x = x - self.x,
        y = y - self.y,
        start = love.timer.getTime(),
        duration = 0.45,
        t = 0,
        maxR = maxR,
    })
end

function Button:mousereleased(x, y, button, ctx, hit)
    if button ~= 1 or self.state.disabled then return end
    if self.state.pressed and hit == self then
        self:emit("onClick")
    end
end

function Button:drawContent()
    local p = self.props
    local variant = p.variant or "filled"
    local radius = self:resolveRadius(p.radius, theme.shape.pill)

    -- 背景
    if variant ~= "text" or (self._bgColor[4] and self._bgColor[4] > 0) then
        draw.roundRect(self.x, self.y, self.w, self.h, radius, self._bgColor)
    end

    -- 边框（outlined）
    if variant == "outlined" then
        draw.roundRectLine(self.x, self.y, self.w, self.h, radius, self:resolveColor(p.color or "primary"), 1.5)
    end

    -- 波纹
    local rippleColor = (variant == "filled") and { 1, 1, 1, 1 } or self:resolveColor(p.color or "primary")
    for _, r in ipairs(self.ripples) do
        local e = animate.easings.cubicOut(math.min(1, r.t))
        local a = (1 - math.min(1, r.t)) * 0.28
        draw.pushClip(self.x, self.y, self.w, self.h)
        love.graphics.setColor({ rippleColor[1], rippleColor[2], rippleColor[3], a })
        love.graphics.circle("fill", self.x + r.x, self.y + r.y, e * r.maxR)
        draw.popClip()
    end

    -- 文本（默认居中，可左/右对齐）
    local f = font.get(theme.font.body)
    local text = p.text or ""
    local tw = f:getWidth(text)
    local align = p.align or "center"
    local padX = p.padX or theme.control.padX
    local tx
    if align == "left" then
        tx = self.x + padX
    elseif align == "right" then
        tx = self.x + self.w - padX - tw
    else
        tx = self.x + (self.w - tw) / 2
    end
    draw.text(text, tx, self.y + (self.h - f:getHeight()) / 2, 0, { font = f, color = self._textColor })

    -- 键盘焦点环
    if self.state.focused then
        draw.roundRectLine(self.x - 2, self.y - 2, self.w + 4, self.h + 4, radius + 2, theme.alpha("primary", 0.6), 2)
    end
end

return Button
