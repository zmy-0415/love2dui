--[[
    animate.lua —— 轻量补间动画（tween）系统
    animate.to(target, { key = endValue }, { duration, easing, onDone })
    支持对数值与颜色表 {r,g,b} 的逐分量插值。
]]

local animate = {}

local active = {}

-- ---------------- 缓动函数 ----------------
local easings = {}
animate.easings = easings

-- 幂次缓动（二次/三次/四次/五次）
local powFns = {
    quad = function(t) return t * t end,
    cubic = function(t) return t * t * t end,
    quart = function(t) return t * t * t * t end,
    quint = function(t) return t * t * t * t * t end,
}
local otherFns = {
    sine = function(t) return 1 - math.cos(t * math.pi / 2) end,
    expo = function(t) return t == 0 and 0 or 2 ^ (10 * (t - 1)) end,
    circ = function(t) return 1 - math.sqrt(1 - t * t) end,
    back = function(t) return t * t * ((1.70158 + 1) * t - 1.70158) end,
    elastic = function(t)
        if t == 0 or t == 1 then return t end
        return -2 ^ (10 * (t - 1)) * math.sin((t * 10 - 10.75) * (2 * math.pi) / 3)
    end,
    bounce = function(t)
        local n, a = 7.5625, 1 / 2.75
        if t < 1 / a then return n * t * t end
        if t < 2 / a then t = t - 1.5 / a; return n * t * t + 0.75 end
        if t < 2.5 / a then t = t - 2.25 / a; return n * t * t + 0.9375 end
        t = t - 2.625 / a; return n * t * t + 0.984375
    end,
}

local function register(name, fn)
    easings[name .. "In"] = fn
    easings[name .. "Out"] = function(t) return 1 - fn(1 - t) end
    easings[name .. "InOut"] = function(t)
        if t < 0.5 then return fn(t * 2) / 2 end
        return 1 - fn((1 - t) * 2) / 2
    end
    -- 默认使用 Out，UI 过渡观感更顺滑
    easings[name] = easings[name .. "Out"]
end

easings.linear = function(t) return t end
for name, fn in pairs(powFns) do register(name, fn) end
for name, fn in pairs(otherFns) do register(name, fn) end

-- ---------------- 补间 ----------------

local function shallowCopy(v)
    if type(v) == "table" then
        local out = {}
        for i, e in ipairs(v) do out[i] = e end
        return out
    end
    return v
end

-- 创建补间动画
function animate.to(target, props, opts)
    opts = opts or {}
    local tw = {
        target = target,
        props = props,
        from = {},
        t = 0,
        duration = opts.duration or 0.22,
        easing = easings[opts.easing or "cubic"] or easings.cubic,
        onDone = opts.onDone,
    }
    for k, v in pairs(props) do
        tw.from[k] = shallowCopy(target[k])
    end
    table.insert(active, tw)
    return tw
end

-- 停止某个目标上的所有动画
function animate.stop(target)
    for i = #active, 1, -1 do
        if active[i].target == target then
            table.remove(active, i)
        end
    end
end

-- 立即完成某个目标上的所有动画
function animate.finish(target)
    for i = #active, 1, -1 do
        local tw = active[i]
        if tw.target == target then
            for k, v in pairs(tw.props) do
                if type(v) == "table" then
                    tw.target[k] = shallowCopy(v)
                else
                    tw.target[k] = v
                end
            end
            if tw.onDone then tw.onDone() end
            table.remove(active, i)
        end
    end
end

-- 每帧推进
function animate.update(dt)
    for i = #active, 1, -1 do
        local tw = active[i]
        tw.t = tw.t + dt
        local p = math.min(1, tw.t / tw.duration)
        local e = tw.easing(p)
        for k, endv in pairs(tw.props) do
            local startv = tw.from[k]
            if type(endv) == "table" then
                -- 生成新表写回，禁止就地修改 target[k] 的既有表：
                -- 该表可能是主题色等共享引用，就地插值会污染全局颜色
                startv = startv or {}
                local cur = {}
                for j = 1, #endv do
                    cur[j] = (startv[j] or 0) + ((endv[j] or 0) - (startv[j] or 0)) * e
                end
                tw.target[k] = cur
            else
                tw.target[k] = startv + (endv - startv) * e
            end
        end
        if p >= 1 then
            if tw.onDone then tw.onDone() end
            table.remove(active, i)
        end
    end
end

return animate
