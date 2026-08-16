--[[
    debug.lua —— 调试工具
    按 F2 切换：布局外框叠加层 + 控件树面板 + 性能信息（FPS/节点数）。
    用法：
        love.keypressed → lumi.debug.toggle()
        love.update     → lumi.debug.update(dt)
        love.draw       → ui:draw() 后调用 lumi.debug.draw(ui)
]]

local font = require("lumi.font")

local debug = {}
debug.enabled = false

local fps, fpsTimer, frameCount = 0, 0, 0
local nodeCount = 0

function debug.toggle()
    debug.enabled = not debug.enabled
    return debug.enabled
end

function debug.update(dt)
    fpsTimer = fpsTimer + dt
    frameCount = frameCount + 1
    if fpsTimer >= 0.5 then
        fps = math.floor(frameCount / fpsTimer + 0.5)
        fpsTimer = 0
        frameCount = 0
    end
end

-- 依据控件特有的字段/方法识别类型（避免使用 debug.getinfo）
local function nodeLabel(node)
    if node.getCols then return "table" end
    if node._expanded then return "tree" end
    if node.isScroll then return "scroll" end
    if type(node._text) == "string" then return "input" end
    if node.ripples then return "button" end
    if node.getTabRects then return "tabs" end
    if node.getItems then return "dropdown" end
    if node.getTops then return "menu" end
    if node.setChecked then return "radio" end
    if node.getFraction then return "progress" end
    if node.min ~= nil then return "slider" end
    if node.getFont then return "label" end
    if node.checked ~= nil then return "toggle" end
    if node.acceptsChildren then return "box" end
    return "widget"
end

local function collect(node, list)
    if not node or not node.visible then return end
    list[#list + 1] = node
    if node.acceptsChildren then
        for _, c in ipairs(node.children) do
            collect(c, list)
        end
    end
end

function debug.draw(ui)
    if not debug.enabled then return end

    local list = {}
    collect(ui.root, list)
    nodeCount = #list

    -- 布局外框：容器蓝色、叶子橙色
    for _, node in ipairs(list) do
        if node.w > 0 and node.h > 0 then
            local color = node.acceptsChildren and { 0.3, 0.7, 1, 0.6 } or { 1, 0.6, 0.3, 0.6 }
            love.graphics.setLineWidth(1)
            love.graphics.setColor(color)
            love.graphics.rectangle("line", node.x, node.y, node.w, node.h)
        end
    end

    -- 信息面板
    local f = font.get(12)
    love.graphics.setFont(f)
    local lines = { "LumiUI Debug", "FPS: " .. fps, "Nodes: " .. nodeCount }
    local maxLines = 32
    local function walk(node, depth)
        if #lines >= maxLines or not node or not node.visible then return end
        lines[#lines + 1] = string.rep("  ", depth) .. nodeLabel(node)
            .. "  [" .. math.floor(node.w) .. "x" .. math.floor(node.h) .. "]"
        if node.acceptsChildren then
            for _, c in ipairs(node.children) do
                walk(c, depth + 1)
                if #lines >= maxLines then break end
            end
        end
    end
    walk(ui.root, 0)

    local lineH = 15
    local pad = 8
    local panelW = 320
    local panelH = #lines * lineH + pad * 2
    love.graphics.setColor({ 0.05, 0.05, 0.08, 0.78 })
    love.graphics.rectangle("fill", 10, 10, panelW, panelH)
    love.graphics.setColor({ 1, 1, 1, 1 })
    for i, line in ipairs(lines) do
        love.graphics.print(line, 10 + pad, 10 + pad + (i - 1) * lineH)
    end
end

return debug
