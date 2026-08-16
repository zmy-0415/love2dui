--[[
    layout.lua —— Flexbox 布局引擎
    两趟算法：measure（自底向上算内容尺寸）+ arrange（自顶向下分配位置）。
    支持 direction / gap / padding / margin / align / justify / grow / alignSelf。
]]

local layout = {}

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

-- wrap 容器的内容尺寸
local function measureWrapped(node, availW, availH)
    local p = node.props
    local dir = p.direction or "column"
    local gap = p.gap or 0
    local mainAvail = (dir == "column") and availH or availW
    if not mainAvail or mainAvail <= 0 then mainAvail = math.huge end
    local recs = {}
    for _, c in ipairs(node.children) do
        if c.visible then
            local mw, mh = c:measure(availW, availH)
            local mt, mr, mb, ml = c:resolveMargin()
            local rec = { mw = mw, mh = mh, mt = mt, mr = mr, mb = mb, ml = ml }
            if dir == "column" then
                rec.main = mh + mt + mb
                rec.cross = mw + ml + mr
            else
                rec.main = mw + ml + mr
                rec.cross = mh + mt + mb
            end
            table.insert(recs, rec)
        end
    end
    local lines = groupLines(recs, gap, mainAvail)
    local mainContent = 0
    local crossContent = 0
    for i, line in ipairs(lines) do
        mainContent = math.max(mainContent, line.mainTotal)
        crossContent = crossContent + line.crossMax
        if i > 1 then crossContent = crossContent + gap end
    end
    local pt, pr, pb, pl = node:resolvePadding()
    if dir == "column" then
        return crossContent + pl + pr, mainContent + pt + pb
    end
    return mainContent + pl + pr, crossContent + pt + pb
end

-- 计算 flex 容器的内容尺寸
function layout.measureContainer(node, availW, availH)
    if node.props.wrap then
        return measureWrapped(node, availW, availH)
    end
    local p = node.props
    local dir = p.direction or "column"
    local gap = p.gap or 0
    local totalMain = 0
    local maxCross = 0
    local count = 0
    for _, c in ipairs(node.children) do
        if c.visible then
            count = count + 1
            local mw, mh = c:measure(availW, availH)
            local mt, mr, mb, ml = c:resolveMargin()
            if dir == "column" then
                totalMain = totalMain + mh + mt + mb
                maxCross = math.max(maxCross, mw + ml + mr)
            else
                totalMain = totalMain + mw + ml + mr
                maxCross = math.max(maxCross, mh + mt + mb)
            end
        end
    end
    if count > 1 then
        totalMain = totalMain + gap * (count - 1)
    end
    local pt, pr, pb, pl = node:resolvePadding()
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

    local recs = {}
    for _, c in ipairs(node.children) do
        if c.visible then
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
            table.insert(recs, rec)
        end
    end
    if #recs == 0 then return end

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
end

-- 按节点自身尺寸布局子节点
function layout.arrangeChildren(node)
    local pt, pr, pb, pl = node:resolvePadding()
    layout.arrangeChildrenSized(node, node.w - pl - pr, node.h - pt - pb)
end

-- 按指定内容尺寸布局子节点（滚动区用更大内容高度）
function layout.arrangeChildrenSized(node, cw, ch)
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

    -- 测量可见子节点
    local vis = {}
    local totalGrow = 0
    for _, c in ipairs(node.children) do
        if c.visible then
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
    if n == 0 then return end

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
end

return layout
