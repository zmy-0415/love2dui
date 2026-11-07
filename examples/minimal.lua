--[[
    examples/minimal.lua —— 最小应用

    演示最朴素的用法：直接创建节点、挂到场景、用 setProps 更新状态。
    声明式链式 API（ui:root():box():label(…)）见同目录其他示例。

    运行：love . minimal
]]

local Box = require("lumi.widgets.box")
local Label = require("lumi.widgets.label")
local Button = require("lumi.widgets.button")

local M = { title = "最小应用" }

function M.build(ui)
    local count = 0
    local counter = Label.new({ text = "点击次数：0", variant = "headline" })

    local button = Button.new({
        text = "点我 +1",
        variant = "filled",
        onClick = function()
            count = count + 1
            -- setProps 会按需失效测量缓存与子树缓存，不需要手动重排
            counter:setProps({ text = "点击次数：" .. count })
        end,
    })

    local card = Box.new({
        direction = "column", gap = 18, padding = 28,
        w = 420, bg = "surface", radius = "large", border = "border",
    })
    card:addChild(counter)
    card:addChild(button)

    ui:root({ direction = "column", align = "center", justify = "center", padding = 24 })
    ui:add(card)
end

return M
