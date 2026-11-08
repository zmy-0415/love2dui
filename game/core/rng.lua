--[[
    game/art/rng.lua —— 确定性伪随机

    程序化美术必须可复现：同一把武器、同一只怪，无论什么时候、在哪台机器上
    生成，长相都要一模一样，否则「这把剑很好看，我想留着」这件事就不成立，
    存档也没法只存一个种子。

    所以这里不用 math.random（全局状态，别的模块一调用就错位），
    而是自带状态的小型 xorshift32：快、够随机、状态只有两个 32 位数。
]]

local Rng = {}
Rng.__index = Rng

local band = bit.band
local bxor = bit.bxor
local lshift = bit.lshift
local rshift = bit.rshift

function Rng.new(seed)
    seed = math.floor(tonumber(seed) or 1)
    local self = setmetatable({}, Rng)
    -- 0 会让 xorshift 卡死，兜一个非零种子
    self.s = band(seed, 0x7fffffff)
    if self.s == 0 then self.s = 0x9e3779b9 end
    -- 预热几轮，避免相近种子产生相近的前几个值（武器外观会撞脸）
    for _ = 1, 6 do self:next() end
    return self
end

-- 把任意长度的数字/字符串混成一个 32 位种子（FNV-1a）
function Rng.hash(...)
    local h = 2166136261
    local n = select("#", ...)
    for i = 1, n do
        local v = select(i, ...)
        local s = tostring(v)
        for j = 1, #s do
            h = bxor(h, s:byte(j))
            h = band(h * 16777619, 0xffffffff)
        end
        h = bxor(h, 0x9e3779b9)
    end
    return h
end

function Rng:next()
    local x = self.s
    x = bxor(x, lshift(x, 13))
    x = bxor(x, rshift(x, 17))
    x = bxor(x, lshift(x, 5))
    x = band(x, 0xffffffff)
    self.s = x
    return x
end

-- [0,1)
-- xorshift 的输出是 32 位无符号，但 LuaJIT 的位运算按有符号整数返回，
-- 所以这里先归一化到 0~2^32-1，否则 unit() 会给出负数。
function Rng:u32()
    local v = self.s
    if v < 0 then v = v + 4294967296 end
    return v
end

function Rng:unit()
    return self:u32() / 4294967296
end

-- [a,b)
function Rng:range(a, b)
    return a + self:unit() * (b - a)
end

-- [a,b] 整数
function Rng:int(a, b)
    if b < a then a, b = b, a end
    return a + self:next() % (b - a + 1)
end

function Rng:chance(p)
    return self:unit() < p
end

function Rng:pick(list)
    if #list == 0 then return nil end
    return list[self:int(1, #list)]
end

-- 带权挑选：weights 与 list 等长，返回元素与下标
function Rng:weighted(list, weights)
    local total = 0
    for i = 1, #list do total = total + (weights[i] or 1) end
    local r = self:unit() * total
    for i = 1, #list do
        r = r - (weights[i] or 1)
        if r <= 0 then return list[i], i end
    end
    return list[#list], #list
end

-- 正态分布（Box-Muller），做自然抖动时比均匀分布好看
function Rng:gauss(mean, sd)
    local u1 = math.max(1e-7, self:unit())
    local u2 = self:unit()
    local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    return mean + z * (sd or 1)
end

-- 从二进制派生：做「第 n 个变体」这类取色很方便
function Rng:bit(n)
    return band(rshift(self:next(), n or 0), 1) == 1
end

return Rng
