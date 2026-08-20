--[[
    carousel.lua —— 图片轮播
    多张图片横向滑动切换：左右箭头 + 底部指示点 + 自动播放（hover/按下时暂停）。
    props: images（src 数组）/ fit（默认 cover）/ auto（秒数或 true=3s）/ arrows / dots / radius / onChange
    用法：ui:carousel({ images = imgs, h = 200, auto = 2.5, onChange = function(i) end })
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local draw = require("lumi.draw")
local res = require("lumi.image")
local Icon = require("lumi.widgets.icon")
local animate = require("lumi.animate")

local Carousel = setmetatable({}, { __index = Widget })
Carousel.__index = Carousel

function Carousel.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Carousel)
    self._page = 1
    self._pos = 1      -- 浮点显示位置（补间目标 = _page）
    self._timer = 0    -- 自动播放计时
    return self
end

function Carousel:pageCount()
    return #(self.props.images or {})
end

function Carousel:getCurrent()
    return self._page
end

-- 跳转到第 i 页（循环回绕），带滑动动画
function Carousel:go(i, silent)
    local n = self:pageCount()
    if n == 0 then return end
    i = ((i - 1) % n) + 1
    if i == self._page then return end
    self._page = i
    self._timer = 0
    animate.stop(self, "_pos")
    animate.to(self, { _pos = i }, { duration = theme.motion.normal, easing = "cubic" })
    if silent ~= true then
        self:emit("onChange", i)
    end
end

-- 对齐到当前页（拖拽回弹）
function Carousel:snapBack()
    animate.stop(self, "_pos")
    animate.to(self, { _pos = self._page }, { duration = theme.motion.normal, easing = "cubic" })
end

function Carousel:next() self:go(self._page + 1) end
function Carousel:prev() self:go(self._page - 1) end

function Carousel:measureContent(availW, availH)
    local w = self.props.w or self.props.width or availW or 320
    return w, self.props.h or self.props.height or 180
end

function Carousel:onUpdate(dt)
    local auto = self.props.auto
    if not auto or self.state.hovered or self.state.pressed then return end
    local dur = (auto == true) and 3 or tonumber(auto) or 3
    self._timer = self._timer + dt
    if self._timer >= dur then
        self._timer = 0
        self:next()
    end
end

-- 箭头热区（圆形命中）
function Carousel:arrowAt(x, y)
    local cy = self.y + self.h / 2
    local r = self:arrowRadius() + 4
    if (x - (self.x + 18)) ^ 2 + (y - cy) ^ 2 <= r * r then return "prev" end
    if (x - (self.x + self.w - 18)) ^ 2 + (y - cy) ^ 2 <= r * r then return "next" end
    return nil
end

function Carousel:arrowRadius()
    return math.max(11, math.min(16, self.h * 0.09))
end

-- 指示点槽位中心 x 坐标列表
function Carousel:dotCenters()
    local n = self:pageCount()
    if n == 0 then return nil end
    local spacing = 16
    local total = (n - 1) * spacing + 20
    local startX = self.x + (self.w - total) / 2 + 10
    local list = {}
    for i = 1, n do
        list[i] = startX + (i - 1) * spacing
    end
    return list
end

function Carousel:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    -- 箭头
    local arrow = self:arrowAt(x, y)
    if arrow == "prev" then self:prev() return end
    if arrow == "next" then self:next() return end
    -- 指示点
    local centers = self:dotCenters()
    if centers and self.props.dots ~= false and y >= self.y + self.h - 20 then
        for i, cx in ipairs(centers) do
            if math.abs(x - cx) <= 10 then
                self:go(i)
                return
            end
        end
    end
    -- 其余区域：启动拖拽
    self._dragging = true
    self._dragX = x
    self._dragStartPos = self._pos
    self._dragDX = 0
    animate.stop(self, "_pos")
end

-- 拖拽跟随（边界施加阻尼，最多拖出 1/3 页）
function Carousel:mousemoved(x, y, ctx)
    if not self._dragging then return end
    local n = self:pageCount()
    local dx = x - self._dragX
    self._dragDX = dx
    local p = self._dragStartPos - dx / self.w
    if p < 1 then
        p = 1 - math.min(0.34, (1 - p) * 0.35)
    elseif p > n then
        p = n + math.min(0.34, (p - n) * 0.35)
    end
    self._pos = p
end

-- 释放：位移超阈值且未越界则切页，否则回弹（拖拽不循环回绕）
function Carousel:mousereleased(x, y, button, ctx, hit)
    if not self._dragging then return end
    self._dragging = false
    local n = self:pageCount()
    local th = math.max(24, self.w * 0.18)
    if self._dragDX <= -th and self._page < n then
        self:go(self._page + 1)
    elseif self._dragDX >= th and self._page > 1 then
        self:go(self._page - 1)
    else
        self:snapBack()
    end
end

function Carousel:drawContent()
    local p = self.props
    local n = self:pageCount()
    local radius = self:resolveRadius(p.radius, 0)
    local images = p.images or {}

    -- 图片区（clip 到自身，圆角时用 stencil）
    local function paint()
        draw.pushClip(self.x, self.y, self.w, self.h)
        if n == 0 then
            draw.roundRect(self.x, self.y, self.w, self.h, radius, theme.color("surface2"))
        else
            for i = 1, n do
                local img = res.load(images[i])
                local dx = self.x + (i - self._pos) * self.w
                if img and dx < self.x + self.w and dx + self.w > self.x then
                    draw.image(img, dx, self.y, self.w, self.h, { fit = p.fit or "cover" })
                end
            end
        end
        draw.popClip()
    end
    if radius > 0 then
        draw.inRound(self.x, self.y, self.w, self.h, radius, paint)
    else
        paint()
    end

    if n == 0 then
        Icon.drawIcon("image", self.x + self.w / 2 - 12, self.y + self.h / 2 - 12, 24, theme.color("muted"))
        return
    end

    -- 左右箭头（hover 时更清晰）
    local hoverBoost = self.state.hovered and 0.32 or 0.22
    local ar = self:arrowRadius()
    local cy = self.y + self.h / 2
    local ax1, ax2 = self.x + 18, self.x + self.w - 18
    local as = ar * 1.1
    love.graphics.setColor(0, 0, 0, hoverBoost)
    love.graphics.circle("fill", ax1, cy, ar)
    love.graphics.circle("fill", ax2, cy, ar)
    Icon.drawIcon("chevron-left", ax1 - as / 2, cy - as / 2, as, { 1, 1, 1, 0.92 })
    Icon.drawIcon("chevron-right", ax2 - as / 2, cy - as / 2, as, { 1, 1, 1, 0.92 })

    -- 底部指示点（激活项为胶囊）
    if p.dots ~= false then
        local centers = self:dotCenters()
        local dy = self.y + self.h - 10
        for i, cx in ipairs(centers) do
            if i == self._page then
                draw.roundRect(cx - 10, dy - 3, 20, 6, 3, { 1, 1, 1, 0.95 })
            else
                love.graphics.setColor(1, 1, 1, 0.5)
                love.graphics.circle("fill", cx, dy, 3)
            end
        end
    end
end

return Carousel
