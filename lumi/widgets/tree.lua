--[[
    tree.lua —— 树
    props.items = { {label="节点", children={ {label="子节点"} }}, ... }
    点击展开/折叠，选中回调 onSelect(item)。
]]

local platform = require("lumi.platform")
local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local Tree = setmetatable({}, { __index = Widget })
Tree.__index = Tree

local ROW_H = 32
local INDENT = 20

function Tree.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Tree)
    self.isScroll = true
    self.scrollY = 0
    self.velocity = 0
    self.contentH = 0
    self.viewH = 0
    self.selected = nil
    self._expanded = setmetatable({}, { __mode = "k" })
    self._flattenCache = nil
    self._flattenItems = nil
    return self
end

-- 外部替换数据源：清空缓存并触发重排/重绘
function Tree:setItems(items)
    self.props.items = items
    self:invalidateFlatten()
    return self
end

function Tree:flatten()
    local rows = {}
    local function walk(items, depth)
        for _, item in ipairs(items or {}) do
            local hasChildren = item.children and #item.children > 0
            table.insert(rows, { item = item, depth = depth, hasChildren = hasChildren })
            if hasChildren and self._expanded[item] then
                walk(item.children, depth + 1)
            end
        end
    end
    walk(self.props.items, 0)
    return rows
end

-- 带缓存的可见行列表（展开/折叠或数据源被替换时失效）
-- 除展开状态外还校验 props.items 的身份：直接赋值新表（如 tree.props.items = newItems）
-- 时旧缓存会继续渲染已经不存在的行，必须在这里兜底。
function Tree:getRows()
    local items = self.props.items
    local rebuilt = false
    if not self._flattenCache or self._flattenItems ~= items then
        self._flattenCache = self:flatten()
        self._flattenItems = items
        rebuilt = true
    end
    if rebuilt then
        -- 行数变化会改变内容高度，需同步滚动范围，否则滚动条与可滚区仍是旧值
        if self.viewH and self.viewH > 0 then
            self.contentH = #self._flattenCache * ROW_H
            self:clampScroll()
        end
        self:invalidate()
    end
    return self._flattenCache
end

function Tree:invalidateFlatten()
    self._flattenCache = nil
    self._flattenItems = nil
    self:invalidate()
end

-- 行高会按可用高裁剪（min(h, availH)），高度依赖 availH
function Tree:dependsOnAvailH()
    return true
end

function Tree:measureContent(availW, availH)
    local h = #self:getRows() * ROW_H
    if availH and availH > 0 then h = math.min(h, availH) end
    return (availW and availW > 0 and availW) or 280, h
end

function Tree:arrange(x, y, w, h)
    if self:canSkipArrange(x, y, w, h) then return end
    self.x, self.y, self.w, self.h = x, y, w, h
    self._subtreeDirty = false
    self.contentH = #self:getRows() * ROW_H
    self.viewH = h
    self:clampScroll()
end

function Tree:clampScroll()
    local maxScroll = math.max(0, self.contentH - self.viewH)
    self.scrollY = math.max(0, math.min(maxScroll, self.scrollY))
end

function Tree:setScroll(v)
    local maxScroll = math.max(0, self.contentH - self.viewH)
    self.scrollY = math.max(0, math.min(maxScroll, v))
end

function Tree:onUpdate(dt)
    if math.abs(self.velocity) > 1 then
        self:setScroll(self.scrollY + self.velocity * dt)
        self.velocity = self.velocity * (1 - math.min(1, dt * 5))
    else
        self.velocity = 0
    end
    if self._ctx then
        local y = self._ctx._mouseY
        self._hoverRow = nil
        if y >= self.y and y < self.y + self.h then
            local idx = math.floor((y - self.y + self.scrollY) / ROW_H) + 1
            local rows = self:getRows()
            if idx >= 1 and idx <= #rows then self._hoverRow = idx end
        end
    end
end

function Tree:wheelmoved(x, y, ctx)
    self.velocity = self.velocity + y * -100
end

function Tree:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    local idx = math.floor((y - self.y + self.scrollY) / ROW_H) + 1
    local rows = self:getRows()
    if idx < 1 or idx > #rows then return end
    local row = rows[idx]
    self.selected = row.item
    if row.hasChildren then
        self._expanded[row.item] = not self._expanded[row.item]
        self:invalidateFlatten()
    end
    self:emit("onSelect", row.item)
end

function Tree:draw()
    if not self.visible then return end
    self:drawBackground()
    local rows = self:getRows()
    local f = font.get(theme.font.body)

    draw.pushClip(self.x, self.y, self.w, self.h)
    -- 可视行虚拟化：仅遍历视口内的行（每行等高 ROW_H，直接算区间）
    local startIdx = math.max(1, math.floor(self.scrollY / ROW_H))
    local endIdx = math.min(#rows, math.ceil((self.scrollY + self.h) / ROW_H) + 1)
    for i = startIdx, endIdx do
        local row = rows[i]
        local rowY = self.y + (i - 1) * ROW_H - self.scrollY
        if rowY + ROW_H >= self.y and rowY < self.y + self.h then
            local x = self.x + row.depth * INDENT + 8
            if i == self._hoverRow then
                draw.roundRect(self.x, rowY, self.w, ROW_H, 0, theme.alpha("text", 0.05))
            end
            if self.selected == row.item then
                draw.roundRect(self.x, rowY, self.w, ROW_H, 0, theme.alpha("primary", 0.12))
            end
            -- 展开箭头
            if row.hasChildren then
                local ax = x + 4
                local ay = rowY + ROW_H / 2
                draw.setColor(theme.color("muted"))
                platform.graphics.setLineWidth(1.5)
                if self._expanded[row.item] then
                    platform.graphics.line(ax - 4, ay - 2, ax, ay + 2)
                    platform.graphics.line(ax, ay + 2, ax + 4, ay - 2)
                else
                    platform.graphics.line(ax - 2, ay - 4, ax + 2, ay)
                    platform.graphics.line(ax + 2, ay, ax - 2, ay + 4)
                end
                x = x + 12
            end
            local color = (self.selected == row.item) and theme.color("primary") or theme.color("text")
            draw.text(row.item.label or "", x + 8, rowY + (ROW_H - f:getHeight()) / 2, 0, { font = f, color = color })
        end
    end
    draw.popClip()

    local maxScroll = math.max(0, self.contentH - self.viewH)
    if maxScroll > 0 then
        local trackW = 6
        local x = self.x + self.w - trackW - 3
        local y = self.y + 3
        local h = self.h - 6
        draw.roundRect(x, y, trackW, h, trackW / 2, theme.alpha("text", 0.06))
        local thumbH = math.max(24, h * (self.viewH / self.contentH))
        local thumbY = y + (h - thumbH) * (self.scrollY / maxScroll)
        draw.roundRect(x, thumbY, trackW, thumbH, trackW / 2, theme.alpha("text", 0.28))
    end
end

return Tree
