--[[
    node.lua —— 节点基类
    所有控件与容器的基础：树结构、测量/布局、绘制生命周期、命中测试、事件钩子。
]]

local platform = require("lumi.platform")
local layout = require("lumi.layout")
local draw = require("lumi.draw")
local theme = require("lumi.theme")

local Node = {}
Node.__index = Node

local function clamp(v, lo, hi)
    if lo ~= nil and v < lo then return lo end
    if hi ~= nil and v > hi then return hi end
    return v
end

-- 解析边距类属性：number / {x=,y=} / {top=,right=,bottom=,left=}
function Node.resolveEdge(v)
    if type(v) == "number" then
        return v, v, v, v
    end
    if type(v) == "table" then
        if v.top or v.bottom or v.left or v.right then
            return v.top or 0, v.right or 0, v.bottom or 0, v.left or 0
        end
        local x = v.x or 0
        local y = v.y or 0
        return y, x, y, x
    end
    return 0, 0, 0, 0
end

function Node.new(props)
    local self = setmetatable({}, Node)
    self.props = props or {}
    self.parent = nil
    self.children = {}
    self.x, self.y, self.w, self.h = 0, 0, 0, 0
    self.visible = self.props.visible ~= false
    self.acceptsChildren = true
    self.clipChildren = false
    self.state = {
        hovered = false,
        pressed = false,
        focused = false,
        -- 焦点环是否可见：键盘导航得到的焦点才画环，鼠标点出来的焦点不画
        focusVisible = false,
        disabled = self.props.disabled and true or false,
    }
    self._ctx = nil
    self._measureCache = nil
    self._sorted = nil
    self._nextOrder = 0
    -- 子树脏标记：自身或任一后代需要重排时为 true，由 invalidate() 沿父链向上点亮。
    -- arrange() 据此判断「几何没变 + 子树干净」时可以整棵跳过（增量布局）。
    self._subtreeDirty = true
    self:init(self.props)
    return self
end

-- 子类初始化钩子
function Node:init() end

-- 使本节点及其祖先的测量缓存失效（内容/子节点变化时调用）
-- 冒泡到根节点时标记场景布局脏，触发下一帧重排（避免每帧无条件全量重排）
function Node:invalidate()
    self._measureCache = nil
    self._cacheCv = nil
    self._hDepend = nil
    self._subtreeDirty = true
    if self.parent then
        self.parent:invalidate()
    elseif self._ctx then
        self._ctx._layoutDirty = true
    end
end

-- 清除整棵子树的测量缓存（主题/字号等全局样式变化后调用）
function Node:clearMeasureCache()
    self._measureCache = nil
    self._cacheCv = nil
    self._hDepend = nil
    self._subtreeDirty = true
    for _, c in ipairs(self.children) do
        c:clearMeasureCache()
    end
end

function Node:addChild(child)
    if child.parent then
        error("节点已存在父级", 2)
    end
    child.parent = self
    self._nextOrder = self._nextOrder + 1
    child._order = self._nextOrder
    table.insert(self.children, child)
    self._sorted = nil
    self:invalidate()
    return child
end

function Node:removeChild(child)
    for i, c in ipairs(self.children) do
        if c == child then
            table.remove(self.children, i)
            child.parent = nil
            self._sorted = nil
            self:invalidate()
            return
        end
    end
end

function Node:clearChildren()
    for _, c in ipairs(self.children) do
        c.parent = nil
    end
    self.children = {}
    self._sorted = nil
    self:invalidate()
end

-- ---------------- 统一的属性更新入口 ----------------

--[[
    直接改 node.props.xxx 有两个隐患：布局/绘制缓存不会失效；visible、disabled、z
    这类属性有"影子状态"（self.visible、state.disabled、父节点的排序缓存），
    只改 props 不会同步。setProps/setProp 把这两件事一起做掉。

    失效策略：白名单只收录"确定不影响尺寸"的属性，其余一律按影响布局处理 ——
    漏列最多多一次重排（安全），错列才会导致布局陈旧（危险）。
]]
local APPEARANCE_KEYS = {}
for _, k in ipairs({
    "bg", "border", "elevation", "radius", "rounded", "color", "colors",
    "fill", "tint", "alpha", "opacity", "placeholder", "src", "images",
    "formatValue", "icon", "iconColor",
}) do
    APPEARANCE_KEYS[k] = true
end

-- 找到所属场景（用于清理 hover 等场景级状态）
function Node:getScene()
    local n = self
    while n do
        if n._ctx then return n._ctx end
        n = n.parent
    end
    return nil
end

-- 同步"影子状态"类属性（不涉及缓存）
function Node:_syncProp(k)
    if k == "disabled" then
        self.state.disabled = self.props.disabled and true or false
        if self.state.disabled then
            self.state.hovered = false
            self.state.pressed = false
            local ctx = self:getScene()
            if ctx and ctx.hover == self then ctx.hover = nil end
        end
    elseif k == "visible" then
        self.visible = self.props.visible ~= false
    end
end

-- 按属性类别选择失效范围
function Node:_invalidateProp(k)
    if k == "z" then
        -- 只影响绘制/命中顺序，与尺寸无关
        if self.parent then self.parent._sorted = nil end
        self._cacheCv = nil
        return
    end
    if APPEARANCE_KEYS[k] then
        -- 只影响像素，丢弃 Canvas 缓存即可
        self._cacheCv = nil
        return
    end
    self:invalidate()
end

--- 更新单个属性，返回 self（链式）
function Node:setProp(key, value)
    if key == nil then return self end
    if self.props[key] == value then return self end
    self.props[key] = value
    self:_syncProp(key)
    self:_invalidateProp(key)
    self:onPropsChanged({ key })
    return self
end

--- 批量更新属性：{ text = "新值", bg = "primary" }，返回 self
function Node:setProps(t)
    if type(t) ~= "table" then return self end
    local changed = nil
    for k, v in pairs(t) do
        if self.props[k] ~= v then
            self.props[k] = v
            changed = changed or {}
            changed[#changed + 1] = k
        end
    end
    if not changed then return self end
    table.sort(changed)   -- 让副作用顺序稳定（便于复现与测试）
    for i = 1, #changed do self:_syncProp(changed[i]) end
    for i = 1, #changed do self:_invalidateProp(changed[i]) end
    self:onPropsChanged(changed)
    return self
end

--- 属性变化后的自定义反应（控件覆写，例如重建内部结构）
--  @param changed table 发生变化的属性名数组
function Node:onPropsChanged(changed) end

-- 按 z-index 排序后的绘制顺序（z 小者先绘制在下层，稳定排序保持插入顺序）
function Node:getDrawOrder()
    if not self._sorted then
        local list = {}
        for i, c in ipairs(self.children) do
            list[i] = c
        end
        table.sort(list, function(a, b)
            local za, zb = a.props.z or 0, b.props.z or 0
            if za ~= zb then return za < zb end
            return (a._order or 0) < (b._order or 0)
        end)
        self._sorted = list
    end
    return self._sorted
end

function Node:resolvePadding()
    return Node.resolveEdge(self.props.padding)
end

function Node:resolveMargin()
    return Node.resolveEdge(self.props.margin)
end

-- 颜色解析：字符串主题色名或 {r,g,b} 表
function Node:resolveColor(c)
    if type(c) == "string" then
        return theme.color(c)
    end
    return c
end

-- 圆角解析：数字或主题圆角名（small/medium/large/pill）
function Node:resolveRadius(v, default)
    if v == nil then return default or 0 end
    if type(v) == "number" then return v end
    return theme.shape[v] or default or 0
end

-- 内容尺寸（容器默认按 flex 求和，叶子控件覆写）
function Node:measureContent(availW, availH)
    if self.acceptsChildren then
        return layout.measureContainer(self, availW, availH)
    end
    return 0, 0
end

-- 尺寸解析：数字直接返回；字符串百分比相对 avail；无法解析返回 nil
function Node:resolveDim(v, avail)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local pct = tonumber(v:match("^(%-?%d+%.?%d*)%%$"))
        if pct and avail and avail > 0 then
            return avail * (pct / 100)
        end
    end
    return nil
end

--[[
    高度是否依赖可用高度 availH。

    布局分两趟：measure 用「父容器给的可用空间」量子节点，arrange 用「自己的内容尺寸」量，
    同一节点在两次调用里的 availH 往往不同（父容器高 366，本行内容高只有 40）。
    对高度与 availH 无关的节点，两个约束只是「足够大」程度不同，结果一样，可以复用缓存；
    百分比高度、滚动类控件（内容高被裁到可用高）则必须按精确约束重算。
]]
function Node:dependsOnAvailH()
    local d = self._hDepend
    if d == nil then
        d = type(self.props.h or self.props.height) == "string"
        if not d and self.acceptsChildren then
            for _, c in ipairs(self.children) do
                if c.visible and c:dependsOnAvailH() then
                    d = true
                    break
                end
            end
        end
        self._hDepend = d
    end
    return d
end

-- 优选尺寸：显式 w/h 优先，否则取内容尺寸，再受 min/max 约束（带缓存）
function Node:measure(availW, availH)
    local keyW = availW or -1
    local keyH = availH or -1
    local cache = self._measureCache
    if cache then
        if cache.kw == keyW and cache.kh == keyH then
            return cache.mw, cache.mh
        end
        -- 宽度必须精确命中；高度约束放宽时，只要上次量出的高度没被约束顶住就直接复用
        if cache.kw == keyW and not self:dependsOnAvailH() then
            local oldH = cache.kh < 0 and math.huge or cache.kh
            local newH = keyH < 0 and math.huge or keyH
            if cache.mh <= oldH and cache.mh <= newH then
                return cache.mw, cache.mh
            end
        end
    end
    local p = self.props
    local w = self:resolveDim(p.w or p.width, availW)
    local h = self:resolveDim(p.h or p.height, availH)
    if (not w) or (not h) then
        local cw, ch = self:measureContent(availW, availH)
        w = w or cw
        h = h or ch
    end
    w = clamp(w, p.minW, p.maxW)
    h = clamp(h, p.minH, p.maxH)
    self._measureCache = { kw = keyW, kh = keyH, mw = w, mh = h }
    return w, h
end

-- 增量布局统计（每次布局遍历由 Scene 清零，调试面板可读）
-- arranged：真正重排的节点数；pruned：几何未变而被整棵跳过的子树根数
Node.layoutStats = { arranged = 0, pruned = 0 }

--[[
    是否可以跳过本次重排。

    条件是「矩形完全没变」且「子树干净」。子树的坐标是绝对屏幕坐标，
    父节点位置不变时后代的坐标也不会变，所以跳过是安全的；
    一旦本节点或任一后代调用了 invalidate()，_subtreeDirty 会沿父链点亮，
    这条路径上的节点都会照常重排，只有旁支被剪掉。
]]
function Node:canSkipArrange(x, y, w, h)
    if x == self.x and y == self.y and w == self.w and h == self.h and not self._subtreeDirty then
        Node.layoutStats.pruned = Node.layoutStats.pruned + 1
        return true
    end
    return false
end

function Node:arrange(x, y, w, h)
    if self:canSkipArrange(x, y, w, h) then return end
    -- 尺寸变化时使子树缓存失效
    if self.props.cache and self._cacheCv and (w ~= self._cacheW or h ~= self._cacheH) then
        self._cacheCv = nil
    end
    self.x, self.y, self.w, self.h = x, y, w, h
    self._subtreeDirty = false
    Node.layoutStats.arranged = Node.layoutStats.arranged + 1
    self:arrangeChildren()
end

function Node:arrangeChildren()
    if self.acceptsChildren then
        layout.arrangeChildren(self)
    end
end

function Node:update(dt)
    self:onUpdate(dt)
    if self.acceptsChildren then
        for _, c in ipairs(self.children) do
            c:update(dt)
        end
    end
end

function Node:onUpdate(dt) end

function Node:draw()
    if not self.visible or self._bpHidden then return end
    -- 快速剔除：完全处于当前 scissor 裁剪区外时跳过整棵子树
    if not draw.rectVisible(self.x, self.y, self.w, self.h) then return end
    if self.props.cache then
        self:drawCached()
    else
        self:renderTree()
    end
end

-- 子树整体绘制（背景 + 内容 + 子节点）
function Node:renderTree()
    self:drawBackground()
    self:drawContent()
    if self.acceptsChildren and #self.children > 0 then
        if self.clipChildren then
            draw.pushClip(self.x, self.y, self.w, self.h)
        end
        for _, c in ipairs(self:getDrawOrder()) do
            c:draw()
        end
        if self.clipChildren then
            draw.popClip()
        end
    end
end

-- props.cache = true 时把整棵子树渲染到 Canvas，此后每帧直接贴图，直到 invalidate/尺寸变化。
-- 适合静态内容（卡片/面板）；子树内 hover、波纹等实时效果会被冻结，动态内容勿用。
function Node:drawCached()
    local cv = self._cacheCv
    if not cv then
        local w = math.max(1, math.floor(self.w + 0.5))
        local h = math.max(1, math.floor(self.h + 0.5))
        cv = platform.newCanvas(w, h)
        platform.graphics.push("all")
        -- LÖVE 12：setCanvas 表参数请求临时 stencil 附件（子树内圆角/圆形裁剪需要）；LÖVE 11 渲染目标自带，降级为普通绑定
        if not pcall(function()
            platform.graphics.setCanvas({ cv, stencil = true })
        end) then
            platform.graphics.setCanvas(cv)
        end
        platform.graphics.clear(0, 0, 0, 0)
        platform.graphics.setScissor() -- 清除继承自父级裁剪区的 scissor（其作用于渲染目标像素）
        platform.graphics.origin()
        platform.graphics.translate(-self.x, -self.y)
        -- scissor 是目标像素坐标（不受 transform 影响），渲染期间叠加平移偏移修正
        local ox, oy = draw.clipOffsetX, draw.clipOffsetY
        draw.clipOffsetX, draw.clipOffsetY = ox - self.x, oy - self.y
        self:renderTree()
        draw.clipOffsetX, draw.clipOffsetY = ox, oy
        platform.graphics.pop()
        draw.resetState()   -- pop 恢复了渲染状态（颜色/字体），缓存作废
        self._cacheCv = cv
        self._cacheW, self._cacheH = self.w, self.h
    end
    draw.setColor(1, 1, 1, 1)
    platform.graphics.draw(cv, self.x, self.y)
end

-- 通用背景绘制（bg/elevation/border 配置生效）
function Node:drawBackground()
    local p = self.props
    if (not p.bg) and (not p.elevation) and (not p.border) then return end
    local radius = self:resolveRadius(p.radius or p.rounded, 0)
    if p.elevation and p.elevation > 0 then
        draw.shadow(self.x, self.y, self.w, self.h, radius, p.elevation)
    end
    if p.bg then
        draw.roundRect(self.x, self.y, self.w, self.h, radius, self:resolveColor(p.bg))
    elseif p.elevation and p.elevation > 0 then
        draw.roundRect(self.x, self.y, self.w, self.h, radius, theme.color("surface"))
    end
    if p.border then
        local bc, bw
        if type(p.border) == "table" then
            bc = p.border.color or "border"
            bw = p.border.width or 1
        else
            bc = p.border
            bw = 1
        end
        draw.roundRectLine(self.x, self.y, self.w, self.h, radius, self:resolveColor(bc), bw)
    end
end

-- 控件自身内容绘制（钩子）
function Node:drawContent() end

function Node:contains(x, y)
    return x >= self.x and x < self.x + self.w and y >= self.y and y < self.y + self.h
end

-- 命中测试：返回最深命中的节点（z 高者优先）
function Node:hitTest(x, y)
    if not self.visible or self._bpHidden then return nil end
    if not self:contains(x, y) then return nil end
    if self.acceptsChildren then
        local order = self:getDrawOrder()
        for i = #order, 1, -1 do
            local hit = order[i]:hitTest(x, y)
            if hit then return hit end
        end
    end
    return self
end

function Node:isInteractive()
    return not self.state.disabled
end

-- 子节点是否参与命中、焦点收集与更新（Tabs 等只激活当前页的容器覆写此方法）
function Node:isChildActive(child)
    return child.visible and not child._bpHidden
end

function Node:isFocusable()
    return false
end

function Node:focus()
    self.state.focused = true
    self.state.focusVisible = true
end

function Node:blur()
    self.state.focused = false
    self.state.focusVisible = false
end

-- 键盘激活（Enter / Space）。可操作控件覆写并返回 true 表示已消费；
-- 返回 false 时按键继续交给 keypressed（输入框靠这一条拿到回车/空格）。
function Node:activate(ctx)
    return false
end

--[[
    把节点滚入最近的滚动祖先视口。

    滚动容器的子树坐标是屏幕坐标（Scroll 在布局后整体平移烘焙），
    所以只需比较矩形、按差值反推新的 scrollY，不必重排。
    嵌套滚动区由内向外逐层处理：内层滚动后节点坐标同步变化，
    外层再按新坐标继续修正。
]]
function Node:reveal(margin)
    if self.w <= 0 or self.h <= 0 then return end
    margin = margin or 6
    local a = self.parent
    while a do
        if a.isScroll and a.setScroll and a.viewH and a.viewH > 0 then
            local top = a.y + margin
            local bottom = a.y + a.h - margin
            if self.y < top then
                a:setScroll(a.scrollY - (top - self.y))
            elseif self.y + self.h > bottom then
                a:setScroll(a.scrollY + (self.y + self.h - bottom))
            end
        end
        a = a.parent
    end
end

-- ---------------- 事件钩子（子类覆写） ----------------

function Node:mousepressed(x, y, button, ctx) end
function Node:mousereleased(x, y, button, ctx, hit) end
function Node:mousemoved(x, y, ctx) end
function Node:wheelmoved(x, y, ctx) end
function Node:keypressed(key, ctx) end
function Node:textinput(text, ctx) end
function Node:textedited(text, start, length, ctx) end
function Node:onHoverEnter() end
function Node:onHoverLeave() end

return Node
