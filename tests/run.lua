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
local Editor = require("lumi.widgets.editor")
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
local Image = require("lumi.widgets.image")
local Avatar = require("lumi.widgets.avatar")
local IconW = require("lumi.widgets.icon")
local Carousel = require("lumi.widgets.carousel")
local res = require("lumi.image")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")
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

-- 绘制冒烟：真正的断言是「不抛异常」，而不是恒真的 check(..., true)
local function draws(desc, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = desc .. " 抛出异常: " .. tostring(err)
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
    draws("input 密码框掩码绘制", function() pi:draw() end)

    -- 密码框点击定位：掩码串的字节偏移需换算成字符数，不能直接当字符数用
    local pf = font.get(theme.font.body)
    local maskW = pf:getWidth("•")
    local pcur = Input.new({ password = true })
    pcur:setText("abcd")
    pcur:arrange(0, 0, 200, 40)
    pcur:setCursorFromX(pcur.x + 12 + maskW * 1.8)
    eq("input 密码框点击定位到字符边界", pcur.cursor, 2)
    pcur:setText("你好世界")
    pcur:setCursorFromX(pcur.x + 12 + maskW * 1.8)
    eq("input 密码框中文点击定位", pcur.cursor, 6)

    -- 长文本横向滚动：光标始终在可视区内
    local lng = Input.new({ text = string.rep("M", 80) })
    lng:arrange(0, 0, 100, 40)
    lng.state.focused = true
    draws("input 长文本绘制", function() lng:draw() end)
    check("input 长文本横向滚动跟随光标", (lng._scrollX or 0) > 0)
    lng:keypressed("home", nil)
    draws("input 回到开头重绘", function() lng:draw() end)
    check("input 光标回到开头后滚动归零", (lng._scrollX or 0) == 0)

    -- 带 label 的输入框：正文绘制字体应为 body，label 的 caption 字体不应泄漏
    local li = Input.new({ label = "标签", text = "你好" })
    li:arrange(0, 0, 200, 60)
    li:draw()
    check("input 正文字体不被 label 泄漏", love.graphics.getFont() == font.get(theme.font.body))
end

local function testEditor()
    local e = Editor.new({})
    e:arrange(0, 0, 200, 100)

    -- 多行文本与行索引
    e:setText("ab\ncd")
    eq("editor 设置多行文本", e:getText(), "ab\ncd")
    eq("editor 行数", e:lineCount(), 2)
    eq("editor 第2行起始", e:lineStart(2), 3)
    eq("editor 第1行文本", e:getLineText(1), "ab")
    eq("editor 第2行文本", e:getLineText(2), "cd")

    -- 行/列换算
    local row, col = e:offsetToRowCol(0)
    eq("editor 偏移0在第1行", row, 1)
    eq("editor 偏移0列", col, 0)
    row, col = e:offsetToRowCol(4)
    eq("editor 偏移4在第2行", row, 2)
    eq("editor 偏移4列", col, 1)
    eq("editor 行列转偏移", e:rowColToOffset(2, 1), 4)

    -- 光标移动：右移跨行、down 到最后一行
    e:setText("ab\ncd")
    e.cursor = 2
    e:moveHorizontal(1, false)
    eq("editor 右移跨行到第2行", e.cursor, 3)
    e:moveVertical(1, false)
    eq("editor down 到最后一行", e.cursor, 5)

    -- 回车插入换行
    e:setText("ab\ncd")
    e.cursor = 2
    e:keypressed("return", nil)
    eq("editor 回车插入换行", e:getText(), "ab\n\ncd")
    eq("editor 回车后行数", e:lineCount(), 3)

    -- backspace 行首合并行 / delete 行尾合并行
    e:setText("ab\ncd")
    e.cursor = 3
    e:keypressed("backspace", nil)
    eq("editor 行首退格合并行", e:getText(), "abcd")
    e:setText("ab\ncd")
    e.cursor = 2
    e:keypressed("delete", nil)
    eq("editor 行尾删除合并行", e:getText(), "abcd")

    -- 选区替换与删除
    e:setText("abcdef")
    e:selectRange(0, 3)
    e:textinput("X", nil)
    eq("editor 选区替换", e:getText(), "Xdef")
    e:setText("abcdef")
    e:selectRange(0, 3)
    e:keypressed("backspace", nil)
    eq("editor 退格删除选区", e:getText(), "def")

    -- 中文多字节移动/退格
    e:setText("你好\n世界")
    e.cursor = 0
    e:moveHorizontal(1, false)
    eq("editor 中文右移一个字符", e.cursor, 3)
    e:moveHorizontal(1, false)
    eq("editor 中文右移到行尾", e.cursor, 6)
    e:moveHorizontal(1, false)
    eq("editor 中文右移跨行", e.cursor, 7)
    e:keypressed("backspace", nil)
    eq("editor 中文行首退格合并", e:getText(), "你好世界")

    -- onChange 触发
    local changed
    e.props.onChange = function(v) changed = v end
    e:setText("x")
    eq("editor onChange 触发", changed, "x")

    -- 查找
    e:setText("hello world")
    local fs, fe = e:find("world")
    eq("editor find 起始", fs, 6)
    eq("editor find 结束", fe, 11)

    -- 全部替换：数量、光标映射到字符边界、无匹配时不污染撤销栈
    local ra = Editor.new({})
    ra:setText("你好你好")
    ra.cursor = 4 -- 落在第一个匹配内部的第二个汉字上
    eq("editor replaceAll 替换数量", ra:replaceAll("你好", "hi"), 2)
    eq("editor replaceAll 文本", ra:getText(), "hihi")
    eq("editor replaceAll 光标映射", ra.cursor, 2)
    local undoBefore = #ra._undoStack
    eq("editor replaceAll 无匹配返回 0", ra:replaceAll("不存在", "x"), 0)
    eq("editor replaceAll 无匹配不写撤销栈", #ra._undoStack, undoBefore)
    eq("editor replaceAll 无匹配不改文本", ra:getText(), "hihi")

    -- 删除型替换后光标必须仍落在合法字符边界
    local rd = Editor.new({})
    rd:setText("你好你好")
    rd.cursor = #rd._text
    rd:replaceAll("好", "")
    eq("editor replaceAll 删除后文本", rd:getText(), "你你")
    check("editor replaceAll 删除后光标合法",
        rd.cursor <= #rd._text and draw.utf8Align(rd._text, rd.cursor) == rd.cursor)

    -- 渲染冒烟（聚焦/选区/行号）
    e:setText("第一行\n第二行\n第三行")
    e.state.focused = true
    e._selAnchor = 0
    e.cursor = #e._text
    e:arrange(0, 0, 200, 60)
    draws("editor 绘制（选区）", function() e:draw() end)
    local ln = Editor.new({ text = "1\n2\n3", lineNumbers = true })
    ln.state.focused = true
    ln:arrange(0, 0, 200, 80)
    draws("editor 绘制（行号）", function() ln:draw() end)

    -- 滚动条拖动
    local sc = Editor.new({ text = ("长行内容\n"):rep(30) })
    sc:arrange(0, 0, 200, 80)
    check("editor 纵向滚动条存在", sc:hasVScrollbar())
    sc:mousepressed(194, 40, 1, nil)
    check("editor 点击滚动条进入拖动", sc._dragScroll == "v")
    check("editor 点击滚动条产生滚动", sc.scrollY > 0)
    sc:mousereleased(nil, nil, 1, nil, nil)
    check("editor 释放清除拖动状态", sc._dragScroll == nil)

    -- 滚轮路由：editor 在外层 scroll 容器内时，滚轮应作用到 editor 而非外层
    local ui = lumi.new()
    ui:root({ direction = "column" }, function(r)
        r:scroll({ w = 200, h = 200, direction = "column" }, function(s)
            s:editor({ h = 60, text = ("长行\n"):rep(30) })
        end)
    end)
    ui:update(1 / 60)
    local outer = ui.root.children[1]
    local ed = outer.children[1]
    ui:mousemoved(100, 30)
    ui:wheelmoved(0, -5)
    check("editor 滚轮滚动自身", ed.scrollY > 0)
    check("editor 滚轮不冒泡到外层", outer.scrollY == 0)

    -- 撤销/重做
    local u = Editor.new({})
    u:arrange(0, 0, 200, 40)
    u:textinput("a", nil)
    u:textinput("b", nil)
    eq("editor 输入后文本", u:getText(), "ab")
    u:undo()
    eq("editor undo 一次", u:getText(), "a")
    u:undo()
    eq("editor undo 两次", u:getText(), "")
    u:redo()
    eq("editor redo 一次", u:getText(), "a")
    u:redo()
    eq("editor redo 两次", u:getText(), "ab")
    u:textinput("c", nil)
    u:redo()
    eq("editor 新编辑后 redo 栈已清空", u:getText(), "abc")

    -- 语法高亮（highlight 回调 + 渲染冒烟）
    local hlCalls = 0
    local hl = Editor.new({
        text = "local x = 123",
        highlight = function(lineText, lineIdx)
            hlCalls = hlCalls + 1
            local segs = {}
            local s = lineText:find("local", 1, true)
            if s then segs[#segs + 1] = { from = s - 1, to = s - 1 + 5, color = "primary" } end
            return segs
        end,
    })
    hl:arrange(0, 0, 200, 40)
    hl:draw()
    check("editor 语法高亮回调被调用", hlCalls > 0)

    -- 查找/替换
    local ft = Editor.new({ text = "foo bar foo" })
    ft:arrange(0, 0, 200, 40)
    ft:setFindText("foo")
    eq("editor 查找匹配数", #ft._matches, 2)
    local m = ft:findNext()
    check("editor 查找下一个", m ~= nil and m.from == 0 and m.to == 3)
    ft:replace("FOO")
    eq("editor 替换下一个", ft:getText(), "FOO bar foo")
    eq("editor 替换全部数量", ft:replaceAll("foo", "X"), 1)
    eq("editor 替换全部结果", ft:getText(), "FOO bar X")
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

    -- 外部替换数据源：行缓存与内容高度都要跟着变
    tr:setItems({ { label = "a" }, { label = "b" }, { label = "c" } })
    eq("tree setItems 后行数", #tr:getRows(), 3)
    eq("tree setItems 后内容高度", tr.contentH, 3 * 32)
    tr.props.items = { { label = "only" } }
    eq("tree 直接改 props.items 行缓存失效", #tr:getRows(), 1)
    eq("tree 直接改 props.items 内容高度同步", tr.contentH, 32)
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

    -- 命中顺序与绘制一致：z 更高的子节点即使后加入也应优先命中
    local zs = Scroll.new({ direction = "column" })
    local top = Box.new({ w = 100, h = 100, z = 5 })
    local bottom = Box.new({ w = 100, h = 100, z = 0 })
    zs:addChild(top)    -- 先加入但 z 更高 → 绘制在上层
    zs:addChild(bottom)
    zs:arrange(0, 0, 200, 200)
    top.x, top.y, bottom.x, bottom.y = 0, 0, 0, 0
    check("scroll 命中遵循 z 序", zs:hitTest(10, 10) == top)
end

local function testRating()
    local rating = Rating.new({ max = 5, value = 2 })
    rating:arrange(0, 0, 200, 30)
    local rv
    rating.props.onChanged = function(v) rv = v end
    rating:mousepressed(0, 15, 1, nil)
    check("rating 点击第1颗", rating.value == 1 and rv == 1)
end

-- ---------------- 布局增强：Grid / 绝对定位 / 响应式 ----------------

local function testGridAbsolute()
    -- Grid 基础：3 列 2 行等分
    local g = Box.new({ display = "grid", cols = 3, gap = 0, w = 300 })
    for _ = 1, 6 do g:addChild(Box.new({ h = 30 })) end
    g:arrange(0, 0, 300, 60)
    eq("grid 单元格宽", g.children[1].w, 100)
    eq("grid 第2格 x", g.children[2].x, 100)
    eq("grid 第2行 y", g.children[4].y, 30)
    eq("grid 行高取内容高", g.children[1].h, 30)

    -- Grid gap
    local g2 = Box.new({ display = "grid", cols = 2, gap = 10, w = 210, h = 70 })
    g2:addChild(Box.new({ h = 20 }))
    g2:addChild(Box.new({ h = 20 }))
    g2:arrange(0, 0, 210, 70)
    eq("grid gap 单元格宽", g2.children[1].w, 100)
    eq("grid gap 列偏移", g2.children[2].x, 110)

    -- colSpan 占位避让
    local g3 = Box.new({ display = "grid", cols = 3, gap = 0, w = 300 })
    g3:addChild(Box.new({ colSpan = 2, h = 20 }))
    g3:addChild(Box.new({ h = 20 }))
    g3:addChild(Box.new({ h = 20 }))
    g3:arrange(0, 0, 300, 100)
    eq("grid colSpan 宽度", g3.children[1].w, 200)
    eq("grid colSpan 避让", g3.children[2].x, 200)
    check("grid colSpan 后续换行", g3.children[3].y > 0)

    -- rowSpan 行高扩张
    local g4 = Box.new({ display = "grid", cols = 2, gap = 0, w = 200 })
    g4:addChild(Box.new({ rowSpan = 2, h = 60 }))
    g4:addChild(Box.new({ h = 20 }))
    g4:addChild(Box.new({ h = 20 }))
    local _, mh4 = g4:measure(200, nil)
    check("grid rowSpan 影响内容高", mh4 >= 60)
    g4:arrange(0, 0, 200, math.ceil(mh4))
    eq("grid rowSpan 跨行高度", g4.children[1].h, 60)
    check("grid rowSpan 邻格在首行", g4.children[2].y == 0)
    check("grid rowSpan 第2格下移", g4.children[3].y > 0)

    -- 测量
    local g5 = Box.new({ display = "grid", cols = 3, gap = 10 })
    for _ = 1, 3 do g5:addChild(Box.new({ w = 50, h = 30 })) end
    local w5, h5 = g5:measure(320, nil)
    eq("grid 测量宽", w5, 320)
    eq("grid 测量高", h5, 30)

    -- 绝对定位
    local a = Box.new({ direction = "column", w = 200, h = 100 })
    a:addChild(Box.new({ h = 20 }))
    a:addChild(Box.new({ position = { x = 10, y = 10 }, w = 40, h = 16 }))
    a:arrange(0, 0, 200, 100)
    check("absolute 定位", a.children[2].x == 10 and a.children[2].y == 10)
    local a2 = Box.new({ w = 200, h = 100 })
    a2:addChild(Box.new({ position = { x = 5, y = 5, anchor = "top-right" }, w = 40, h = 16 }))
    a2:arrange(0, 0, 200, 100)
    eq("absolute top-right", a2.children[1].x, 200 - 5 - 40)
    local a3 = Box.new({ w = 200, h = 100 })
    a3:addChild(Box.new({ position = { x = "10%", y = "20%" }, w = 40, h = 10 }))
    a3:arrange(0, 0, 200, 100)
    check("absolute 百分比", a3.children[1].x == 20 and a3.children[1].y == 20)
    local a4 = Box.new({ w = 200, h = 100 })
    a4:addChild(Box.new({ position = { x = 6, y = 6, anchor = "bottom-right" }, w = 30, h = 12 }))
    a4:arrange(0, 0, 200, 100)
    check("absolute bottom-right", a4.children[1].x == 200 - 6 - 30 and a4.children[1].y == 100 - 6 - 12)
    -- 绝对定位不占布局流（无显式 h 的容器，内容高只算 flex 子节点）
    local a5 = Box.new({ direction = "column", w = 200 })
    a5:addChild(Box.new({ h = 20 }))
    a5:addChild(Box.new({ position = { x = 10, y = 10 }, w = 40, h = 16 }))
    local _, mah = a5:measure(nil, nil)
    eq("absolute 不占 flex 空间", mah, 20)

    -- 响应式断点
    local r = Box.new({ direction = "row", w = 500, h = 40 })
    r:addChild(Box.new({ grow = 1, h = 40, hideBelow = 600 }))
    r:addChild(Box.new({ grow = 1, h = 40 }))
    r:arrange(0, 0, 500, 40)
    check("hideBelow 窄时隐藏", r.children[1]._bpHidden == true)
    eq("hideBelow 隐藏不占空间", r.children[2].w, 500)
    check("hideBelow 隐藏不响应命中", r.children[1]:hitTest(50, 20) == nil)
    r:arrange(0, 0, 700, 40)
    check("hideBelow 宽时显示", r.children[1]._bpHidden ~= true)
    eq("hideBelow 显示后平分", r.children[1].w, 350)

    local r2 = Box.new({ direction = "row", w = 800, h = 40 })
    r2:addChild(Box.new({ grow = 1, h = 40, hideAbove = 700 }))
    r2:arrange(0, 0, 800, 40)
    check("hideAbove 宽时隐藏", r2.children[1]._bpHidden == true)
end

-- ---------------- 性能：剔除 / 子树缓存 / 虚拟化 ----------------

local function testPerf()
    -- rectVisible
    check("rectVisible 无裁剪恒可见", draw.rectVisible(0, 0, 10, 10))
    draw.pushClip(100, 100, 50, 50)
    check("rectVisible 裁剪外不可见", not draw.rectVisible(0, 0, 10, 10))
    check("rectVisible 相交可见", draw.rectVisible(90, 90, 20, 20))
    check("rectVisible 内部可见", draw.rectVisible(110, 110, 10, 10))
    draw.pushClip(200, 200, 50, 50) -- 交集为空
    check("rectVisible 空交集不可见", not draw.rectVisible(0, 0, 9999, 9999))
    draw.popClip()
    draw.popClip()
    check("rectVisible 出栈后恢复", draw.rectVisible(0, 0, 10, 10))

    -- Canvas 子树缓存
    local box = Box.new({ cache = true, w = 120, h = 80, bg = "surface", direction = "column", gap = 4 })
    box:addChild(Label.new({ text = "缓存面板" }))
    box:addChild(Label.new({ text = "第二行" }))
    box:arrange(0, 0, 120, 80)
    box:draw()
    check("cache 首帧生成 Canvas", box._cacheCv ~= nil)
    local cv = box._cacheCv
    box:draw()
    check("cache 次帧复用", box._cacheCv == cv)
    box:invalidate()
    check("cache invalidate 失效", box._cacheCv == nil)
    box:draw()
    box:arrange(0, 0, 150, 90)
    check("cache 尺寸变化失效", box._cacheCv == nil)

    -- 嵌套子树含圆角裁剪时缓存渲染不报错（clipOffset 修正路径）
    local nested = Box.new({ cache = true, w = 100, h = 100, bg = "surface", radius = "medium", direction = "column" })
    nested:addChild(Avatar.new({ text = "L", size = 40 }))
    nested:arrange(0, 0, 100, 100)
    nested:draw()
    check("cache 含 stencil 子树渲染", nested._cacheCv ~= nil)

    -- tree 可视行虚拟化：深滚动后绘制正确
    local items = {}
    for i = 1, 200 do items[i] = { label = "节点" .. i } end
    local tr = Tree.new({ items = items })
    tr:arrange(0, 0, 240, 160)
    tr:setScroll(99999) -- 滚到底
    tr:draw()
    check("tree 虚拟化底部绘制", tr.scrollY > 0)

    -- ---------------- 绘制热路径优化 ----------------
    -- setColor 去重：连续同色只下发一次
    local rawSetColor = love.graphics.setColor
    local colorCalls = 0
    love.graphics.setColor = function(...) colorCalls = colorCalls + 1; return rawSetColor(...) end
    draw.resetState()
    draw.setColor({ 1, 0, 0, 1 })
    draw.setColor({ 1, 0, 0 })
    draw.setColor(1, 0, 0, 1)
    eq("setColor 同色只下发一次", colorCalls, 1)
    draw.setColor({ 0, 1, 0, 1 })
    eq("setColor 换色重新下发", colorCalls, 2)
    love.graphics.setColor = rawSetColor
    draw.resetState()

    -- setFont 去重
    local rawSetFont = love.graphics.setFont
    local fontCalls = 0
    love.graphics.setFont = function(...) fontCalls = fontCalls + 1; return rawSetFont(...) end
    draw.resetState()
    local bf = font.get(theme.font.body)
    draw.setFont(bf)
    draw.setFont(bf)
    eq("setFont 同字体只下发一次", fontCalls, 1)
    love.graphics.setFont = rawSetFont
    draw.resetState()

    -- textWidth 缓存
    local measures = 0
    local fakeFont = { getWidth = function(_, s) measures = measures + 1; return #s * 7 end }
    eq("textWidth 首次测量", draw.textWidth(fakeFont, "abc"), 21)
    eq("textWidth 命中缓存", draw.textWidth(fakeFont, "abc"), 21)
    eq("textWidth 只测量一次", measures, 1)
    eq("textWidth 空串为 0", draw.textWidth(fakeFont, ""), 0)

    -- roundRect 复用顶点缓冲（不再每帧新建 56 个数字的表）
    local bufs = {}
    local rawPolygon = love.graphics.polygon
    love.graphics.polygon = function(mode, pts) bufs[#bufs + 1] = pts; return rawPolygon(mode, pts) end
    draw.roundRect(0, 0, 10, 10, 3, { 1, 1, 1 })
    draw.roundRect(0, 0, 20, 20, 5, { 1, 1, 1 })
    draw.roundRectLine(0, 0, 20, 20, 5, { 1, 1, 1 }, 1)
    love.graphics.polygon = rawPolygon
    check("roundRect 复用填充顶点表", bufs[1] ~= nil and bufs[1] == bufs[2])
    check("描边使用独立顶点表", bufs[3] ~= nil and bufs[3] ~= bufs[1])
    eq("圆角矩形顶点数固定", bufs[1] and #bufs[1] or 0, 56)

    -- table 2000 行绘制冒烟（既有虚拟化）
    local rows = {}
    for i = 1, 2000 do rows[i] = { i, "x" } end
    local tb = Table.new({ columns = { "A", "B" }, rows = rows })
    tb:arrange(0, 0, 300, 150)
    tb:setScroll(99999)
    draws("table 2000 行虚拟化绘制", function() tb:draw() end)
end

-- ---------------- 图片组件 ----------------

local function testImage()
    -- 占位图生成与缓存
    local ph = res.placeholder("t1", 64, 40)
    check("placeholder 生成 Canvas", ph ~= nil and ph:getWidth() == 64 and ph:getHeight() == 40)
    check("placeholder 缓存复用", res.placeholder("t1", 64, 40) == ph)

    -- 资源加载：路径失败安全返回 nil
    check("res.load 不存在的路径返回 nil", res.load("not_exists.png") == nil)
    check("res.load 可绘制对象透传", res.load(ph) == ph)
    check("res.load 函数源", res.load(function() return ph end) == ph)

    -- fit 布局计算
    local dx, dy, dw, dh = draw.calcFit(64, 40, 100, 100, "cover")
    eq("calcFit cover 铺满", math.floor(dw + 0.5), 160)
    dx, dy, dw, dh = draw.calcFit(64, 40, 100, 100, "contain")
    eq("calcFit contain 放入", math.floor(dw + 0.5), 100)
    dx, dy, dw, dh = draw.calcFit(64, 40, 100, 50, "contain")
    eq("calcFit contain 高受限", math.floor(dh + 0.5), 50)
    dx, dy, dw, dh = draw.calcFit(64, 40, 100, 100, "center")
    eq("calcFit center 原始尺寸", dw, 64)
    dx, dy, dw, dh = draw.calcFit(64, 40, 100, 100, "stretch")
    eq("calcFit stretch", dw == 100 and dh == 100, true)

    -- Image 测量：显式 w 按比例推导 h
    local img = Image.new({ src = ph, w = 128 })
    local mw, mh = img:measure(nil, nil)
    eq("image 显式宽度按比例", math.floor(mh + 0.5), 80)
    -- 无图时占位尺寸可测、可绘制
    local fb = Image.new({ w = 80, h = 60 })
    fb:measure(nil, nil)
    fb:arrange(0, 0, 80, 60)
    draws("image 无图占位绘制", function() fb:draw() end)
    -- 圆角 + cover 绘制冒烟（stencil 路径）
    img:arrange(0, 0, 128, 80)
    img.props.radius = "medium"
    draws("image 圆角绘制", function() img:draw() end)
    -- 点击回调
    local clicked = false
    local btn = Image.new({ src = ph, w = 50, h = 50, onClick = function() clicked = true end })
    btn:arrange(0, 0, 50, 50)
    btn.state.pressed = true
    btn:mousereleased(25, 25, 1, nil, btn)
    check("image onClick 触发", clicked)

    -- Avatar
    local av = Avatar.new({ text = "lumi", size = 44 })
    local aw, ah = av:measure(nil, nil)
    eq("avatar 尺寸", aw == 44 and ah == 44, true)
    check("avatar 文字回退取首字符", av:getFallbackText() == "l")
    check("avatar 中文首字符", Avatar.new({ text = "张伟" }):getFallbackText() == "张")
    av:arrange(0, 0, 44, 44)
    draws("avatar 绘制（文字回退）", function() av:draw() end)
    local avs = Avatar.new({ src = ph, size = 40, badge = 128 })
    avs:arrange(0, 0, 40, 40)
    draws("avatar 绘制（图片 + 角标）", function() avs:draw() end)

    -- Icon
    local ic = IconW.new({ name = "home", size = 30 })
    local icw, ich = ic:measure(nil, nil)
    eq("icon 尺寸", icw == 30 and ich == 30, true)
    ic:arrange(0, 0, 30, 30)
    draws("icon 绘制", function() ic:draw() end)
    local unk = IconW.new({ name = "不存在的图标" })
    unk:arrange(0, 0, 24, 24)
    draws("icon 未知图标名安全", function() unk:draw() end)
    -- 内置图标全部可绘制
    local allOk = true
    for name in pairs(IconW.icons) do
        local ok = pcall(IconW.drawIcon, name, 0, 0, 24, { 1, 1, 1 })
        if not ok then allOk = false end
    end
    check("icon 全部内置图标绘制无错", allOk)

    -- Carousel
    local changedTo
    local car = Carousel.new({ images = { ph, ph, ph }, onChange = function(i) changedTo = i end })
    car:arrange(0, 0, 300, 150)
    eq("carousel 页数", car:pageCount(), 3)
    car:next()
    check("carousel next", car:getCurrent() == 2 and changedTo == 2)
    car:next()
    car:next()
    check("carousel 循环回绕到第1页", car:getCurrent() == 1)
    car:prev()
    check("carousel prev 回绕到末页", car:getCurrent() == 3)
    for _ = 1, 30 do lumi.animate.update(1 / 60) end
    check("carousel 滑动动画到位", math.abs(car._pos - 3) < 0.01)
    -- 箭头点击
    car:mousepressed(car.x + 18, car.y + 75, 1, nil)
    check("carousel 点击左箭头", car:getCurrent() == 2)
    car:mousepressed(car.x + car.w - 18, car.y + 75, 1, nil)
    check("carousel 点击右箭头", car:getCurrent() == 3)
    -- 指示点点击
    local dots = car:dotCenters()
    car:mousepressed(dots[1], car.y + car.h - 10, 1, nil)
    check("carousel 点击指示点跳转", car:getCurrent() == 1)
    -- 自动播放（hover 暂停）
    local car2 = Carousel.new({ images = { ph, ph }, auto = 0.5 })
    car2:arrange(0, 0, 200, 100)
    car2:onUpdate(0.3)
    check("carousel 自动播放未到时不切换", car2:getCurrent() == 1)
    car2:onUpdate(0.3)
    check("carousel 自动播放切换", car2:getCurrent() == 2)
    car2.state.hovered = true
    car2:onUpdate(1.0)
    check("carousel hover 暂停自动播放", car2:getCurrent() == 2)
    -- 绘制冒烟（含圆角/空图片）
    draws("carousel 绘制", function() car:draw() end)
    local round = Carousel.new({ images = { ph }, radius = "large" })
    round:arrange(0, 0, 200, 100)
    local empty = Carousel.new({})
    empty:arrange(0, 0, 200, 100)
    draws("carousel 圆角/空数据绘制", function()
        round:draw()
        empty:draw()
    end)
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

-- ---------------- 交互性 / 动画 ----------------

local function testInteractivity()
    -- Overlay 进出场动画（真实 Scene 驱动）
    local ui = lumi.new()
    ui:root({})
    local closed = false
    local node = Box.new({ w = 100, h = 50 })
    ui:openOverlay(node, { onClose = function() closed = true end })
    check("overlay 进场起始 _ovT = 0", node._ovT == 0 and node._ovAnim == true)
    for _ = 1, 20 do lumi.animate.update(1 / 60) end
    eq("overlay 进场动画到位", node._ovT, 1)
    ui:closeOverlay(node)
    check("overlay 退场动画期间保留", #ui.overlays == 1 and node._closing == true)
    check("overlay 退场起始回调未触发", not closed)
    for _ = 1, 20 do lumi.animate.update(1 / 60) end
    check("overlay 退场动画后移除", #ui.overlays == 0)
    check("overlay onClose 触发", closed)
    -- anim = false 直接开/关，无动画
    local plain = Box.new({ w = 10, h = 10 })
    ui:openOverlay(plain, { anim = false })
    check("overlay anim=false 无进场动画", plain._ovAnim == nil)
    ui:closeOverlay(plain)
    check("overlay anim=false 立即移除", #ui.overlays == 0)

    -- Dialog 关闭按钮热区
    local dctx = fakeCtx()
    local dlg = Dialog.new({ title = "t", closable = true })
    dlg:arrange(100, 100, 300, 200)
    dctx.openOverlay(dlg)
    local cx, cy, cw, ch = dlg:closeRect()
    check("dialog closable 热区有效", cx ~= nil and cx >= 100 and cy >= 100)
    dlg:mousepressed(cx + cw / 2, cy + ch / 2, 1, dctx)
    check("dialog 点击关闭按钮", #dctx.overlays == 0)
    local dlg2 = Dialog.new({ title = "t" })
    dlg2:arrange(0, 0, 300, 200)
    check("dialog 非 closable 无热区", dlg2:closeRect() == nil)

    -- Dropdown 箭头旋转补间：展开 → 1，收起 → 0
    local dctx2 = fakeCtx()
    local dd = Dropdown.new({ items = { "a", "b" }, value = "a" })
    dd:arrange(0, 0, 150, 40)
    dd:mousepressed(10, 10, 1, dctx2)
    dd:onUpdate(1 / 60)
    for _ = 1, 20 do lumi.animate.update(1 / 60) end
    eq("dropdown 展开箭头转向 1", dd._arrowT, 1)
    dd:toggle(dctx2)
    dd:onUpdate(1 / 60)
    for _ = 1, 20 do lumi.animate.update(1 / 60) end
    eq("dropdown 收起箭头回到 0", dd._arrowT, 0)

    -- Carousel 拖拽切页 / 回弹 / 边界阻尼
    local ph = res.placeholder("drag", 64, 40)
    local car = Carousel.new({ images = { ph, ph, ph } })
    car:arrange(0, 0, 300, 150)
    -- 向左拖 → 露出下一页
    car:mousepressed(150, 75, 1, nil)
    check("carousel 按下进入拖拽", car._dragging == true)
    car:mousemoved(90, 75, nil)
    check("carousel 拖拽跟随（向左拖露出下一页）", car._pos > 1)
    car:mousereleased(90, 75, 1, nil)
    check("carousel 左拖超阈值切下一页", car:getCurrent() == 2)
    for _ = 1, 30 do lumi.animate.update(1 / 60) end
    check("carousel 切页滑动到位", math.abs(car._pos - 2) < 0.01)
    -- 位移不足回弹
    car:mousepressed(150, 75, 1, nil)
    car:mousemoved(160, 75, nil)
    car:mousereleased(160, 75, 1, nil)
    check("carousel 小位移回弹不切页", car:getCurrent() == 2)
    for _ = 1, 30 do lumi.animate.update(1 / 60) end
    -- 向右拖 → 回上一页
    car:mousepressed(150, 75, 1, nil)
    car:mousemoved(240, 75, nil)
    check("carousel 向右拖露出上一页", car._pos < 2)
    car:mousereleased(240, 75, 1, nil)
    check("carousel 右拖超阈值切上一页", car:getCurrent() == 1)
    for _ = 1, 30 do lumi.animate.update(1 / 60) end
    -- 边界阻尼：首页继续向右拖最多让出 0.34 页
    car:mousepressed(150, 75, 1, nil)
    car:mousemoved(600, 75, nil)
    check("carousel 边界阻尼限制越界", car._pos >= 0.65 and car._pos <= 1)
    car:mousereleased(600, 75, 1, nil)
    for _ = 1, 30 do lumi.animate.update(1 / 60) end

    -- Slider 键盘调整与 clamp
    local sl = Slider.new({ min = 0, max = 100, value = 50 })
    sl:keypressed("right", nil)
    eq("slider 右键 + 5%", sl.value, 55)
    sl:keypressed("up", nil)
    eq("slider 上键等效右键", sl.value, 60)
    sl:keypressed("left", nil)
    eq("slider 左键 - 5%", sl.value, 55)
    local s0 = Slider.new({ min = 0, max = 100, value = 2 })
    s0:keypressed("left", nil)
    s0:keypressed("left", nil)
    eq("slider 下限 clamp 到 0", s0.value, 0)
    local s100 = Slider.new({ min = 0, max = 100, value = 98 })
    s100:keypressed("right", nil)
    s100:keypressed("right", nil)
    eq("slider 上限 clamp 到 100", s100.value, 100)

    -- Toast 类型
    local tui = lumi.new()
    tui:root({})
    tui:toast("默认")
    tui:toast("成功", "success")
    tui:toast("错误", "error")
    tui:toast("信息", "info")
    check("toast 入队数量", #tui.toasts == 4)
    eq("toast 类型记录", tui.toasts[2].type, "success")
    tui:update(3.0)
    check("toast 超时自动移除", #tui.toasts == 0)
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

    -- 每组独立执行：某组抛异常只记一条失败，不会中断后续所有用例
    local groups = {
        { "基础控件", testBasic },
        { "按钮", testButton },
        { "动画", testAnimate },
        { "输入框", testInput },
        { "编辑器", testEditor },
        { "选区", testSelection },
        { "滑块", testSlider },
        { "下拉", testDropdown },
        { "标签页", testTabs },
        { "表格", testTable },
        { "树", testTree },
        { "菜单", testMenu },
        { "对话框", testDialog },
        { "滚动区", testScroll },
        { "评分", testRating },
        { "Grid/绝对定位", testGridAbsolute },
        { "性能", testPerf },
        { "图片", testImage },
        { "布局", testLayout },
        { "场景", testScene },
        { "交互", testInteractivity },
        { "主题", testTheme },
    }
    for _, g in ipairs(groups) do
        local ok, err = xpcall(g[2], function(e)
            if debug and debug.traceback then return debug.traceback(tostring(e), 2) end
            return tostring(e)
        end)
        if not ok then
            failed = failed + 1
            failures[#failures + 1] = string.format("[%s] 异常中断: %s", g[1], tostring(err))
        end
    end

    print(string.format("[TEST] %d total, %d passed, %d failed", passed + failed, passed, failed))
    for _, f in ipairs(failures) do
        print("  [FAIL] " .. f)
    end
    return failed
end

return M
