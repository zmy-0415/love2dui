--[[
    table.lua —— 表格
    props.columns = { {label="列名", width=120}, ... }，rows = { {"a","b"}, ... }
    表头固定、行悬停/选中高亮、垂直滚动、onRowClick(index, row)。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")
local wheel = require("lumi.wheel")

local Table = setmetatable({}, { __index = Widget })
Table.__index = Table

function Table.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Table)
    self.isScroll = true
    self.scrollY = 0
    self.velocity = 0
    self.contentH = 0
    self.viewH = 0
    self.selected = props.selected
    return self
end

function Table:getCols()
    local out = {}
    for i, c in ipairs(self.props.columns or {}) do
        if type(c) == "table" then out[i] = c else out[i] = { label = c } end
    end
    return out
end

function Table:getColWidths()
    local cols = self:getCols()
    local fixedTotal, autoCount = 0, 0
    for _, c in ipairs(cols) do
        if c.width then fixedTotal = fixedTotal + c.width else autoCount = autoCount + 1 end
    end
    local autoW = autoCount > 0 and math.max(60, (self.w - fixedTotal) / autoCount) or 0
    local widths = {}
    for _, c in ipairs(cols) do
        widths[#widths + 1] = c.width or autoW
    end
    return widths
end

-- 行高会按可用高裁剪（min(h, availH)），高度依赖 availH
function Table:dependsOnAvailH()
    return true
end

function Table:measureContent(availW, availH)
    local headerH = self.props.headerHeight or 40
    local rowH = self.props.rowHeight or 36
    local h = headerH + #(self.props.rows or {}) * rowH
    if availH and availH > 0 then h = math.min(h, availH) end
    return (availW and availW > 0 and availW) or 400, h
end

function Table:arrange(x, y, w, h)
    if self:canSkipArrange(x, y, w, h) then return end
    self.x, self.y, self.w, self.h = x, y, w, h
    self._subtreeDirty = false
    local headerH = self.props.headerHeight or 40
    local rowH = self.props.rowHeight or 36
    self.contentH = headerH + #(self.props.rows or {}) * rowH
    self.viewH = h
    self:clampScroll()
end

function Table:clampScroll()
    local maxScroll = math.max(0, self.contentH - self.viewH)
    self.scrollY = math.max(0, math.min(maxScroll, self.scrollY))
end

function Table:setScroll(v)
    local maxScroll = math.max(0, self.contentH - self.viewH)
    self.scrollY = math.max(0, math.min(maxScroll, v))
end

function Table:onUpdate(dt)
    wheel.update(self, dt)
    if self._ctx then
        local headerH = self.props.headerHeight or 40
        local rowH = self.props.rowHeight or 36
        local y = self._ctx._mouseY
        self._hoverRow = nil
        if y >= self.y + headerH and y < self.y + self.h then
            local idx = math.floor((y - self.y - headerH + self.scrollY) / rowH) + 1
            local rows = self.props.rows or {}
            if idx >= 1 and idx <= #rows then self._hoverRow = idx end
        end
    end
end

function Table:wheelmoved(x, y, ctx)
    wheel.scroll(self, y)
end

function Table:mousepressed(x, y, button, ctx)
    if button ~= 1 or self.state.disabled then return end
    local headerH = self.props.headerHeight or 40
    local rowH = self.props.rowHeight or 36
    if y < self.y + headerH then return end
    local idx = math.floor((y - self.y - headerH + self.scrollY) / rowH) + 1
    local rows = self.props.rows or {}
    if idx >= 1 and idx <= #rows then
        self.selected = idx
        self:emit("onRowClick", idx, rows[idx])
    end
end

function Table:draw()
    if not self.visible then return end
    self:drawBackground()
    local cols = self:getCols()
    local widths = self:getColWidths()
    local headerH = self.props.headerHeight or 40
    local rowH = self.props.rowHeight or 36
    local rows = self.props.rows or {}
    local f = font.get(theme.font.body)

    draw.pushClip(self.x, self.y, self.w, self.h)

    -- 表头
    draw.roundRect(self.x, self.y, self.w, headerH, 0, theme.color("surface2"))
    local hx = self.x
    for i, c in ipairs(cols) do
        draw.text(c.label or "", hx + 12, self.y + (headerH - f:getHeight()) / 2, 0, { font = f, color = theme.color("muted") })
        hx = hx + widths[i]
    end

    -- 行（r 为 0 基行位置，rowIndex 为 1 基数据下标）
    local viewTop = self.y + headerH
    local startRow = math.floor(self.scrollY / rowH)
    local visibleCount = math.ceil((self.h - headerH) / rowH) + 1
    local endRow = math.min(#rows - 1, startRow + visibleCount - 1)
    for r = startRow, endRow do
        local rowIndex = r + 1
        local rowY = viewTop + r * rowH - self.scrollY
        if rowY + rowH >= viewTop and rowY < self.y + self.h then
            if rowIndex == self.selected then
                draw.roundRect(self.x, rowY, self.w, rowH, 0, theme.alpha("primary", 0.14))
            elseif self._hoverRow == rowIndex then
                draw.roundRect(self.x, rowY, self.w, rowH, 0, theme.alpha("text", 0.05))
            end
            local cx = self.x
            local row = rows[rowIndex]
            for ci = 1, #cols do
                local cell = row[ci]
                local txt = (cell ~= nil) and tostring(cell) or ""
                draw.text(txt, cx + 12, rowY + (rowH - f:getHeight()) / 2, 0, { font = f, color = theme.color("text") })
                cx = cx + widths[ci]
            end
        end
    end
    draw.popClip()

    -- 滚动条
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

return Table
