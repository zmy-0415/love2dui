--[[
    examples/forms.lua —— 表单控件

    按钮变体、输入框（含密码 / 禁用 / 多行）、选择控件、滑块与进度、下拉。
    交互结果通过 ctx.feedback 输出到控制台与 Toast。

    运行：love . forms
]]

local M = { title = "表单控件" }

function M.build(ui, ctx)
    local feedback = ctx.feedback

    ui:root({ direction = "column" })
      :scroll({ grow = 1, padding = 24, gap = 22, direction = "column" }, function(c)

          c:label("表单控件", { variant = "display", color = "primary" })
          c:label("所有控件都支持 Tab 聚焦、回车激活与禁用态。", { color = "muted" })

          -- 按钮
          c:divider({ text = "按钮 Button" })
          c:box({ direction = "row", gap = 12, wrap = true }, function(r)
              r:button("Filled", { variant = "filled", onClick = function() feedback("Filled") end })
              r:button("Tonal", { variant = "tonal", onClick = function() feedback("Tonal") end })
              r:button("Outlined", { variant = "outlined", onClick = function() feedback("Outlined") end })
              r:button("Text", { variant = "text", onClick = function() feedback("Text") end })
              r:button("禁用", { disabled = true })
              r:button("带提示", { tooltip = "悬停 0.5 秒后出现的 Tooltip" })
          end)

          -- 输入框
          c:divider({ text = "输入框 Input" })
          c:box({ direction = "row", gap = 20 }, function(r)
              r:box({ grow = 1, direction = "column", gap = 14 }, function(x)
                  x:input({ label = "用户名", placeholder = "请输入用户名",
                      onChange = function(v) print("[forms] 用户名 = " .. v) end })
                  x:input({ label = "密码", password = true, placeholder = "掩码显示" })
                  x:input({ label = "禁用", placeholder = "不可编辑", disabled = true })
              end)
              r:box({ grow = 1, direction = "column", gap = 14 }, function(x)
                  x:input({ label = "邮箱", placeholder = "name@example.com",
                      onSubmit = function(v) feedback("提交：" .. v) end })
                  x:input({ label = "长文本（横向滚动跟随光标）",
                      text = "这是一段很长很长的内容，用来观察光标跟随时的横向滚动效果" })
                  x:label("Enter 提交；Ctrl+A / C / V 支持全选与剪贴板", { variant = "caption", color = "muted" })
              end)
          end)

          -- 选择控件
          c:divider({ text = "选择控件 Checkbox / Switch / Radio" })
          c:box({ direction = "row", gap = 20 }, function(r)
              r:box({ grow = 1, direction = "column", gap = 12, bg = "surface", radius = "medium", padding = 16, border = "border" }, function(x)
                  x:label("复选框 / 开关", { variant = "title" })
                  x:checkbox({ label = "记住我", checked = true, onChanged = function(v) feedback("记住我 = " .. tostring(v)) end })
                  x:checkbox({ label = "接收通知", onChanged = function(v) feedback("通知 = " .. tostring(v)) end })
                  x:checkbox({ label = "禁用项", disabled = true })
                  x:switch({ label = "深色模式", checked = true, onChanged = function(v) feedback("深色模式 = " .. tostring(v)) end })
                  x:switch({ label = "自动更新", onChanged = function(v) feedback("自动更新 = " .. tostring(v)) end })
              end)
              r:box({ grow = 1, direction = "column", gap = 12, bg = "surface", radius = "medium", padding = 16, border = "border" }, function(x)
                  x:label("单选组", { variant = "title" })
                  x:radio({ label = "Windows", checked = true, group = "os", onChanged = function() feedback("系统：Windows") end })
                  x:radio({ label = "macOS", group = "os", onChanged = function() feedback("系统：macOS") end })
                  x:radio({ label = "Linux", group = "os", onChanged = function() feedback("系统：Linux") end })
                  x:radio({ label = "禁用项", group = "os", disabled = true })
              end)
          end)

          -- 滑块
          c:divider({ text = "滑块 Slider" })
          c:box({ direction = "column", gap = 16, bg = "surface", radius = "medium", padding = 16, border = "border" }, function(x)
              x:slider({ min = 0, max = 100, value = 60, showValue = true,
                  onChanged = function(v) print("[forms] 音量 = " .. v) end })
              x:slider({ min = 0, max = 10, value = 3, step = 1, showValue = true,
                  onChanged = function(v) print("[forms] 档位 = " .. v) end })
              x:label("Tab 聚焦后可用方向键微调（Shift 加大步长）", { variant = "caption", color = "muted" })
          end)

          -- 进度
          c:divider({ text = "进度 Progress" })
          c:box({ direction = "row", gap = 24, align = "center" }, function(r)
              r:box({ grow = 1, direction = "column", gap = 10 }, function(x)
                  x:progress({ value = 0.35 })
                  x:progress({ value = 0.75, color = "success" })
                  x:progress({ value = 0.92, color = "warning" })
              end)
              r:progress({ mode = "circular", value = 0.6, showValue = true, size = 76 })
              r:progress({ mode = "circular", value = 0.25, color = "error", size = 76 })
          end)

          -- 下拉
          c:divider({ text = "下拉 Dropdown" })
          c:box({ direction = "row", gap = 20 }, function(r)
              r:box({ grow = 1, direction = "column", gap = 8 }, function(x)
                  x:label("平台", { variant = "caption", color = "muted" })
                  x:dropdown({
                      items = { "Windows", "macOS", "Linux", "Android", "iOS", "Web", "其他" },
                      value = "Windows",
                      onChanged = function(v) feedback("平台：" .. v) end,
                  })
              end)
              r:box({ grow = 1, direction = "column", gap = 8 }, function(x)
                  x:label("禁用", { variant = "caption", color = "muted" })
                  x:dropdown({ items = { "不可选" }, value = "不可选", disabled = true })
              end)
          end)

          -- 分页
          c:divider({ text = "标签页 Tabs" })
          c:tabs({ tabs = { "账号", "通知", "高级" }, active = 1,
              onChanged = function(i) print("[forms] 第 " .. i .. " 页") end }, function(t)
              t:box({ padding = 16, bg = "surface", radius = "large", direction = "column", gap = 8 }, function(x)
                  x:label("账号设置", { variant = "title" })
                  x:input({ label = "昵称", placeholder = "请输入昵称" })
              end)
              t:box({ padding = 16, bg = "surface", radius = "large", direction = "column", gap = 8 }, function(x)
                  x:label("通知设置", { variant = "title" })
                  x:switch({ label = "邮件提醒", checked = true })
                  x:switch({ label = "桌面推送" })
              end)
              t:box({ padding = 16, bg = "surface", radius = "large", direction = "column", gap = 8 }, function(x)
                  x:label("高级选项", { variant = "title" })
                  x:label("非活动页不参与命中测试，也不会被 Tab 键聚焦。", { color = "muted", wrap = true })
              end)
          end)

      end)
end

return M
