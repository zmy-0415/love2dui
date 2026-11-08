--[[
    game/core/tiles.lua —— 方块定义表

    世界是一张 id 网格，这个文件是 id 的全部含义。所有「这块东西能不能站、
    挖得动挖不动、挖下来掉什么、长什么样」都只在这里定义一次，
    其它模块一律查表，不许散落 if-else。

    颜色说明：地形现在走「色块」路线（M0/M1 只要分层能一眼分辨），
    到 M3 会整体换成瓦片贴图。所以这里直接写十六进制色，不经过
    game/art/palette（那是角色与武器的色域，和地形不是一回事）。
    但派生规则照抄：dark / base / light 三阶用同一组系数，保证画面协调。
]]

local T = {}

-- 与 palette 相同的阶系数，只是范围更宽一点（地形需要更强的明暗对比才分得清层）
local function scale(c, k)
    local r = c[1] * k
    local g = c[2] * k
    local b = c[3] * k
    if r > 1 then r = 1 end
    if g > 1 then g = 1 end
    if b > 1 then b = 1 end
    return { r, g, b }
end

local function hex(s)
    return {
        tonumber(s:sub(2, 3), 16) / 255,
        tonumber(s:sub(4, 5), 16) / 255,
        tonumber(s:sub(6, 7), 16) / 255,
    }
end

-- 定义。字段含义：
--   solid  是否阻挡移动
--   hard   基准挖掘秒数（除以工具效率后得到实际时间）
--   tier   需要的镐等级，0 = 徒手可挖
--   drop   挖掉后掉落物 key，nil 表示掉自己，false 表示什么都不掉
--   glow   自发光强度 0~1，用于矿石与岩浆
--   bg     背景方块：不碰撞、不可挖，只用来画洞壁
local DEFS = {
    { key = "air",     name = "空气",     solid = false, hard = 0,    tier = 0, drop = false },
    { key = "grass",   name = "草皮",     solid = true,  hard = 0.16, tier = 0, col = "#4f7a3a", drop = "dirt" },
    { key = "dirt",    name = "泥土",     solid = true,  hard = 0.20, tier = 0, col = "#6b4f34" },
    { key = "sand",    name = "砂砾",     solid = true,  hard = 0.14, tier = 0, col = "#c0ad78" },
    { key = "stone",   name = "岩石",     solid = true,  hard = 0.55, tier = 1, col = "#5a616e" },
    { key = "deep",    name = "深岩",     solid = true,  hard = 0.95, tier = 2, col = "#454b58" },
    { key = "bedrock", name = "基岩",     solid = true,  hard = -1,   tier = 9, col = "#262a32" },
    { key = "wood",    name = "树干",     solid = false, hard = 0.35, tier = 0, col = "#6b4526" },
    { key = "leaves",  name = "枝叶",     solid = false, hard = 0.10, tier = 0, col = "#3f6b34", drop = "fiber" },

    -- 矿脉。glow 只给晶簇，铜和铁靠颜色区分，否则洞里到处发光反而看不清路
    { key = "copper",  name = "铜矿",     solid = true,  hard = 0.75, tier = 1, col = "#c07a3c", drop = "copper" },
    { key = "iron",    name = "铁矿",     solid = true,  hard = 1.10, tier = 1, col = "#9aa4b2", drop = "iron" },
    { key = "crystal", name = "晶簇",     solid = true,  hard = 1.60, tier = 2, col = "#4fc4dd", drop = "crystal", glow = 0.55 },

    -- 触发方块：挖掉它会唤醒石喉。做成方块而不是触发器脚本，
    -- 是因为「挖到不该挖的东西」比「走到不该走的地方」更符合这个游戏的动词
    { key = "ore_core", name = "脉动矿核", solid = true, hard = 2.4, tier = 2,
      col = "#d05070", drop = "crystal", glow = 0.9 },

    -- 背景层
    { key = "bg_dirt",   name = "土壁",   solid = false, hard = 0, tier = 0, drop = false, bg = true, col = "#3d2d1e" },
    { key = "bg_stone",  name = "岩壁",   solid = false, hard = 0, tier = 0, drop = false, bg = true, col = "#2e333d" },
    { key = "bg_deep",   name = "深岩壁", solid = false, hard = 0, tier = 0, drop = false, bg = true, col = "#232730" },
}

T.defs = {}
T.byKey = {}
for i, d in ipairs(DEFS) do
    local id = i - 1
    d.id = id
    if d.col then
        local c = hex(d.col)
        d.base = c
        d.dark = scale(c, 0.66)
        d.light = scale(c, 1.30)
        d.edge = scale(c, 0.48)
    end
    d.solid = d.solid and true or false
    d.bg = d.bg or false
    d.glow = d.glow or 0
    d.drop = (d.drop == nil) and d.key or d.drop
    T.defs[id] = d
    T.byKey[d.key] = d
end

T.AIR = T.byKey.air.id

function T.get(id)
    return T.defs[id] or T.defs[0]
end

function T.id(key)
    local d = T.byKey[key]
    if not d then error("未知方块: " .. tostring(key)) end
    return d.id
end

-- 这块 id 是否阻挡移动
function T.solid(id)
    local d = T.defs[id]
    return d ~= nil and d.solid
end

-- 挖得动吗（hard < 0 表示永久方块）
function T.mineable(id)
    local d = T.defs[id]
    return d ~= nil and d.hard > 0 and not d.bg
end

-- 给定镐等级，这块挖得动吗
function T.canMine(id, tier)
    local d = T.defs[id]
    if not d or d.bg or d.hard <= 0 then return false end
    return (tier or 0) >= d.tier
end

-- 实际挖掘秒数 = 硬度 / 工具效率
function T.mineTime(id, efficiency)
    local d = T.defs[id]
    if not d or d.hard <= 0 then return math.huge end
    return d.hard / math.max(0.05, efficiency or 1)
end

return T
