--[[
    widget.lua —— Widget 基类
    继承自 Node，默认不可作为容器（叶子控件），提供统一回调触发。
]]

local Node = require("lumi.node")

local Widget = setmetatable({}, { __index = Node })
Widget.__index = Widget

function Widget.new(props)
    local self = Node.new(props or {})
    setmetatable(self, Widget)
    self.acceptsChildren = false
    return self
end

-- 触发用户回调（onClick / onChanged 等）
function Widget:emit(name, ...)
    local cb = self.props[name]
    if type(cb) == "function" then
        return cb(...)
    end
end

return Widget
