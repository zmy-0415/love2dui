--[[
    game/core/forge.lua —— 铁砧

    M1 的合成是「点一条配方，换一把更强的剑」——玩家没有选择，只有升级。
    M2 把它改成组装：

        选刃材（挖来的）  ×  选柄（打怪来的）  ×  选芯（交叉换来的）  ×  选品类

    为什么要让玩家点四次而不是给一张 800 条的配方表：
    配方表把选择变成搜索，玩家会在意念里背最优解；
    逐个选部件把选择变成理解，玩家会记住「长枪要退半步」「镰刀怕单体」。

    词条数量由投入决定（刃档+柄档+芯档），所以：
        中期（铁+骨+炎）只能滚 1 条   → 有词条就值得留
        后期（虚空+虚空+雷）滚 2 条   → 值得反复重铸直到刷到想要的组合

    「重铸」是这套系统里真正让人上头的地方，所以 seed 每次不同但可复现：
    同一个存档点重铸，结果一样；花一次材料重铸，结果不同。
]]

local Rng = require("game.core.rng")
local Weapons = require("game.data.weapons")
local Parts = require("game.data.parts")
local Affix = require("game.core.affix")

local Forge = {}

-- 刃材目录。tier 决定「第几次升级」，cost 决定「要挖多久」
Forge.blades = {
    { id = "wood",    name = "木刃",   tier = 1, cost = { wood = 4 } },
    { id = "copper",  name = "铜刃",   tier = 1, cost = { copper = 4, wood = 1 } },
    { id = "iron",    name = "铁刃",   tier = 2, cost = { iron = 5, wood = 1 } },
    { id = "crystal", name = "晶刃",   tier = 3, cost = { crystal = 4, iron = 2 } },
    { id = "void",    name = "虚空刃", tier = 4, cost = { core_stone = 6, crystal = 2 } },
}

-- 品类目录（顺序即 UI 顺序）
Forge.classes = {
    { id = "sword",  name = "剑",   hint = "全能，起手快" },
    { id = "dagger", name = "匕首", hint = "极快，能边跑边打" },
    { id = "spear",  name = "长枪", hint = "射程 56，但贴身打不到" },
    { id = "sickle", name = "镰刀", hint = "群体，打多只不衰减" },
    { id = "great",  name = "大剑", hint = "宽判定，被围住时开缺口" },
    { id = "axe",    name = "战斧", hint = "破韧最高，专治石傀儡" },
    { id = "hammer", name = "战锤", hint = "击退 270，空了很亏" },
    { id = "bow",    name = "弓",   hint = "远程，但箭会被地形吃掉" },
}

local BLADE_BY_ID = {}
for _, b in ipairs(Forge.blades) do BLADE_BY_ID[b.id] = b end

function Forge.blade(id)
    return BLADE_BY_ID[id or "copper"] or BLADE_BY_ID.copper
end

function Forge.bladeTier(id)
    return Forge.blade(id).tier
end

-- ---------------------------------------------------------------- 成本

-- 刃 + 柄 + 芯 的材料总消耗
function Forge.cost(spec)
    spec = spec or {}
    return Parts.costOf(spec, Forge.blade(spec.bladeMat).cost)
end

-- 缺什么，给 UI 显示
function Forge.missing(spec, inv)
    local out = {}
    for k, n in pairs(Forge.cost(spec)) do
        local have = inv:count(k)
        if have < n then
            out[#out + 1] = string.format("%s %d/%d", k, have, n)
        end
    end
    table.sort(out)
    return table.concat(out, " ")
end

function Forge.canAssemble(spec, inv)
    for k, n in pairs(Forge.cost(spec)) do
        if inv:count(k) < n then return false, Forge.missing(spec, inv) end
    end
    return true
end

-- ---------------------------------------------------------------- 词条

--[[
    能滚几条词条，只看「投入了多少档位」。

    门槛定在 4 和 9 是算过的：
        铜刃(1)+木柄(1)+无芯(0) = 2   → 0 条，开局别指望词条
        铁刃(2)+骨柄(2)+无芯(0) = 4   → 1 条，第一次「值得留」的武器
        晶刃(3)+铁柄(3)+毒芯(2) = 8   → 1 条
        虚空(4)+虚空(5)+雷芯(2) = 11 → 2 条，后期刷词条的区间

    这条规则让「重铸」在后期才有意义：早期武器没有词条位，玩家不会把
    材料浪费在反复重铸一把铜剑上，而是先去挖铁。
]]
function Forge.affixCount(spec)
    spec = spec or {}
    local sum = Forge.bladeTier(spec.bladeMat)
        + Parts.hilt(spec.hilt).tier
        + Parts.core(spec.core).tier
    if sum >= 9 then return 2 end
    if sum >= 4 then return 1 end
    return 0
end

-- ---------------------------------------------------------------- 预览

--[[
    不消耗材料地算出「如果现在锻造，会得到什么」。
    UI 用它显示伤害/前后摇/元素；测试用它断言「换柄确实改了速度」。

    affixes 传 nil 时给 0 条词条的裸数值（预览里词条是未知的，
    所以不应该显示词条加成——否则玩家会以为已经确定了）
]]
function Forge.preview(spec)
    local r = Weapons.resolve({
        class = spec.class or "sword",
        bladeMat = spec.bladeMat or "copper",
        hilt = spec.hilt or "wood",
        core = spec.core or "none",
        hiltTier = Parts.hilt(spec.hilt).tier,
        bladeTier = Forge.bladeTier(spec.bladeMat),
        affixes = {},
    })
    r.cost = Forge.cost(spec)
    r.affixCount = Forge.affixCount(spec)
    r.bladeName = Forge.blade(spec.bladeMat).name
    r.hiltName = Parts.hilt(spec.hilt).name
    r.coreName = Parts.core(spec.core).name
    return r
end

-- ---------------------------------------------------------------- 组装

--[[
    真正消耗材料并换装。返回 ok, err, affixes

    seed 不给时按「世界种子 + 第几次锻造」推，所以：
        - 同一局里第一次锻造的结果是固定的（可复现、可回放、可测试）
        - 每次锻造结果不同（可刷）
    给了 seed 就完全由 seed 决定（测试用）
]]
function Forge.assemble(game, spec, seed)
    spec = spec or {}
    local ok, err = Forge.canAssemble(spec, game.inv)
    if not ok then return false, "材料不足：" .. tostring(err) end

    -- 先扣材料再组装。反过来的话，如果组装抛错材料就白扣了
    for k, n in pairs(Forge.cost(spec)) do
        game.inv:take(k, n)
    end

    game.forgeCount = (game.forgeCount or 0) + 1
    local s = seed or Rng.hash(
        game.world.seed, game.forgeCount,
        spec.class or "sword", spec.bladeMat or "copper",
        spec.hilt or "wood", spec.core or "none")

    local affixes = Affix.roll(s, Forge.affixCount(spec))
    local hilt = Parts.hilt(spec.hilt)
    local core = Parts.core(spec.core)

    local full = {
        class = spec.class or "sword",
        bladeMat = spec.bladeMat or "copper",
        bladeTier = Forge.bladeTier(spec.bladeMat),
        hilt = hilt.id,
        hiltMat = hilt.id,
        hiltTier = hilt.tier,
        core = core.id,
        coreMat = core.art,
        coreTier = core.tier,
        affixes = affixes,
        seed = s,
    }

    game:equip(full)
    game.stats.forged = (game.stats.forged or 0) + 1
    return true, nil, affixes
end

return Forge
