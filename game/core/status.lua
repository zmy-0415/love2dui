--[[
    game/core/status.lua —— 元素状态

    四种元素不是「四种颜色的伤害」，是四种处理敌人的不同手段。
    这条原则决定了每一种都必须有**只有它能做的事**：

        burn  燃烧   持续掉血，且**可以致死**  → 磨高血量目标（石傀儡、Boss）
        venom 剧毒   持续掉血，但**不致死**    → 压血线，把收尾留给玩家
        chill 霜蚀   移速降到 55%              → 处理贴脸的快怪（矿虫）
        shock 雷痕   下一次受击 +30%，然后消失 → 奖励节奏，惩罚乱砍

    「毒不致死」是刻意的：如果毒能杀人，玩家就会砍一刀然后跑开等，
    战斗变成一个计时器。留 1 血，意味着最后一下必须自己打出来。

    为什么 DoT 每 0.5 秒结算一次而不是每帧：
    每帧扣 0.05 点血会让血条一直在跳，读不出「还剩多少」。
    0.5 秒一跳既能读出节奏，又不会让玩家觉得罚站。

    结算顺序固定为 ORDER 而不是 pairs：pairs 的顺序在 Lua 里不保证，
    而「毒留 1 血」的 clamp 依赖当前血量，顺序不同会得到不同结果——
    那存档回放就会对不上。这个细节有断言守着。
]]

local Status = {}

-- 元素定义。per 是每跳的基础伤害，会乘层数
Status.KINDS = {
    burn = {
        name = "燃烧",
        dur = 3.0,
        tickEvery = 0.5,
        per = 1.6,
        color = { 1.00, 0.55, 0.24 },
        short = "燃",
    },
    venom = {
        name = "剧毒",
        dur = 4.0,
        tickEvery = 0.5,
        per = 1.1,
        noKill = true,
        color = { 0.55, 0.85, 0.30 },
        short = "毒",
    },
    chill = {
        name = "霜蚀",
        dur = 2.2,
        slow = 0.55,
        color = { 0.55, 0.86, 1.00 },
        short = "霜",
    },
    shock = {
        name = "雷痕",
        dur = 5.0,
        vuln = 0.30,
        color = { 0.72, 0.78, 1.00 },
        short = "雷",
    },
}

-- 固定结算顺序，保证可复现
local ORDER = { "burn", "venom", "chill", "shock" }

--[[
    施加状态。规则：
      - 层数取「较大值」，不叠加层数（叠层会让两把同元素武器变成四倍伤害）
      - 时间取「较长值」，也就是刷新而不是累加
        这两条一起构成「持续输出才有效」的正反馈，而不是「叠一下就走」
]]
function Status.apply(m, kind, lv)
    local K = Status.KINDS[kind]
    if not K then return false end
    lv = math.max(1, math.floor(lv or 1))
    m.status = m.status or {}
    local s = m.status[kind]
    if not s then
        s = { t = 0, lv = 0, acc = 0 }
        m.status[kind] = s
    end
    if lv > s.lv then s.lv = lv end
    if K.dur > s.t then s.t = K.dur end
    return true
end

--[[
    推进所有状态。返回本帧造成的总持续伤害（由调用方据此判断死亡）。
    直接改 m.hp，不走 mob:hurt —— DoT 不应该触发击退、硬直、无敌帧，
    否则一只被点燃的怪会一直被打断，永远走不到玩家面前。
]]
function Status.update(m, dt)
    if not m.status then return 0 end

    local total = 0
    for i = 1, #ORDER do
        local kind = ORDER[i]
        local s = m.status[kind]
        if s then
            local K = Status.KINDS[kind]
            s.t = s.t - dt

            if K.per then
                s.acc = s.acc + dt
                while s.acc >= K.tickEvery do
                    s.acc = s.acc - K.tickEvery
                    local d = K.per * s.lv
                    if K.noKill then
                        -- 留 1 血：最后一下必须玩家自己打
                        d = math.min(d, math.max(0, m.hp - 1))
                    end
                    if d > 0 then
                        m.hp = m.hp - d
                        total = total + d
                    end
                end
            end

            if s.t <= 0 then m.status[kind] = nil end
        end
    end
    return total
end

-- 移速系数（霜蚀）
function Status.speedMul(m)
    if m.status and m.status.chill then
        return Status.KINDS.chill.slow
    end
    return 1
end

-- 易伤系数（雷痕）。注意这里**不消耗**，消耗要显式调 consume
function Status.vulnMul(m)
    if m.status and m.status.shock then
        return 1 + Status.KINDS.shock.vuln
    end
    return 1
end

-- 受击时调用：雷痕是一次性的，用掉就没了
function Status.consumeShock(m)
    if m.status and m.status.shock then
        m.status.shock = nil
        return true
    end
    return false
end

function Status.clear(m)
    m.status = nil
end

-- 给渲染用：按固定顺序列出还在生效的状态
function Status.active(m)
    if not m.status then return nil end
    local out = {}
    for i = 1, #ORDER do
        local kind = ORDER[i]
        local s = m.status[kind]
        if s then
            out[#out + 1] = {
                kind = kind,
                t = s.t,
                lv = s.lv,
                color = Status.KINDS[kind].color,
                short = Status.KINDS[kind].short,
            }
        end
    end
    if #out == 0 then return nil end
    return out
end

return Status
