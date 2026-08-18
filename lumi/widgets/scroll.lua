--[[
    scroll.lua —— 滚动区
    scissor 裁剪 + 惯性滚动 + 滚动条。内容超出视口时垂直滚动。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local layout = require("lumi.layout")
local draw = require("lumi.draw")

local Scroll = setmetatable({}, { __index = Widget })
Scroll.__index = Scroll

function Scroll.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Scroll)
    self.acceptsChildren = true
    self.clipChildren = true
    self.isScroll = true
    self.scrollY = 0
    self.velocity = 0
    self.contentH = 0
    self.viewH = 0
    self._bakedY = 0
    return self
end

function Scroll:measureContent(availW, availH)
    local cw, ch = layout.measureContainer(self, availW, math.huge)
    local maxH = (availH and availH > 0) and availH or ch
    return cw, math.min(ch, maxH)
end

function Scroll:arrange(x, y, w, h)
    self.x, self.y, self.w, self.h = x, y, w, h
    local pt, pr, pb, pl = self:resolvePadding()
    local cw = w - pl - pr
    local _, ch = layout.measureContainer(self, cw, math.huge)
    self.contentH = ch + pt + pb
    self.viewH = h
    self:clampScroll()
    -- 先按滚动量 0 布局子树，再整体平移烘焙到当前滚动位置，
    -- 使子树坐标始终为屏幕坐标（scissor/hitTest 直接可用），同时滚动无需重测重排
    self._bakedY = 0
    layout.arrangeChildrenSized(self, cw, ch)
    self:_applyScroll(self.scrollY)
end

function Scroll:clampScroll()
    local maxScroll = math.max(0, self.contentH - self.viewH)
    self.scrollY = math.max(0, math.min(maxScroll, self.scrollY))
end

-- 递归平移子树：滚动时仅整体移动已布局好的节点坐标
local function shiftTree(node, dy)
    node.y = node.y + dy
    for i = 1, #node.children do
        shiftTree(node.children[i], dy)
    end
end

-- 将子树烘焙到目标滚动量（内容坐标 -> 屏幕坐标的整体偏移）
function Scroll:_applyScroll(target)
    local dy = self._bakedY - target
    if dy == 0 then return end
    for i = 1, #self.children do
        shiftTree(self.children[i], dy)
    end
    self._bakedY = target
end

function Scroll:setScroll(v)
    local maxScroll = math.max(0, self.contentH - self.viewH)
    local nv = math.max(0, math.min(maxScroll, v))
    if nv ~= self.scrollY then
        self.scrollY = nv
        self:_applyScroll(nv)
    end
end

function Scroll:onUpdate(dt)
    if math.abs(self.velocity) > 1 then
        self:setScroll(self.scrollY + self.velocity * dt)
        self.velocity = self.velocity * (1 - math.min(1, dt * 5))
    else
        self.velocity = 0
    end
end

function Scroll:wheelmoved(x, y, ctx)
    self.velocity = self.velocity + y * -100
end

function Scroll:hitTest(x, y)
    if not self.visible or self._bpHidden or not self:contains(x, y) then return nil end
    for i = #self.children, 1, -1 do
        local hit = self.children[i]:hitTest(x, y)
        if hit then return hit end
    end
    return self
end

function Scroll:draw()
    if not self.visible then return end
    self:drawBackground()
    if #self.children > 0 then
        draw.pushClip(self.x, self.y, self.w, self.h)
        for _, c in ipairs(self:getDrawOrder()) do
            c:draw()
        end
        draw.popClip()
    end
    self:drawScrollbar()
end

function Scroll:drawScrollbar()
    local maxScroll = math.max(0, self.contentH - self.viewH)
    if maxScroll <= 0 then return end
    local trackW = 6
    local x = self.x + self.w - trackW - 3
    local y = self.y + 3
    local h = self.h - 6
    draw.roundRect(x, y, trackW, h, trackW / 2, theme.alpha("text", 0.06))
    local thumbH = math.max(24, h * (self.viewH / self.contentH))
    local thumbY = y + (h - thumbH) * (self.scrollY / maxScroll)
    draw.roundRect(x, thumbY, trackW, thumbH, trackW / 2, theme.alpha("text", 0.28))
end

return Scroll
