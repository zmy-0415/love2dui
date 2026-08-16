--[[
    box.lua —— 通用容器 / 面板 / 卡片
    通过 props.bg / elevation / border / radius 呈现不同外观。
    纯布局用（无外观）时完全透明。
]]

local Widget = require("lumi.widget")

local Box = setmetatable({}, { __index = Widget })
Box.__index = Box

function Box.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Box)
    self.acceptsChildren = true
    return self
end

return Box
