--[[
    layout.lua —— Flexbox / Grid 布局引擎
    两趟算法：measure（自底向上算内容尺寸）+ arrange（自顶向下分配位置）。
    支持 direction / gap / align / justify / grow / alignSelf / wrap / 百分比尺寸；
    display="grid" 时启用网格布局（cols / colSpan / rowSpan）；
    子节点 position={x=,y=} 时绝对定位（不占布局流）；hideBelow/hideAbove 响应式显隐。
]]

local layout = {}

-- ---------------- 响应式显隐 / 绝对定位判定 ----------------

-- 依据容器内容宽判断子节点是否显示（hideBelow/hideAbove 断点），并记录到 _bpHidden 供 draw/hitTest 使用
function layout.childShown(c, crossW)
    local lo, hi = c.props.hideBelow, c.props.hideAbove
    if lo == nil and hi == nil then return true end
    local shown = true
    if lo and crossW and crossW > 0 and crossW < lo then shown = false end
    if hi and crossW and crossW > 0 and crossW > hi then shown = false end
    c._bpHidden = not shown
    return shown
end

-- 绝对定位子节点（position = {x=,y=,anchor=}），不参与 flex/grid 布局流
local function isAbsolute(c)
    return type(c.props.position) == "table"
end

-- ---------------- Grid 布局 ----------------

-- 解析 grid 间距：gap 为数字或 {x=,y=}，rowGap/colGap 可单独覆盖
local function gridGaps(p)
    local gx, gy
    if type(p.gap) == "table" then
        gx = p.gap.x or 0
        gy = p.gap.y or 0
    else
        gx = p.gap or 0
        gy = p.gap or 0
    end
    gx = p.colGap or gx
    gy = p.rowGap or gy
    return gx, gy
end

-- 收集参与网格的可见子节点（跳过绝对定位与断点隐藏）
local function gridCollect(node, crossW)
    local vis = {}
    for _, c in ipairs(node.children) do
        if c.visible and not isAbsolute(c) and layout.childShown(c, crossW) then
            vis[#vis + 1] = { c = c, cs = math.max(1, c.props.colSpan or 1), rs = math.max(1, c.props.rowSpan or 1) }
        end
    end
    return vis
end

-- 占位矩阵放置：顺序填充，遇 colSpan/rowSpan 占据多格；返回每个子节点的 {row,col} 与总行数
local function gridPlace(vis, cols)
    local occupied = {}
    local function occ(r, c) return occupied[r * 4096 + c] end
    local placements = {}
    local r, c = 1, 1
    local maxRow = 1
    for i, rec in ipairs(vis) do
        local cs = math.min(cols, rec.cs)
        rec.cs = cs
        while true do
            local fit = (c + cs - 1 <= cols)
            if fit then
                for dr = 0, rec.rs - 1 do
                    for dc = 0, cs - 1 do
                        if occ(r + dr, c + dc) then fit = false; break end
                    end
                    if not fit then break end
                end
            end
            if fit then break end
            c = c + 1
            if c > cols then c = 1; r = r + 1 end
        end
        for dr = 0, rec.rs - 1 do
            for dc = 0, cs - 1 do
                occupied[(r + dr) * 4096 + (c + dc)] = true
            end
        end
        placements[i] = { row = r, col = c }
        if r + rec.rs - 1 > maxRow then maxRow = r + rec.rs - 1 end
        c = c + cs
        if c > cols then c = 1; r = r + 1 end
    end
    return placements, maxRow
end

-- 计算每行高度：单行子节点取最大需求高；跨行子节点不足时把差额均摊到跨度各行
local function gridRowHeights(vis, placements, nrows, gy)
    local rowH = {}
    for r = 1, nrows do rowH[r] = 0 end
    for i, rec in ipairs(vis) do
        local pl = placements[i]
        if rec.rs == 1 and rec.mh > rowH[pl.row] then
            rowH[pl.row] = rec.mh
        end
    end
    for i, rec in ipairs(vis) do
        local pl = placements[i]
        if rec.rs > 1 then
            local needed = rec.mh + (rec.rs - 1) * gy
            local cur = (rec.rs - 1) * gy
            for r = pl.row, pl.row + rec.rs - 1 do cur = cur + rowH[r] end
            if needed > cur then
                local extra = (needed - cur) / rec.rs
                for r = pl.row, pl.row + rec.rs - 1 do rowH[r] = rowH[r] + extra end
            end
        end
    end
    return rowH
end

-- 网格测量/排列共用的几何计算：
-- 返回 vis（含 mw/mh 测量值）、placements、rowH、cellW、gx、gy
local function gridGeometry(node, contentW)
    local p = node.props
    local cols = math.max(1, math.floor(tonumber(p.cols) or 1))
    local gx, gy = gridGaps(p)

    local vis = gridCollect(node, contentW)
    local placements, nrows = gridPlace(vis, cols)

    -- 单元格宽度：容器宽已知按公式；未知（无约束测量）时取子节点最大自然宽
    local cellW
    if contentW and contentW > 0 then
        cellW = math.max(0, (contentW - (cols - 1) * gx) / cols)
    else
        cellW = 0
        for _, rec in ipairs(vis) do
            local mw = rec.c:measure(nil, nil)
            if mw > cellW then cellW = mw end
        end
    end

    -- 按跨度宽度重测（跨列子节点可用更宽的约束）
    for i, rec in ipairs(vis) do
        local spanW = cellW * rec.cs + (rec.cs - 1) * gx
        local mw, mh = rec.c:measure(spanW, nil)
        rec.mw, rec.mh = mw, mh
    end

    local rowH = gridRowHeights(vis, placements, nrows, gy)
    return vis, placements, rowH, cellW, gx, gy, cols, nrows
end

-- 网格内容尺寸
local function measureGrid(node, availW, availH)
    local pt, pr, pb, pl = node:resolvePadding()
    local contentW = (availW and availW > 0) and (availW - pl - pr) or nil
    local vis, placements, rowH, cellW, gx, gy, cols, nrows = gridGeometry(node, contentW)
    local totalH = pt + pb
    for r = 1, nrows do totalH = totalH + rowH[r] end
    if nrows > 1 then totalH = totalH + (nrows - 1) * gy end
    return cols * cellW + (cols - 1) * gx + pl + pr, totalH
end

-- 网格排列：格子内垂直对齐遵循 align/alignSelf（stretch 填满行高）
local function arrangeGrid(node, cw, ch)
    local pt, pr, pb, pl = node:resolvePadding()
    local p = node.props
    local vis, placements, rowH, cellW, gx, gy, cols, nrows = gridGeometry(node, cw - pl - pr)

    -- 每行 y 起点
    local rowY = {}
    local acc = node.y + pt
    for r = 1, nrows do
        rowY[r] = acc
        acc = acc + rowH[r] + gy
    end

    for i, rec in ipairs(vis) do
        local pl2 = placements[i]
        local x = node.x + pl + (pl2.col - 1) * (cellW + gx)
        local w = cellW * rec.cs + (rec.cs - 1) * gx
        local h = (rec.rs - 1) * gy
        for r = pl2.row, pl2.row + rec.rs - 1 do h = h + rowH[r] end
        local y = rowY[pl2.row]

        local csAlign = rec.c.props.alignSelf or p.align or "stretch"
        local explicitCross = rec.c.props.h or rec.c.props.height
        local hh, yy = h, y
        if explicitCross or (csAlign ~= "stretch") then
            hh = rec.mh
            if csAlign == "center" then
                yy = y + (h - hh) / 2
            elseif csAlign == "end" then
                yy = y + h - hh
            end
        end
        rec.c:arrange(math.floor(x), math.floor(yy), math.floor(math.max(0, w)), math.floor(math.max(0, hh)))
    end
end

-- ---------------- 绝对定位排列 ----------------

-- 放置绝对定位子节点：position = {x=,y=,anchor=}，相对父容器内容区
-- x/y 支持数字与百分比字符串；anchor: top-left(默认)/top-right/bottom-left/bottom-right/center
local function placeAbsolute(node, cw, ch)
    local pt, pr, pb, pl = node:resolvePadding()
    local ax, ay = node.x + pl, node.y + pt
    local aw, ah = cw - pl - pr, ch - pt - pb
    for _, c in ipairs(node.children) do
        if c.visible and isAbsolute(c) and layout.childShown(c, aw) then
            local pos = c.props.position
            local mw, mh = c:measure(aw, ah)
            local w = c:resolveDim(c.props.w or c.props.width, aw) or mw
            local h = c:resolveDim(c.props.h or c.props.height, ah) or mh
            local x = c:resolveDim(pos.x, aw) or 0
            local y = c:resolveDim(pos.y, ah) or 0
            local anchor = pos.anchor or "top-left"
            if anchor == "top-right" or anchor == "bottom-right" then
                x = aw - x - w
            elseif anchor == "center" then
                x = (aw - w) / 2 + x
            end
            if anchor == "bottom-left" or anchor == "bottom-right" then
                y = ah - y - h
            elseif anchor == "center" then
                y = (ah - h) / 2 + y
            end
            c:arrange(math.floor(ax + x), math.floor(ay + y), math.floor(math.max(0, w)), math.floor(math.max(0, h)))
        end
    end
end

-- 将子节点按主轴尺寸分组为多行（wrap 换行用）
local function groupLines(recs, gap, mainSize)
    local lines = {}
    local cur = { items = {}, mainTotal = 0, crossMax = 0 }
    for _, rec in ipairs(recs) do
        local add = rec.main
        if #cur.items > 0 then add = add + gap end
        if #cur.items > 0 and cur.mainTotal + add > mainSize then
            table.insert(lines, cur)
            cur = { items = {}, mainTotal = 0, crossMax = 0 }
            add = rec.main
        end
        table.insert(cur.items, rec)
        cur.mainTotal = cur.mainTotal + add
        cur.crossMax = math.max(cur.crossMax, rec.cross)
    end
    table.insert(lines, cur)
    return lines
end

-- 收集参与 flex 布局的子节点记录（跳过隐藏 / 绝对定位 / 断点隐藏，含测量与边距）
local function flexCollect(node, availW, availH, crossW)
    local recs = {}
    for _, c in ipairs(node.children) do
        if c.visible and not isAbsolute(c) and layout.childShown(c, crossW) then
            local mw, mh = c:measure(availW, availH)
            local mt, mr, mb, ml = c:resolveMargin()
            recs[#recs + 1] = { c = c, mw = mw, mh = mh, mt = mt, mr = mr, mb = mb, ml = ml }
        end
    end
    return recs
end

-- 依据方向填充 rec.main / rec.cross
local function fillMainCross(recs, dir)
    for _, rec in ipairs(recs) do
        if dir == "column" then
            rec.main = rec.mh + rec.mt + rec.mb
            rec.cross = rec.mw + rec.ml + rec.mr
        else
            rec.main = rec.mw + rec.ml + rec.mr
            rec.cross = rec.mh + rec.mt + rec.mb
        end
    end
end

-- wrap 容器的内容尺寸
local function measureWrapped(node, availW, availH)
    local p = node.props
    local dir = p.direction or "column"
    local gap = p.gap or 0
    local pt, pr, pb, pl = node:resolvePadding()
    local contentW = (availW and availW > 0) and (availW - pl - pr) or availW
    local mainAvail = (dir == "column") and availH or contentW
    if not mainAvail or mainAvail <= 0 then mainAvail = math.huge end
    local recs = flexCollect(node, contentW, availH, contentW)
    fillMainCross(recs, dir)
    local lines = groupLines(recs, gap, mainAvail)
    local mainContent = 0
    local crossContent = 0
    for i, line in ipairs(lines) do
        mainContent = math.max(mainContent, line.mainTotal)
        crossContent = crossContent + line.crossMax
        if i > 1 then crossContent = crossContent + gap end
    end
    if dir == "column" then
        return crossContent + pl + pr, mainContent + pt + pb
    end
    return mainContent + pl + pr, crossContent + pt + pb
end

-- 计算 flex 容器的内容尺寸
function layout.measureContainer(node, availW, availH)
    if node.props.display == "grid" then
        return measureGrid(node, availW, availH)
    end
    if node.props.wrap then
        return measureWrapped(node, availW, availH)
    end
    local p = node.props
    local dir = p.direction or "column"
    local gap = p.gap or 0
    local pt, pr, pb, pl = node:resolvePadding()
    -- 子节点可用宽度是内容宽（不含 padding）：arrange 阶段传的就是内容宽，
    -- 两处不一致会让子节点的测量缓存键永远对不上，每个脏帧都要重测一遍
    local contentW = (availW and availW > 0) and (availW - pl - pr) or availW
    local recs = flexCollect(node, contentW, availH, contentW)
    fillMainCross(recs, dir)
    local totalMain = 0
    local maxCross = 0
    local count = #recs
    for _, rec in ipairs(recs) do
        totalMain = totalMain + rec.main
        maxCross = math.max(maxCross, rec.cross)
    end
    if count > 1 then
        totalMain = totalMain + gap * (count - 1)
    end
    if dir == "column" then
        return maxCross + pl + pr, totalMain + pt + pb
    end
    return totalMain + pl + pr, maxCross + pt + pb
end

-- 根据 justify 计算每个子节点在主轴的起点
local function computeStarts(mains, gap, mainSize, justify)
    local n = #mains
    local total = 0
    for _, m in ipairs(mains) do total = total + m end
    total = total + gap * (n - 1)
    local free = mainSize - total
    local starts = {}
    if n == 0 then return starts end
    if n == 1 then
        local lead = 0
        if justify == "center" then lead = free / 2
        elseif justify == "end" then lead = free end
        starts[1] = lead
        return starts
    end
    if justify == "space-between" then
        local extra = free / (n - 1)
        local pos = 0
        for i = 1, n do
            starts[i] = pos
            pos = pos + mains[i] + gap + extra
        end
    elseif justify == "space-around" then
        local extra = free / n
        local pos = extra / 2
        for i = 1, n do
            starts[i] = pos
            pos = pos + mains[i] + gap + extra
        end
    elseif justify == "space-evenly" then
        local extra = free / (n + 1)
        local pos = extra
        for i = 1, n do
            starts[i] = pos
            pos = pos + mains[i] + gap + extra
        end
    elseif justify == "center" then
        local pos = free / 2
        for i = 1, n do
            starts[i] = pos
            pos = pos + mains[i] + gap
        end
    elseif justify == "end" then
        local pos = free
        for i = 1, n do
            starts[i] = pos
            pos = pos + mains[i] + gap
        end
    else
        local pos = 0
        for i = 1, n do
            starts[i] = pos
            pos = pos + mains[i] + gap
        end
    end
    return starts
end

-- wrap 换行布局：子节点沿主轴排满后换行
local function arrangeWrapped(node, cw, ch)
    local p = node.props
    local dir = p.direction or "column"
    local gap = p.gap or 0
    local align = p.align or "stretch"
    local justify = p.justify or "start"
    local pt, pr, pb, pl = node:resolvePadding()
    local cx = node.x + pl
    local cy = node.y + pt

    local mainSize = (dir == "column") and ch or cw

    local recs = flexCollect(node, cw, ch, cw)
    fillMainCross(recs, dir)
    if #recs == 0 then
        placeAbsolute(node, cw, ch)
        return
    end

    local lines = groupLines(recs, gap, mainSize)

    local crossPos = 0
    for _, line in ipairs(lines) do
        local mains = {}
        for _, rec in ipairs(line.items) do mains[#mains + 1] = rec.main end
        local starts = computeStarts(mains, gap, mainSize, justify)

        for i, rec in ipairs(line.items) do
            local c = rec.c
            local csAlign = c.props.alignSelf or align
            local explicitCross
            if dir == "column" then
                explicitCross = c.props.w or c.props.width
            else
                explicitCross = c.props.h or c.props.height
            end
            local crossLen
            if csAlign == "stretch" and not explicitCross then
                crossLen = line.crossMax
            else
                crossLen = rec.cross
            end
            local itemCrossPos = 0
            if csAlign == "center" then
                itemCrossPos = (line.crossMax - crossLen) / 2
            elseif csAlign == "end" then
                itemCrossPos = line.crossMax - crossLen
            end

            local pos = starts[i]
            local childX, childY, childW, childH
            if dir == "column" then
                childX = cx + crossPos + rec.ml + itemCrossPos
                childY = cy + pos + rec.mt
                childW = crossLen - rec.ml - rec.mr
                childH = rec.main - rec.mt - rec.mb
            else
                childX = cx + pos + rec.ml
                childY = cy + crossPos + rec.mt + itemCrossPos
                childW = rec.main - rec.ml - rec.mr
                childH = crossLen - rec.mt - rec.mb
            end
            c:arrange(math.floor(childX), math.floor(childY), math.floor(math.max(0, childW)), math.floor(math.max(0, childH)))
        end
        crossPos = crossPos + line.crossMax + gap
    end
    placeAbsolute(node, cw, ch)
end

-- 按节点自身尺寸布局子节点
function layout.arrangeChildren(node)
    local pt, pr, pb, pl = node:resolvePadding()
    layout.arrangeChildrenSized(node, node.w - pl - pr, node.h - pt - pb)
end

-- 按指定内容尺寸布局子节点（滚动区用更大内容高度）
function layout.arrangeChildrenSized(node, cw, ch)
    if node.props.display == "grid" then
        arrangeGrid(node, cw, ch)
        placeAbsolute(node, cw, ch)
        return
    end
    if node.props.wrap then
        arrangeWrapped(node, cw, ch)
        return
    end
    local p = node.props
    local dir = p.direction or "column"
    local gap = p.gap or 0
    local align = p.align or "stretch"
    local justify = p.justify or "start"
    local pt, pr, pb, pl = node:resolvePadding()
    local cx = node.x + pl
    local cy = node.y + pt

    local mainSize = (dir == "column") and ch or cw
    local crossSize = (dir == "column") and cw or ch

    -- 测量可见子节点（跳过绝对定位与断点隐藏）
    local vis = {}
    local totalGrow = 0
    for _, c in ipairs(node.children) do
        if c.visible and not isAbsolute(c) and layout.childShown(c, cw) then
            local mw, mh = c:measure(cw, ch)
            local mt, mr, mb, ml = c:resolveMargin()
            local rec = { c = c, mw = mw, mh = mh, mt = mt, mr = mr, mb = mb, ml = ml }
            if dir == "column" then
                rec.main = mh + mt + mb
                rec.cross = mw + ml + mr
            else
                rec.main = mw + ml + mr
                rec.cross = mh + mt + mb
            end
            table.insert(vis, rec)
            totalGrow = totalGrow + (c.props.grow or 0)
        end
    end

    local n = #vis
    if n == 0 then
        placeAbsolute(node, cw, ch)
        return
    end

    -- grow 分配剩余空间
    local totalMain = 0
    local mains = {}
    for _, rec in ipairs(vis) do
        totalMain = totalMain + rec.main
        mains[#mains + 1] = rec.main
    end
    totalMain = totalMain + gap * (n - 1)
    local freeMain = mainSize - totalMain
    if totalGrow > 0 and freeMain > 0 then
        for _, rec in ipairs(vis) do
            local g = rec.c.props.grow or 0
            if g > 0 then
                rec.main = rec.main + freeMain * (g / totalGrow)
            end
        end
        mains = {}
        for _, rec in ipairs(vis) do mains[#mains + 1] = rec.main end
    end

    local starts = computeStarts(mains, gap, mainSize, justify)

    for i, rec in ipairs(vis) do
        local c = rec.c
        local csAlign = c.props.alignSelf or align
        local explicitCross
        if dir == "column" then
            explicitCross = c.props.w or c.props.width
        else
            explicitCross = c.props.h or c.props.height
        end
        local crossLen
        if csAlign == "stretch" and not explicitCross then
            crossLen = crossSize
        else
            crossLen = rec.cross
        end
        local crossPos = 0
        if csAlign == "center" then
            crossPos = (crossSize - crossLen) / 2
        elseif csAlign == "end" then
            crossPos = crossSize - crossLen
        end

        local childX, childY, childW, childH
        local pos = starts[i]
        if dir == "column" then
            childX = cx + rec.ml + crossPos
            childY = cy + pos + rec.mt
            childW = crossLen - rec.ml - rec.mr
            childH = rec.main - rec.mt - rec.mb
        else
            childX = cx + pos + rec.ml
            childY = cy + rec.mt + crossPos
            childW = rec.main - rec.ml - rec.mr
            childH = crossLen - rec.mt - rec.mb
        end
        c:arrange(math.floor(childX), math.floor(childY), math.floor(math.max(0, childW)), math.floor(math.max(0, childH)))
    end
    placeAbsolute(node, cw, ch)
end

return layout
