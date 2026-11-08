--[[
    game/data/recipes.lua —— 消耗品配方

    M1 这里还放着四条武器配方。M2 把它们全删了，原因不是「功能挪走了」，
    而是**两条并存的路线会互相污染**：

        如果既有「点一下得到铁剑」，又有「选部件造铁剑」，
        玩家会永远用前者，因为前者更便宜也更快。
        于是部件系统就变成装饰，锻造 UI 也就没人打开。

    所以现在的分工很硬：
        武器  → 只能锻造（game/core/forge.lua）
        消耗品 → 只能按配方做（这个文件）

    消耗品保留配方形态是合理的：口粮不需要「选柄选芯」，
    它就是一个「2 个甲壳换 40 血」的兑换，加选择反而是噪音。

    配方结构做成数据而不是函数：以后要加工作台等级、解锁条件、配方书 UI，
    都是往表里加字段，不用改逻辑。
]]

local R = {}

-- 顺序就是 UI 里的显示顺序
R.list = {
    {
        id = "ration",
        name = "洞穴口粮",
        desc = "回复 40 生命。便宜，随处可做",
        cost = { chitin = 2, membrane = 1 },
        -- effect 是给 Game 的指令，具体怎么应用由 Game 解释，
        -- 这样数据层不需要知道玩家对象长什么样
        effect = { kind = "heal", amount = 40 },
    },
    {
        id = "elixir",
        name = "蚀液药",
        desc = "回复 65 生命。毒囊换的，深层的保命件",
        cost = { bile = 3, crystal = 1 },
        effect = { kind = "heal", amount = 65 },
    },
    {
        id = "hearth",
        name = "火种",
        desc = "回复 100 生命。要矿核碎屑，打 Boss 前备一份",
        cost = { core_stone = 2, chitin = 3 },
        effect = { kind = "heal", amount = 100 },
    },
}

R.byId = {}
for _, r in ipairs(R.list) do
    R.byId[r.id] = r
end

function R.get(id)
    return R.byId[id]
end

-- 玩家现在能不能做这条
function R.canCraft(recipe, inv)
    for key, n in pairs(recipe.cost) do
        if inv:count(key) < n then return false end
    end
    return true
end

-- 缺什么，用于 UI 提示
function R.missing(recipe, inv)
    local out = {}
    for key, n in pairs(recipe.cost) do
        local have = inv:count(key)
        if have < n then
            out[#out + 1] = string.format("%s %d/%d", key, have, n)
        end
    end
    table.sort(out)
    return table.concat(out, " ")
end

return R
