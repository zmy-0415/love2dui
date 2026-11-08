--[[
    game/data/recipes.lua —— 合成配方

    M1 只保留「挖到的东西能变成战斗力」这一条主线的配方。
    设计文档里 120 条配方的量放在 M2，现在多一条都是负担。

    配方结构刻意做成数据而不是函数：以后要加工作台等级、解锁条件、
    配方书 UI，都是往表里加字段，不用改逻辑。
]]

local R = {}

-- 顺序就是 UI 里的显示顺序
R.list = {
    {
        id = "copper_sword",
        name = "铜剑",
        desc = "比初始木剑快一点，伤害 13 → 16",
        cost = { copper = 3, wood = 2 },
        -- effect 是给 Game 的指令，具体怎么应用由 Game 解释，
        -- 这样数据层不需要知道武器系统长什么样
        effect = { kind = "weapon", weapon = "sword", material = "copper", tier = 1 },
    },
    {
        id = "iron_sword",
        name = "铁剑",
        desc = "伤害 16 → 18，刃更亮",
        cost = { iron = 3, wood = 1 },
        effect = { kind = "weapon", weapon = "sword", material = "iron", tier = 2 },
    },
    {
        id = "iron_axe",
        name = "铁斧",
        desc = "慢但破韧 30，专治石傀儡",
        cost = { iron = 4, wood = 2 },
        effect = { kind = "weapon", weapon = "axe", material = "iron", tier = 2 },
    },
    {
        id = "crystal_blade",
        name = "晶刃",
        desc = "伤害 24，打 Boss 的答案",
        cost = { crystal = 3, iron = 2 },
        effect = { kind = "weapon", weapon = "sword", material = "crystal", tier = 3 },
    },
    {
        id = "ration",
        name = "洞穴口粮",
        desc = "回复 40 生命",
        cost = { chitin = 2, membrane = 1 },
        effect = { kind = "heal", amount = 40 },
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
