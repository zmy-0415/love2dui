--[[
    examples/data.lua —— 数据展示

    2000 行表格（可视行虚拟化）、树、图片轮播、图片适配模式与头像角标。

    运行：love . data
]]

local lumi = require("lumi")

local M = { title = "数据展示" }

function M.build(ui, ctx)
    local ph = lumi.image.placeholder
    local cover = ph("data-cover", 640, 360, { 0.16, 0.32, 0.72 }, { 0.42, 0.22, 0.68 }, "cover")
    local wide = ph("data-wide", 640, 360, { 0.72, 0.36, 0.16 }, { 0.85, 0.62, 0.20 }, "contain")
    local tall = ph("data-tall", 640, 360, { 0.13, 0.55, 0.42 }, { 0.36, 0.68, 0.30 }, "center")
    local alt = ph("data-alt", 640, 360, { 0.62, 0.18, 0.36 }, { 0.86, 0.40, 0.30 }, "480×288")

    ui:root({ direction = "column" })
      :scroll({ grow = 1, padding = 24, gap = 22, direction = "column" }, function(c)

          c:label("数据展示", { variant = "display", color = "primary" })
          c:label("表格与树都只绘制可视行，2000 行数据的开销与 20 行相同。", { color = "muted" })

          -- 大表格
          c:divider({ text = "表格 Table（2000 行虚拟化）" })
          local rows = {}
          for i = 1, 2000 do
              rows[i] = {
                  "条目 #" .. i,
                  "虚拟化渲染：只构造并绘制可视区内的行",
                  i % 7 == 0 and "通过" or "待定",
              }
          end
          c:table({
              h = 220,
              columns = {
                  { label = "名称", width = 160 },
                  { label = "说明" },
                  { label = "状态", width = 80 },
              },
              rows = rows,
              onRowClick = function(i, row) ctx.feedback(string.format("第 %d 行：%s", i, row[1])) end,
          })

          -- 小表格
          c:divider({ text = "表格 Table（常规数据）" })
          c:table({
              h = 200,
              columns = {
                  { label = "姓名", width = 140 },
                  { label = "部门" },
                  { label = "职位" },
                  { label = "状态", width = 90 },
              },
              rows = {
                  { "张伟", "研发部", "工程师", "在职" },
                  { "李娜", "设计部", "设计师", "在职" },
                  { "王强", "市场部", "经理", "休假" },
                  { "赵敏", "产品部", "产品经理", "在职" },
                  { "陈杰", "研发部", "实习生", "试用" },
                  { "刘洋", "运营部", "运营专员", "在职" },
              },
              onRowClick = function(i, row) ctx.feedback(string.format("第 %d 行：%s", i, row[1])) end,
          })

          -- 树
          c:divider({ text = "树 Tree" })
          c:tree({
              h = 230,
              items = {
                  { label = "项目文件", children = {
                      { label = "src", children = {
                          { label = "main.lua" },
                          { label = "config.lua" },
                          { label = "lumi/", children = {
                              { label = "context.lua" },
                              { label = "layout.lua" },
                              { label = "draw.lua" },
                          } },
                      } },
                      { label = "assets" },
                      { label = "README.md" },
                  } },
                  { label = "文档", children = {
                      { label = "guide.md" },
                      { label = "custom-widget.md" },
                  } },
                  { label = "CHANGELOG.md" },
              },
              onSelect = function(item) ctx.feedback("选中：" .. (item.label or "")) end,
          })

          -- 轮播
          c:divider({ text = "图片轮播 Carousel" })
          c:carousel({
              images = { cover, wide, tall, alt },
              h = 240,
              radius = "large",
              auto = 3,
              onChange = function(i) print("[data] 轮播到第 " .. i .. " 张") end,
          })
          c:label("支持拖拽切页（边界阻尼回弹）、箭头与指示点点击", { variant = "caption", color = "muted" })

          -- 图片适配
          c:divider({ text = "图片适配 fit = cover / contain / center" })
          c:box({ direction = "row", gap = 12, h = 130 }, function(r)
              r:image({ src = wide, w = 180, h = 130, fit = "cover", radius = "small" })
              r:image({ src = tall, w = 180, h = 130, fit = "contain", bg = "surface2", radius = "small" })
              r:image({ src = alt, w = 180, h = 130, fit = "center", bg = "surface2", radius = "small" })
              r:image({ src = "assets/不存在.png", w = 180, h = 130, radius = "small" })
          end)
          c:label("最后一张故意给了不存在的路径，用来展示加载失败占位。", { variant = "caption", color = "muted" })

          -- 头像
          c:divider({ text = "头像 Avatar（图片 / 文字回退 / 角标）" })
          c:box({ direction = "row", gap = 12, align = "center" }, function(a)
              a:avatar({ src = wide, size = 48, onClick = function() ctx.feedback("点击头像") end })
              a:avatar({ text = "lumi", size = 48 })
              a:avatar({ text = "张伟", size = 48, color = "success" })
              a:avatar({ src = tall, size = 48, badge = 3 })
              a:avatar({ text = "M", size = 48, badge = true })
              a:avatar({ text = "橙", size = 48, badge = 128 })
          end)

      end)
end

return M
