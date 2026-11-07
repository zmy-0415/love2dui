--[[
    dropdown.lua —— 下拉选择框
    items: 字符串列表或 {label=, value=} 列表；点击展开浮动列表，选中回调 onChanged(value)。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")
local animate = require("lumi.animate")
local Overlay = require("lumi.widgets.overlay")
local Button = require("lumi.widgets.button")
local Scroll = require("lumi.widgets.scroll")

local Dropdown = setmetatable({}, { __index = Widget })
Dropdown.__index = Dropdown

function Dropdown.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Dropdown)
    self.value = props.value
    self._list = nil
    self._arrowT = 0 -- 箭头旋转进度：0 向下（收起）/ 1 向上（展开）
    return self
end

function Dropdown:isFocusable()
    return not self.state.disabled
end

function Dropdown:getItems()
    local out = {}
    for i, it in ipairs(self.props.items or {}) do
        if type(it) == "table" then
            out[i] = { label = it.label or it.value, value = it.value or it.label }
        else
            out[i] = { label = it, value = it }
        end
    end
    return out
end

function Dropdown:getLabel()
    local items = self:getItems()
    for _, it in ipairs(items) do
        if it.value == self.value then return it.label end
    end
    if self.props.placeholder then return self.props.placeholder end
    if items[1] then return items[1].label end
    return ""
end

function Dropdown:measureContent(availW, availH)
    return self.props.w or 200, self.props.height or theme.control.height
end

function Dropdown:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    self:toggle(ctx)
end

function Dropdown:onUpdate(dt)
    -- 箭头旋转跟随展开状态（按目标值判断，避免补间中途反复重启）
    local target = self._list and 1 or 0
    if (self._arrowTarget or 0) ~= target then
        self._arrowTarget = target
        animate.stop(self, "_arrowT")
        animate.to(self, { _arrowT = target }, { duration = theme.motion.fast, easing = "cubic" })
    end
end

function Dropdown:toggle(ctx)
    -- 只有仍在栈中的列表才算展开；正在退场的旧列表直接丢弃并重新打开
    local list = self._list
    if list and not list._closing then
        ctx:closeOverlay(list)
        self._list = nil
        return
    end
    self._list = nil
    local items = self:getItems()
    -- 左右 padding 设为 0，使选项宽度与下拉框宽度一致、文字起始位置对齐；
    -- 上下保留 4 让列表项不贴圆角边缘
    local list = Overlay.new({ bg = "surface", elevation = 3, radius = theme.shape.medium, padding = { x = 0, y = 4 }, direction = "column" })
    list.acceptsChildren = true

    local content = list
    local maxItems = 6
    if #items > maxItems then
        local sc = Scroll.new({ direction = "column" })
        list:addChild(sc)
        content = sc
        list.h = maxItems * 36 + 8
    else
        list.h = #items * 36 + 8
    end

    for _, it in ipairs(items) do
        local selected = (it.value == self.value)
        content:addChild(Button.new({
            text = it.label,
            variant = "text",
            align = "left",
            padX = 12,
            radius = theme.shape.small,
            h = 36,
            textColor = selected and theme.color("primary") or theme.color("text"),
            onClick = function()
                self.value = it.value
                self:emit("onChanged", it.value)
                if self._list then
                    ctx:closeOverlay(self._list)
                    self._list = nil
                end
            end,
        }))
    end

    list.w = self.w
    list.x = self.x
    list.y = self.y + self.h + 4
    self._list = list
    ctx:openOverlay(list, {
        closeOnOutside = true,
        -- 列表被外部点击 / Escape 关闭时同步状态，否则箭头卡在展开态、再次点击不重开
        onClose = function()
            if self._list == list then self._list = nil end
        end,
    })
end

function Dropdown:drawContent()
    local p = self.props
    local radius = self:resolveRadius(p.radius, theme.shape.medium)
    local base = self:resolveColor(p.color or "primary")

    draw.roundRect(self.x, self.y, self.w, self.h, radius, theme.color("surface2"))
    local border = theme.color("border")
    local bw = 1
    if self.state.focused or self._list then
        border = base
        bw = 2
    end
    draw.roundRectLine(self.x, self.y, self.w, self.h, radius, border, bw)

    local f = font.get(theme.font.body)
    local label = self:getLabel()
    draw.text(label, self.x + 12, self.y + (self.h - f:getHeight()) / 2, self.w - 36, { font = f, color = theme.color("text"), ellipsis = true })

    -- 箭头（展开时旋转 180°）
    local ax = self.x + self.w - 18
    local ay = self.y + self.h / 2
    love.graphics.push()
    love.graphics.translate(ax, ay)
    love.graphics.rotate((self._arrowT or 0) * math.pi)
    draw.setColor(theme.color("muted"))
    love.graphics.setLineWidth(2)
    love.graphics.line(-4, -2, 0, 2)
    love.graphics.line(0, 2, 4, -2)
    love.graphics.pop()
    draw.resetState()   -- pop 恢复渲染状态，缓存作废
end

return Dropdown
