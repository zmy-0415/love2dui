--[[
    event.lua —— 事件相关的树遍历工具
    焦点收集、滚动祖先查找等。
]]

local event = {}

-- 按绘制顺序收集所有可聚焦节点
function event.collectFocusable(node, list)
    if not node or not node.visible then return end
    if node:isFocusable() then
        table.insert(list, node)
    end
    if node.acceptsChildren then
        for _, c in ipairs(node.children) do
            event.collectFocusable(c, list)
        end
    end
end

return event
