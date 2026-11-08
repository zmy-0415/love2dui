# LumiUI 使用文档

LumiUI 是一个 LÖVE（Love2D）保留模式 Material Design UI 框架，采用声明式组件树 + Flexbox 布局。内置 20+ 控件、两套主题、补间动画、中文输入法（IME）支持与调试工具。

- 运行环境：LÖVE 11.x（Lua 5.1 / LuaJIT）
- 入口：`local lumi = require("lumi")`

---

## 目录

1. [快速开始](#快速开始)
2. [核心概念](#核心概念)
3. [键盘与焦点](#键盘与焦点)
4. [通用 Props](#通用-props)
5. [布局系统](#布局系统)
6. [组件速查](#组件速查)
7. [组件详解](#组件详解)
8. [主题系统](#主题系统)
9. [动画系统](#动画系统)
10. [自定义控件](#自定义控件)
11. [调试工具](#调试工具)
12. [完整案例](#完整案例)

---

## 快速开始

```lua
local lumi = require("lumi")

local ui

function love.load()
    ui = lumi.new()

    ui:root({ direction = "column", padding = 20, gap = 12 })
      :label("你好，LumiUI", { variant = "title" })
      :button("点击我", { variant = "filled", onClick = function() print("clicked") end })
      :input({ placeholder = "输入点什么…", onChange = function(v) print(v) end })
end

function love.update(dt) ui:update(dt) end
function love.draw() ui:draw() end

function love.mousepressed(x, y, b) ui:mousepressed(x, y, b) end
function love.mousereleased(x, y, b) ui:mousereleased(x, y, b) end
function love.mousemoved(x, y) ui:mousemoved(x, y) end
function love.wheelmoved(x, y) ui:wheelmoved(x, y) end
function love.keypressed(k) ui:keypressed(k) end
function love.textinput(t) ui:textinput(t) end
function love.textedited(t, s, l) ui:textedited(t, s, l) end
function love.resize(w, h) ui:resize(w, h) end
```

要点：
- `lumi.new()` 返回一个场景对象 `ui`，所有 UI 都挂在这个场景上。
- 通过 `love.*` 回调把事件转发给 `ui:*` 对应方法。
- `ui:root(props)` 建立根容器，之后链式调用构建组件树。

---

## 核心概念

### 保留模式组件树

UI 是一棵组件树。每个控件继承自 `Widget`（`lumi/widget.lua`）→ `Node`（`lumi/node.lua`），拥有统一的布局、绘制、命中测试与事件钩子。

### 场景构建器（链式调用）

`ui:xxx(props)` 系列方法把控件挂到**当前游标**（`_cursor`）指向的容器下：

| 规则 | 说明 |
|---|---|
| 容器控件（box/scroll/tabs/dialog 等） | `add` 后游标进入该容器，后续子节点挂到它下面 |
| 叶子控件（button/input/label 等） | `add` 后游标不动，留在父容器 |
| `childrenFn` 参数 | 传 `function(c) ... end` 时，临时把游标切到该容器，结束后自动恢复 |
| `ui:up()` | 手动把游标上移一级（退出当前容器） |

```lua
-- 三种写法等价
ui:root({ direction = "row" })
  :box({ direction = "column" })
  :label("A")
  :label("B")
  :up()
  :button("C")
```

```lua
-- 更推荐：childrenFn 形式，作用域清晰
ui:root({ direction = "row" }, function(r)
    r:box({ direction = "column" }, function(c)
        c:label("A")
        c:label("B")
    end)
    r:button("C")
end)
```

### 事件回调

控件通过 `props` 接收回调，命名约定：

| 回调 | 参数 | 常用控件 |
|---|---|---|
| `onClick` | — | button、menu 项 |
| `onChanged` | `checked` / `value` / `index` | checkbox/switch/radio、slider、dropdown、tabs |
| `onChange` | `text` | input、editor |
| `onSubmit` | `text` | input（回车提交） |
| `onRowClick` | `index, row` | table |
| `onSelect` | `item` | tree |

### 场景级操作

| 方法 | 说明 |
|---|---|
| `ui:setTheme("dark"/"light")` | 切换主题（会清空布局缓存并重排） |
| `ui:dialog(props, childrenFn)` | 打开模态弹窗，返回 dialog 节点 |
| `ui:toast("消息")` | 底部弹出提示，2.5 秒后消失 |
| `ui:closeTopOverlay()` / `ui:closeAllOverlays()` | 关闭顶层/全部悬浮层 |
| `ui:setFocus(node)` | 手动设置焦点（`nil` 取消） |
| `ui:focusNext(reverse)` | 把焦点移到下一个/上一个可聚焦控件 |
| `ui:focusScope()` | 当前焦点作用域（有模态时为该模态，否则为根节点） |
| `ui:invalidateLayout()` | 强制全量重排（清空整棵树测量缓存） |
| `ui.layoutStats` | 最近一次重排统计：`{ arranged = N, pruned = M }` |

---

## 键盘与焦点

框架自带一套完整的键盘操作，鼠标能用的事情键盘基本都能做。

### 焦点顺序

- 按绘制顺序遍历可聚焦控件，`Tab` 前进、`Shift+Tab` 后退，首尾循环。
- 可聚焦控件的判定是 `isFocusable()`：按钮、复选框、开关、单选框、滑块、下拉框、标签页、菜单栏，以及输入框/编辑器。
- `disabled = true` 的控件不可聚焦，`visible = false` 或被隐藏的标签页内容会被整棵跳过。
- `Esc`：先关闭最顶层悬浮层（下拉/菜单/弹窗），没有悬浮层时清除焦点。

### 焦点作用域

| 场景 | Tab 行为 |
|---|---|
| 普通页面 | 在根节点子树内循环 |
| 模态弹窗打开 | 只在弹窗内循环，不会跑到被遮住的控件上；打开时焦点自动移入弹窗 |
| 下拉/菜单展开 | 第一次 `Tab` 先收起浮层，再继续导航 |

### 激活与方向键

| 控件 | `Enter` / `Space` | 方向键 |
|---|---|---|
| button | 触发 `onClick` | — |
| checkbox / switch | 切换并触发 `onChanged` | — |
| radio | 选中自己 | 组内上下左右移动选中项与焦点 |
| dropdown | 展开/收起列表 | ↑/↓ 直接改值（原生 `<select>` 行为） |
| tabs | — | ←/↑ 上一页，→/↓ 下一页（循环） |
| menu | 展开/收起第一项菜单 | 展开时 ←/→ 切换同级菜单 |
| slider | — | ←/→ 或 ↑/↓ 按步长调整 |
| input / editor | 回车提交 / 换行（不被激活逻辑吞掉） | 光标移动、Home/End、PageUp/PageDown |

### 焦点环与滚动

- 焦点环只在**键盘**操作得到焦点时绘制；鼠标点出来的焦点不画环（避免点击后一直亮着）。
- `Tab` 到视口外的控件会自动滚动到可见位置（`node:reveal()`，由内向外逐层处理嵌套滚动区）。

### 自定义控件接入键盘

```lua
function MyWidget:isFocusable()
    return not self.state.disabled
end

-- Enter / Space：返回 true 表示按键已消费
function MyWidget:activate(ctx)
    if self.state.disabled then return false end
    self:emit("onClick")
    return true
end

-- 方向键等其余按键
function MyWidget:keypressed(key, ctx)
    if key == "left" then ... end
end
```

绘制焦点环时用 `self.state.focusVisible` 而不是 `self.state.focused`，才能跟鼠标点击区分开。

---

## 通用 Props

以下属性几乎所有控件都可用（由 `Node` 基类统一处理）：

### 尺寸

| Prop | 类型 | 说明 |
|---|---|---|
| `w` / `width` | number 或 `"50%"` 字符串 | 宽。百分比相对父容器可用尺寸 |
| `h` / `height` | number 或百分比 | 高 |
| `minW` / `maxW` | number | 宽上下限 |
| `minH` / `maxH` | number | 高上下限 |
| `grow` | number | flex 剩余空间分配权重（仅容器内子节点有效） |
| `alignSelf` | `"start"/"center"/"end"/"stretch"` | 覆盖父容器的 `align` |

### 外观

| Prop | 类型 | 说明 |
|---|---|---|
| `bg` | 色名或 `{r,g,b}` | 背景填充（自动圆角） |
| `elevation` | number | 阴影层级（1~5），越大越深 |
| `border` | 色名 或 `{color=, width=}` | 描边 |
| `radius` / `rounded` | number 或 `"small"/"medium"/"large"/"pill"` | 圆角 |
| `color` | 色名或 `{r,g,b}` | 主色调（控件各自的含义见下文） |
| `padding` | number / `{x=,y=}` / `{top,right,bottom,left}` | 内边距 |
| `margin` | 同上 | 外边距 |
| `z` | number | 绘制层级，大的在上层 |
| `visible` | boolean | 是否可见（默认 true） |

### 状态

| Prop | 类型 | 说明 |
|---|---|---|
| `disabled` | boolean | 禁用（不可交互、显示禁用态） |
| `tooltip` | string | 悬停 0.5 秒后显示提示气泡 |

### 运行时修改属性

属性变化要用 `setProps` / `setProp`，不要直接写 `node.props.xxx` —— 直接改属性不会：
清空布局/绘制缓存、同步 `visible` 与 `disabled` 的影子状态（`self.visible`、
`state.disabled`）、让父节点的 z 排序缓存失效。

```lua
btn:setProps({ text = "已保存", disabled = true })   -- 支持批量
label:setProp("text", "更新后的文案")                 -- 单个，均返回 self 可链式
```

失效范围按属性自动选择：

| 属性类别 | 举例 | 后果 |
|---|---|---|
| 布局相关 | `w/h`、`padding`、`gap`、`text` | 清空测量缓存 + 标记场景重排 |
| 仅外观 | `bg`、`border`、`elevation`、`radius`、`color` | 只丢弃 Canvas 缓存，不重排 |
| 层级/显隐/禁用 | `z`、`visible`、`disabled` | 同步影子状态，按需失效 |

删除白名单之外的属性一律按"影响布局"处理：宁可多一次重排，也不会留下陈旧布局。

需要自定义反应时覆写钩子（变更键已按字母序排好）：

```lua
function MyWidget:onPropsChanged(changed)
    for _, k in ipairs(changed) do
        if k == "items" then self:_rebuild(); break end
    end
end
```


```lua
ui:root({ direction = "column", gap = 8 })
  :box({
      bg = "surface",
      elevation = 2,
      radius = "large",
      border = { color = "border", width = 1 },
      padding = { x = 16, y = 12 },
      w = "100%",
  }, function(c)
      c:label("带阴影和边框的卡片")
      c:button("禁用", { disabled = true, tooltip = "不可点击" })
  end)
```

---

## 布局系统

布局由 `lumi/layout.lua` 实现，是简化版 Flexbox。仅**容器控件**（box/panel/scroll 等）参与布局。

### 方向与对齐

| Prop | 取值 | 默认 | 说明 |
|---|---|---|---|
| `direction` | `"row"` / `"column"` | `"column"` | 主轴方向 |
| `gap` | number | `0` | 子节点间距 |
| `align` | `"start"/"center"/"end"/"stretch"` | `"stretch"` | 交叉轴对齐 |
| `justify` | `"start"/"center"/"end"/"space-between"/"space-around"/"space-evenly"` | `"start"` | 主轴对齐 |
| `wrap` | boolean | `false` | 子节点排满后换行 |

```lua
ui:root({ direction = "row", gap = 12, align = "center", justify = "space-between" }, function(r)
    r:button("左")
    r:button("中")
    r:button("右")
end)
```

### grow 分配剩余空间

```lua
ui:root({ direction = "row", w = 400, h = 48 }, function(r)
    r:box({ grow = 1, bg = "surface2" })   -- 占 1 份
    r:box({ grow = 2, bg = "surface" })    -- 占 2 份
end)
```

### 百分比尺寸

```lua
ui:root({ direction = "row", w = 400 }, function(r)
    r:box({ w = "30%", h = 40, bg = "surface2" })
    r:box({ w = "70%", h = 40, bg = "surface" })
end)
```

### 边距/内边距写法

```lua
padding = 16                          -- 四边 16
padding = { x = 20, y = 10 }          -- 上下 10，左右 20
padding = { top = 8, right = 16, bottom = 8, left = 16 }
```

### Grid 网格布局

容器设置 `display = "grid"` 后启用网格布局：子节点按 `cols` 列顺序填入单元格，支持跨行跨列。

| Prop | 类型 | 默认 | 说明 |
|---|---|---|---|
| `display` | `"grid"` | — | 启用网格布局 |
| `cols` | number | `1` | 列数 |
| `gap` | number 或 `{x=,y=}` | `0` | 网格间距（x=列距，y=行距） |
| `colGap` / `rowGap` | number | — | 单独覆盖列距/行距 |

子节点 props：`colSpan`（跨列数）、`rowSpan`（跨行数）；格子内垂直对齐沿用 `align`/`alignSelf`（`stretch` 填满行高）。行高取该行内容最大需求高，跨行子节点不足时把差额均摊到跨度各行。

```lua
ui:root({ display = "grid", cols = 3, gap = 10 }, function(g)
    g:box({ colSpan = 2, h = 64, bg = "primary" }, function() end)   -- 占 2 列
    g:box({ rowSpan = 2, h = 120, bg = "surface2" }, function() end) -- 占 2 行
    g:box({ h = 28, bg = "surface2" }, function() end)
    g:box({ h = 28, bg = "surface2" }, function() end)
end)
```

### 绝对定位

子节点设置 `position` 后脱离布局流（不占 flex/grid 空间），相对父容器**内容区**定位。

```lua
position = {
    x = 10,            -- 数字或百分比字符串（"10%"）
    y = 10,
    anchor = "top-right", -- top-left(默认)/top-right/bottom-left/bottom-right/center
}
```

```lua
ui:root({ h = 96, bg = "surface2", clipChildren = true, direction = "column" }, function(rel)
    rel:label("卡片内容……")
    -- 右上角徽标
    rel:box({ position = { x = 8, y = 8, anchor = "top-right" }, bg = "error", radius = 999 }, function(b)
        b:label("NEW", { variant = "caption", color = "onPrimary" })
    end)
    -- 右下角悬浮按钮
    rel:box({ position = { x = 8, y = 8, anchor = "bottom-right" }, w = 32, h = 32, bg = "primary", radius = 999 })
end)
```

尺寸未显式指定时取测量值；`w`/`h` 支持百分比。

### 响应式显隐

子节点按**容器内容宽**断点显示/隐藏（窗口 resize 后下一帧生效，隐藏节点不参与布局与命中测试）：

```lua
ui:root({ direction = "row" }, function(r)
    r:box({ hideBelow = 700, ... })   -- 容器内容宽 < 700 时隐藏
    r:box({ hideAbove = 700, ... })   -- 容器内容宽 > 700 时隐藏
end)
```

### 布局失效与增量重排

框架不会每帧重排：只有调用过 `invalidate()`（`setProp` / `setProps` / 增删子节点会自动调用）
的场景才会在下一帧重排，并且**只重排变化路径**——几何没变、子树又没变的兄弟节点会被整棵剪掉。

```lua
label:setProp("text", "新文案")   -- 自动失效，下一帧只重排这条路径
-- 直接改 node.props.text = "..." 不会失效，布局保持旧值（别这么写）
```

| 场景 | 是否重排 | 说明 |
|---|---|---|
| `setProp` / `setProps` | 是 | 布局类属性重排，纯外观属性（`bg` / `color` 等）只丢 Canvas 缓存 |
| `addChild` / `removeChild` / `clearChildren` | 是 | 结构变化 |
| `ui:setTheme()` / `ui:invalidateLayout()` / `ui:resize()` | 是（全量） | 清空整棵树的测量缓存 |
| 滚动（`setScroll` / 滚轮 / 惯性） | 否 | 只平移已排好的坐标 |
| 动画补间 `x` / `y` / `w` / `h` | 否 | 动画帧不触发重排；需要随动画改布局请显式 `invalidate()` |

调试面板（`F2`）里的 `Layout: N arranged / M pruned` 就是最近一次重排的命中情况；
`ui.layoutStats` 也可在代码里读。基准脚本 `tests/bench.lua` 会打印全量/增量/滚动的耗时对比。

> 自定义控件若在 `measureContent` 里让高度依赖可用高度 `availH`（例如按可用高裁剪内容），
> 需要覆写 `dependsOnAvailH()` 返回 `true`，否则不同空闲高度之间可能复用测量缓存。

---

## 组件速查

| 组件 | 方法 | 类别 | 说明 |
|---|---|---|---|
| box / panel | `ui:box({...}, fn)` | 容器 | 通用容器/卡片 |
| scroll | `ui:scroll({...}, fn)` | 容器 | 滚动区 |
| tabs | `ui:tabs({...}, fn)` | 容器 | 标签页（子节点即各页内容） |
| label | `ui:label("文本", {...})` | 叶子 | 文本标签 |
| button | `ui:button("文本", {...})` | 叶子 | 按钮 |
| input | `ui:input({...})` | 叶子 | 单行输入框 |
| editor | `ui:editor({...})` | 叶子 | 多行文本编辑器 |
| checkbox | `ui:checkbox({...})` | 叶子 | 复选框 |
| switch | `ui:switch({...})` | 叶子 | 开关 |
| radio | `ui:radio({...})` | 叶子 | 单选按钮 |
| slider | `ui:slider({...})` | 叶子 | 滑块 |
| progress | `ui:progress({...})` | 叶子 | 进度条 |
| dropdown | `ui:dropdown({...})` | 叶子 | 下拉选择 |
| table | `ui:table({...})` | 叶子 | 表格 |
| tree | `ui:tree({...})` | 叶子 | 树 |
| menu | `ui:menu({...})` | 叶子 | 菜单栏 |
| divider | `ui:divider({...})` | 叶子 | 分隔线 |
| image | `ui:image({...})` | 叶子 | 图片显示（fit / 圆角 / 染色 / 点击） |
| avatar | `ui:avatar({...})` | 叶子 | 头像（圆形裁剪 / 文字回退 / 角标） |
| icon | `ui:icon("home", {...})` | 叶子 | 矢量图标（30+ 内置） |
| carousel | `ui:carousel({...})` | 叶子 | 图片轮播（箭头 / 指示点 / 自动播放） |
| dialog | `ui:dialog({...}, fn)` | 悬浮层 | 模态弹窗 |
| toast | `ui:toast("消息")` | 悬浮层 | 轻提示 |
| tooltip | `props.tooltip = "…"` | 悬浮层 | 悬停提示 |

---

## 组件详解

### box / panel —— 通用容器

最基础的容器，通过 `bg` / `elevation` / `border` / `radius` 呈现卡片外观；纯布局时可完全透明。

```lua
ui:root({ direction = "column", gap = 12 })
  :box({ direction = "row", gap = 8 }, function(r)
      r:label("行内布局")
      r:button("按钮")
  end)
  :panel({ bg = "surface", elevation = 2, radius = "large", padding = 16 }, function(c)
      c:label("panel 是 box 的别名", { variant = "subtitle" })
      c:label("卡片内容", { color = "muted" })
  end)
```

---

### scroll —— 滚动区

容器类，内容超出视口时纵向滚动（滚轮 + 惯性）。子节点会按**更大内容高度**布局并整体平移。

```lua
ui:root({ w = 300, h = 400 }, function(r)
    r:scroll({ grow = 1, padding = 16, gap = 8, direction = "column" }, function(s)
        for i = 1, 50 do
            s:label("第 " .. i .. " 行")
        end
    end)
end)
```

---

### label —— 文本标签

首参为文本。支持字号阶梯、颜色、换行、省略号。

| Prop | 类型 | 说明 |
|---|---|---|
| `variant` | `"caption"/"body"/"subtitle"/"title"/"headline"/"display"` 或数字字号 | 字号（默认 `body`） |
| `color` | 色名或颜色表 | 文本颜色（默认 `text`） |
| `align` | `"left"/"center"/"right"` | 对齐 |
| `wrap` | boolean | 按宽度自动换行 |
| `ellipsis` | boolean | 超宽省略号（默认开启，`wrap` 时无效） |

```lua
ui:root({ direction = "column", gap = 8, w = 320 })
  :label("大标题", { variant = "display", color = "primary" })
  :label("副标题", { variant = "subtitle", color = "muted" })
  :label("这是一段会自动换行的长文本内容，超出容器宽度后折行显示。", { wrap = true })
```

---

### button —— 按钮

首参为文本。Material Design 3 四种变体，带状态过渡动画与点击波纹。

| Prop | 类型 | 说明 |
|---|---|---|
| `variant` | `"filled"/"tonal"/"outlined"/"text"` | 变体（默认 `filled`） |
| `color` | 色名或颜色表 | 主色（默认 `primary`） |
| `textColor` | 色名或颜色表 | 覆盖文字颜色 |
| `align` | `"left"/"center"/"right"` | 文字对齐（默认居中） |
| `padX` | number | 水平内边距 |
| `height` | number | 高度（默认 `theme.control.height`） |
| `onClick` | function | 点击回调 |

```lua
ui:root({ direction = "row", gap = 12 }, function(r)
    r:button("Filled", { variant = "filled", onClick = function() print("filled") end })
    r:button("Tonal", { variant = "tonal" })
    r:button("Outlined", { variant = "outlined", color = "success" })
    r:button("Text", { variant = "text" })
    r:button("禁用", { disabled = true })
end)
```

---

### input —— 单行输入框

支持 label、占位符、密码掩码、中文 IME、光标/选区、剪贴板。

| Prop | 类型 | 说明 |
|---|---|---|
| `text` | string | 初始文本 |
| `label` | string | 顶部小标签（可选） |
| `placeholder` | string | 占位符 |
| `password` | boolean | 密码掩码（`•`） |
| `height` | number | 输入区高度 |
| `onChange` | function(text) | 文本变化回调 |
| `onSubmit` | function(text) | 回车提交回调（提交后失焦） |

方法：`getText()`、`setText(text)`。

```lua
ui:root({ direction = "column", gap = 12, w = 320 }, function(c)
    c:input({ label = "用户名", placeholder = "请输入用户名", onChange = function(v) print(v) end })
    c:input({ label = "密码", password = true, placeholder = "请输入密码" })
    c:input({ label = "搜索", onSubmit = function(v) print("搜索: " .. v) end })
end)
```

键盘支持：左右移动（UTF-8 字符边界）、Home/End、退格/删除、`Ctrl+A/C/X/V` 全选/复制/剪切/粘贴。

---

### editor —— 多行文本编辑器

多行编辑，支持行号、语法高亮、撤销/重做、查找/替换、纵向/横向滚动。

| Prop | 类型 | 说明 |
|---|---|---|
| `text` | string | 初始文本（`\n` 分行） |
| `placeholder` | string | 占位符 |
| `lineNumbers` | boolean | 显示行号栏（默认 false） |
| `minLines` / `maxLines` | number | 高度按行数约束 |
| `h` | number | 显式高度（优先于行数） |
| `highlight` | function(lineText, lineIdx) | 语法高亮回调，见下 |
| `onChange` | function(text) | 文本变化回调 |

**语法高亮**：`highlight` 返回分段数组 `{{from=字节, to=字节, color=色}, ...}`（0-based 半开字节偏移，`from`/`to` 来自 `string.find` 的 `-1` 换算）：

```lua
ui:editor({
    h = 160,
    lineNumbers = true,
    text = "local x = 42\nreturn x",
    highlight = function(lineText, lineIdx)
        local segs = {}
        local s = 1
        while true do
            local a, b = lineText:find("%d+", s)
            if not a then break end
            segs[#segs + 1] = { from = a - 1, to = b, color = "warning" }
            s = b + 1
        end
        local a, b = lineText:find("local", 1, true)
        if a then segs[#segs + 1] = { from = a - 1, to = b, color = "primary" } end
        return segs
    end,
})
```

**方法 API**：

| 方法 | 说明 |
|---|---|
| `getText()` / `setText(text)` | 读写文本 |
| `undo()` / `redo()` | 撤销 / 重做 |
| `lineCount()` / `getLineText(i)` | 行数 / 取第 i 行文本 |
| `lineStart(i)` / `lineEnd(i)` | 第 i 行起止字节偏移 |
| `offsetToRowCol(offset)` | 字节偏移 → `行, 列` |
| `rowColToOffset(row, col)` | `行, 列` → 字节偏移 |
| `getCursorRowCol()` / `setCursorRowCol(row, col)` | 光标行列 |
| `selectionRange()` / `hasSelection()` / `selectRange(a, b)` | 选区操作 |
| `find(text, from)` / `findAll(text)` | 查找（返回 0-based 字节区间） |
| `setFindText(text)` | 设置查找词并高亮所有匹配 |
| `findNext()` / `findPrev()` | 选中并滚动到下一个/上一个匹配 |
| `replace(replacement)` | 替换当前选中匹配或下一个 |
| `replaceAll(text, replacement)` | 替换全部，返回数量 |
| `snapshot()` / `restore(snap)` | 状态快照（供自定义撤销栈） |
| `scrollToCursor()` / `scrollToOffset(offset)` | 滚动到光标/偏移 |

**键盘支持**：方向键（跨行）、Home/End（行内，`Ctrl` 时文档首尾）、PageUp/PageDown、退格/删除（行边界自动合并行）、回车插入换行、`Ctrl+A/C/X/V`、`Ctrl+Z` 撤销、`Ctrl+Y` 或 `Ctrl+Shift+Z` 重做。

---

### checkbox / switch / radio —— 选择控件

三者均为 `props.checked` 初始状态 + `onChanged(checked)` 回调。

键盘：`Tab` 聚焦后 `Space` / `Enter` 切换；单选组内用 `↑`/`↓`/`←`/`→` 移动选中项。

**checkbox**：

```lua
ui:root({ direction = "column", gap = 12 }, function(c)
    c:checkbox({ label = "记住我", checked = true, onChanged = function(v) print(v) end })
    c:checkbox({ label = "接收通知" })
end)
```

**switch**：

```lua
ui:root({ direction = "column", gap = 12 }, function(c)
    c:switch({ label = "深色模式", checked = true, onChanged = function(v) print(v) end })
    c:switch({ label = "自动更新" })
end)
```

**radio**（`group` 相同的互斥，需放在同一父容器下）：

```lua
ui:root({ direction = "column", gap = 12 }, function(c)
    c:label("请选择系统", { variant = "caption", color = "muted" })
    c:radio({ label = "Windows", checked = true, group = "os" })
    c:radio({ label = "macOS", group = "os" })
    c:radio({ label = "Linux", group = "os", onChanged = function(v) print("Linux=" .. tostring(v)) end })
end)
```

三者均可用 `color` 覆盖主色（默认 `primary`）。

---

### slider —— 滑块

| Prop | 类型 | 说明 |
|---|---|---|
| `min` / `max` | number | 范围（默认 0 / 100） |
| `value` | number | 初始值 |
| `step` | number | 步进（可选） |
| `showValue` | boolean | 右侧显示数值 |
| `w` | number | 宽度（默认 160） |
| `onChanged` | function(value) | 值变化回调 |

方法：`setValue(v)`。

交互：鼠标拖拽即时更新；Tab 聚焦后可用方向键（←/→ 或 ↑/↓）调整，带焦点环指示。步进优先用 `step`，未设置时取范围的 5%。

```lua
ui:root({ direction = "column", gap = 16, w = 320 }, function(c)
    c:slider({ min = 0, max = 100, value = 60, showValue = true, onChanged = function(v) print(v) end })
    c:slider({ min = 0, max = 10, value = 3, step = 1, showValue = true })
end)
```

---

### progress —— 进度条

| Prop | 类型 | 说明 |
|---|---|---|
| `mode` | `"linear"/"circular"` | 线性 / 环形（默认 linear） |
| `value` | number | 当前值 |
| `max` | number | 上限（默认 1） |
| `color` | 色名或颜色表 | 主色 |
| `thickness` | number | 线宽（linear 的高度 / circular 的环宽） |
| `size` | number | circular 的直径 |
| `showValue` | boolean | circular 显示百分比 |
| `w` | number | linear 宽度 |

方法：`setValue(v)`。

```lua
ui:root({ direction = "column", gap = 16, w = 320 }, function(c)
    c:progress({ value = 0.35 })
    c:progress({ value = 0.75, color = "success", thickness = 12 })
    c:progress({ mode = "circular", value = 0.6, showValue = true, size = 72 })
end)
```

---

### dropdown —— 下拉选择框

| Prop | 类型 | 说明 |
|---|---|---|
| `items` | 字符串数组 或 `{label=, value=}` 数组 | 选项 |
| `value` | 任意 | 当前值 |
| `placeholder` | string | 无匹配时的占位 |
| `w` / `height` | number | 尺寸 |
| `onChanged` | function(value) | 选择回调 |

展开时列表自锚点缩放滑入（Material 菜单风格），箭头 180° 旋转补间；点击外部或选中后自动收起。

键盘：聚焦后 `Enter` / `Space` 展开收起，`↑` / `↓` 像原生 `<select>` 一样直接改值（列表开着时会同时收起）。

```lua
ui:dropdown({
    items = { "Windows", "macOS", "Linux", "Android", "iOS", "Web" },
    value = "Windows",
    onChanged = function(v) print("选择: " .. v) end,
})

-- 或者 label / value 分离
ui:dropdown({
    items = { { label = "管理员", value = 1 }, { label = "普通用户", value = 2 } },
    value = 1,
    onChanged = function(v) print("角色 id: " .. v) end,
})
```

---

### tabs —— 标签页

容器类：`props.tabs` 定义标签名，**子节点依次对应每个标签页的内容**（第 1 个子节点对应第 1 个标签）。

| Prop | 类型 | 说明 |
|---|---|---|
| `tabs` | 字符串数组 | 标签名 |
| `active` | number | 起始页（1 基，默认 1） |
| `onChanged` | function(index) | 切换回调 |

键盘：聚焦标签栏后 `←` / `→`（或 `↑` / `↓`）切页，首尾循环。

```lua
ui:tabs({ tabs = { "概览", "详情", "设置" }, active = 1, onChanged = function(i) print(i) end }, function(t)
    t:box({ padding = 16, bg = "surface", radius = "large", direction = "column", gap = 8 }, function(x)
        x:label("概览内容", { variant = "subtitle" })
    end)
    t:box({ padding = 16, bg = "surface", radius = "large" }, function(x)
        x:label("详情内容")
    end)
    t:box({ padding = 16, bg = "surface", radius = "large" }, function(x)
        x:label("设置内容")
    end)
end)
```

---

### table —— 表格

| Prop | 类型 | 说明 |
|---|---|---|
| `columns` | `{ {label="列名", width=120}, ... }` 或字符串数组 | 列定义（无 `width` 的列均分剩余） |
| `rows` | 二维数组 `{ {"a","b"}, ... }` | 数据 |
| `selected` | number | 初始选中行（1 基） |
| `headerHeight` / `rowHeight` | number | 表头 / 行高（默认 40 / 36） |
| `h` | number | 高度 |
| `onRowClick` | function(index, row) | 行点击回调 |

```lua
ui:table({
    h = 220,
    columns = {
        { label = "姓名", width = 160 },
        { label = "部门" },
        { label = "职位" },
    },
    rows = {
        { "张伟", "研发部", "工程师" },
        { "李娜", "设计部", "设计师" },
        { "王强", "市场部", "经理" },
    },
    onRowClick = function(i, row) print("第 " .. i .. " 行: " .. row[1]) end,
})
```

---

### tree —— 树

| Prop | 类型 | 说明 |
|---|---|---|
| `items` | 嵌套 `{label=, children={...}}` 数组 | 节点 |
| `h` | number | 高度 |
| `onSelect` | function(item) | 选中回调（点击节点触发，含展开/折叠） |

```lua
ui:tree({
    h = 200,
    items = {
        { label = "项目文件", children = {
            { label = "src", children = { { label = "main.lua" }, { label = "config.lua" } } },
            { label = "assets" },
        } },
        { label = "文档", children = { { label = "README.md" } } },
        { label = "README.md" },
    },
    onSelect = function(item) print("选中: " .. (item.label or "")) end,
})
```

---

### menu —— 菜单栏

| Prop | 类型 | 说明 |
|---|---|---|
| `items` | 数组 | 见下 |
| `bg` / `padding` | — | 菜单栏外观 |

`items` 结构：

```lua
{
    { label = "文件", items = {                         -- 有子项 → 展开下拉
        { label = "新建", onClick = fn },
        { divider = true },                            -- 分隔线
        { label = "退出", onClick = fn },
    } },
    { label = "帮助", onClick = fn },                  -- 无子项 → 顶层直接触发
}
```

```lua
ui:menu({
    items = {
        { label = "文件", items = {
            { label = "新建", onClick = function() print("新建") end },
            { label = "打开", onClick = function() print("打开") end },
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
```

点击展开下拉，悬停可在已展开状态下切换菜单。

键盘：聚焦菜单栏后 `Enter` / `Space` 展开第一项，展开时 `←` / `→` 切换同级菜单，`Esc` 收起。

---

### divider —— 分隔线

| Prop | 类型 | 说明 |
|---|---|---|
| `text` | string | 中间标题（可选） |
| `direction` | `"horizontal"/"vertical"` | 方向（默认 horizontal） |
| `color` | 色名或颜色表 | 线色 |

```lua
ui:root({ direction = "column", gap = 12, w = 320 })
  :divider({ text = "按钮 Button" })
  :button("按钮")
  :divider()
```

---

### image —— 图片显示

支持四种 fit 模式与圆角裁剪（stencil 实现），加载失败或未设置 `src` 时显示占位图标。

| Prop | 类型 | 说明 |
|---|---|---|
| `src` | 路径字符串 / Image / Canvas / function | 图片源（函数源在构建时调用一次） |
| `fit` | `"contain"/"cover"/"stretch"/"center"` | 填充模式（默认 `cover`） |
| `radius` | number 或圆角名 | 圆角裁剪 |
| `tint` | 色名或颜色表 | 染色 |
| `bg` | 色名或颜色表 | 无图占位底色（默认 `surface2`） |
| `onClick` | function | 点击回调（可点击时 hover 提亮） |

`fit` 模式说明：`contain` 完整放入留白、`cover` 铺满裁剪、`stretch` 拉伸变形、`center` 原始尺寸居中。显式只设置 `w`（或 `h`）时，另一边按图片比例自动推导。

```lua
ui:root({ direction = "row", gap = 12 }, function(r)
    r:image({ src = "assets/a.png", w = 200, h = 120, fit = "cover", radius = "medium" })
    r:image({ src = "assets/b.png", w = 200, h = 120, fit = "contain", bg = "surface2" })
end)
```

无图片资源时可用 `lumi.image.placeholder` 生成渐变占位图（Canvas，带缓存）：

```lua
local ph = lumi.image.placeholder("key", 480, 288, { 0.2, 0.4, 0.8 }, { 0.6, 0.2, 0.6 }, "水印文字")
r:image({ src = ph, w = 480, h = 288 })
```

路径加载由 `lumi.image.load` 统一缓存，失败安全返回 nil（不抛错）。

---

### avatar —— 头像

圆形裁剪显示图片；无图时以文字回退（取 `text` 首字符，按内容哈希自动选背景色）。

| Prop | 类型 | 说明 |
|---|---|---|
| `src` | 图片源 | 头像图片（可选） |
| `text` / `name` | string | 文字回退内容（取首字符） |
| `size` | number | 直径（默认 40） |
| `color` | 色名或颜色表 | 回退背景色（默认按文字哈希轮换） |
| `textColor` | 色名或颜色表 | 回退文字色（默认 `onPrimary`） |
| `badge` | `true` 或数字 | 角标：true 显示圆点，数字显示计数（99+ 封顶） |
| `onClick` | function | 点击回调（hover 显示光环） |

```lua
ui:root({ direction = "row", gap = 10, align = "center" }, function(r)
    r:avatar({ src = "a.png", size = 44 })
    r:avatar({ text = "lumi", size = 44 })
    r:avatar({ src = "a.png", size = 44, badge = 3 })
    r:avatar({ text = "M", size = 44, badge = true })
end)
```

---

### icon —— 矢量图标

首参为图标名。内置 30+ 线条风格图标（24×24 网格，随尺寸等比缩放），无需任何图片资源。

| Prop | 类型 | 说明 |
|---|---|---|
| `name` | string | 图标名（也可作首参传入） |
| `size` | number | 尺寸（默认 24） |
| `color` | 色名或颜色表 | 颜色（默认 `text`） |

内置图标：`home user settings search close check plus minus heart star trash edit play pause folder file image download upload refresh menu warning info mail lock calendar more arrow-left/right/up/down chevron-left/right/up/down`。未知图标名安全降级为占位方块。

```lua
ui:root({ direction = "row", gap = 12 }, function(r)
    r:icon("home", { size = 26 })
    r:icon("settings", { size = 26, color = "primary" })
    r:icon("trash", { size = 26, color = "error" })
end)
```

其他控件可复用静态绘制：`require("lumi.widgets.icon").drawIcon(name, x, y, size, color)`。

---

### carousel —— 图片轮播

多张图片横向滑动切换，带补间动画、左右箭头与底部指示点（激活项为胶囊）。

| Prop | 类型 | 说明 |
|---|---|---|
| `images` | 图片源数组 | 轮播内容 |
| `w` / `h` | number | 尺寸（默认 320×180，建议显式指定或用 grow） |
| `fit` | string | 填充模式（默认 `cover`） |
| `auto` | number 或 `true` | 自动播放间隔秒数（true = 3s，默认不自动） |
| `arrows` / `dots` | boolean | 显示箭头 / 指示点（默认 true） |
| `radius` | number 或圆角名 | 圆角裁剪 |
| `onChange` | function(index) | 切换回调 |

交互：可直接**拖拽切页**——按住图片左右拖动实时跟随，位移超过阈值（约 1/5 页宽）松手即切换，否则回弹；首尾页有边界阻尼，最多拖出 1/3 页。悬停或按下时自动播放暂停；箭头与指示点均可点击。

```lua
ui:carousel({
    images = { "a.png", "b.png", "c.png" },
    h = 220, radius = "large", auto = 2.5,
    onChange = function(i) print("第 " .. i .. " 张") end,
})
```

方法：`:next()` / `:prev()` / `:go(i)` / `:getCurrent()`。

---

### dialog —— 模态弹窗

通过 `ui:dialog(props, childrenFn)` 创建，自动居中并带遮罩。进场遮罩淡入 + 面板中心缩放（0.94 → 1），退场反向；ESC / 点击遮罩 / 关闭按钮均可关闭。

| Prop | 类型 | 说明 |
|---|---|---|
| `title` | string | 标题（可选） |
| `w` | number | 宽度（默认 420） |
| `dismissible` | boolean | 点击遮罩是否关闭（默认 true） |
| `closable` | boolean | 右上角显示关闭按钮（悬停有高亮反馈） |

```lua
ui:dialog({ title = "关于 LumiUI" }, function(p)
    p:label("这是一个模态弹窗。", { wrap = true })
    p:box({ direction = "row", gap = 8, justify = "end" }, function(x)
        x:button("取消", { variant = "text", onClick = function() ui:closeAllOverlays() end })
        x:button("确定", { variant = "filled", onClick = function() ui:closeAllOverlays() end })
    end)
end)
```

---

### toast —— 轻提示

```lua
ui:toast("这是一条 Toast 通知")            -- 默认样式，2.5 秒后自动消失
ui:toast("已保存", "success")             -- 左侧绿色色条 + 对勾图标
ui:toast("网络连接失败", "error")          -- 红色色条 + 警告图标
ui:toast("提示内容", "info")               -- 主题色条 + 信息图标
```

多条 Toast 自底部向上堆叠；进场自下滑入，退场上滑淡出。

### tooltip —— 悬停提示

任意控件加 `tooltip` prop：

```lua
ui:button("悬停我", { tooltip = "这是一个 Tooltip 提示气泡" })
```

---

## 主题系统

主题由 `lumi/theme.lua` 管理，全局单例，两套配色 + 样式 tokens。

### 切换主题

```lua
ui:setTheme("dark")     -- 或 "light"
lumi.theme.set("light") -- 等价底层 API
```

### 自定义主题

```lua
-- 基于某模式覆盖部分 token
lumi.theme.custom("dark", {
    colors = { primary = "#FF7A45" },   -- 覆盖主色
    shape = { medium = 12 },            -- 覆盖圆角规格
})

-- 或整体构建后应用
local t = lumi.theme.build("light")
t.colors.primary = { 0.1, 0.5, 0.4 }
lumi.theme.apply(t)
```

### 颜色 token

| 名称 | 说明 |
|---|---|
| `background` / `surface` / `surface2` | 背景层级 |
| `border` | 边框 |
| `primary` / `primaryDim` / `onPrimary` | 主色系 |
| `text` / `muted` | 文本 |
| `error` / `success` / `warning` | 语义色 |
| `overlay` | 遮罩 |

颜色值支持色名（`"primary"`）、十六进制字符串（主题定义时）、或 `{r,g,b}` / `{r,g,b,a}` 表（0~1 浮点）。

### 其他 token

```lua
lumi.theme.shape = { small = 4, medium = 8, large = 14, pill = 999 }   -- 圆角
lumi.theme.font  = { caption = 12, body = 14, subtitle = 16, title = 18, headline = 24, display = 32 }
lumi.theme.motion = { fast = 0.15, normal = 0.22, slow = 0.32 }        -- 动画时长（秒）
lumi.theme.control = { height = 40, minWidth = 88, padX = 16, padY = 10 }
```

---

## 动画系统

`lumi/animate.lua` 提供轻量补间动画，支持数值与颜色表插值。

```lua
local animate = require("lumi.animate")   -- 或 lumi.animate

-- animate.to(target, { field = endValue }, { duration, easing, onDone })
animate.to(myNode, { x = 300 }, { duration = 0.3, easing = "cubic", onDone = function() print("done") end })
animate.to(myNode, { _bgColor = { 1, 0, 0 } }, { duration = 0.22 })

animate.stop(myNode)     -- 停止该目标上的所有动画
animate.finish(myNode)   -- 立即完成该目标上的所有动画
```

缓动函数（`easing` 参数）：`linear`、`quad`、`cubic`、`quart`、`quint`、`sine`、`expo`、`circ`、`back`、`elastic`、`bounce`，均可加 `In` / `Out` / `InOut` 后缀（如 `"cubicInOut"`），默认用 `Out`。

> 注意：颜色表插值会**生成新表写回**，不会就地污染共享的主题色引用。

`animate.update(dt)` 已被 `Scene:update` 内部调用，无需手动推进。

---

## 自定义控件

通过 `lumi.register(name, ctor, kind)` 注册，之后即可像内置控件一样链式使用。

| kind | 调用形式 |
|---|---|
| `"props"` | `ui:name({...})` |
| `"text"` | `ui:name("文本", {...})` |
| `"container"` | `ui:name({...}, function(c) ... end)` |

```lua
-- demo/rating.lua
local Widget = require("lumi.widget")
local Rating = setmetatable({}, { __index = Widget })
Rating.__index = Rating

function Rating.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Rating)
    self.max = props.max or 5
    self.value = props.value or 0
    return self
end

function Rating:isFocusable() return not self.state.disabled end
function Rating:measureContent(availW, availH) return 120, 24 end

function Rating:drawContent()
    -- 在 self.x/self.y/self.w/self.h 内绘制
end

function Rating:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    self:setValue(1)
end

function Rating:setValue(v)
    if v ~= self.value then
        self.value = v
        self:emit("onChanged", v)
    end
end

return Rating
```

```lua
lumi.register("rating", require("demo.rating").new, "props")

ui:root({ direction = "row" })
  :rating({ max = 5, value = 3, onChanged = function(v) print(v) end })
```

**自定义控件基类生命周期**（详见 `docs/custom-widget.md`）：

| 方法 | 作用 |
|---|---|
| `measureContent(availW, availH)` | 返回优选尺寸（叶子控件必须） |
| `arrange(x, y, w, h)` | 设置矩形并布局子节点（仅容器） |
| `drawContent()` | 绘制内容 |
| `drawBackground()` | 通用背景/阴影/边框 |
| `isFocusable()` | 是否可聚焦（Tab 可达） |
| `activate(ctx)` | 键盘 Enter / Space 激活，返回 `true` 表示已消费 |
| `reveal(margin)` | 把节点滚入最近的滚动祖先视口（框架在聚焦时自动调用） |
| `mousepressed/released/moved/wheelmoved` | 鼠标事件钩子 |
| `keypressed/textinput/textedited` | 键盘与文本事件钩子 |
| `emit(name, ...)` | 触发用户回调 |

- 状态：`self.state` 含 `hovered / pressed / focused / focusVisible / disabled`，由框架维护；
  画焦点环请用 `focusVisible`（只在键盘操作时点亮），`focused` 表示"持有焦点"。
- 内容变化需调用 `self:invalidate()` 使布局缓存失效。
- 容器控件需设置 `self.acceptsChildren = true`。
- 需要滚轮事件（并阻止冒泡到外层滚动容器）时设置 `self.isScroll = true`。

---

## 性能优化

框架内置三项绘制优化，对使用者透明；重内容场景可显式开启子树缓存。

### 子树 Canvas 缓存（props.cache）

容器设置 `cache = true` 后，整棵子树（含背景与子控件）渲染到一张 Canvas，此后每帧直接贴图，直到缓存失效：

```lua
c:box({ cache = true, bg = "surface", radius = "medium", padding = 14 }, function(p)
    p:label("静态面板", { variant = "h3" })
    p:label("整棵子树只画一次……", { color = "muted" })
end)
```

失效时机：`invalidate()`（内容变化）、节点尺寸变化、主题切换。
注意：子树内的 hover 高亮、波纹、动画会被冻结在首帧——**仅用于静态内容**；子树内的圆角/圆形裁剪（stencil）在缓存渲染中同样受支持。

### 绘制快速剔除

每帧绘制时，与当前 scissor 裁剪区**完全不相交**的节点整棵跳过（`draw.rectVisible`）。滚动容器（scroll/table/tree）中滚出视口的内容不再产生绘制调用；更新与事件仍正常处理。

### 可视行虚拟化

table 与 tree 仅遍历并绘制视口内的行——2000 行表格的每帧成本与 20 行相同，滚动惯性、悬停、选中均不受影响。

---

## 调试工具

`lumi/debug.lua`：按 **F2** 切换调试叠加层（布局外框 + 控件树 + FPS/节点数）。

```lua
local lumi = require("lumi")

function love.keypressed(k)
    if k == "f2" then lumi.debug.toggle(); return end
    ui:keypressed(k)
end
function love.update(dt) ui:update(dt); lumi.debug.update(dt) end
function love.draw() ui:draw(); lumi.debug.draw(ui) end
```

---

## 后端与可测试性

框架内部所有 LÖVE 调用都收敛在 `lumi/platform.lua`，其余模块不直接接触全局 `love`。
这意味着可以换掉后端（做纯 Lua 单测、录制绘制调用、移植到其它运行时）。

### 注入后端

```lua
local lumi = require("lumi")
local platform = require("lumi.platform")

-- 方式一：创建场景时注入（只需提供用到的子表，缺的走空实现）
local ui = lumi.new({ backend = myBackend })

-- 方式二：随时替换
platform.install(myBackend)     -- myBackend 形状与 love 一致即可
platform.install()              -- 传空 = 重新探测全局 love
```

后端表里的 `graphics` 必须是完整的图形接口（绘制原语直接转发，不做包装）；其余子表可缺省。

### 语义接口

`platform` 还提供一组"与 LÖVE 签名不同、便于替换"的语义函数：

| 函数 | 说明 |
|---|---|
| `platform.now()` | 当前时间（秒），动画、光标闪烁、Toast 计时都用它 |
| `platform.isDown(key)` | 按键是否按下（Shift/Ctrl 判断） |
| `platform.setTextInput(on, x, y, w, h)` | 开关 IME，带矩形时在光标处弹候选框 |
| `platform.clipboardGet()` / `platform.clipboardSet(text)` | 剪贴板 |
| `platform.windowSize()` | 窗口宽高 |
| `platform.newFont(size)` / `platform.newFontFromData(data, size)` | 字体 |
| `platform.newCanvas(w, h)` / `platform.newImage(path)` | 画布 / 图片（后者失败返回 nil） |

### 假时钟

动画与光标闪烁依赖真实时间，不便复现。测试里可以冻结时钟：

```lua
platform.freezeTime(10)      -- 定位到第 10 秒
platform.advance(0.6)        -- 推进到 10.6 秒（光标闪烁刚好翻转）
platform.resumeTime()        -- 回到真实时间
```

---

## 完整案例

一个设置面板，综合展示容器、选择控件、输入、下拉、滑块与弹窗：

```lua
local lumi = require("lumi")

local ui
local settings = { dark = true, notify = false, volume = 60, os = "Windows" }

function love.load()
    ui = lumi.new()

    ui:root({ direction = "column" }, function(root)
        root:menu({
            items = {
                { label = "文件", items = {
                    { label = "设置", onClick = function() openSettings() end },
                    { divider = true },
                    { label = "退出", onClick = function() love.event.quit() end },
                } },
            },
            bg = "surface",
            padding = { x = 16 },
        })

        root:scroll({ grow = 1, padding = 24, gap = 16, direction = "column" }, function(c)
            c:label("设置", { variant = "display", color = "primary" })

            c:divider({ text = "外观" })
            c:switch({ label = "深色模式", checked = settings.dark,
                onChanged = function(v)
                    settings.dark = v
                    ui:setTheme(v and "dark" or "light")
                end })

            c:divider({ text = "偏好" })
            c:box({ direction = "column", gap = 12 }, function(x)
                x:switch({ label = "接收通知", checked = settings.notify,
                    onChanged = function(v) settings.notify = v end })
                x:label("请选择系统", { variant = "caption", color = "muted" })
                x:radio({ label = "Windows", checked = true, group = "os" })
                x:radio({ label = "macOS", group = "os" })
                x:radio({ label = "Linux", group = "os" })
            end)

            c:divider({ text = "音量" })
            c:slider({ min = 0, max = 100, value = settings.volume, showValue = true,
                onChanged = function(v) settings.volume = v end })

            c:divider({ text = "关于" })
            c:box({ direction = "row", gap = 12 }, function(r)
                r:button("打开弹窗", { variant = "filled", onClick = openSettings })
                r:button("显示 Toast", { variant = "tonal",
                    onClick = function() ui:toast("设置已保存") end })
            end)
        end)
    end)
end

function openSettings()
    ui:dialog({ title = "关于" }, function(p)
        p:label("LumiUI 是一个 Love2D Material UI 框架。", { wrap = true })
        p:box({ direction = "row", gap = 8, justify = "end" }, function(x)
            x:button("关闭", { variant = "filled", onClick = function() ui:closeAllOverlays() end })
        end)
    end)
end

-- love.update / love.draw / 事件转发 见「快速开始」一节
```
