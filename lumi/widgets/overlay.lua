--[[
    overlay.lua —— 带进出场变换的浮层容器
    供 dropdown / menu 等弹出层使用：进场从锚点角缩放 + 上滑入（Material 菜单风格），
    _ovT 进度由 Scene:openOverlay 的补间驱动（0 → 1 进场，1 → 0 退场）。
    用法：局部替换 Box —— local list = Overlay.new(props)，其余行为同 Box。
]]

local Box = require("lumi.widgets.box")
local draw = require("lumi.draw")

local Overlay = setmetatable({}, { __index = Box })
Overlay.__index = Overlay

function Overlay.new(props)
    local self = Box.new(props or {})
    setmetatable(self, Overlay)
    self.acceptsChildren = true
    return self
end

function Overlay:draw()
    if not self.visible then return end
    local t = self._ovT
    if t and t < 1 then
        local s = 0.92 + 0.08 * t
        local oy = -10 * (1 - t) -- 自上滑入
        love.graphics.push()
        love.graphics.translate(self.x, self.y + oy)
        love.graphics.scale(s, s)
        love.graphics.translate(-self.x, -(self.y + oy))
        Box.draw(self)
        love.graphics.pop()
        draw.resetState()   -- pop 恢复渲染状态，缓存作废
    else
        Box.draw(self)
    end
end

return Overlay
