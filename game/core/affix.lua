--[[
    game/core/affix.lua —— 词条

    词条是「刷」的发动机。它要解决一个具体问题：
    如果一把铁剑永远等于另一把铁剑，玩家打到第二把就没有任何理由捡起来。
    词条让同一把铁剑有身份——「这把是锋利+吸血」，「那把是疾风+长臂」。

    三条设计约束，写在这里是为了以后加词条时别破坏它们：

      1. 每条词条必须是**可感知的**。
         「+3% 伤害」在 16px 的画面里玩家永远感觉不到，等于没有。
         所以数值都开到 12%~25% 这个量级。

      2. 词条不能互相吃掉。
         如果五个词条都在加伤害，它们实际是一个词条。
         现在伤害类只有 2 条（锋利/残忍），其余分别管速度、范围、续航、元素。

      3. 随机必须可复现。
         用种子驱动（同一份存档读两次得到同样的词条），不碰 math.random。
         否则「我这把好剑」在重启后就变了，刷装备的意义直接消失。

    词条挂在 W.resolve(spec) 算出来的 r 上，靠改 r 的字段生效。
    所以加一条新词条不需要改任何其它文件——只要在这里加一个 apply。
]]

local Rng = require("game.core.rng")

local A = {}

-- 权重决定稀有度：10 常见、4 少见、2 稀有
A.list = {
    {
        id = "sharp", name = "锋利", weight = 10,
        desc = "伤害 +18%",
        look = { edge = 0.9 },
        apply = function(r) r.damage = r.damage * 1.18 end,
    },
    {
        id = "swift", name = "疾风", weight = 10,
        desc = "后摇 -16%",
        apply = function(r) r.recovery = r.recovery * 0.84 end,
    },
    {
        id = "heavy", name = "沉重", weight = 8,
        desc = "破韧 +25%",
        look = { rim = true },
        apply = function(r) r.poise = r.poise * 1.25 end,
    },
    {
        id = "long", name = "长臂", weight = 8,
        desc = "射程 +8",
        apply = function(r) r.reach = r.reach + 8 end,
    },
    {
        id = "keen", name = "锐利", weight = 6,
        desc = "暴击率 +12%（暴击 ×1.7）",
        look = { teeth = true },
        apply = function(r) r.crit = r.crit + 0.12 end,
    },
    {
        id = "steady", name = "稳固", weight = 6,
        desc = "出刀机动 +0.15（能边跑边打）",
        apply = function(r) r.mobility = math.min(1, r.mobility + 0.15) end,
    },
    {
        id = "splitter", name = "裂口", weight = 6,
        desc = "群体衰减改善（第二个目标少掉 10% 伤害）",
        apply = function(r) r.falloff = math.min(1, r.falloff + 0.10) end,
    },
    {
        id = "vamp", name = "吸血", weight = 4,
        desc = "每次命中回复 2 点生命",
        look = { glow = "blood" },
        apply = function(r) r.leech = r.leech + 2 end,
    },
    {
        id = "reaper", name = "收割", weight = 4,
        desc = "击杀回复 5 点生命",
        look = { glow = "blood" },
        apply = function(r) r.killHeal = (r.killHeal or 0) + 5 end,
    },
    {
        id = "brutal", name = "残忍", weight = 4,
        desc = "对硬直中的目标伤害 +25%",
        apply = function(r) r.staggerBonus = (r.staggerBonus or 0) + 0.25 end,
    },
    {
        id = "kindle", name = "引燃", weight = 2,
        desc = "元素等级 +1；无芯时直接附燃烧",
        look = { glow = "ember" },
        apply = function(r)
            if r.element then
                r.elementLv = (r.elementLv or 1) + 1
            else
                r.element = "burn"
                r.elementLv = 1
            end
        end,
    },
    {
        id = "ruin", name = "破城", weight = 2,
        desc = "打 Boss 弱点伤害 +12%",
        look = { glow = "void", edge = 0.8 },
        apply = function(r) r.weakBonus = (r.weakBonus or 0) + 0.12 end,
    },
}

A.byId = {}
for _, a in ipairs(A.list) do A.byId[a.id] = a end

function A.get(id)
    return A.byId[id]
end

-- 视觉装饰：给 game/art/weapon.lua 用，保证「看得见的词条」只有一处定义
function A.look(id)
    local a = A.byId[id]
    return a and a.look
end

function A.desc(id)
    local a = A.byId[id]
    return a and a.desc or ""
end

function A.name(id)
    local a = A.byId[id]
    return a and a.name or id
end

--[[
    滚词条。纯函数：同一个 seed 一定得到同一组 id。
    不重复（同一把武器不会出现两条"锋利"），按权重抽，抽完从池里移出。

    n 由稀有度决定：普通武器 0 条，好武器 2 条。
    调用方如果传 n 大于池子大小，就取满为止。
]]
function A.roll(seed, n)
    n = n or 0
    if n <= 0 then return {} end
    local rng = Rng.new(seed)
    local pool, weights = {}, {}
    for i, a in ipairs(A.list) do
        pool[i] = a
        weights[i] = a.weight
    end

    local out = {}
    for _ = 1, math.min(n, #pool) do
        local chosen, idx = rng:weighted(pool, weights)
        out[#out + 1] = chosen.id
        table.remove(pool, idx)
        table.remove(weights, idx)
    end
    return out
end

return A
