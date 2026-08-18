--[[
    LumiUI 测试入口（自包含，覆盖全部控件）
    运行：love .
    交互结果会通过 print 输出到控制台（用 lovec.exe 运行可见），同时以 Toast 提示。

    无头自检：lovec.exe 项目目录（创建 verify.flag 后运行会自动退出）
]]

local lumi = require("lumi")

local ui
local verifyQuit = false
local verifyExitCode = 0

-- 交互回调：打印到控制台 + 弹出 Toast，方便在 GUI/控制台下都能看到反馈
local function feedback(msg)
    print("[LumiUI] " .. msg)
    ui:toast(msg)
end

function love.load(args)
    ui = lumi.new()

    -- 注册自定义控件（示例：星级评分）
    lumi.register("rating", require("demo.rating").new, "props")

    -- 顶部菜单栏
    ui:root({ direction = "column" })
      :menu({
          items = {
              { label = "文件", items = {
                  { label = "新建", onClick = function() feedback("新建") end },
                  { label = "打开", onClick = function() feedback("打开") end },
                  { divider = true },
                  { label = "退出", onClick = function() love.event.quit() end },
              } },
              { label = "主题", items = {
                  { label = "深色", onClick = function() ui:setTheme("dark") end },
                  { label = "浅色", onClick = function() ui:setTheme("light") end },
              } },
          },
          bg = "surface",
          padding = { x = 16 },
      })
      :scroll({ grow = 1, padding = 28, gap = 24, direction = "column" }, function(c)

          c:label("LumiUI 框架测试", { variant = "display", color = "primary" })
          c:label("所有控件均已加载，交互结果打印到控制台", { variant = "body", color = "muted" })

          -- 按钮
          c:divider({ text = "按钮 Button" })
          c:box({ direction = "row", gap = 12 }, function(r)
              r:button("Filled", { variant = "filled", onClick = function() feedback("Filled 点击") end })
              r:button("Tonal", { variant = "tonal", onClick = function() feedback("Tonal 点击") end })
              r:button("Outlined", { variant = "outlined", onClick = function() feedback("Outlined 点击") end })
              r:button("Text", { variant = "text", onClick = function() feedback("Text 点击") end })
              r:button("禁用", { disabled = true })
              r:button("悬停提示", { tooltip = "这是一个 Tooltip 提示气泡" })
          end)

          -- 输入框
          c:divider({ text = "输入框 Input" })
          c:box({ direction = "row", gap = 16 }, function(r)
              r:box({ grow = 1, direction = "column", gap = 8 }, function(x)
                  x:input({ label = "用户名", placeholder = "请输入用户名", onChange = function(v) print("[input] 用户名 = " .. v) end })
                  x:input({ label = "密码", password = true, placeholder = "请输入密码" })
              end)
              r:box({ grow = 1, direction = "column", gap = 8 }, function(x)
                  x:input({ label = "邮箱", placeholder = "name@example.com", onSubmit = function(v) feedback("提交: " .. v) end })
                  x:input({ label = "禁用", placeholder = "不可编辑", disabled = true })
              end)
          end)

          -- 多行编辑器
          c:divider({ text = "多行编辑器 Editor（撤销/重做 Ctrl+Z/Y、语法高亮、行号）" })
          c:editor({
              h = 140,
              lineNumbers = true,
              text = "local x = 42\nfor i = 1, 10 do\n  x = x + i\nend\nreturn x",
              highlight = function(lineText, lineIdx)
                  local segs = {}
                  local s = 1
                  while true do
                      local a, b = lineText:find("%d+", s)
                      if not a then break end
                      segs[#segs + 1] = { from = a - 1, to = b, color = "warning" }
                      s = b + 1
                  end
                  for _, kw in ipairs({ "local", "for", "do", "end", "return" }) do
                      local p = 1
                      while true do
                          local a, b = lineText:find(kw, p, true)
                          if not a then break end
                          segs[#segs + 1] = { from = a - 1, to = b, color = "primary" }
                          p = b + 1
                      end
                  end
                  return segs
              end,
              onChange = function(v) print("[editor] 内容更新（" .. #v .. " 字节）") end,
          })

          -- 选择控件
          c:divider({ text = "选择控件 Checkbox / Switch / Radio" })
          c:box({ direction = "row", gap = 16 }, function(r)
              r:box({ grow = 1, direction = "column", gap = 12 }, function(x)
                  x:checkbox({ label = "记住我", checked = true, onChanged = function(v) print("[checkbox] 记住我 = " .. tostring(v)) end })
                  x:checkbox({ label = "接收通知", onChanged = function(v) print("[checkbox] 通知 = " .. tostring(v)) end })
                  x:switch({ label = "深色模式", checked = true, onChanged = function(v) feedback("深色模式 = " .. tostring(v)) end })
                  x:switch({ label = "自动更新", onChanged = function(v) print("[switch] 自动更新 = " .. tostring(v)) end })
              end)
              r:box({ grow = 1, direction = "column", gap = 12 }, function(x)
                  x:label("请选择系统", { variant = "caption", color = "muted" })
                  x:radio({ label = "Windows", checked = true, group = "os", onChanged = function(v) print("[radio] Windows") end })
                  x:radio({ label = "macOS", group = "os", onChanged = function(v) print("[radio] macOS") end })
                  x:radio({ label = "Linux", group = "os", onChanged = function(v) print("[radio] Linux") end })
              end)
          end)

          -- 滑块与进度
          c:divider({ text = "滑块与进度 Slider / Progress" })
          c:box({ direction = "row", gap = 24 }, function(r)
              r:box({ grow = 1, direction = "column", gap = 12 }, function(x)
                  x:slider({ min = 0, max = 100, value = 60, showValue = true, onChanged = function(v) print("[slider] 音量 = " .. v) end })
                  x:slider({ min = 0, max = 10, value = 3, step = 1, showValue = true, onChanged = function(v) print("[slider] 档位 = " .. v) end })
              end)
              r:box({ direction = "row", gap = 24, align = "center" }, function(x)
                  x:box({ grow = 1, direction = "column", gap = 8 }, function(y)
                      y:progress({ value = 0.35 })
                      y:progress({ value = 0.75, color = "success" })
                  end)
                  x:progress({ mode = "circular", value = 0.6, showValue = true, size = 72 })
              end)
          end)

          -- 布局增强
          c:divider({ text = "布局增强 Grid / Absolute / 响应式" })
          -- Grid 基础：3 列等分
          c:box({ display = "grid", cols = 3, gap = 10 }, function(g)
              for i = 1, 6 do
                  g:box({ h = 52, bg = "surface2", radius = "medium", align = "center", justify = "center" }, function(b)
                      b:label("G" .. i, { color = "muted" })
                  end)
              end
          end)
          -- Grid 跨行跨列
          c:box({ display = "grid", cols = 3, gap = 10, h = 128 }, function(g)
              g:box({ colSpan = 2, bg = "primary", radius = "medium", align = "center", justify = "center" }, function(b)
                  b:label("colSpan = 2", { color = "onPrimary" })
              end)
              g:box({ rowSpan = 2, bg = "surface2", radius = "medium", align = "center", justify = "center" }, function(b)
                  b:label("rowSpan = 2", { color = "muted" })
              end)
              g:box({ bg = "surface2", radius = "medium", align = "center", justify = "center" }, function(b)
                  b:label("1×1", { color = "muted" })
              end)
              g:box({ bg = "surface2", radius = "medium", align = "center", justify = "center" }, function(b)
                  b:label("1×1", { color = "muted" })
              end)
              g:box({ colSpan = 3, bg = "surface2", radius = "medium", align = "center", justify = "center" }, function(b)
                  b:label("colSpan = 3", { color = "muted" })
              end)
          end)
          -- 绝对定位：徽标与悬浮按钮（position + anchor）
          c:box({ h = 104, bg = "surface2", radius = "medium", padding = 16, clipChildren = true, direction = "column", gap = 6 }, function(rel)
              rel:label("绝对定位 position / anchor", { variant = "h3" })
              rel:label("角标与悬浮按钮固定在容器四角，不占布局流", { color = "muted" })
              rel:box({ position = { x = 10, y = 10, anchor = "top-right" }, bg = "error", radius = 999, padding = { x = 8, y = 2 } }, function(bdg)
                  bdg:label("NEW", { variant = "caption", color = "onPrimary" })
              end)
              rel:box({ position = { x = 10, y = 10, anchor = "bottom-right" }, bg = "primary", radius = 999, w = 32, h = 32, align = "center", justify = "center" }, function(fb)
                  fb:icon("close", { size = 16, color = "onPrimary" })
              end)
              rel:box({ position = { x = 10, y = 10, anchor = "bottom-left" }, bg = "success", radius = 999, w = 32, h = 32, align = "center", justify = "center" }, function(fb)
                  fb:icon("check", { size = 16, color = "onPrimary" })
              end)
          end)
          -- 响应式断点：拖动窗口宽度观察切换
          c:box({ direction = "row", gap = 10 }, function(r)
              r:box({ grow = 1, h = 44, bg = "primary", radius = "medium", align = "center", justify = "center", hideBelow = 700 }, function(b)
                  b:label("宽窗口可见 hideBelow = 700", { color = "onPrimary" })
              end)
              r:box({ grow = 1, h = 44, bg = "success", radius = "medium", align = "center", justify = "center", hideAbove = 700 }, function(b)
                  b:label("窄窗口可见 hideAbove = 700", { color = "onPrimary" })
              end)
          end)
          c:label("拖动窗口宽度，观察上方色块切换（响应式断点）", { variant = "caption", color = "muted" })

          -- 图片组件
          c:divider({ text = "图片组件 Image / Avatar / Icon / Carousel" })
          local ph = lumi.image.placeholder
          local ph1 = ph("demo1", 480, 288, { 0.16, 0.32, 0.72 }, { 0.42, 0.22, 0.68 }, "480×288")
          local ph2 = ph("demo2", 480, 288, { 0.72, 0.36, 0.16 }, { 0.85, 0.62, 0.20 }, "Cover")
          local ph3 = ph("demo3", 480, 288, { 0.13, 0.55, 0.42 }, { 0.36, 0.68, 0.30 }, "Contain")
          local ph4 = ph("demo4", 480, 288, { 0.62, 0.18, 0.36 }, { 0.86, 0.40, 0.30 }, "Center")
          c:box({ direction = "row", gap = 16 }, function(r)
              r:image({ src = ph1, w = 220, h = 132, radius = "medium", onClick = function() feedback("点击图片") end })
              r:box({ direction = "column", gap = 10 }, function(x)
                  x:label("Avatar（无图时文字回退）", { variant = "caption", color = "muted" })
                  x:box({ direction = "row", gap = 10, align = "center" }, function(a)
                      a:avatar({ src = ph2, size = 44, onClick = function() feedback("点击头像") end })
                      a:avatar({ text = "lumi", size = 44 })
                      a:avatar({ text = "张伟", size = 44, color = "success" })
                      a:avatar({ src = ph3, size = 44, badge = 3 })
                      a:avatar({ text = "M", size = 44, badge = true })
                      a:avatar({ text = "橙", size = 44, badge = 128 })
                  end)
                  x:box({ direction = "row", gap = 10, align = "center", wrap = true }, function(a)
                      for _, name in ipairs({ "home", "user", "settings", "search", "close", "check", "heart", "star",
                          "trash", "edit", "play", "pause", "folder", "file", "image", "download", "upload", "refresh",
                          "menu", "warning", "info", "mail", "lock", "calendar", "more" }) do
                          a:box({ direction = "column", gap = 4, align = "center", w = 56 }, function(ic)
                              ic:icon(name, { size = 26, color = "text" })
                              ic:label(name, { variant = "caption", color = "muted", align = "center" })
                          end)
                      end
                  end)
              end)
          end)
          c:box({ direction = "row", gap = 12, h = 120, align = "center" }, function(r)
              r:image({ src = ph2, w = 160, h = 120, fit = "cover", radius = "small" })
              r:image({ src = ph3, w = 160, h = 120, fit = "contain", bg = "surface2", radius = "small" })
              r:image({ src = ph4, w = 160, h = 120, fit = "center", bg = "surface2", radius = "small" })
              r:image({ src = "assets/不存在.png", w = 160, h = 120, radius = "small" }) -- 加载失败占位
          end)
          c:carousel({ images = { ph1, ph2, ph3, ph4 }, h = 220, radius = "large", auto = 2.5,
              onChange = function(i) print("[carousel] 切换到第 " .. i .. " 张") end })

          -- 性能
          c:divider({ text = "性能 Performance（可视行虚拟化 / 裁剪剔除 / 子树缓存）" })
          -- 2000 行表格：仅绘制可视区行
          local bigRows = {}
          for i = 1, 2000 do
              bigRows[i] = { "条目 #" .. i, "虚拟化渲染——仅绘制可视行", i % 7 == 0 and "通过" or "待定" }
          end
          c:table({
              h = 190,
              columns = {
                  { label = "名称", width = 150 },
                  { label = "说明" },
                  { label = "状态", width = 70 },
              },
              rows = bigRows,
              onRowClick = function(i, row) feedback("第 " .. i .. " 行: " .. row[1]) end,
          })
          c:label("上表 2000 行数据，滚动流畅（F2 打开调试面板查看 FPS 与节点数）", { variant = "caption", color = "muted" })
          -- 子树缓存：静态面板整棵渲染进 Canvas，每帧直接贴图
          c:box({ direction = "row", gap = 12 }, function(row)
              row:box({ cache = true, grow = 1, bg = "surface", radius = "medium", padding = 14, direction = "column", gap = 8, border = "border" }, function(p)
                  p:label("静态面板 cache = true", { variant = "h3" })
                  p:label("整棵子树渲染到 Canvas，每帧直接贴图。", { color = "muted" })
                  p:box({ direction = "row", gap = 10 }, function(ic)
                      ic:icon("heart", { size = 20, color = "primary" })
                      ic:icon("star", { size = 20, color = "warning" })
                      ic:icon("check", { size = 20, color = "success" })
                      ic:icon("info", { size = 20, color = "muted" })
                  end)
              end)
              row:box({ grow = 1, bg = "surface", radius = "medium", padding = 14, direction = "column", gap = 8, border = "border" }, function(p)
                  p:label("动态面板（对照）", { variant = "h3" })
                  p:label("每帧重绘全部内容；滚动出视口的节点被快速剔除。", { color = "muted" })
                  p:box({ direction = "row", gap = 10 }, function(ic)
                      ic:icon("play", { size = 20, color = "primary" })
                      ic:icon("pause", { size = 20, color = "muted" })
                      ic:icon("refresh", { size = 20, color = "success" })
                      ic:icon("download", { size = 20, color = "warning" })
                  end)
              end)
          end)

          -- 自定义控件
          c:divider({ text = "自定义控件 Custom Widget" })
          c:box({ direction = "row", gap = 16, align = "center" }, function(r)
              r:label("评分：", { variant = "body" })
              r:rating({ max = 5, value = 3, onChanged = function(v) feedback("评分 " .. v) end })
          end)

          -- 下拉与标签页
          c:divider({ text = "下拉与标签页 Dropdown / Tabs" })
          c:box({ direction = "row", gap = 16 }, function(r)
              r:box({ grow = 1, direction = "column", gap = 8 }, function(x)
                  x:label("选择一个平台", { variant = "caption", color = "muted" })
                  x:dropdown({
                      items = { "Windows", "macOS", "Linux", "Android", "iOS", "Web", "其他" },
                      value = "Windows",
                      onChanged = function(v) feedback("选择: " .. v) end,
                  })
              end)
              r:box({ grow = 1 })
          end)
          c:tabs({ tabs = { "概览", "详情", "设置" }, active = 1, onChanged = function(i) print("[tabs] 切换到第 " .. i .. " 页") end }, function(t)
              t:box({ padding = 16, bg = "surface", radius = "large", direction = "column", gap = 8 }, function(x)
                  x:label("概览内容", { variant = "subtitle" })
                  x:label("这是第一个标签页的内容。", { color = "muted" })
              end)
              t:box({ padding = 16, bg = "surface", radius = "large", direction = "column", gap = 8 }, function(x)
                  x:label("详情内容", { variant = "subtitle" })
                  x:label("这是第二个标签页的内容。", { color = "muted" })
              end)
              t:box({ padding = 16, bg = "surface", radius = "large", direction = "column", gap = 8 }, function(x)
                  x:label("设置内容", { variant = "subtitle" })
                  x:label("这是第三个标签页的内容。", { color = "muted" })
              end)
          end)

          -- 表格
          c:divider({ text = "表格 Table" })
          c:table({
              h = 220,
              columns = {
                  { label = "姓名", width = 160 },
                  { label = "部门" },
                  { label = "职位" },
                  { label = "状态" },
              },
              rows = {
                  { "张伟", "研发部", "工程师", "在职" },
                  { "李娜", "设计部", "设计师", "在职" },
                  { "王强", "市场部", "经理", "休假" },
                  { "赵敏", "产品部", "产品经理", "在职" },
                  { "陈杰", "研发部", "实习生", "试用" },
                  { "刘洋", "运营部", "运营专员", "在职" },
              },
              onRowClick = function(i, row) feedback("第 " .. i .. " 行: " .. row[1]) end,
          })

          -- 树
          c:divider({ text = "树 Tree" })
          c:tree({
              h = 200,
              items = {
                  { label = "项目文件", children = {
                      { label = "src", children = { { label = "main.lua" }, { label = "config.lua" } } },
                      { label = "assets" },
                  } },
                  { label = "文档", children = { { label = "README.md" }, { label = "CHANGELOG.md" } } },
                  { label = "README.md" },
              },
              onSelect = function(item) feedback("选中: " .. (item.label or "")) end,
          })

          -- 反馈
          c:divider({ text = "反馈 Dialog / Toast" })
          c:box({ direction = "row", gap = 12 }, function(r)
              r:button("打开弹窗", { variant = "filled", onClick = function()
                  ui:dialog({ title = "关于 LumiUI" }, function(p)
                      p:label("这是一个模态弹窗，点击遮罩或按钮关闭。", { wrap = true })
                      p:box({ direction = "row", gap = 8, justify = "end" }, function(x)
                          x:button("取消", { variant = "text", onClick = function() ui:closeAllOverlays() end })
                          x:button("确定", { variant = "filled", onClick = function() ui:closeAllOverlays(); feedback("已确认") end })
                      end)
                  end)
              end })
              r:button("显示 Toast", { variant = "tonal", onClick = function() feedback("这是一条 Toast 通知") end })
              r:button("切换主题", { variant = "outlined", onClick = function()
                  local mode = lumi.theme.current.mode
                  ui:setTheme(mode == "dark" and "light" or "dark")
                  feedback("已切换到" .. (mode == "dark" and "浅色" or "深色") .. "主题")
              end })
              r:button("自定义主题", { variant = "outlined", onClick = function()
                  lumi.theme.custom("dark", { colors = { primary = "#FF7A45" }, shape = { medium = 12 } })
                  feedback("已应用自定义橙色主题")
              end })
              r:button("恢复默认", { variant = "text", onClick = function()
                  ui:setTheme("dark")
                  feedback("已恢复默认深色主题")
              end })
          end)

      end)

    -- 无头自检：构建 + 数帧更新/绘制 + 弹窗/命中测试
    local verifyMode = (love.filesystem.getInfo("verify.flag") ~= nil)
        or (os.getenv("LUMI_VERIFY") == "1")
    if verifyMode then
        ui:update(1 / 60)
        ui:draw()
        ui:dialog({ title = "自检弹窗" }, function(p)
            p:label("自检内容")
            p:button("确定")
        end)
        ui:update(1 / 60)
        ui:draw()
        ui:mousepressed(10, 10, 1)
        ui:mousereleased(10, 10, 1)
        ui:update(1 / 60)
        ui:draw()
        -- 中文输入 UTF-8 回归测试：左移/退格/插入/绘制不得出现解码错误
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
        -- 输入法组合态（textedited）也应能正常绘制并带下划线
        ti:textedited("nihao", 6, 0)
        ti:draw()
        ti:textinput("好", nil)
        ti:draw()
        -- 选区 + 剪贴板测试
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
        -- 换行文本（wrap）回归测试
        local Label = require("lumi.widgets.label")
        local wl = Label.new({ text = "这是一个会换行的长文本测试内容", wrap = true })
        wl:measure(120, nil)
        wl:arrange(0, 0, 120, 60)
        wl:draw()
        -- 文本输入区域 API（输入法候选窗定位）可用性检查
        love.keyboard.setTextInput(true, 0, 0, 100, 30)
        love.keyboard.setTextInput(false)
        -- 新增布局特性：百分比尺寸 / z-index / flex-wrap
        local Box = require("lumi.widgets.box")
        local wrapRoot = Box.new({ direction = "row", wrap = true, gap = 8, w = 300 })
        for i = 1, 6 do
            wrapRoot:addChild(Box.new({ w = "30%", h = 30, bg = "surface2", radius = "small" }))
        end
        wrapRoot:arrange(0, 0, 300, 200)
        wrapRoot:draw()
        local zRoot = Box.new({ direction = "row", w = 200, h = 40 })
        zRoot:addChild(Box.new({ w = "50%", bg = "surface", z = 0 }))
        zRoot:addChild(Box.new({ w = "50%", bg = "primary", z = 10 }))
        zRoot:arrange(0, 0, 200, 40)
        zRoot:draw()
        -- 主题定制 API 测试
        lumi.theme.custom("light", { colors = { primary = "#00AA88" }, shape = { medium = 12 } })
        lumi.theme.apply(lumi.theme.build("dark"))
        -- 调试工具测试
        lumi.debug.update(1 / 60)
        lumi.debug.toggle()
        lumi.debug.draw(ui)
        lumi.debug.toggle()
        -- 运行全部控件功能测试套件
        local failed = require("tests.run").run()
        verifyExitCode = (failed > 0) and 1 or 0
        verifyQuit = true
    end
end

function love.update(dt)
    ui:update(dt)
    lumi.debug.update(dt)
    if verifyQuit then love.event.quit(verifyExitCode) end
end

function love.draw()
    ui:draw()
    lumi.debug.draw(ui)
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
    ui:wheelmoved(x, y)
end

function love.keypressed(k)
    if k == "f2" then
        lumi.debug.toggle()
        return
    end
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
