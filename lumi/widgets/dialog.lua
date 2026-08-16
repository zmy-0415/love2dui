--[[
    dialog.lua —— 模态弹窗
    props.title 标题；子节点作为内容。遮罩 + 阴影 + 圆角面板。
    由 Scene:dialog(props, childrenFn) 创建并居中显示。
]]

local Box = require("lumi.widgets.box")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local Dialog = setmetatable({}, { __index = Box })
Dialog.__index = Dialog

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

function Dialog:draw()
    if not self.visible then return end
    -- 遮罩
    love.graphics.setColor({ 0, 0, 0, 0.55 })
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    -- 面板
    local radius = self:resolveRadius(self.props.radius, theme.shape.large)
    draw.shadow(self.x, self.y, self.w, self.h, radius, 3)
    draw.roundRect(self.x, self.y, self.w, self.h, radius, theme.color("surface"))
    if self.props.title then
        local f = font.get(theme.font.title)
        draw.text(self.props.title, self.x + 24, self.y + 20, 0, { font = f, color = theme.color("text") })
    end
    for _, c in ipairs(self:getDrawOrder()) do
        c:draw()
    end
end

return Dialog
