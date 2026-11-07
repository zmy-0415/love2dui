--[[
    examples/theme.lua —— 主题与视觉定制

    演示 theme.set / theme.custom / theme.apply 三种用法：
    theme.custom 会立即生效，之后调用 ui:invalidateLayout() 让布局按新字号与新圆角重排。

    运行：love . theme
    提示：F1 也可以在深色/浅色之间快速切换。
]]

local lumi = require("lumi")

local M = { title = "主题定制" }

local function swatch(label, color)
    return { label = label, color = color }
end

local PALETTE = {
    swatch("primary", "primary"),
    swatch("secondary", "secondary"),
    swatch("surface", "surface"),
    swatch("surface2", "surface2"),
    swatch("success", "success"),
    swatch("warning", "warning"),
    swatch("error", "error"),
    swatch("border", "border"),
}

local function apply(ui, fn, tip)
    fn()
    -- 主题会改变字号与圆角，必须让布局按新 token 重新测量
    ui:invalidateLayout()
    if tip then ui:toast(tip) end
end

function M.build(ui, ctx)
    local function reset()
        lumi.theme.set("dark")
    end

    ui:root({ direction = "column" })
      :scroll({ grow = 1, padding = 24, gap = 22, direction = "column" }, function(c)

          c:label("主题定制", { variant = "display", color = "primary" })
          c:label("所有控件都从 theme.current 取色与取字号，切换主题即刻生效。", { color = "muted" })

          -- 预设
          c:divider({ text = "预设与自定义" })
          c:box({ direction = "row", gap = 10, wrap = true }, function(r)
              r:button("深色", { variant = "filled", onClick = function()
                  apply(ui, function() ui:setTheme("dark") end, "已切换到深色主题")
              end })
              r:button("浅色", { variant = "tonal", onClick = function()
                  apply(ui, function() ui:setTheme("light") end, "已切换到浅色主题")
              end })
              r:button("橙色主色", { variant = "outlined", onClick = function()
                  apply(ui, function()
                      lumi.theme.custom(lumi.theme.current.mode, { colors = { primary = "#FF7A45" } })
                  end, "主色 → 橙色")
              end })
              r:button("绿色主色", { variant = "outlined", onClick = function()
                  apply(ui, function()
                      lumi.theme.custom(lumi.theme.current.mode, { colors = { primary = "#00A86B" } })
                  end, "主色 → 绿色")
              end })
              r:button("圆角 0", { variant = "outlined", onClick = function()
                  apply(ui, function()
                      lumi.theme.custom(lumi.theme.current.mode, { shape = { small = 0, medium = 0, large = 0 } })
                  end, "已关闭圆角")
              end })
              r:button("大圆角", { variant = "outlined", onClick = function()
                  apply(ui, function()
                      lumi.theme.custom(lumi.theme.current.mode, { shape = { small = 8, medium = 16, large = 24 } })
                  end, "已放大圆角")
              end })
              r:button("紧凑排版", { variant = "outlined", onClick = function()
                  apply(ui, function()
                      lumi.theme.custom(lumi.theme.current.mode, {
                          control = { height = 32, padX = 12, padY = 6 },
                          font = { body = 13, caption = 11 },
                      })
                  end, "控件高度 40 → 32")
              end })
              r:button("恢复默认", { variant = "text", onClick = function()
                  apply(ui, reset, "已恢复默认深色主题")
              end })
          end)

          -- 色板
          c:divider({ text = "当前色板" })
          c:box({ display = "grid", cols = 4, gap = 12 }, function(g)
              for _, item in ipairs(PALETTE) do
                  g:box({ direction = "column", gap = 8, padding = 12, bg = "surface2", radius = "medium" }, function(sw)
                      sw:box({ h = 44, bg = item.color, radius = "small", border = "border" })
                      sw:label(item.label, { variant = "caption", color = "muted" })
                  end)
              end
          end)

          -- 字号阶梯
          c:divider({ text = "字号阶梯（来自 theme.font）" })
          c:box({ direction = "column", gap = 8, bg = "surface", radius = "medium", padding = 16, border = "border" }, function(x)
              x:label("Display 32 —— 页面主标题", { variant = "display" })
              x:label("Headline 24 —— 区块标题", { variant = "headline" })
              x:label("Title 18 —— 卡片标题", { variant = "title" })
              x:label("Subtitle 16 —— 次级标题", { variant = "subtitle" })
              x:label("Body 14 —— 正文内容，控件默认字号", { variant = "body" })
              x:label("Caption 12 —— 辅助说明与标签", { variant = "caption", color = "muted" })
          end)

          -- 组件对照
          c:divider({ text = "组件对照" })
          c:box({ direction = "row", gap = 14, wrap = true, align = "center" }, function(r)
              r:button("Filled", { variant = "filled" })
              r:button("Tonal", { variant = "tonal" })
              r:button("Outlined", { variant = "outlined" })
              r:button("Text", { variant = "text" })
              r:switch({ label = "开关", checked = true })
              r:checkbox({ label = "复选框", checked = true })
              r:avatar({ text = "AB", size = 40 })
          end)
          c:box({ direction = "row", gap = 14 }, function(r)
              r:box({ grow = 1, direction = "column", gap = 10, bg = "surface", radius = "large", padding = 16, border = "border" }, function(x)
                  x:label("卡片标题", { variant = "title" })
                  x:label("卡片正文用来观察表面的层级与边框配色。", { color = "muted", wrap = true })
                  x:progress({ value = 0.6 })
              end)
              r:box({ grow = 1, direction = "column", gap = 10, bg = "surface2", radius = "large", padding = 16 }, function(x)
                  x:label("次级表面", { variant = "title" })
                  x:label("surface2 常用于分区背景。", { color = "muted", wrap = true })
                  x:slider({ min = 0, max = 100, value = 45 })
              end)
          end)

          c:label("主题对象结构：theme.current = { mode, colors, shape, font, motion, control }",
              { variant = "caption", color = "muted" })

      end)
end

return M
