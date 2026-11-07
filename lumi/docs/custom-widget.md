# LumiUI 自定义控件开发规范

LumiUI 采用保留模式组件树。所有控件都继承自 `Widget`（`lumi/widget.lua`），
`Widget` 又继承自 `Node`（`lumi/node.lua`）。

## 一、基类生命周期

| 方法 | 作用 | 是否需覆写 |
|---|---|---|
| `init(props)` | 构造后初始化（设置自身字段） | 可选 |
| `measureContent(availW, availH)` | 返回控件优选尺寸 (w, h) | 必须（叶子控件） |
| `arrange(x, y, w, h)` | 设置自身矩形并布局子节点 | 仅容器 |
| `onUpdate(dt)` | 每帧更新（动画、状态过渡） | 可选 |
| `drawContent()` | 绘制控件内容（自身矩形内） | 必须 |
| `drawBackground()` | 通用背景/阴影/边框（读 props.bg/elevation/border） | 可选 |
| `isFocusable()` | 是否可聚焦（Tab 键到达） | 可选 |
| `mousepressed/released/moved/wheelmoved` | 鼠标事件钩子 | 可选 |
| `keypressed` / `textinput` / `textedited` | 键盘与文本事件钩子 | 可选 |
| `emit(name, ...)` | 触发用户回调（如 onChanged） | 调用即可 |

**容器控件**需把 `self.acceptsChildren = true`（叶子控件默认 false）。

## 二、子类化范式

```lua
local Widget = require("lumi.widget")
local MyWidget = setmetatable({}, { __index = Widget })
MyWidget.__index = MyWidget

function MyWidget.new(props)
    local self = Widget.new(props or {})   -- 创建 Node 基础
    setmetatable(self, MyWidget)           -- 绑定到本类
    -- 初始化自身字段 ...
    return self
end

function MyWidget:measureContent(availW, availH)
    return 120, 32
end

function MyWidget:drawContent()
    -- 在 self.x/self.y/self.w/self.h 内绘制
end

return MyWidget
```

## 三、注册到场景构建器

```lua
local lumi = require("lumi")
lumi.register("mywidget", MyWidget.new, "props")   -- ui:mywidget({...})
-- kind 可选：
--   "props"     只接受 props 表            ui:mywidget({...})
--   "text"      首参为文本                ui:mywidget("文字", {...})
--   "container" 可含子节点（含 childrenFn）ui:mywidget({...}, function(c) ... end)
```

注册后即可像内置控件一样链式使用：

```lua
ui:root({ direction = "column" })
  :mywidget({ color = "primary", onChanged = function(v) print(v) end })
```

## 四、完整示例

参见 `demo/rating.lua`（星级评分控件），要点：

```lua
function Rating:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    local idx = math.floor((x - self.x) / (self.props.size + self.props.gap)) + 1
    self:setValue(idx)
end

function Rating:setValue(v)
    if v ~= self.value then
        self.value = v
        self:emit("onChanged", v)   -- 触发用户回调
    end
end
```

## 五、注意事项

- **状态**：`self.state` 含 `hovered / pressed / focused / disabled`，由框架维护，
  读取它实现悬停/按压样式。
- **主题**：通过 `require("lumi.theme")` 取色，`self:resolveColor(c)` 支持色名/颜色表。
- **文本**：使用 `require("lumi.font")` 与 `require("lumi.draw")` 的工具（已处理 CJK）。
- **颜色/字体**：请用 `draw.setColor(...)`、`draw.setFont(...)` 代替 `love.graphics.setColor/setFont`。
  框架会缓存当前颜色与字体，连续同值不再下发；若绕过这层直接调用 `love.graphics`，
  缓存会与实际状态不一致，导致后续绘制被错误跳过。跨 `love.graphics.push("all")/pop()`
  之后调用 `draw.resetState()` 丢弃缓存。
- **测量缓存**：若控件内容在运行时变化，需调用 `self:invalidate()` 使布局缓存失效。
- **动画**：`require("lumi.animate")` 的 `animate.to(self, {field = value}, {duration=..})`。
- **事件**：事件钩子的 `ctx` 参数是场景对象，可用于 `ctx:setFocus(...)`、`ctx:openOverlay(...)` 等。
