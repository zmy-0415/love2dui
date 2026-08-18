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

    -- 渲染冒烟（聚焦/选区/行号）
    e:setText("第一行\n第二行\n第三行")
    e.state.focused = true
    e._selAnchor = 0
    e.cursor = #e._text
    e:arrange(0, 0, 200, 60)
    e:draw()
    check("editor 绘制（选区）", true)
    local ln = Editor.new({ text = "1\n2\n3", lineNumbers = true })
    ln.state.focused = true
    ln:arrange(0, 0, 200, 80)
    ln:draw()
    check("editor 绘制（行号）", true)

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
    fb:draw()
    check("image 无图占位绘制", true)
    -- 圆角 + cover 绘制冒烟（stencil 路径）
    img:arrange(0, 0, 128, 80)
    img.props.radius = "medium"
    img:draw()
    check("image 圆角绘制", true)
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
    av:draw()
    check("avatar 绘制（文字回退）", true)
    local avs = Avatar.new({ src = ph, size = 40, badge = 128 })
    avs:arrange(0, 0, 40, 40)
    avs:draw()
    check("avatar 绘制（图片 + 角标）", true)

    -- Icon
    local ic = IconW.new({ name = "home", size = 30 })
    local icw, ich = ic:measure(nil, nil)
    eq("icon 尺寸", icw == 30 and ich == 30, true)
    ic:arrange(0, 0, 30, 30)
    ic:draw()
    check("icon 绘制", true)
    local unk = IconW.new({ name = "不存在的图标" })
    unk:arrange(0, 0, 24, 24)
    unk:draw()
    check("icon 未知图标名安全", true)
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
    car:draw()
    local round = Carousel.new({ images = { ph }, radius = "large" })
    round:arrange(0, 0, 200, 100)
    round:draw()
    local empty = Carousel.new({})
    empty:arrange(0, 0, 200, 100)
    empty:draw()
    check("carousel 圆角/空数据绘制", true)
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
    testEditor()
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
    testImage()
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
