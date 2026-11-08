--[[
    game/data/parts.lua —— 武器部件（柄 / 芯）

    M2 把武器拆成三件事：刃（品类 + 材质）、柄、芯。
    拆的理由不是「内容量」，是**让玩家的取舍发生在不同维度上**：

        刃   决定「打多重」       → 挖矿换来的（铜→铁→晶）
        柄   决定「打多快、多稳」 → 打怪换来的（木头→骨→铁→虚空）
        芯   决定「打中之后怎样」 → 三种材料交叉换来的

    如果柄也加伤害、芯也加伤害，三条线就退化成一条，玩家只会照着总数比。
    所以这里的约束写死：
        柄**几乎不加伤害**（1.00~1.20，勉强够形成偏好）
        芯**完全不加伤害**，只换元素状态

    芯的四种元素对应四种「敌人处理方式」，这是有意的：
        ember 燃烧   持续伤害，用来磨血厚的目标（石傀儡、Boss）
        frost 霜蚀   减速，用来处理贴脸的快怪（矿虫）
        venom 剧毒   长时持续但**不致死**，用来压血线、把收尾交给玩家
        arc   雷痕   易伤，用来配合下一发 —— 它要的是节奏而不是数值
]]

local P = {}

-- ---------------------------------------------------------------- 柄

P.hilts = {
    {
        id = "wood", name = "木柄", tier = 1,
        -- 木柄是整张表的 1.0 基准。所有数值都以它为单位相乘，
        -- 所以改平衡时只要动别的柄，开局手感不会被牵动
        dmg = 1.00, poise = 1.00,
        windup = 1.00, recovery = 1.00,
        knock = 1.00, reach = 0,
        desc = "标准柄。轻、便宜，没有任何加成",
        cost = { wood = 2 },
    },
    {
        id = "bone", name = "骨柄", tier = 2,
        -- 骨柄是「快」的一端：前后摇都缩，代价是击退弱
        dmg = 1.00, poise = 0.95,
        windup = 0.90, recovery = 0.92,
        knock = 0.86, reach = 0,
        desc = "前后摇各缩一成，击退变弱。削韧型武器配它很舒服",
        cost = { chitin = 3, wood = 1 },
    },
    {
        id = "iron", name = "铁柄", tier = 3,
        -- 铁柄是「稳」的一端：更慢，但击退与破韧都上去了
        dmg = 1.10, poise = 1.20,
        windup = 1.06, recovery = 1.10,
        knock = 1.30, reach = 0,
        desc = "慢半拍，但击退 +30%、破韧 +20%。打石傀儡的标配",
        cost = { iron = 3 },
    },
    {
        id = "void", name = "虚空柄", tier = 5,
        -- 虚空柄同时给速度和重量，但材料要 Boss 之后才有，
        -- 它是「后期把所有线都收拢」的那一档，不是中期的最优解
        dmg = 1.20, poise = 1.30,
        windup = 1.00, recovery = 1.00,
        knock = 1.15, reach = 2,
        desc = "又稳又快，还长两像素。但它只掉在石喉身上",
        cost = { core_stone = 4, crystal = 2 },
    },
}

-- ---------------------------------------------------------------- 芯

P.cores = {
    {
        id = "none", name = "无芯", tier = 0,
        element = nil,
        art = "crystal",
        desc = "什么都不加。便宜、可靠、没有意外",
        cost = {},
    },
    {
        id = "ember", name = "炎芯", tier = 1,
        element = "burn", lv = 1,
        art = "ember",
        desc = "命中附带燃烧：3 秒内再掉约 9 点。磨血用的",
        cost = { copper = 2, wood = 1 },
    },
    {
        id = "frost", name = "霜芯", tier = 1,
        element = "chill", lv = 1,
        art = "ice",
        desc = "命中附带霜蚀：移速降到 55%，持续 2.2 秒",
        cost = { crystal = 1, copper = 1 },
    },
    {
        id = "venom", name = "毒芯", tier = 2,
        element = "venom", lv = 1,
        art = "rot",
        desc = "命中附带剧毒：4 秒持续掉血，但**不会致死**",
        cost = { bile = 2, chitin = 1 },
    },
    {
        id = "arc", name = "雷芯", tier = 2,
        element = "shock", lv = 1,
        art = "crystal",
        desc = "命中挂雷痕：下一次受击 +30%，然后消失。要配得上节奏",
        cost = { membrane = 2, iron = 1 },
    },
}

-- ---------------------------------------------------------------- 查询

local BY = { hilt = {}, core = {} }
for _, h in ipairs(P.hilts) do BY.hilt[h.id] = h end
for _, c in ipairs(P.cores) do BY.core[c.id] = c end

function P.hilt(id)
    return BY.hilt[id or "wood"] or BY.hilt.wood
end

function P.core(id)
    return BY.core[id or "none"] or BY.core.none
end

-- 组装的材料总消耗：刃材 + 柄 + 芯。返回一张 cost 表
function P.costOf(spec, bladeCost)
    spec = spec or {}
    local out = {}
    local function merge(t)
        for k, n in pairs(t or {}) do
            out[k] = (out[k] or 0) + n
        end
    end
    merge(bladeCost)
    merge(P.hilt(spec.hilt).cost)
    merge(P.core(spec.core).cost)
    return out
end

return P
