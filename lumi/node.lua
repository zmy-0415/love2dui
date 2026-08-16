--[[
    node.lua —— 节点基类
    所有控件与容器的基础：树结构、测量/布局、绘制生命周期、命中测试、事件钩子。
]]

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
        disabled = self.props.disabled and true or false,
    }
    self._ctx = nil
    self._measureCache = nil
    self._sorted = nil
    self._nextOrder = 0
    self:init(self.props)
    return self
end

-- 子类初始化钩子
function Node:init() end

-- 使本节点及其祖先的测量缓存失效（内容/子节点变化时调用）
-- 冒泡到根节点时标记场景布局脏，触发下一帧重排（避免每帧无条件全量重排）
function Node:invalidate()
    self._measureCache = nil
    if self.parent then
        self.parent:invalidate()
    elseif self._ctx then
        self._ctx._layoutDirty = true
    end
end

-- 清除整棵子树的测量缓存（主题/字号等全局样式变化后调用）
function Node:clearMeasureCache()
    self._measureCache = nil
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

-- 优选尺寸：显式 w/h 优先，否则取内容尺寸，再受 min/max 约束（带缓存）
function Node:measure(availW, availH)
    local keyW = availW or -1
    local keyH = availH or -1
    local cache = self._measureCache
    if cache and cache.kw == keyW and cache.kh == keyH then
        return cache.mw, cache.mh
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

function Node:arrange(x, y, w, h)
    self.x, self.y, self.w, self.h = x, y, w, h
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
    if not self.visible then return end
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
    if not self.visible then return nil end
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

function Node:isFocusable()
    return false
end

function Node:focus()
    self.state.focused = true
end

function Node:blur()
    self.state.focused = false
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
