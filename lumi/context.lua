--[[
    context.lua —— 场景调度器（对外主入口 lumi.new() 返回的对象）
    维护 UI 树、悬停/焦点/按下状态、悬浮层（下拉/菜单/弹窗）、tooltip、toast。
    负责把 love.* 事件转发给对应控件。
]]

local platform = require("lumi.platform")
local theme = require("lumi.theme")
local animate = require("lumi.animate")
local event = require("lumi.event")
local font = require("lumi.font")
local draw = require("lumi.draw")
local tooltip = require("lumi.widgets.tooltip")
local Icon = require("lumi.widgets.icon")

local Box = require("lumi.widgets.box")
local Label = require("lumi.widgets.label")
local Button = require("lumi.widgets.button")
local Input = require("lumi.widgets.input")
local Editor = require("lumi.widgets.editor")
local Checkbox = require("lumi.widgets.checkbox")
local Switch = require("lumi.widgets.switch")
local Radio = require("lumi.widgets.radio")
local Slider = require("lumi.widgets.slider")
local Progress = require("lumi.widgets.progress")
local Dropdown = require("lumi.widgets.dropdown")
local Tabs = require("lumi.widgets.tabs")
local Table = require("lumi.widgets.table")
local Tree = require("lumi.widgets.tree")
local Menu = require("lumi.widgets.menu")
local Dialog = require("lumi.widgets.dialog")
local Divider = require("lumi.widgets.divider")
local Scroll = require("lumi.widgets.scroll")
local Image = require("lumi.widgets.image")
local Avatar = require("lumi.widgets.avatar")
local Icon = require("lumi.widgets.icon")
local Carousel = require("lumi.widgets.carousel")

local Scene = {}
Scene.__index = Scene

-- ---------------- Builder 构造辅助 ----------------

local function textWidget(ctor)
    return function(self, a, b)
        local props
        if type(a) == "table" then
            props = a
        else
            props = b or {}
            props.text = a
        end
        return self:add(ctor(props))
    end
end

local function propWidget(ctor)
    return function(self, props)
        return self:add(ctor(props or {}))
    end
end

local function container(ctor)
    return function(self, props, childrenFn)
        return self:add(ctor(props or {}), childrenFn)
    end
end

Scene.box = container(Box.new)
Scene.panel = container(Box.new)
Scene.scroll = container(Scroll.new)
Scene.tabs = container(Tabs.new)
Scene.label = textWidget(Label.new)
Scene.button = textWidget(Button.new)
Scene.input = propWidget(Input.new)
Scene.editor = propWidget(Editor.new)
Scene.checkbox = propWidget(Checkbox.new)
Scene.switch = propWidget(Switch.new)
Scene.radio = propWidget(Radio.new)
Scene.slider = propWidget(Slider.new)
Scene.progress = propWidget(Progress.new)
Scene.dropdown = propWidget(Dropdown.new)
Scene.table = propWidget(Table.new)
Scene.tree = propWidget(Tree.new)
Scene.menu = propWidget(Menu.new)
Scene.divider = propWidget(Divider.new)
Scene.image = propWidget(Image.new)
Scene.avatar = propWidget(Avatar.new)
Scene.icon = textWidget(Icon.new)
Scene.carousel = propWidget(Carousel.new)

-- 注册自定义控件构造器，使其可通过 ui:name(...) 使用
-- kind: "text"（首参为文本）、"props"（仅 props 表）、"container"（可含子节点）
function Scene.register(name, ctor, kind)
    kind = kind or "props"
    if kind == "text" then
        Scene[name] = textWidget(ctor)
    elseif kind == "container" then
        Scene[name] = container(ctor)
    else
        Scene[name] = propWidget(ctor)
    end
    return Scene
end

-- ---------------- 生命周期 ----------------

function Scene.new()
    local self = setmetatable({}, Scene)
    self._cursor = nil
    self.root = nil
    self.overlays = {}
    self.modal = nil
    self.hover = nil
    self.focus = nil
    self.pressed = nil
    self._mouseX, self._mouseY = 0, 0
    self._keyboard = false   -- 最近一次交互是否来自键盘（决定焦点环是否可见）
    self.width, self.height = platform.windowSize()
    self._layoutDirty = true
    self._tooltipTarget = nil
    self._tooltipTimer = 0
    self.tooltipNode = nil
    self.toasts = {}
    return self
end

function Scene:setTheme(mode)
    if type(mode) == "table" then
        theme.apply(mode)
    else
        theme.set(mode)
    end
    self:invalidateLayout()
    return self
end

-- 标记布局失效并清空测量缓存（主题切换 / 动态增删节点 / resize 时）
function Scene:invalidateLayout()
    if self.root then self.root:clearMeasureCache() end
    self._layoutDirty = true
end

function Scene:root(props, childrenFn)
    local node = Box.new(props or {})
    self.root = node
    node._ctx = self
    self._cursor = node
    if childrenFn then
        childrenFn(self)
    end
    return self
end

-- 添加控件到当前游标位置；带 childrenFn 时临时切换游标并在结束后恢复
function Scene:add(node, childrenFn)
    local parent = self._cursor
    if not parent then
        error("缺少父节点，请先调用 ui:root()", 2)
    end
    parent:addChild(node)
    node._ctx = self
    if childrenFn then
        local prev = self._cursor
        self._cursor = node
        childrenFn(self)
        self._cursor = prev
    elseif node.acceptsChildren then
        self._cursor = node
    end
    return self
end

-- 返回上一级容器（用于链式构建时退出当前容器）
function Scene:up()
    if self._cursor and self._cursor.parent then
        self._cursor = self._cursor.parent
    end
    return self
end

-- ---------------- 悬浮层 ----------------

-- 进场动画：_ovT 从 0 补到 1（组件绘制时据此做 fade/scale/slide）
local function overlayIn(node)
    node._ovT = 0
    node._ovAnim = true
    animate.to(node, { _ovT = 1 }, { duration = 0.18, easing = "cubic" })
end

-- 节点是否位于某棵子树内（浮层打开/关闭时判定焦点归属）
local function isInside(node, root)
    local n = node
    while n do
        if n == root then return true end
        n = n.parent
    end
    return false
end

function Scene:openOverlay(node, opts)
    opts = opts or {}
    node._overlayOpts = opts
    node._closeNotified = nil
    node._ctx = self
    if opts.modal then
        self.modal = node
        -- 焦点必须跟着模态走：否则键盘输入会落到被遮住的控件上（看不见但仍在收事件）
        if not (self.focus and isInside(self.focus, node)) then
            local list = {}
            event.collectFocusable(node, list)
            self:setFocus(list[1])
        end
    end
    table.insert(self.overlays, node)
    if node.w and node.h then
        node:arrange(node.x, node.y, node.w, node.h)
    end
    if opts.anim ~= false then overlayIn(node) end
    return node
end

-- 从栈中移除浮层并统一善后：解除模态、清理 hover/focus、触发一次 onClose
local function detachOverlay(self, node)
    for i, o in ipairs(self.overlays) do
        if o == node then
            table.remove(self.overlays, i)
            break
        end
    end
    if self.modal == node then self.modal = nil end
    if self.hover and isInside(self.hover, node) then
        self.hover.state.hovered = false
        self.hover = nil
    end
    if self.focus and isInside(self.focus, node) then
        self:setFocus(nil)
    end
    node._closing = nil
    local opts = node._overlayOpts
    if opts and opts.onClose and not node._closeNotified then
        node._closeNotified = true
        opts.onClose()
    end
end

-- 关闭悬浮层：带动画节点先播退场（期间不参与命中），结束后真正移除
function Scene:closeOverlay(node)
    for i, o in ipairs(self.overlays) do
        if o == node then
            if node._ovAnim and not node._closing then
                -- 立即解除模态拦截，退场动画只负责视觉
                if self.modal == node then self.modal = nil end
                if self.hover and isInside(self.hover, node) then
                    self.hover.state.hovered = false
                    self.hover = nil
                end
                node._closing = true
                animate.stop(node)
                animate.to(node, { _ovT = 0 }, {
                    duration = 0.14, easing = "quad",
                    onDone = function()
                        detachOverlay(self, node)
                    end,
                })
                return true
            end
            detachOverlay(self, node)
            return true
        end
    end
    return false
end

function Scene:closeTopOverlay()
    local top = self:topOverlay()
    if top then
        self:closeOverlay(top)
        return true
    end
    return false
end

function Scene:closeAllOverlays()
    while #self.overlays > 0 do
        self:closeOverlay(self.overlays[#self.overlays])
    end
end

-- 当前可交互的顶层悬浮层（跳过退场中的）
function Scene:topOverlay()
    for i = #self.overlays, 1, -1 do
        if not self.overlays[i]._closing then return self.overlays[i] end
    end
    return nil
end

-- ---------------- 命中与焦点 ----------------

-- 模态层在 overlays 中的位置：位于它下方的浮层不参与交互
function Scene:_modalIndex()
    if not self.modal then return nil end
    for i, o in ipairs(self.overlays) do
        if o == self.modal then return i end
    end
    return nil
end

-- 在浮层栈中查找命中目标，返回 (节点, 是否被浮层拦截)。
-- 模态层之上的浮层优先（弹窗里的下拉/菜单可以正常交互），其次模态层；
-- 栈中存在活动浮层时，落在其外的点不会穿透到 root。
function Scene:_overlayTarget(x, y)
    local from = self:_modalIndex() or 1
    local hasLive = false
    for i = #self.overlays, from, -1 do
        local o = self.overlays[i]
        if not o._closing then
            hasLive = true
            if o:contains(x, y) then
                return o:hitTest(x, y), true
            end
        end
    end
    if self.modal then
        if self.modal:contains(x, y) then return self.modal:hitTest(x, y), true end
        return nil, true
    end
    return nil, hasLive
end

function Scene:hitTest(x, y)
    local hit, blocked = self:_overlayTarget(x, y)
    if hit then return hit end
    if blocked then return nil end
    if self.root then return self.root:hitTest(x, y) end
    return nil
end

-- 键盘 focus ring 只在「最近一次输入是键盘」时显示，鼠标点出来的焦点不画环
function Scene:setFocus(node)
    if self.focus == node then
        if node then node.state.focusVisible = self._keyboard end
        return
    end
    if self.focus then self.focus:blur() end
    self.focus = node
    if node then
        node:focus()
        node.state.focusVisible = self._keyboard
        node:reveal()   -- Tab 到视口外的控件时自动滚进来
    end
end

-- 焦点作用域：模态存在时键盘导航被困在模态内，不能 Tab 到被遮住的控件
function Scene:focusScope()
    return self.modal or self.root
end

function Scene:focusNext(reverse)
    local list = {}
    event.collectFocusable(self:focusScope(), list)
    if #list == 0 then return end
    local idx = 0
    for i, n in ipairs(list) do
        if n == self.focus then idx = i; break end
    end
    local next
    if reverse then
        next = (idx > 1) and list[idx - 1] or list[#list]
    else
        next = (idx < #list) and list[idx + 1] or list[1]
    end
    self:setFocus(next)
end

-- ---------------- 输入事件 ----------------

function Scene:_press(hit, x, y, button)
    if hit then
        self.pressed = hit
        hit.state.pressed = true
        if hit:isFocusable() then
            self:setFocus(hit)
        elseif hit:isInteractive() then
            self:setFocus(nil)
        end
        hit:mousepressed(x, y, button, self)
    else
        self:setFocus(nil)
    end
end

function Scene:mousepressed(x, y, button)
    self._mouseX, self._mouseY = x, y
    self._keyboard = false   -- 鼠标交互：本次焦点不画焦点环
    -- 从最高层浮层开始：命中则交互，落空则关闭该层并吞掉这次点击（不穿透到下层）
    local from = self:_modalIndex() or 1
    for i = #self.overlays, from, -1 do
        local o = self.overlays[i]
        if not o._closing then
            if o:contains(x, y) then
                self:_press(o:hitTest(x, y), x, y, button)
            elseif o == self.modal then
                local opts = o._overlayOpts or {}
                if opts.closeOnOutside ~= false then self:closeOverlay(o) end
            else
                self:closeOverlay(o)
            end
            return
        end
    end
    local hit = self.root and self.root:hitTest(x, y) or nil
    self:_press(hit, x, y, button)
end

function Scene:mousereleased(x, y, button)
    local hit = self:hitTest(x, y)
    local pressed = self.pressed
    if pressed then
        pressed:mousereleased(x, y, button, self, hit)
        pressed.state.pressed = false
        self.pressed = nil
    end
end

function Scene:mousemoved(x, y)
    self._mouseX, self._mouseY = x, y
    local hit = self:hitTest(x, y)
    if hit ~= self.hover then
        if self.hover then
            self.hover.state.hovered = false
            self.hover:onHoverLeave()
        end
        self.hover = hit
        if hit then
            hit.state.hovered = true
            hit:onHoverEnter()
        end
    end
    if self.pressed then self.pressed:mousemoved(x, y, self) end

    -- tooltip 触发
    local target = (hit and hit.props and hit.props.tooltip) and hit or nil
    if target ~= self._tooltipTarget then
        self._tooltipTarget = target
        self._tooltipTimer = 0.5
        self.tooltipNode = nil
    end
end

function Scene:wheelmoved(x, y)
    local hit = self:hitTest(self._mouseX, self._mouseY)
    local n = hit
    while n do
        if n.isScroll then
            n:wheelmoved(x, y, self)
            break
        end
        n = n.parent
    end
end

function Scene:keypressed(key)
    -- 键盘一按下就切到「键盘模态」：此后获得的焦点才显示焦点环
    self._keyboard = true
    if self.focus then self.focus.state.focusVisible = true end

    if key == "escape" then
        if self:closeTopOverlay() then return end
        if self.focus then self:setFocus(nil) end
        return
    end
    if key == "tab" then
        -- 下拉/菜单这类非模态浮层先关掉，焦点不跳到被浮层盖住的控件上
        local top = self:topOverlay()
        if top and top ~= self.modal then
            self:closeOverlay(top)
            return
        end
        local reverse = platform.isDown("lshift") or platform.isDown("rshift")
        self:focusNext(reverse)
        return
    end
    -- Enter / Space 激活当前焦点控件（输入类控件不实现 activate，按键照常下传）
    if key == "return" or key == "kpenter" or key == "space" then
        local f = self.focus
        if f and not f.state.disabled and f:activate(self) then return end
    end
    if self.focus then self.focus:keypressed(key, self) end
end

function Scene:textinput(t)
    if self.focus then self.focus:textinput(t, self) end
end

function Scene:textedited(text, start, length)
    if self.focus then self.focus:textedited(text, start, length, self) end
end

function Scene:resize(w, h)
    self.width, self.height = w, h
    self._layoutDirty = true
end

-- ---------------- 弹窗 / 提示 ----------------

function Scene:dialog(props, childrenFn)
    props = props or {}
    local d = Dialog.new(props)
    if childrenFn then
        local prev = self._cursor
        self._cursor = d
        childrenFn(self)
        self._cursor = prev
    end
    local w = props.w or 420
    local _, h = d:measure(w, self.height)
    h = math.min(h, self.height - 80)
    d.x = math.floor((self.width - w) / 2)
    d.y = math.floor((self.height - h) / 2)
    d.w = w
    d.h = h
    self:openOverlay(d, { modal = true, closeOnOutside = props.dismissible ~= false })
    return d
end

-- 轻提示：type = nil / "info" / "success" / "error"
function Scene:toast(msg, type)
    table.insert(self.toasts, { text = msg, t = 0, dur = 2.5, type = type })
    return self
end

-- ---------------- 更新与绘制 ----------------

function Scene:update(dt)
    animate.update(dt)
    if self.root then
        self.root:update(dt)
    end
    for _, o in ipairs(self.overlays) do
        o:update(dt)
    end
    -- 仅在布局脏时重排（构建/动态增删/主题切换/resize），滚动与动画帧不再全量重排
    if self._layoutDirty then
        self._layoutDirty = false
        if self.root then
            self.root:arrange(0, 0, self.width, self.height)
        end
        for _, o in ipairs(self.overlays) do
            if o.w and o.h then o:arrange(o.x, o.y, o.w, o.h) end
        end
    end
    -- 聚焦输入框时，持续把系统文本输入区域同步到其最新位置（输入法候选窗定位）
    if self.focus and self.focus.updateTextInput then
        self.focus:updateTextInput()
    end
    -- tooltip
    if self._tooltipTarget then
        self._tooltipTimer = self._tooltipTimer - dt
        if self._tooltipTimer <= 0 and not self.tooltipNode then
            self.tooltipNode = tooltip.make(self._tooltipTarget.props.tooltip)
        end
    else
        self.tooltipNode = nil
    end
    -- toasts
    for i = #self.toasts, 1, -1 do
        local t = self.toasts[i]
        t.t = t.t + dt
        if t.t > t.dur then table.remove(self.toasts, i) end
    end
end

-- toast 类型 → 图标与色条
local toastMeta = {
    info = { icon = "info", color = "primary" },
    success = { icon = "check", color = "success" },
    error = { icon = "warning", color = "error" },
}

function Scene:drawToasts()
    local f = font.get(theme.font.body)
    local n = #self.toasts
    for i, t in ipairs(self.toasts) do
        -- 进场自下滑入，退场上滑淡出
        local tIn = math.min(1, t.t / 0.25)
        local tOut = math.min(1, (t.dur - t.t) / 0.4)
        local alpha = math.min(tIn, tOut)
        local yOff = (1 - tIn) * 24 - (1 - tOut) * 12
        local meta = t.type and toastMeta[t.type] or nil
        local text = t.text
        local tw = draw.textWidth(f, text)
        local iconW = meta and 26 or 0
        local bw = tw + 32 + iconW
        local bh = 40
        local bx = (self.width - bw) / 2
        local by = self.height - 90 - (n - i) * (bh + 10) + yOff
        draw.roundRect(bx, by, bw, bh, 20, { 0.10, 0.10, 0.12, 0.92 * alpha })
        if meta then
            -- 左侧色条 + 状态图标
            draw.roundRect(bx + 6, by + 8, 4, bh - 16, 2, theme.alpha(meta.color, alpha))
            Icon.drawIcon(meta.icon, bx + 16, by + (bh - 18) / 2, 18, theme.alpha(meta.color, alpha))
        end
        draw.text(text, bx + 16 + iconW, by + (bh - f:getHeight()) / 2, 0,
            { font = f, color = { 1, 1, 1, alpha } })
    end
end

function Scene:draw()
    platform.graphics.clear(theme.color("background"))
    if self.root then self.root:draw() end
    for _, o in ipairs(self.overlays) do
        o:draw()
    end
    if self.tooltipNode then
        local tw, th = self.tooltipNode:measure(400, 100)
        local tx = self._mouseX + 14
        local ty = self._mouseY + 18
        if tx + tw > self.width then tx = self._mouseX - tw - 14 end
        if ty + th > self.height then ty = self._mouseY - th - 18 end
        self.tooltipNode:arrange(tx, ty, tw, th)
        self.tooltipNode:draw()
    end
    if #self.toasts > 0 then
        self:drawToasts()
    end
end

return Scene
