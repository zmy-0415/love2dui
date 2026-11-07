--[[
    selfcheck.lua —— 集成自检（需要真实 LÖVE 环境）

    由 main.lua 在检测到 verify.flag / LUMI_VERIFY=1 时调用：
    构建好的界面 → 数帧更新与绘制 → 弹窗与命中测试 → 控件级回归
    （UTF-8 光标 / IME / 剪贴板 / 百分比布局 / z-index）→ 完整测试套件，
    最后按失败数退出（0 = 全部通过）。

    用法（项目根目录）：
        echo. > verify.flag && lovec .
        # 或 LUMI_VERIFY=1 lovec .
]]

local M = {}

local function section(title)
    print("[SELFCHECK] " .. title)
end

function M.run(ui)
    section("界面构建与数帧渲染")
    ui:update(1 / 60)
    ui:draw()

    ui:dialog({ title = "自检弹窗" }, function(p)
        p:label("自检内容")
        p:button("确定")
    end)
    ui:update(1 / 60)
    ui:draw()

    -- 点击遮罩（10,10）应关闭弹窗，而不是穿透到下面的界面
    ui:mousepressed(10, 10, 1)
    ui:mousereleased(10, 10, 1)
    ui:update(1 / 60)
    ui:draw()

    section("输入框：UTF-8 光标 / 退格 / IME 组合态")
    local Input = require("lumi.widgets.input")
    local ti = Input.new({ text = "你好世界" })
    ti:setText("你好世界")
    ti.state.focused = true
    ti:arrange(0, 0, 200, 40)
    for _ = 1, 5 do ti:keypressed("left", nil) end
    ti:keypressed("backspace", nil)
    ti:textinput("中", nil)
    ti:keypressed("right", nil)
    ti:draw()
    -- 组合态（textedited）应能正常绘制并带下划线
    ti:textedited("nihao", 6, 0)
    ti:draw()
    ti:textinput("好", nil)
    ti:draw()

    section("输入框：选区 + 剪贴板")
    local ci = Input.new({ text = "剪贴板测试" })
    ci._selAnchor = 0
    ci.cursor = #ci._text
    ci.state.focused = true
    ci:arrange(0, 0, 200, 40)
    ci:draw()
    ci:copy()
    ci:cut()
    ci:paste()
    ci:draw()

    section("换行文本与输入法候选窗区域")
    local Label = require("lumi.widgets.label")
    local wl = Label.new({ text = "这是一个会换行的长文本测试内容", wrap = true })
    wl:measure(120, nil)
    wl:arrange(0, 0, 120, 60)
    wl:draw()
    if love.keyboard and love.keyboard.setTextInput then
        love.keyboard.setTextInput(true, 0, 0, 100, 30)
        love.keyboard.setTextInput(false)
    end

    section("布局特性：百分比 / z-index / flex-wrap")
    local Box = require("lumi.widgets.box")
    local wrapRoot = Box.new({ direction = "row", wrap = true, gap = 8, w = 300 })
    for _ = 1, 6 do
        wrapRoot:addChild(Box.new({ w = "30%", h = 30, bg = "surface2", radius = "small" }))
    end
    wrapRoot:arrange(0, 0, 300, 200)
    wrapRoot:draw()

    local zRoot = Box.new({ direction = "row", w = 200, h = 40 })
    zRoot:addChild(Box.new({ w = "50%", bg = "surface", z = 0 }))
    zRoot:addChild(Box.new({ w = "50%", bg = "primary", z = 10 }))
    zRoot:arrange(0, 0, 200, 40)
    zRoot:draw()

    section("主题定制与调试面板")
    local lumi = require("lumi")
    lumi.theme.custom("light", { colors = { primary = "#00AA88" }, shape = { medium = 12 } })
    lumi.theme.apply(lumi.theme.build("dark"))
    lumi.debug.update(1 / 60)
    lumi.debug.toggle()
    lumi.debug.draw(ui)
    lumi.debug.toggle()

    section("功能测试套件")
    local failed = require("tests.run").run()

    print(string.format("[SELFCHECK] %s", failed == 0 and "全部通过" or (failed .. " 项失败")))
    if love.event and love.event.quit then
        love.event.quit(failed > 0 and 1 or 0)
    end
    return failed
end

return M
