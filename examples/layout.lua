--[[
    examples/layout.lua —— 布局系统

    覆盖 Flexbox（行列、gap、grow、百分比、对齐、换行）、Grid（跨行跨列）、
    绝对定位（position + anchor）与响应式断点（hideBelow / hideAbove）。

    运行：love . layout
    提示：拖动窗口宽度观察响应式色块与换行行为。
]]

local M = { title = "布局系统" }

function M.build(ui)
    ui:root({ direction = "column" })
      :scroll({ grow = 1, padding = 24, gap = 22, direction = "column" }, function(c)

          c:label("布局系统", { variant = "display", color = "primary" })
          c:label("Flex 为主，Grid 与绝对定位作为补充；所有尺寸都可百分比化。", { color = "muted" })

          -- Flex 方向
          c:divider({ text = "Flex 方向与间距" })
          c:box({ direction = "row", gap = 10 }, function(r)
              for i = 1, 4 do
                  r:box({ grow = 1, h = 56, bg = "primary", radius = "medium", align = "center", justify = "center" }, function(b)
                      b:label("row " .. i, { color = "onPrimary", variant = "caption" })
                  end)
              end
          end)
          c:box({ direction = "column", gap = 8 }, function(col)
              for i = 1, 3 do
                  col:box({ h = 34, bg = "surface2", radius = "small", padding = { x = 12 }, align = "center" }, function(b)
                      b:label("column " .. i, { variant = "caption", color = "muted" })
                  end)
              end
          end)

          -- grow 与百分比
          c:divider({ text = "grow 与百分比宽度" })
          c:box({ direction = "row", gap = 10, h = 52 }, function(r)
              r:box({ w = 120, bg = "surface2", radius = "small", align = "center", justify = "center" }, function(b)
                  b:label("120px", { variant = "caption" })
              end)
              r:box({ grow = 1, bg = "primary", radius = "small", align = "center", justify = "center" }, function(b)
                  b:label("grow = 1", { variant = "caption", color = "onPrimary" })
              end)
              r:box({ grow = 2, bg = "success", radius = "small", align = "center", justify = "center" }, function(b)
                  b:label("grow = 2", { variant = "caption", color = "onPrimary" })
              end)
          end)
          c:box({ direction = "row", gap = 10, h = 44 }, function(r)
              r:box({ w = "25%", bg = "surface2", radius = "small", align = "center", justify = "center" }, function(b)
                  b:label("25%", { variant = "caption" })
              end)
              r:box({ w = "50%", bg = "surface2", radius = "small", align = "center", justify = "center" }, function(b)
                  b:label("50%", { variant = "caption" })
              end)
              r:box({ w = "25%", bg = "surface2", radius = "small", align = "center", justify = "center" }, function(b)
                  b:label("25%", { variant = "caption" })
              end)
          end)

          -- 对齐
          c:divider({ text = "对齐 align / justify" })
          c:box({ direction = "row", gap = 10, h = 96, bg = "surface2", radius = "medium", padding = 12 }, function(r)
              r:box({ w = 60, h = 28, bg = "primary", radius = "small" })
              r:box({ w = 60, h = 52, bg = "success", radius = "small" })
              r:box({ w = 60, h = 40, bg = "warning", radius = "small" })
              r:box({ w = 60, h = 72, bg = "error", radius = "small" })
          end)
          c:box({ direction = "row", gap = 10, h = 56, bg = "surface2", radius = "medium", padding = 12, align = "center" }, function(r)
              r:label("align = center 让不同高度的子节点垂直居中", { variant = "caption", color = "muted" })
          end)
          c:box({ direction = "row", gap = 10, h = 56, bg = "surface2", radius = "medium", padding = 12, justify = "end", align = "center" }, function(r)
              r:label("justify = end 靠右", { variant = "caption", color = "muted" })
              r:button("按钮", { variant = "outlined" })
          end)

          -- 换行
          c:divider({ text = "换行 wrap" })
          c:box({ direction = "row", gap = 8, wrap = true, bg = "surface2", radius = "medium", padding = 12 }, function(w)
              for i = 1, 12 do
                  w:box({ w = 74, h = 34, bg = "surface", radius = "small", align = "center", justify = "center" }, function(b)
                      b:label("项 " .. i, { variant = "caption", color = "muted" })
                  end)
              end
          end)

          -- Grid
          c:divider({ text = "Grid 等分与跨行跨列" })
          c:box({ display = "grid", cols = 4, gap = 10 }, function(g)
              for i = 1, 8 do
                  g:box({ h = 48, bg = "surface2", radius = "small", align = "center", justify = "center" }, function(b)
                      b:label(tostring(i), { variant = "caption", color = "muted" })
                  end)
              end
          end)
          c:box({ display = "grid", cols = 3, gap = 10, h = 132 }, function(g)
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

          -- 绝对定位
          c:divider({ text = "绝对定位 position / anchor" })
          c:box({ h = 116, bg = "surface2", radius = "medium", padding = 16, clipChildren = true, direction = "column", gap = 6 }, function(rel)
              rel:label("绝对定位不占布局流", { variant = "title" })
              rel:label("右下角悬浮按钮、右上角角标、左下角状态点都固定在容器四角", { color = "muted" })
              rel:box({ position = { x = 12, y = 12, anchor = "top-right" }, bg = "error", radius = 999, padding = { x = 8, y = 2 } }, function(bdg)
                  bdg:label("NEW", { variant = "caption", color = "onPrimary" })
              end)
              rel:box({ position = { x = 12, y = 12, anchor = "bottom-right" }, bg = "primary", radius = 999, w = 36, h = 36, align = "center", justify = "center" }, function(fb)
                  fb:icon("close", { size = 16, color = "onPrimary" })
              end)
              rel:box({ position = { x = 12, y = 12, anchor = "bottom-left" }, bg = "success", radius = 999, w = 36, h = 36, align = "center", justify = "center" }, function(fb)
                  fb:icon("check", { size = 16, color = "onPrimary" })
              end)
          end)

          -- 响应式
          c:divider({ text = "响应式断点 hideBelow / hideAbove" })
          c:box({ direction = "row", gap = 10 }, function(r)
              r:box({ grow = 1, h = 48, bg = "primary", radius = "medium", align = "center", justify = "center", hideBelow = 900 }, function(b)
                  b:label("宽度 ≥ 900 时可见", { color = "onPrimary" })
              end)
              r:box({ grow = 1, h = 48, bg = "success", radius = "medium", align = "center", justify = "center", hideAbove = 900 }, function(b)
                  b:label("宽度 < 900 时可见", { color = "onPrimary" })
              end)
          end)
          c:label("拖动窗口宽度，观察上方两个色块互相替换。", { variant = "caption", color = "muted" })

      end)
end

return M
