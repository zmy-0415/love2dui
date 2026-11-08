--[[
    game/core/inventory.lua —— 背包

    M1 只需要「挖到东西能捡、能查数量、合成时能扣」。所以不做格子拖拽、
    不做排序、不做装备槽——那些等有 UI 需求了再说。

    但有三件事现在就要做对：
      1. 堆叠上限按物品区分（矿 99、方块 999），别全用一个数
      2. add 返回「没装下的数量」，拾取逻辑据此决定掉落物是否消失
      3. 顺序稳定：新物品追加到第一个空位，不重排，否则玩家会觉得物品在跳
]]

local Inv = {}
Inv.__index = Inv

-- 每类物品的堆叠上限
local STACK = {
    copper = 999, iron = 999, crystal = 999,
    dirt = 999, stone = 999, wood = 999, fiber = 999,
    default = 99,
}

function Inv.new(slots)
    local self = setmetatable({ slots = {}, size = slots or 40 }, Inv)
    for i = 1, self.size do self.slots[i] = nil end
    return self
end

function Inv:stackMax(key)
    return STACK[key] or STACK.default
end

-- 加入物品，返回没放下的数量（0 表示全部收下）
function Inv:add(key, n)
    n = n or 1
    local max = self:stackMax(key)

    -- 先补已有堆
    for i = 1, self.size do
        local s = self.slots[i]
        if s and s.key == key and s.n < max then
            local room = max - s.n
            local take = math.min(room, n)
            s.n = s.n + take
            n = n - take
            if n <= 0 then return 0 end
        end
    end

    -- 再开新槽
    for i = 1, self.size do
        if not self.slots[i] then
            local take = math.min(max, n)
            self.slots[i] = { key = key, n = take }
            n = n - take
            if n <= 0 then return 0 end
        end
    end

    return n
end

function Inv:count(key)
    local total = 0
    for i = 1, self.size do
        local s = self.slots[i]
        if s and s.key == key then total = total + s.n end
    end
    return total
end

-- 扣除，返回是否扣成功。不足则一点不扣（不做部分扣除，避免合成到一半材料消失）
function Inv:take(key, n)
    if self:count(key) < n then return false end
    for i = 1, self.size do
        local s = self.slots[i]
        if s and s.key == key then
            local use = math.min(s.n, n)
            s.n = s.n - use
            n = n - use
            if s.n <= 0 then self.slots[i] = nil end
            if n <= 0 then return true end
        end
    end
    return true
end

function Inv:isFull()
    for i = 1, self.size do
        if not self.slots[i] then return false end
    end
    return true
end

-- 已用槽数，HUD 显示用
function Inv:used()
    local n = 0
    for i = 1, self.size do
        if self.slots[i] then n = n + 1 end
    end
    return n
end

return Inv
