# 更新日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)：`MAJOR.MINOR.PATCH`。

## 0.5.0 — 2026-11-08

增量布局：此前任何一处 `setProp` 都会让下一帧重排整棵树，一个 1200 节点的列表改一行文字
也要 3 ms 左右。这一版引入子树脏标记与测量缓存放宽，只重排变化路径。

### 新增

- **增量布局** —— `Node._subtreeDirty` 由 `invalidate()` 沿父链点亮；`arrange()` 在「矩形完全没变 +
  子树干净」时整棵跳过（`Node:canSkipArrange`）。滚动区、标签页、表格、树等覆写了 `arrange` 的
  控件同样走剪枝，避免一个大滚动区被旁支改动整体重排。
- **布局统计** —— `ui.layoutStats` 暴露最近一次重排的 `arranged` / `pruned` 节点数，
  调试面板（F2）多一行 `Layout: N arranged / M pruned`。
- **基准脚本** —— `tests/bench.lua`：构造 N 行列表，分别测量全量重排、滚动、增量重排的耗时与
  剪枝率，并校验增量后的几何与全量构建完全一致。
- **对拍脚本** —— `tests/fuzz_layout.lua`：随机施加 120 次属性变更（文本 / 可见性 / 宽度 /
  padding / gap / align），每次都用「同一串变更从头构建」的树作为参照逐节点比对矩形。
  注入「脏标记不上传」的缺陷后它能立刻报出 119 处不一致，可作为剪枝逻辑的保险丝。

### 修复

- **测量缓存跨约束复用** —— 之前缓存键严格按 `(availW, availH)` 命中，而 measure 阶段用父容器的
  可用空间、arrange 阶段用自己的内容尺寸，同一节点每帧按两套键各测一遍，缓存形同虚设。
  现在高度与 `availH` 无关的节点（无百分比高度、非滚动类）在约束放宽时直接复用
  （`Node:dependsOnAvailH`）。
- **padding 容器的子节点测量宽度** —— `measureContainer` / `measureWrapped` 之前把含 padding 的
  外宽传给子节点，与 arrange 阶段的内容宽不一致（顺带也是缓存键对不上的主因）。现在统一用内容宽，
  padding 容器里的 `wrap` 文本也会按真实可用宽度换行。
- **滚动区重排后的坐标** —— 改完内容重排时不再「先按滚动量 0 排布再整体平移」，而是直接以
  「内容原点 = 视口 y − 滚动量」排布：未变化的行坐标不变，剪枝才能生效。

### 实测

1203 节点（滚动区里 300 行卡片）：

| 场景 | 重排节点 | 剪枝子树 | 耗时 |
|---|---|---|---|
| 全量重排（主题切换 / resize） | 1202 | 0 | 2.9 ms |
| 仅滚动 | 0 | — | 0.07 ms |
| 改一行文本（增量） | 3 | 302 | 0.62 ms |

## 0.4.0 — 2026-11-08

键盘可操作闭环：Tab 到按钮按空格没反应、弹窗打开后 Tab 焦点跑到背后、鼠标点一下按钮焦点环
一直亮着——这一版把这三类问题一起解决，并让完整测试套件脱离 LÖVE 运行。

### 新增

- **键盘激活** —— `Node:activate(ctx)` 钩子 + `Scene:keypressed` 路由：`Enter` / `Space` 触发
  button 的 `onClick`、checkbox/switch 的切换、radio 的选中、dropdown 的展开收起、menu 的展开。
  输入框与编辑器不实现 `activate`，回车（提交/换行）照常下传。
- **焦点作用域** —— 模态弹窗打开时 `Tab` 只在弹窗内循环，打开瞬间焦点自动移入弹窗；
  下拉/菜单这类非模态浮层展开时，第一次 `Tab` 先收起它。
- **控件方向键** —— 单选组内 `↑`/`↓`/`←`/`→` 移动选中项与焦点（循环）；标签页 `←`/`→` 切页；
  下拉框 `↑`/`↓` 像原生 `<select>` 一样直接改值；菜单展开后 `←`/`→` 切换同级菜单。
- **键盘焦点环** —— `Node.state.focusVisible`：只有键盘导航得到的焦点才画环（button / checkbox /
  switch / image / avatar / slider / radio / tabs），鼠标点击不再留下一圈常亮描边；单选按钮
  此前完全没有焦点反馈，这次补上。
- **焦点自动滚入视口** —— `Node:reveal(margin)`：`Tab` 到视口外的控件时按矩形差值反推 `scrollY`
  滚进来，嵌套滚动区由内向外逐层处理，不触发重排。
- **`tests/love_stub.lua` + `tests/full.lua`** —— 用假后端拼出最小的全局 `love`，
  `tests/run.lua` 的完整套件（310 条）从此不需要 LÖVE 与显卡，CI 三套解释器都跑。

### 修复

- **菜单 `Esc` 后立刻被重新展开** —— 面板处于退场动画时 `_open` 尚未清空，鼠标正好停在菜单栏上
  会触发 `onUpdate` 的悬停切换。现在退场期间跳过悬停切换。
- **假后端 scissor 无状态** —— `getScissor` 恒返回整窗，导致嵌套裁剪交集算错、剔除断言失效；
  现改为有状态的 `setScissor`/`getScissor`。
- **假后端字体不折行** —— `getWrap` 恒返回单行，`label` 的换行高度断言在无头环境永远不成立；
  现按宽度切分。

### 测试

- 完整套件 266 → 310 条（新增「键盘与焦点」分组 44 条：Tab 顺序与循环、Shift+Tab、激活、
  方向键、模态焦点陷阱、焦点环绘制次数、自动滚动、菜单 Esc）
- headless 11 条、示例冒烟 49 条保持全绿
- 反向验证：把实现回退到 0.3.0 后再跑新用例，8 条断言失败，确认断言非恒真

## 0.3.0 — 2026-11-08

示例与文档版本：把 500 行的单一入口拆成可按需运行的示例，并补上示例级回归。

### 新增

- **示例目录 `examples/`** —— `main.lua` 变成启动器，`love . <name>` 选择示例：
  `showcase`（默认）/ `minimal` / `layout` / `forms` / `editor` / `data` / `theme`
- **`examples/boot.lua`** —— 示例公共外壳：窗口标题、事件转发、F1 主题切换、F2 调试面板、`ctx.feedback`
- **`tests/selfcheck.lua`** —— 把原先写在 `main.lua` 里的集成自检抽出，改为对"当前示例"跑界面级回归
- **`tests/examples.lua`** —— 逐个构建示例并完成建树 / 布局 / 两帧绘制，纯 Lua 可跑
- **`tests/fake_backend.lua`** —— 抽出可复用的记录型后端，`headless.lua` 与 `examples.lua` 共用
- **启动脚本支持示例名** —— `run.bat editor` / `debug.bat layout`

### 变更

- `main.lua` 从 501 行缩减为启动器（参数解析 + verify 模式）
- `tests/headless.lua` 改用共享的假后端，断言数量不变

### 测试

- 示例冒烟 49 条（7 个示例 × 7 项）
- 完整套件 266 条、headless 11 条保持全绿

## 0.2.0 — 2026-11-08

架构与正确性版本：收敛后端依赖、补齐失效入口，并修掉一批交互缺陷。

### 新增

- **后端适配层 `lumi/platform.lua`** —— `lumi/` 下不再直接引用全局 `love`，所有调用（图形、时钟、剪贴板、IME、窗口、资源创建）经此转发；`lumi.new({ backend = ... })` 可注入自定义后端
- **假时钟** —— `platform.freezeTime` / `advance` / `resumeTime`，让动画与光标闪烁可确定性复现
- **统一属性入口** —— `Node:setProps(t)` / `setProp(k, v)` / `onPropsChanged(changed)`，自动按属性类别选择失效范围（布局 / 仅外观 / 层级与显隐）
- **`tests/headless.lua`** —— 不启动 LÖVE 的冒烟测试，CI 可在纯 Lua 环境跑
- **`tools/pack.ps1`** —— 一键打包 `.love` 发行包（版本号取自 `lumi/init.lua`）
- **CI** —— GitHub Actions：多种 Lua 解释器的 headless 测试、xvfb 下的完整套件、luacheck

### 修复

- **模态与浮层嵌套** —— 弹窗打开时其上的下拉/菜单无法交互；改为按浮层栈层级路由，模态只拦截其下方层级，关闭后焦点归还
- **Tabs 非活动页穿透** —— 隐藏页仍参与命中测试与 Tab 焦点收集
- **Dropdown 状态残留** —— 被外部点击或 Esc 关闭后箭头卡住、再次点击只清理不重开
- **Input** —— 密码掩码下把字节偏移当字符数导致光标跳位；长文本没有横向滚动；`charToByte` 越界返回 `nil` 破坏光标
- **Editor** —— `replaceAll` 可能把光标停在 UTF-8 字符内部；无匹配时仍写撤销快照并清空重做栈
- **Tree** —— 外部替换 `props.items` 后仍渲染旧行集，内容高度与滚动条不更新
- **Scroll** —— 命中按插入顺序而非 z 序，与绘制顺序不一致
- **属性影子状态** —— 直接改 `props.disabled` / `props.visible` / `props.z` 不生效，现由 `setProps` 统一同步
- **测试套件** —— 某组异常中断整套；11 处恒真的 `check(..., true)` 冒烟断言改为真实判定

### 性能

- 绘制热路径每帧分配 **168.58 KB → 0.23 KB**（同场景 100 帧实测，关闭 GC 统计）
- 圆角矩形顶点表复用，直角路径改走 `rectangle`；阴影分层颜色表随层级缓存
- `setColor` / `setFont` 状态去重（跨 `push/pop` 后自动失效）
- 文本测宽缓存（按字体分表，512 条上限）
- `Icon.drawIcon` 的 8 个转发闭包提为模块级常量

### 测试

- 完整套件 266 条断言（原 133 条，且 22 组独立隔离执行）
- headless 冒烟 11 条

## 0.1.0 — 初始版本

- 保留模式组件树、Flexbox + Grid 布局、20+ Material Design 控件、深浅主题、补间动画、F2 调试层
