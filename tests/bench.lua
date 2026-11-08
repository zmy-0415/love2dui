--[[
    bench.lua —— 布局性能基准（纯 Lua，不需要 LÖVE）

        luajit tests/bench.lua [行数] [迭代次数]

    构造一个「滚动区 + N 行卡片」的列表（每行 1 个容器 + 3 个控件），对比三种场景：
      full    全量重排（invalidateLayout：主题切换、窗口 resize 走这条路）
      scroll  仅滚动（只会平移坐标，不重排）
      incr    增量重排（改一行里的一个文本，其余行应被整棵剪掉）

    输出每次布局的耗时与「重排 / 剪枝」节点数，用来看剪枝率与量级。
    断言只针对结构性指标（剪枝数、坐标一致性），耗时仅打印 ——
    机器负载不同，时间断言会变成随机失败源。
]]

local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or "."
package.path = dir .. "/../?.lua;" .. dir .. "/../?/init.lua;" .. package.path

local install = dofile(dir .. "/love_stub.lua")
install({ width = 900, height = 600 })

local lumi = require("lumi")

local ROWS = tonumber(arg and arg[1]) or 300
local ITERS = tonumber(arg and arg[2]) or 60

local function build()
    local ui = lumi.new({ width = 900, height = 600 })
    ui:root({ direction = "column", padding = 12, gap = 8 }, function(r)
        r:label("通讯录", { variant = "title" })
        r:scroll({ h = 520, direction = "column", gap = 6 }, function(s)
            for i = 1, ROWS do
                s:box({ direction = "row", gap = 8, padding = 8, bg = "surface", radius = "medium" }, function(row)
                    row:label("第 " .. i .. " 行", { w = 110 })
                    row:label("描述文本 " .. i, { wrap = true, grow = 1 })
                    row:button("操作", { w = 72 })
                end)
            end
        end)
    end)
    ui:update(1 / 60)
    return ui
end

-- 统计节点总数
local function countNodes(node)
    local n = 1
    for _, c in ipairs(node.children) do n = n + countNodes(c) end
    return n
end

local ui = build()
local total = countNodes(ui.root)
local scroll = ui.root.children[2]
local sampleLabel = scroll.children[math.floor(ROWS / 2)].children[2]

print(string.format("[BENCH] rows=%d nodes=%d iters=%d", ROWS, total, ITERS))

local function bench(name, prepare)
    -- 预热，避免首轮的分配/字符串驻留算进平均
    for _ = 1, 5 do
        prepare()
        ui:update(1 / 60)
    end
    local arranged, pruned = 0, 0
    local t0 = os.clock()
    for _ = 1, ITERS do
        prepare()
        ui:update(1 / 60)
        arranged = arranged + ui.layoutStats.arranged
        pruned = pruned + ui.layoutStats.pruned
    end
    local ms = (os.clock() - t0) * 1000 / ITERS
    print(string.format("  %-8s %7.3f ms/frame   arranged %.0f  pruned %.0f",
        name, ms, arranged / ITERS, pruned / ITERS))
    return ms
end

local fullMs = bench("full", function()
    ui:invalidateLayout()
end)

bench("scroll", function()
    scroll:setScroll((scroll.scrollY + 37) % math.max(1, scroll.contentH - scroll.viewH))
end)

local i = 0
local incrMs = bench("incr", function()
    i = i + 1
    sampleLabel:setProp("text", "描述文本 " .. i)
end)

-- ---------------- 结构断言 ----------------

local ok = true
local function expect(cond, msg)
    if not cond then
        ok = false
        print("  [FAIL] " .. msg)
    end
end

-- 增量的最后一帧只应重排变化路径，其余行被剪掉
expect(ui.layoutStats.pruned >= ROWS - 2,
    string.format("增量重排应剪掉几乎全部行，实际剪枝 %d / %d 行", ui.layoutStats.pruned, ROWS))
expect(ui.layoutStats.arranged < total * 0.1,
    string.format("增量重排节点数应远小于总节点数（%d / %d）", ui.layoutStats.arranged, total))

-- 坐标一致性：把同一棵树的文本改回去，增量重排后的矩形应与新建树完全一致
local function snapshot(node, out)
    out[#out + 1] = string.format("%d,%d,%d,%d", node.x, node.y, node.w, node.h)
    for _, c in ipairs(node.children) do snapshot(c, out) end
end

local mid = math.floor(ROWS / 2)
scroll:setScroll(0)   -- 上面测滚动时挪过位置，比对几何前先复位
sampleLabel:setProp("text", "描述文本 0")
ui:update(1 / 60)

local fresh = build()
fresh.root.children[2].children[mid].children[2]:setProp("text", "描述文本 0")
fresh:update(1 / 60)

local a, b = {}, {}
snapshot(ui.root, a)
snapshot(fresh.root, b)
local same = (#a == #b)
if same then
    for k = 1, #a do
        if a[k] ~= b[k] then same = false break end
    end
end
expect(same, "增量重排后的几何应与全量构建完全一致")

if ok then
    print(string.format("[BENCH] ok  (full %.2fx)", fullMs / math.max(incrMs, 0.0001)))
    os.exit(0)
else
    os.exit(1)
end
