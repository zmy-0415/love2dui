# 更新日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)：`MAJOR.MINOR.PATCH`。

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
