--[[
    fuzz_layout.lua —— 增量布局的随机变更对拍（纯 Lua，不需要 LÖVE）

        luajit tests/fuzz_layout.lua [种子]

    做法：建一棵「标题 + 滚动区 5 行卡片 + 页脚」的树，随机施加 120 次属性变更
    （文本 / 可见性 / 宽度 / padding / gap / align），每次变更后：

      1. 让增量布局跑一帧；
      2. 另建一棵同样的树，按同样的变更序列从头构建，也跑一帧；
      3. 逐节点比对矩形。

    剪枝出错最典型的表现就是「旁支没跟着动」或「坐标停在旧值」，两者都会让第 3 步对不上。
    默认种子固定，失败可复现；换种子可扩大覆盖面。
]]

local script = (arg and arg[0]) or "tests/fuzz_layout.lua"
local dir = script:match("^(.*)[/\\][^/\\]+$") or "."
package.path = dir .. "/../?.lua;" .. dir .. "/../?/init.lua;" .. package.path

local install = dofile(dir .. "/love_stub.lua")
install({ width = 800, height = 600 })

local lumi = require("lumi")

local SEED = tonumber(arg and arg[1]) or 1234
local STEPS = 120
math.randomseed(SEED)

local TEXTS = {
    "短", "中等长度的文本", "这是一段很长的文本内容，会折行显示",
    "", "abc def", "中文混排 abc 123",
}

local function build()
    local ui = lumi.new({ width = 800, height = 600 })
    ui:root({ direction = "column", gap = 6, padding = 10 }, function(r)
        r:label("标题", { variant = "title" })
        r:scroll({ h = 380, direction = "column", gap = 5 }, function(s)
            for i = 1, 5 do
                s:box({ direction = "row", gap = 6, padding = 4, bg = "surface", radius = "medium" }, function(row)
                    row:label("行 " .. i, { w = 90 })
                    row:box({ direction = "column", grow = 1, gap = 2 }, function(col)
                        col:label("主文本 " .. i, { wrap = true })
                        col:label("副文本 " .. i)
                    end)
                    row:box({ direction = "row", gap = 4, padding = 2 }, function(tags)
                        tags:label("A" .. i)
                        tags:label("B" .. i)
                    end)
                end)
            end
        end)
        r:label("页脚")
    end)
    return ui
end

local function resolve(ui, path)
    local n = ui.root
    for _, i in ipairs(path) do
        n = n.children[i]
    end
    return n
end

local function snapshot(node, out)
    -- 隐藏节点不参与布局，保留的是隐藏前的旧矩形，不参与比对
    if not node.visible then return end
    out[#out + 1] = string.format("%d,%d,%d,%d", node.x, node.y, node.w, node.h)
    for _, c in ipairs(node.children) do
        snapshot(c, out)
    end
end

local function randomPath()
    local row = math.random(1, 5)
    local branch = math.random(1, 3)
    if branch == 1 then return { 2, row, 1 } end
    if branch == 2 then return { 2, row, 2, math.random(1, 2) } end
    return { 2, row, 3, math.random(1, 2) }
end

local function randomOp()
    local r = math.random()
    if r < 0.40 then
        return { kind = "text", path = randomPath(), value = TEXTS[math.random(#TEXTS)] }
    elseif r < 0.55 then
        return { kind = "visible", path = randomPath(), value = math.random() > 0.3 }
    elseif r < 0.70 then
        return { kind = "w", path = randomPath(), value = ({ 60, 90, 140, 200, "50%" })[math.random(5)] }
    elseif r < 0.82 then
        return { kind = "padding", path = { 2, math.random(1, 5) }, value = math.random(0, 8) }
    elseif r < 0.92 then
        return { kind = "gap", path = { 2, math.random(1, 5), math.random(1, 3) }, value = math.random(0, 10) }
    end
    return { kind = "align", path = { 2, math.random(1, 5) }, value = ({ "start", "center", "end" })[math.random(3)] }
end

local function apply(ui, op)
    local node = resolve(ui, op.path)
    if not node then return false end
    if op.kind == "text" then node:setProp("text", op.value)
    elseif op.kind == "visible" then node:setProp("visible", op.value)
    elseif op.kind == "w" then node:setProp("w", op.value)
    elseif op.kind == "padding" then node:setProp("padding", op.value)
    elseif op.kind == "gap" then node:setProp("gap", op.value)
    elseif op.kind == "align" then node:setProp("align", op.value) end
    return true
end

local ui = build()
ui:update(1 / 60)

local applied = {}
local fails, checks = 0, 0

for step = 1, STEPS do
    local op = randomOp()
    if apply(ui, op) then
        applied[#applied + 1] = op
        ui:update(1 / 60)

        -- 同一串变更从头构建一遍，作为增量结果的参照
        local fresh = build()
        for _, o in ipairs(applied) do apply(fresh, o) end
        fresh:update(1 / 60)

        local a, b = {}, {}
        snapshot(ui.root, a)
        snapshot(fresh.root, b)
        checks = checks + 1

        local same = (#a == #b)
        if same then
            for i = 1, #a do
                if a[i] ~= b[i] then
                    same = false
                    print(string.format("  [FAIL] step %d (%s) 节点 #%d: 增量 %s / 全量 %s",
                        step, op.kind, i, a[i], b[i]))
                    break
                end
            end
        else
            print(string.format("  [FAIL] step %d 节点数不一致: %d / %d", step, #a, #b))
        end
        if not same then fails = fails + 1 end
    end
end

print(string.format("[FUZZ] seed=%d steps=%d checks=%d failed=%d", SEED, #applied, checks, fails))
os.exit(fails == 0 and 0 or 1)
