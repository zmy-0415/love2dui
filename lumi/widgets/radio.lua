--[[
    radio.lua —— 单选按钮
    支持 group 分组互斥，onChanged(checked)。
]]

local platform = require("lumi.platform")
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
    if self.props.label then w = w + 8 + draw.textWidth(f, self.props.label) end
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

-- 键盘激活：Space / Enter 选中自己（单选按钮不能被"取消"，与原生行为一致）
function Radio:activate()
    if self.state.disabled then return false end
    self:setChecked(true)
    return true
end

-- 收集同组单选按钮（按树内顺序），用于方向键在组内移动
local function collectGroup(self, ctx)
    local out = {}
    local group = self.props.group
    if not group then return out end
    local function walk(n)
        if not n or not n.visible or n._bpHidden then return end
        if n.setChecked and n.props and n.props.group == group and not n.state.disabled then
            out[#out + 1] = n
        end
        if n.acceptsChildren then
            for _, c in ipairs(n.children) do
                if n:isChildActive(c) then walk(c) end
            end
        end
    end
    walk(ctx and (ctx.modal or ctx.root) or self.parent)
    if #out == 0 then out[1] = self end
    return out
end

-- 组内方向键移动选中项（WAI-ARIA radiogroup 的键盘习惯）
function Radio:keypressed(key, ctx)
    if self.state.disabled then return end
    if key ~= "left" and key ~= "up" and key ~= "right" and key ~= "down" then return end
    local list = collectGroup(self, ctx)
    if #list < 2 then return end
    local idx = 1
    for i, n in ipairs(list) do
        if n == self then idx = i; break end
    end
    local dir = (key == "left" or key == "up") and -1 or 1
    local nxt = list[idx + dir] or (dir > 0 and list[1] or list[#list])
    nxt:setChecked(true)
    if ctx then ctx:setFocus(nxt) end
end

function Radio:drawContent()
    local p = self.props
    local size = 20
    local bx = self.x
    local by = self.y + (self.h - size) / 2
    local base = self:resolveColor(p.color or "primary")
    local cxb = bx + size / 2
    local cyb = by + size / 2

    draw.setColor(self.state.hovered and theme.color("surface") or theme.color("surface2"))
    platform.graphics.circle("fill", cxb, cyb, size / 2)

    platform.graphics.setLineWidth(2)
    draw.setColor(self.checked and base or theme.color("border"))
    platform.graphics.circle("line", cxb, cyb, size / 2 - 1)

    if self._anim > 0 then
        draw.setColor({ base[1], base[2], base[3], self._anim })
        platform.graphics.circle("fill", cxb, cyb, (size / 2 - 4) * self._anim)
    end

    if p.label then
        local f = font.get(theme.font.body)
        draw.text(p.label, bx + size + 8, self.y + (self.h - f:getHeight()) / 2, 0, { font = f, color = theme.color("text") })
    end

    -- 键盘焦点环（单选按钮此前没有焦点反馈）
    if self.state.focusVisible then
        platform.graphics.setLineWidth(1.5)
        draw.setColor(theme.alpha("primary", 0.6))
        platform.graphics.circle("line", cxb, cyb, size / 2 + 3)
    end
end

return Radio
