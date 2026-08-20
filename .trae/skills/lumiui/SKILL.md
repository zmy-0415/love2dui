---
name: lumiui
description: "Build LÖVE (Love2D) UI with LumiUI, the retained-mode Material Design framework in lumi/. Invoke when writing Love2D GUI code, composing widgets via ui:root(), or modifying the LumiUI framework."
---

# LumiUI 开发指南

LÖVE (Love2D) 保留模式 Material Design UI 框架。声明式链式构建 + Flexbox/Grid 布局，内置 24 个控件、深/浅主题、补间动画、中文 IME 支持。

## 库位置与参考资料（本仓库内）

| 资源 | 路径 |
|---|---|
| 框架源码 | `lumi/`（入口 `lumi/init.lua`，控件 `lumi/widgets/`） |
| 完整 API 文档 | `lumi/docs/guide.md`（属性表以它为准） |
| 自定义控件规范 | `lumi/docs/custom-widget.md` |
| 全控件演示 | `main.lua` |
| 测试套件 | `tests/run.lua`（无头自检，133 断言） |

写代码前若不确定某控件完整属性，先查 guide.md 对应章节，不要凭空编造 prop。

## 最小应用模板

```lua
local lumi = require("lumi")
local ui

function love.load()
    ui = lumi.new()
    ui:root({ direction = "column", padding = 20, gap = 12 }, function(c)
        c:label("标题", { variant = "title" })
        c:button("点击", { onClick = function() ui:toast("clicked") end })
    end)
end

function love.update(dt) ui:update(dt) end
function love.draw() ui:draw() end
function love.mousepressed(x, y, b) ui:mousepressed(x, y, b) end
function love.mousereleased(x, y, b) ui:mousereleased(x, y, b) end
function love.mousemoved(x, y) ui:mousemoved(x, y) end
function love.wheelmoved(x, y) ui:wheelmoved(x, y) end
function love.keypressed(k) ui:keypressed(k) end
function love.textinput(t) ui:textinput(t) end
function love.textedited(t, s, l) ui:textedited(t, s, l) end   -- IME 必须
function love.resize(w, h) ui:resize(w, h) end
```

**所有 love 回调都必须转发**（漏 `textedited` 则中文输入法候选失效）。F2 调试面板需在 keypressed 中拦截：

```lua
function love.keypressed(k)
    if k == "f2" then lumi.debug.toggle(); return end
    ui:keypressed(k)
end
```

## 构建器规则（游标机制）

- `ui:xxx(props)` 把控件挂到当前游标容器下
- **容器控件**（box/scroll/tabs/dialog）挂载后游标进入容器；**叶子控件**（button/label/input）挂载后游标不动
- 推荐 childrenFn 形式（作用域清晰，结束自动恢复游标）：

```lua
ui:root({ direction = "row" }, function(r)
    r:box({ direction = "column" }, function(c)
        c:label("A")
    end)
    r:button("C")
end)
```

- `ui:up()` 手动游标上移一级；漏写时子节点会挂错父容器

## 控件速查

| 方法 | 关键 props | 回调 |
|---|---|---|
| `box` / `panel` | `bg` `elevation` `border` `radius` `padding` `cache` | — |
| `scroll` | `grow` `padding` `gap` `direction` | — |
| `label("文本")` | `variant`(caption/body/subtitle/title/headline/display) `color` `align` `wrap` `ellipsis` | — |
| `button("文本")` | `variant`(filled/tonal/outlined/text) `color` `textColor` `align` `height` | `onClick` |
| `input` | `text` `label` `placeholder` `password` | `onChange(text)` `onSubmit(text)` |
| `editor` | `text` `lineNumbers` `minLines/maxLines` `highlight(lineText,lineIdx)→segs` | `onChange(text)` |
| `checkbox` / `switch` | `checked` `label` `color` | `onChanged(bool)` |
| `radio` | `checked` `label` `group`(同名互斥，须同父容器) | `onChanged(bool)` |
| `slider` | `min` `max` `value` `step` `showValue` | `onChanged(v)` |
| `progress` | `mode`(linear/circular) `value` `max` `color` `thickness` `size` | — |
| `dropdown` | `items`(字符串或{label=,value=}) `value` `placeholder` | `onChanged(v)` |
| `tabs` | `tabs`(字符串数组) `active`；子节点依次为各页内容 | `onChanged(i)` |
| `table` | `columns`({label=,width=}或字符串) `rows`(二维数组) `selected` `h` | `onRowClick(i,row)` |
| `tree` | `items`({label=,children=}) `h` | `onSelect(item)` |
| `menu` | `items`({label=,items={...}}，{divider=true} 分隔) | 项内 `onClick` |
| `divider` | `text` `direction` | — |
| `image` | `src`(路径/Image/Canvas/function) `fit`(contain/cover/stretch/center) `radius` `tint` | `onClick` |
| `avatar` | `src` `text`(无图回退取首字符) `size` `badge`(true 或数字) | `onClick` |
| `icon("名称")` | `size` `color`；内置 30+：home user settings search close check plus minus heart star trash edit play pause folder file image download upload refresh menu warning info mail lock calendar more arrow-*/chevron-* | — |
| `carousel` | `images` `h` `fit` `auto`(秒或 true) `arrows` `dots` `radius`；支持拖拽切页 | `onChange(i)` |

图片源可用 `lumi.image.placeholder(key, w, h, c1, c2, "水印")` 生成渐变占位 Canvas。

## 通用 Props（所有控件）

- 尺寸：`w`/`h`（数值或 `"50%"`）、`minW/maxW/minH/maxH`、`grow`（flex 权重）、`alignSelf`
- 外观：`bg`、`elevation`(1~5)、`border`、`radius`(数值或 small/medium/large/pill)、`color`、`padding`/`margin`（数值或 `{x=,y=}` 或 `{top,right,bottom,left}`）、`z`、`visible`
- 状态：`disabled`、`tooltip`
- 颜色写法：色名（"primary"）或 `{r,g,b[,a]}`（0~1 浮点）

## 布局（lumi/layout.lua，简化 Flexbox）

- 容器：`direction`(row/column)、`gap`、`align`(start/center/end/stretch)、`justify`(start/center/end/between)、`wrap`
- Grid：`display="grid"`、`cols`、`colSpan`、`rowSpan`
- 绝对定位：`position = { x=, y=, anchor="top-left/top-right/bottom-left/bottom-right" }`（不占布局流，x/y 支持百分比）
- 响应式：`hideBelow = 700` / `hideAbove = 700`（窗口宽度断点，隐藏时不占空间不响应命中）

## 场景级 API

```lua
ui:setTheme("dark")            -- 或 "light"
ui:dialog({ title=, w=, closable=, dismissible= }, childrenFn)  -- 模态弹窗
ui:toast(msg, "info"/"success"/"error")   -- 类型图标 + 色条
ui:closeTopOverlay() / ui:closeAllOverlays()
ui:setFocus(node)              -- nil 取消焦点
ui:invalidateLayout()          -- 动态增删节点后必须调用
lumi.register(name, ctor, "text"/"props"/"container")  -- 注册自定义控件
```

ESC 关闭顶层悬浮层、Tab 循环聚焦由框架自动处理。

## 主题与动画

```lua
-- 自定义主题（覆盖部分 token）
lumi.theme.custom("dark", { colors = { primary = "#FF7A45" }, shape = { medium = 12 } })

-- 颜色 token：background/surface/surface2/border/primary/primaryDim/onPrimary/text/muted/error/success/warning/overlay
-- 其他 token：lumi.theme.shape / font / motion{fast,normal,slow} / control

-- 补间动画（数值与颜色表插值；由 ui:update 自动推进）
lumi.animate.to(node, { x = 300 }, { duration = 0.3, easing = "cubic", onDone = fn })
lumi.animate.stop(node, "x")    -- 第二参可选，仅停某属性
lumi.animate.finish(node)       -- 立即完成
-- easing：linear quad cubic quart quint sine expo circ back elastic bounce，可加 In/Out/InOut 后缀，默认 Out
```

## 自定义控件

```lua
local Widget = require("lumi.widget")
local My = setmetatable({}, { __index = Widget })
My.__index = My

function My.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, My)
    return self
end

function My:measureContent(availW, availH) return 120, 24 end  -- 叶子必须
function My:drawContent() end                                   -- 在 self.x/y/w/h 内绘制
function My:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    self:emit("onChanged", v)      -- 触发用户回调
end

lumi.register("my", My.new, "props")   -- 之后 ui:my({...}) 使用
```

- 容器控件：`self.acceptsChildren = true`；需滚轮不冒泡时 `self.isScroll = true`
- 内容变化后调 `self:invalidate()`；`self.state` 含 hovered/pressed/focused/disabled（框架维护）
- 生命周期：`measureContent` / `arrange` / `drawContent` / `drawBackground` / `isFocusable` / 鼠标键盘钩子，详见 `lumi/docs/custom-widget.md`

## 性能 / 调试 / 测试

- **子树缓存**：静态容器 `cache = true` 整棵渲染进 Canvas。仅用于静态内容（hover/波纹/动画会冻结）
- **虚拟化**：table/tree 自动只绘可视行，2000 行如 20 行，无需处理
- **裁剪剔除**：滚动容器外内容自动跳过绘制
- **调试**：F2（布局外框 + 控件树 + FPS），`lumi.debug.toggle/update/draw`
- **测试**：创建 `verify.flag` 文件或 `LUMI_VERIFY=1` 后运行 `love .` 自动跑 `tests/run.lua` 并以退出码报告；或直接执行 `test.bat`

## 常见坑

1. 漏转发 `love.textedited` → 中文 IME 候选窗不显示
2. 动态增删节点后未调 `ui:invalidateLayout()` → 布局不更新
3. `onChange`（input/editor 文本）与 `onChanged`（checkbox/slider/dropdown/tabs 值）命名不同，别混用
4. radio 互斥要求同 `group` 且在同一父容器下
5. `cache = true` 用在含交互反馈的子树上会冻结动效
6. carousel/image 若不显式给尺寸，记得用 `grow` 或 `w/h`，默认尺寸很小
7. editor 语法高亮的 `from/to` 是 **0-based 半开字节偏移**（`string.find` 结果需 `-1` 换算），UTF-8 中文占多字节
