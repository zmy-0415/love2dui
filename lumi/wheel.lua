--[[
    wheel.lua —— 滚轮位移与惯性推进（Scroll / Table / Tree / Editor 共用）

    旧实现把滚轮事件整体折成「速度」：velocity += y * -100，再由 onUpdate
    按 5/s 的速率衰减。位移等于初速除以衰减率，也就是 100 / 5 = 20px——
    一格滚轮只走一行多；而且第一帧只移动 1.67px，要等好几帧才走完，
    用起来又慢又拖手。

    现在拆成两段：
    · 立即位移：一格滚轮当帧就走出 STEP 像素，跟手、无延迟；
    · 惯性尾巴：再补一点初速做收尾，总量 = STEP * (1 + INERTIA)，
      快速连滚时有滑动感，但不会像纯惯性模型那样「先慢后快」。
]]

local Wheel = {}

-- 一格滚轮（y = ±1）的位移像素：约 3 行正文，与桌面系统默认一致
Wheel.STEP = 64
-- 惯性尾巴占 STEP 的比例（0 表示完全无惯性）
Wheel.INERTIA = 0.3
-- 惯性衰减速率（1/s）：越大停得越快
Wheel.DECAY = 12
-- 低于此速度直接归零（px/s），避免无限小尾巴
Wheel.MIN_VELOCITY = 2

--- 单个滚动控件的每格步长：props.wheelStep 优先，否则用模块默认
--  改全局手感：require("lumi").wheel.STEP = 96
function Wheel.stepOf(node)
    local p = node.props
    if p and p.wheelStep then return p.wheelStep end
    return Wheel.STEP
end

--- 处理一次滚轮输入（y 为 LÖVE 的纵向滚动量，正值向上）
function Wheel.scroll(node, y)
    if not y or y == 0 then return end
    local step = Wheel.stepOf(node)
    local before = node.scrollY
    -- 立即位移：滚轮一格就是一格，不再等惯性积分
    node:setScroll(before - y * step)
    if node.scrollY == before then
        -- 已经在边界且继续往边界方向滚：清掉旧惯性，
        -- 否则反向滚的时候要先「卸力」，会有明显迟滞
        node.velocity = 0
        return
    end
    -- 尾巴距离 = 初速 / DECAY
    node.velocity = -y * step * Wheel.INERTIA * Wheel.DECAY
end

--- 每帧推进惯性（指数衰减用解析积分，保证不同帧率下滑行距离一致）
function Wheel.update(node, dt)
    local v = node.velocity or 0
    if v == 0 then return end
    if math.abs(v) < Wheel.MIN_VELOCITY then
        node.velocity = 0
        return
    end
    local k = Wheel.DECAY
    local decay = math.exp(-k * dt)
    local before = node.scrollY
    -- ∫v·e^(-k·t)dt 在 [0, dt] 上的精确值：v·(1 - e^(-k·dt)) / k
    node:setScroll(before + v * (1 - decay) / k)
    if node.scrollY == before then
        node.velocity = 0
        return
    end
    node.velocity = v * decay
end

return Wheel
