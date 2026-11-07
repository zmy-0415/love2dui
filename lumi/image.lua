--[[
    image.lua —— 图片资源模块
    统一加载与缓存（路径 / Image 对象 / 生成函数），内置占位图生成器（渐变 Canvas）。
    用法：local res = require("lumi.image"); res.load("assets/a.png")
]]

local draw = require("lumi.draw")

local res = {}

local cache = {}

-- 判断是否已是可绘制对象（Image / Canvas / 自定义带 typeOf 的表）
local function isDrawable(v)
    if type(v) == "userdata" then return true end
    if type(v) == "table" and type(v.typeOf) == "function" then return true end
    return false
end

-- 加载图片（带缓存），失败返回 nil（不抛错）：
-- src 为路径字符串 → love.graphics.newImage；可绘制对象 → 原样返回；function → 调用取结果
function res.load(src)
    if src == nil then return nil end
    if isDrawable(src) then return src end
    if type(src) == "function" then
        local ok, v = pcall(src)
        if ok and isDrawable(v) then return v end
        return nil
    end
    if type(src) ~= "string" then return nil end
    local hit = cache[src]
    if hit ~= nil then
        return hit or nil
    end
    local ok, img = pcall(love.graphics.newImage, src)
    cache[src] = ok and img or false
    return cache[src] or nil
end

-- 清空路径缓存（主题切换等需要重建资源时）
function res.clear()
    cache = {}
end

-- ---------------- 占位图 ----------------

local phCache = {}

-- 生成对角线渐变占位图（Canvas，带缓存）
-- key 为缓存键；from/to 为 {r,g,b}；label 可选水印文字
function res.placeholder(key, w, h, from, to, label)
    key = tostring(key) .. "_" .. w .. "x" .. h .. "_" .. tostring(label)
    local hit = phCache[key]
    if hit then return hit end

    from = from or { 0.30, 0.42, 0.85 }
    to = to or { 0.58, 0.26, 0.66 }

    local cv = love.graphics.newCanvas(w, h)
    love.graphics.push("all")
    love.graphics.setCanvas(cv)
    -- 对角线渐变：按 (x+y) 比例插值
    local diag = w + h - 2
    for x = 0, w - 1 do
        for y = 0, h - 1, 4 do
            local t = (x + y) / math.max(1, diag)
            draw.setColor(
                from[1] + (to[1] - from[1]) * t,
                from[2] + (to[2] - from[2]) * t,
                from[3] + (to[3] - from[3]) * t,
                1)
            love.graphics.line(x, y, x, y + 4)
        end
    end
    -- 装饰圆（低透明度，增加层次）
    draw.setColor(1, 1, 1, 0.10)
    love.graphics.circle("fill", w * 0.72, h * 0.32, math.min(w, h) * 0.28)
    draw.setColor(0, 0, 0, 0.10)
    love.graphics.circle("fill", w * 0.25, h * 0.78, math.min(w, h) * 0.22)
    if label then
        draw.setColor(1, 1, 1, 0.85)
        love.graphics.print(label, 10, 8)
    end
    love.graphics.setCanvas()
    love.graphics.pop()
    draw.resetState()   -- pop 恢复了渲染状态，缓存作废

    phCache[key] = cv
    return cv
end

return res
