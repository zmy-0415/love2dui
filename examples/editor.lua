--[[
    examples/editor.lua —— 多行编辑器

    语法高亮 + 行号 + 撤销/重做 + 查找替换 + 双向滚动。
    工具条按钮直接操作编辑器节点，说明"链式构建"与"显式节点"可以混用。

    运行：love . editor
    快捷键：Ctrl+Z 撤销 / Ctrl+Y（或 Ctrl+Shift+Z）重做 / Ctrl+F 查找下一处
]]

local Box = require("lumi.widgets.box")
local Label = require("lumi.widgets.label")
local Button = require("lumi.widgets.button")
local Editor = require("lumi.widgets.editor")

local SAMPLE = table.concat({
    "-- LumiUI 编辑器示例",
    "local total = 0",
    "",
    "local function add(a, b)",
    "    -- 数字与关键字都有高亮",
    "    return a + b",
    "end",
    "",
    "for i = 1, 10 do",
    '    total = add(total, i * 2)',
    "end",
    "",
    'print("合计: " .. total)',
    "return total",
}, "\n")

local KEYWORDS = {
    ["local"] = true, ["function"] = true, ["return"] = true, ["for"] = true,
    ["do"] = true, ["end"] = true, ["if"] = true, ["then"] = true,
    ["else"] = true, ["while"] = true, ["in"] = true, ["and"] = true,
    ["or"] = true, ["not"] = true, ["nil"] = true, ["true"] = true, ["false"] = true,
}

-- 按字节区间返回高亮分段（from 含、to 不含，均为 0 基偏移）
local function highlight(line)
    local segs = {}
    local function push(from, to, color)
        segs[#segs + 1] = { from = from, to = to, color = color }
    end

    -- 字符串（先扫，避免把字符串里的数字当数字高亮）
    local quoted = {}
    local s = 1
    while true do
        local a, b = line:find('"[^"]*"', s)
        if not a then break end
        quoted[#quoted + 1] = { a, b }
        push(a - 1, b, "success")
        s = b + 1
    end

    local function inString(pos)
        for _, r in ipairs(quoted) do
            if pos >= r[1] and pos <= r[2] then return true end
        end
        return false
    end

    -- 注释（-- 之后整行）
    local commentAt = line:find("%-%-", 1, false)
    if commentAt then push(commentAt - 1, #line, "muted") end

    -- 数字
    local n = 1
    while true do
        local a, b = line:find("%d+", n)
        if not a then break end
        if not inString(a) and not (commentAt and a >= commentAt) then
            push(a - 1, b, "warning")
        end
        n = b + 1
    end

    -- 关键字
    for word in line:gmatch("[%a_][%w_]*") do
        if KEYWORDS[word] then
            local p = 1
            while true do
                local a, b = line:find(word, p, true)
                if not a then break end
                -- 只匹配整词
                local prev = a > 1 and line:sub(a - 1, a - 1) or ""
                local nextc = line:sub(b + 1, b + 1)
                if not prev:match("[%w_]") and not nextc:match("[%w_]")
                    and not inString(a) and not (commentAt and a >= commentAt) then
                    push(a - 1, b, "primary")
                end
                p = b + 1
            end
        end
    end

    return segs
end

local M = { title = "多行编辑器" }

function M.build(ui, ctx)
    local status = Label.new({ text = "", variant = "caption", color = "muted" })

    local editor = Editor.new({
        h = 340,
        lineNumbers = true,
        text = SAMPLE,
        highlight = highlight,
        onChange = function(v)
            local lines = select(2, v:gsub("\n", "")) + 1
            status:setProps({ text = string.format("%d 行 · %d 字节 · 高亮按行计算", lines, #v) })
        end,
    })
    status:setProps({
        text = string.format("%d 行 · %d 字节 · 高亮按行计算",
            select(2, SAMPLE:gsub("\n", "")) + 1, #SAMPLE),
    })

    ui:root({ direction = "column", padding = 24, gap = 14 }, function(c)
        c:label("多行编辑器", { variant = "display", color = "primary" })
        c:label("点击进入编辑；支持选区、剪贴板、撤销/重做、查找替换与双向滚动。", { color = "muted" })

        c:box({ direction = "row", gap = 10, wrap = true }, function(r)
            r:button("撤销", { variant = "tonal", onClick = function() editor:undo() end })
            r:button("重做", { variant = "tonal", onClick = function() editor:redo() end })
            r:button("查找 print", { variant = "outlined", onClick = function()
                editor:setFindText("print")
                editor:findNext()
                ctx.feedback("已定位到 print")
            end })
            r:button("全部替换 total → sum", { variant = "outlined", onClick = function()
                local n = editor:replaceAll("total", "sum")
                ctx.feedback(string.format("替换 %d 处", n))
            end })
            r:button("全选", { variant = "text", onClick = function() editor:selectRange(0, #editor:getText()) end })
            r:button("重置内容", { variant = "text", onClick = function() editor:setText(SAMPLE) end })
        end)

        c:add(editor)
        c:add(status)
        c:label("Ctrl+Z 撤销 · Ctrl+Y 重做 · Ctrl+A 全选 · Ctrl+C/V 剪贴板", { variant = "caption", color = "muted" })
    end)
end

return M
