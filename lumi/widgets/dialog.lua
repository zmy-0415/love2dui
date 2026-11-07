--[[
    dialog.lua —— 模态弹窗
    props.title 标题；子节点作为内容。遮罩 + 阴影 + 圆角面板。
    由 Scene:dialog(props, childrenFn) 创建并居中显示。
    进出场：遮罩淡入淡出 + 面板中心缩放（_ovT 由 Scene 补间）。
    props.closable = true 显示右上角关闭按钮。
]]

local Box = require("lumi.widgets.box")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")
local Icon = require("lumi.widgets.icon")

local Dialog = setmetatable({}, { __index = Box })
Dialog.__index = Dialog

local CLOSE_SIZE = 30

function Dialog.new(props)
    local self = Box.new(props or {})
    setmetatable(self, Dialog)
    self.acceptsChildren = true
    local p = self.props
    local top = p.title and 60 or 24
    p.padding = p.padding or { top = top, right = 24, bottom = 24, left = 24 }
    p.direction = p.direction or "column"
    p.gap = p.gap or 12
    return self
end

-- 关闭按钮热区（含 6px 余量），未启用时返回 nil
function Dialog:closeRect()
    if not self.props.closable then return nil end
    return self.x + self.w - 14 - CLOSE_SIZE, self.y + 14, CLOSE_SIZE, CLOSE_SIZE
end

function Dialog:mousepressed(x, y, button, ctx)
    if button ~= 1 then return end
    local cx, cy, cw, ch = self:closeRect()
    if cx and x >= cx and x < cx + cw and y >= cy and y < cy + ch then
        if ctx then ctx:closeOverlay(self) end
    end
end

function Dialog:draw()
    if not self.visible then return end
    local t = self._ovT or 1
    -- 遮罩（随进出场淡入淡出，不受面板缩放影响）
    draw.setColor({ 0, 0, 0, 0.55 * t })
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    -- 面板：中心缩放进场（0.94 → 1）
    local radius = self:resolveRadius(self.props.radius, theme.shape.large)
    love.graphics.push()
    if t < 1 then
        local s = 0.94 + 0.06 * t
        local cx = self.x + self.w / 2
        local cy = self.y + self.h / 2
        love.graphics.translate(cx, cy)
        love.graphics.scale(s, s)
        love.graphics.translate(-cx, -cy)
    end
    draw.shadow(self.x, self.y, self.w, self.h, radius, 3)
    draw.roundRect(self.x, self.y, self.w, self.h, radius, theme.color("surface"))
    if self.props.title then
        local f = font.get(theme.font.title)
        draw.text(self.props.title, self.x + 24, self.y + 20, self.w - 48 - (self.props.closable and CLOSE_SIZE or 0),
            { font = f, color = theme.color("text"), ellipsis = true })
    end
    if self.props.closable then
        local cx, cy, cw, ch = self:closeRect()
        local ctx = self._ctx
        local mx, my = ctx and ctx._mouseX or -1, ctx and ctx._mouseY or -1
        if mx >= cx and mx < cx + cw and my >= cy and my < cy + ch then
            draw.roundRect(cx, cy, cw, ch, ch / 2, theme.alpha("text", 0.08))
        end
        Icon.drawIcon("close", cx + (cw - 16) / 2, cy + (ch - 16) / 2, 16, theme.color("muted"))
    end
    for _, c in ipairs(self:getDrawOrder()) do
        c:draw()
    end
    love.graphics.pop()
    draw.resetState()   -- pop 恢复渲染状态，缓存作废
end

return Dialog
