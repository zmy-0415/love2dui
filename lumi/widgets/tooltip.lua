--[[
    tooltip.lua —— 提示气泡
    由 Scene 管理的浮动层，此处提供构造辅助函数。
]]

local Box = require("lumi.widgets.box")
local Label = require("lumi.widgets.label")
local theme = require("lumi.theme")

local tooltip = {}

-- 构造一个浮动提示气泡节点
function tooltip.make(text)
    local node = Box.new({
        bg = "surface",
        elevation = 3,
        radius = theme.shape.small,
        padding = { x = 10, y = 6 },
    })
    node.acceptsChildren = true
    node:addChild(Label.new({ text = text, variant = "caption", color = "text" }))
    return node
end

return tooltip
