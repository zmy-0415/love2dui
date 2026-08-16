--[[
    Notepad++ 复刻版（基于 LumiUI / LÖVE）
    多标签文本编辑器：语法高亮、行号、查找/替换、转到行、缩放、文件读写。

    运行：love .
    无头自检：lovec.exe 项目目录（创建 verify.flag 或设置 LUMI_VERIFY=1 后自动退出）
]]

local lumi = require("lumi")
local App = require("npp.app")
local syntax = require("npp.syntax")

local ui
local app
local verifyQuit = false
local verifyExitCode = 0

local function findById(node, id)
    if not node then return nil end
    if node.props and node.props.id == id then return node end
    if node.acceptsChildren then
        for _, c in ipairs(node.children) do
            local r = findById(c, id)
            if r then return r end
        end
    end
    return nil
end

function love.load(args)
    ui = lumi.new()

    lumi.register("npp_tabbar", require("npp.tabbar").new, "props")
    lumi.register("npp_statusbar", require("npp.statusbar").new, "props")
    lumi.register("npp_toolbar", require("npp.toolbar").new, "props")

    app = App.new(ui)

    ui:root({ direction = "column" })
      :menu({ items = app:menuItems(), bg = "surface", padding = { x = 12 } })
      :npp_toolbar({ app = app, items = app:toolbarItems() })
      :npp_tabbar({ app = app })
      :editor({
          id = "editor",
          grow = 1,
          maxH = 120,
          lineNumbers = true,
          placeholder = "在此输入文本…（Ctrl+N 新建 / Ctrl+O 打开 / Ctrl+S 保存）",
          highlight = function(lineText, lineIdx)
              local d = app.docs[app.active]
              if not d then return nil end
              return syntax.highlight(d.lang, lineText)
          end,
          onChange = function() app:onEditorChange() end,
      })
      :npp_statusbar({ app = app })

    app:attach(findById(ui.root, "editor"))
    ui:setFocus(app.editor)

    -- 无头自检
    local verifyMode = (love.filesystem.getInfo("verify.flag") ~= nil)
        or (os.getenv("LUMI_VERIFY") == "1")
    if verifyMode then
        verifyExitCode = runVerify()
        verifyQuit = true
    end
end

-- ---------------- 无头自检 ----------------

function runVerify()
    local failed = 0
    local function check(desc, cond)
        if not cond then
            failed = failed + 1
            print("  [FAIL] " .. desc)
        end
    end

    -- 基础构建 + 数帧更新/绘制
    for _ = 1, 3 do
        ui:update(1 / 60)
        ui:draw()
    end
    check("根节点构建", ui.root ~= nil)
    check("编辑器绑定", app.editor ~= nil)
    check("编辑器填充布局", app.editor.h > 100)
    check("编辑器不越界", app.editor.y + app.editor.h <= love.graphics.getHeight())

    -- 语法高亮冒烟
    local luaSegs = syntax.highlight("lua", "local x = 42 -- comment")
    check("Lua 语法高亮有分段", luaSegs ~= nil and #luaSegs > 0)
    local xmlSegs = syntax.highlight("xml", '<div class="a">text</div>')
    check("XML 语法高亮有分段", xmlSegs ~= nil and #xmlSegs > 0)
    local jsSegs = syntax.highlight("js", "const x = 1; // hi")
    check("JS 语法高亮有分段", jsSegs ~= nil and #jsSegs > 0)
    check("扩展名检测", syntax.detect("main.lua") == "lua" and syntax.detect("a.py") == "python")

    -- 目录列举（FFI 优先 / popen 回退）：源码所在父目录必含若干子目录
    local fs = require("npp.fs")
    local srcBase = love.filesystem.getSourceBaseDirectory() or "."
    local vdirs, vfiles = fs.listDir(srcBase)
    check("目录列举（后端 " .. fs.backend .. "）", #vdirs >= 1)

    -- 文档操作
    app:newFile()
    check("新建文档", #app.docs == 2 and app.active == 2)
    app.editor:setText("hello\nworld")
    check("编辑器文本", app.editor:getText() == "hello\nworld")
    app:switchTo(1)
    check("切换文档", app.active == 1)
    app:switchTo(2)
    check("切回文档", app.editor:getText() == "hello\nworld")

    -- 查找
    app:_applyFind("world")
    app:findNext()
    local a, b = app.editor:selectionRange()
    check("查找并选中", a ~= nil and app.editor:getText():sub(a + 1, b) == "world")

    -- 缩放
    app:setZoom(120)
    check("缩放字号", app.editor.props.fontSize == 16)
    app:setZoom(100)

    -- 文件读写（保存目录内临时文件，用 love.filesystem 创建与清理）
    local tmpName = "_npp_verify.lua"
    love.filesystem.write(tmpName, "local x = 1\n-- 测试\n")
    local tmpPath = love.filesystem.getSaveDirectory() .. "/" .. tmpName
    local f = io.open(tmpPath, "rb")
    if f then
        f:close()
        local before = #app.docs
        app:openPath(tmpPath)
        check("打开文件", #app.docs == before + 1 and app.docs[app.active].lang == "lua")
        app.docs[app.active].path = tmpPath
        app.docs[app.active].name = tmpName
        app.docs[app.active].lang = "lua"
        app:_writeFile(app.docs[app.active])
        check("保存文件", love.filesystem.getInfo(tmpName) ~= nil)
    else
        print("  [WARN] 无法读取临时文件，跳过文件读写自检")
    end
    love.filesystem.remove(tmpName)

    -- Unicode 路径读写（中文文件名，修复 io.open 的 illegal byte sequence）
    local uniName = "中文测试.lua"
    local uniContent = "local x = 1\n"
    local saveRoot = love.filesystem.getSaveDirectory()
    local wok = fs.writeFile(saveRoot .. "/" .. uniName, uniContent)
    local rdata = wok and fs.readFile(saveRoot .. "/" .. uniName)
    check("Unicode 路径读写", wok == true and rdata == uniContent)
    love.filesystem.remove(uniName)

    -- 关闭标签页（先标记为已保存，避免触发未保存确认弹窗）
    app.docs[app.active].dirty = false
    local n = #app.docs
    app:closeTab(app.active)
    check("关闭标签页", #app.docs == n - 1)

    -- 清空所有文档的未保存标记，避免退出自检时触发退出确认弹窗
    for _, d in ipairs(app.docs) do d.dirty = false end

    -- 弹窗构建冒烟（打开 → 绘制 → 关闭，捕获运行时错误）
    app.cwd = love.filesystem.getSourceBaseDirectory() or "."
    local function dialogSmoke(desc, openFn)
        local ok, err = pcall(openFn)
        check(desc, ok)
        if not ok then print("    " .. tostring(err)) end
        ui:update(1 / 60)
        ui:draw()
        ui:closeAllOverlays()
        ui:update(1 / 60)
        ui:draw()
    end
    dialogSmoke("查找弹窗", function() app:findDialog() end)
    dialogSmoke("替换弹窗", function() app:replaceDialog() end)
    dialogSmoke("转到行弹窗", function() app:gotoDialog() end)
    dialogSmoke("关于弹窗", function() app:aboutDialog() end)
    dialogSmoke("另存为弹窗", function() app:saveAs() end)
    dialogSmoke("打开文件弹窗", function() app:openDialog() end)

    -- 框架测试套件（确保 editor 扩展未破坏原能力）
    local tFailed = require("tests.run").run()
    return failed + tFailed
end

-- ---------------- love 回调 ----------------

function love.update(dt)
    ui:update(dt)
    if verifyQuit then love.event.quit(verifyExitCode) end
end

function love.draw()
    ui:draw()
end

function love.mousepressed(x, y, b)
    ui:mousepressed(x, y, b)
end

function love.mousereleased(x, y, b)
    ui:mousereleased(x, y, b)
end

function love.mousemoved(x, y)
    ui:mousemoved(x, y)
end

function love.wheelmoved(x, y)
    -- Ctrl + 滚轮：编辑器缩放
    if love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then
        if y > 0 then app:zoomIn() else app:zoomOut() end
        return
    end
    ui:wheelmoved(x, y)
end

function love.keypressed(k)
    if app:onKey(k) then return end
    ui:keypressed(k)
end

function love.textinput(t)
    ui:textinput(t)
end

function love.textedited(text, start, length)
    ui:textedited(text, start, length)
end

function love.resize(w, h)
    ui:resize(w, h)
end

function love.quit()
    return app:onQuit()
end
