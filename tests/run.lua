--[[
    run.lua —— LumiUI 功能测试套件
    覆盖所有内置控件与核心能力（布局/主题/事件），由无头自检调用。
    用法：require("tests.run").run()  →  返回失败数（0 表示全部通过）。
]]

local lumi = require("lumi")
local Box = require("lumi.widgets.box")
local Label = require("lumi.widgets.label")
local Button = require("lumi.widgets.button")
local Input = require("lumi.widgets.input")
local Checkbox = require("lumi.widgets.checkbox")
local Switch = require("lumi.widgets.switch")
local Radio = require("lumi.widgets.radio")
local Slider = require("lumi.widgets.slider")
local Progress = require("lumi.widgets.progress")
local Dropdown = require("lumi.widgets.dropdown")
local Tabs = require("lumi.widgets.tabs")
local Table = require("lumi.widgets.table")
local Tree = require("lumi.widgets.tree")
local Menu = require("lumi.widgets.menu")
local Dialog = require("lumi.widgets.dialog")
local Divider = require("lumi.widgets.divider")
local Scroll = require("lumi.widgets.scroll")
local tooltip = require("lumi.widgets.tooltip")
local theme = require("lumi.theme")
local font = require("lumi.font")
local Rating = require("demo.rating")

local M = {}

local passed, failed = 0, 0
local failures = {}

local function check(desc, cond)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = desc
    end
end

local function eq(desc, actual, expected)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = desc .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")"
    end
end

-- 供下拉/菜单使用的伪场景
local function fakeCtx()
    local overlays = {}
    return {
        overlays = overlays,
        openOverlay = function(_, node, opts) table.insert(overlays, node) end,
        closeOverlay = function(_, node)
            for i, o in ipairs(overlays) do
                if o == node then table.remove(overlays, i); break end
            end
        end,
    }
end

-- ---------------- 基础控件 ----------------

local function testBasic()
    -- Label 测量
    local l = Label.new({ text = "你好" })
    local lw, lh = l:measure(nil, nil)
    check("label 尺寸 > 0", lw > 0 and lh > 0)

    -- Label 换行
    local wl = Label.new({ text = "这是一段非常长的中文文本内容", wrap = true })
    local _, wh = wl:measure(60, nil)
    check("label 换行高度 > 单行", wh > font.get(14):getHeight())

    -- Divider
    local dv = Divider.new({})
    local dw, dh = dv:measure(200, nil)
    check("divider 横向尺寸", dw == 200 and dh == 1)

    -- Progress 线性 / 环形
    local pl = Progress.new({ value = 0.5 })
    local plw, plh = pl:measure(160, nil)
    check("progress 线性尺寸", plw > 0 and plh > 0)
    local pc = Progress.new({ mode = "circular", value = 0.5 })
    local pcw, pch = pc:measure(nil, nil)
    check("progress 环形尺寸", pcw > 0 and pch > 0)

    -- Tooltip
    local tip = tooltip.make("提示")
    local tw, th = tip:measure(200, 100)
    check("tooltip 尺寸", tw > 0 and th > 0)
end

local function testButton()
    local clicked = false
    local btn = Button.new({ text = "按钮", onClick = function() clicked = true end })
    btn:arrange(0, 0, 100, 40)
    btn.state.pressed = true
    btn:mousereleased(50, 20, 1, nil, btn)
    check("button 点击触发 onClick", clicked)

    clicked = false
    btn.state.pressed = true
    btn:mousereleased(500, 500, 1, nil, nil)
    check("button 外部释放不触发", not clicked)
end

local function testAnimate()
    local primary = theme.color("primary")
    local before = { primary[1], primary[2], primary[3] }
    local btn = Button.new({ variant = "filled" })
    -- 触发 hover 状态变化，产生颜色过渡动画，随后推进数帧
    btn.state.hovered = true
    btn:onUpdate(1 / 60)
    for _ = 1, 5 do lumi.animate.update(1 / 60) end
    local same = true
    for i = 1, 3 do
        if math.abs(primary[i] - before[i]) > 0.0001 then same = false end
    end
    check("按钮动画不污染主题色", same)
end

local function testInput()
    local i = Input.new({})
    i:arrange(0, 0, 200, 40)

    -- 插入与光标
    i:textinput("ab", nil)
    eq("input 插入文本", i:getText(), "ab")
    eq("input 光标在末尾", i.cursor, 2)

    -- 中文（多字节）光标移动
    i:setText("你好")
    eq("input 中文光标在末尾", i.cursor, 6)
    i:keypressed("left", nil)
    eq("input 中文左移一个字符", i.cursor, 3)
    i:keypressed("left", nil)
    eq("input 中文左移到开头", i.cursor, 0)

    -- 退格 / 删除
    i:setText("abc"); i.cursor = 3
    i:keypressed("backspace", nil)
    eq("input 退格删除一个字符", i:getText(), "ab")
    i:setText("abc"); i.cursor = 0
    i:keypressed("delete", nil)
    eq("input Delete 删除一个字符", i:getText(), "bc")

    -- 选区
    i:setText("abcdef"); i._selAnchor = 0; i.cursor = 3
    check("input 有选区", i:hasSelection())
    i:deleteRange(0, 3)
    eq("input 删除选区", i:getText(), "def")

    -- 输入替换选区
    i:setText("abcdef"); i._selAnchor = 0; i.cursor = 3
    i:textinput("X", nil)
    eq("input 选区替换", i:getText(), "Xdef")

    -- 退格删除选区
    i:setText("abcdef"); i._selAnchor = 0; i.cursor = 3
    i:keypressed("backspace", nil)
    eq("input 退格删除选区", i:getText(), "def")

    -- 剪切确定性清空（剪贴板读写在无头环境可能不可用，paste 仅做冒烟）
    i:setText("hello"); i._selAnchor = 0; i.cursor = 5
    i:cut()
    eq("input 剪切清空文本", i:getText(), "")
    i:paste()

    -- 密码框多字节掩码：光标/IME 绘制不应触发 UTF-8 解码错误
    local pi = Input.new({ password = true })
    pi:setText("你好")
    pi.state.focused = true
    pi._imeText = "n"
    pi:arrange(0, 0, 200, 40)
    pi:draw()
    check("input 密码框掩码绘制", true)

    -- 带 label 的输入框：正文绘制字体应为 body，label 的 caption 字体不应泄漏
    local li = Input.new({ label = "标签", text = "你好" })
    li:arrange(0, 0, 200, 60)
    li:draw()
    check("input 正文字体不被 label 泄漏", love.graphics.getFont() == font.get(theme.font.body))
end

local function testSelection()
    local cb = Checkbox.new({})
    cb:arrange(0, 0, 20, 20)
    local v
    cb.props.onChanged = function(x) v = x end
    cb.state.pressed = true
    cb:mousereleased(10, 10, 1, nil, cb)
    check("checkbox 点击选中", cb.checked == true and v == true)

    local sw = Switch.new({})
    sw:arrange(0, 0, 60, 30)
    local sv
    sw.props.onChanged = function(x) sv = x end
    sw.state.pressed = true
    sw:mousereleased(10, 10, 1, nil, sw)
    check("switch 点击打开", sw.checked == true and sv == true)

    local parent = Box.new({})
    local r1 = Radio.new({ group = "g", checked = true })
    local r2 = Radio.new({ group = "g" })
    parent:addChild(r1); parent:addChild(r2)
    r2:setChecked(true)
    check("radio 组互斥", r1.checked == false and r2.checked == true)
end

local function testSlider()
    local s = Slider.new({ min = 0, max = 100, value = 50 })
    s:arrange(0, 0, 200, 30)
    s:mousepressed(200, 15, 1, nil)
    eq("slider 点最右 = 100", s.value, 100)
    s:mousepressed(0, 15, 1, nil)
    eq("slider 点最左 = 0", s.value, 0)

    local s2 = Slider.new({ min = 0, max = 10, step = 1, value = 0 })
    s2:arrange(0, 0, 200, 30)
    s2:mousepressed(100, 15, 1, nil)
    check("slider 步进为整数", s2.value == math.floor(s2.value) and s2.value >= 0 and s2.value <= 10)
end

local function testDropdown()
    local ctx = fakeCtx()
    local changedTo
    local dd = Dropdown.new({ items = { "a", "b", "c" }, value = "a", onChanged = function(v) changedTo = v end })
    dd:arrange(0, 0, 150, 40)
    dd:mousepressed(10, 10, 1, ctx)
    check("dropdown 点击打开列表", #ctx.overlays == 1)
    local list = ctx.overlays[1]
    check("dropdown 列表项数", #list.children == 3)
    list.children[2]:emit("onClick")
    eq("dropdown onChanged", changedTo, "b")
    check("dropdown 选择后关闭", #ctx.overlays == 0)

    -- 选项按钮应撑满下拉框宽度（选项设置了 h，不应阻止宽度 stretch）
    local ctx2 = fakeCtx()
    local dd2 = Dropdown.new({ items = { "Windows", "macOS", "Linux", "Android", "iOS", "Web", "其他" }, value = "Windows" })
    dd2:arrange(0, 0, 300, 40)
    dd2:mousepressed(10, 10, 1, ctx2)
    local list2 = ctx2.overlays[1]
    list2:arrange(list2.x, list2.y, list2.w, list2.h)
    local sc = list2.children[1]
    local fullWidth = (sc.w == list2.w)
    for _, b in ipairs(sc.children) do
        if b.w ~= list2.w then fullWidth = false end
    end
    check("dropdown 选项宽度撑满下拉框", fullWidth)
end

local function testTabs()
    local changedTab
    local tabs = Tabs.new({ tabs = { "a", "b", "c" }, active = 1, onChanged = function(i) changedTab = i end })
    tabs:addChild(Box.new({})); tabs:addChild(Box.new({})); tabs:addChild(Box.new({}))
    tabs:arrange(0, 0, 300, 100)
    tabs:mousepressed(150, 10, 1, nil)
    check("tabs 切换到第2页", tabs.active == 2 and changedTab == 2)
end

local function testTable()
    local clickedRow
    local tb = Table.new({ columns = { { label = "c" } }, rows = { { "a" }, { "b" }, { "c" } }, onRowClick = function(i, row) clickedRow = i end })
    tb:arrange(0, 0, 200, 200)
    tb:mousepressed(10, 50, 1, nil)
    check("table 点击第1行", clickedRow == 1 and tb.selected == 1)
end

local function testTree()
    local items = { { label = "root", children = { { label = "child" } } } }
    local selected
    local tr = Tree.new({ items = items, h = 100, onSelect = function(item) selected = item end })
    tr:arrange(0, 0, 200, 100)
    tr:mousepressed(10, 10, 1, nil)
    check("tree 点击展开", tr._expanded[items[1]] == true)
    check("tree onSelect", selected == items[1])
    check("tree 展开后行数增加", #tr:getRows() == 2)
end

local function testMenu()
    local ctx = fakeCtx()
    local menuClicked = false
    local menu = Menu.new({ items = { { label = "文件", items = { { label = "新建", onClick = function() menuClicked = true end } } } } })
    menu:arrange(0, 0, 200, 40)
    menu:mousepressed(10, 10, 1, ctx)
    check("menu 点击打开", #ctx.overlays == 1)
    local panel = ctx.overlays[1]
    panel.children[1]:emit("onClick")
    check("menu 项点击触发", menuClicked == true)
    check("menu 点击后关闭", #ctx.overlays == 0)
end

local function testDialog()
    local dlg = Dialog.new({ title = "测试" })
    dlg:addChild(Label.new({ text = "内容" }))
    local w, h = dlg:measure(300, 400)
    check("dialog 有尺寸", w > 0 and h > 0)
end

local function testScroll()
    local sc = Scroll.new({ direction = "column" })
    for i = 1, 10 do sc:addChild(Label.new({ text = "行" .. i })) end
    sc:arrange(0, 0, 100, 50)
    check("scroll 内容超出视口", sc.contentH > sc.viewH)
    sc:setScroll(100)
    eq("scroll setScroll", sc.scrollY, 100)
    sc:setScroll(-100)
    eq("scroll 向上 clamp 到 0", sc.scrollY, 0)
    sc:wheelmoved(0, -5, nil)
    sc:onUpdate(0.1)
    check("scroll 滚轮滚动", sc.scrollY > 0)
end

local function testRating()
    local rating = Rating.new({ max = 5, value = 2 })
    rating:arrange(0, 0, 200, 30)
    local rv
    rating.props.onChanged = function(v) rv = v end
    rating:mousepressed(0, 15, 1, nil)
    check("rating 点击第1颗", rating.value == 1 and rv == 1)
end

-- ---------------- 布局 ----------------

local function testLayout()
    -- 百分比
    local b = Box.new({ direction = "row", w = 200, h = 40 })
    b:addChild(Box.new({ w = "50%", h = 20 }))
    b:arrange(0, 0, 200, 40)
    eq("百分比宽度", b.children[1].w, 100)

    -- column 中仅设置 h 的子节点仍应 stretch 宽度（h 不应被误判为显式 cross 尺寸）
    local cb = Box.new({ direction = "column", w = 200, h = 100 })
    cb:addChild(Box.new({ h = 30 }))
    cb:arrange(0, 0, 200, 100)
    eq("column 中 h 不阻止宽度 stretch", cb.children[1].w, 200)

    -- z-index 绘制顺序
    local zb = Box.new({ direction = "row" })
    zb:addChild(Box.new({ z = 10 }))
    zb:addChild(Box.new({ z = 0 }))
    local order = zb:getDrawOrder()
    check("z-index 排序", order[1].props.z == 0 and order[2].props.z == 10)

    -- flex-wrap
    local wr = Box.new({ direction = "row", wrap = true, gap = 0, w = 100 })
    for i = 1, 4 do wr:addChild(Box.new({ w = 40, h = 10 })) end
    wr:arrange(0, 0, 100, 100)
    check("wrap 第3个换到第2行", wr.children[3].y > wr.children[1].y)

    -- grow 分配
    local gb = Box.new({ direction = "row", w = 100, h = 20 })
    gb:addChild(Box.new({ grow = 1 }))
    gb:addChild(Box.new({ grow = 1 }))
    gb:arrange(0, 0, 100, 20)
    eq("grow 均分", gb.children[1].w, 50)
end

-- ---------------- 场景 / 事件 ----------------

local function testScene()
    local ui = lumi.new()
    ui:root({ direction = "column" }, function(r)
        r:input({})
        r:input({})
    end)
    ui:update(1 / 60)
    ui:keypressed("tab")
    check("Tab 聚焦第1个输入框", ui.focus == ui.root.children[1])
    ui:keypressed("tab")
    check("Tab 聚焦第2个输入框", ui.focus == ui.root.children[2])
    ui:textinput("X")
    eq("textinput 转发到聚焦输入框", ui.root.children[2]:getText(), "X")
    -- 点击空白失焦
    ui:mousepressed(9999, 9999, 1)
    check("点击空白失焦", ui.focus == nil)
end

-- ---------------- 主题 ----------------

local function testTheme()
    theme.custom("dark", { colors = { primary = "#FF0000" } })
    local p = theme.color("primary")
    check("自定义主题主色为红", math.abs(p[1] - 1) < 0.01 and math.abs(p[2]) < 0.01)
    theme.set("dark")
    check("恢复默认主题", theme.current.mode == "dark")
end

function M.run()
    passed, failed, failures = 0, 0, {}

    testBasic()
    testButton()
    testAnimate()
    testInput()
    testSelection()
    testSlider()
    testDropdown()
    testTabs()
    testTable()
    testTree()
    testMenu()
    testDialog()
    testScroll()
    testRating()
    testLayout()
    testScene()
    testTheme()

    print(string.format("[TEST] %d total, %d passed, %d failed", passed + failed, passed, failed))
    for _, f in ipairs(failures) do
        print("  [FAIL] " .. f)
    end
    return failed
end

return M
