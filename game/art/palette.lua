--[[
    game/art/palette.lua —— 受限调色板

    程序化美术最容易翻车的地方不是形状，是颜色：每把武器、每只怪单独挑色，
    几百个物件摆在一起就会脏。所以这里只允许从「材质色」派生颜色：

        每个材质一条色相轨道，派生 dark / base / light / edge / glow 五阶
        派生规则固定（朝黑混 / 朝白混 / 朝高饱和混），不手工调

    这样任意数量、任意组合的程序化物件，色域是收敛的。
    想换整体色调（比如血月、熔核、深渊），只改 ambient 一个数，全局跟着变。

    颜色一律返回 0~1 的 {r,g,b}，与 love.graphics.setColor 一致。
]]

local P = {}

local function hex(s)
    local r = tonumber(s:sub(2, 3), 16) / 255
    local g = tonumber(s:sub(4, 5), 16) / 255
    local b = tonumber(s:sub(6, 7), 16) / 255
    return { r, g, b }
end

-- 朝白混（t>0）或朝黑混（t<0），t 取 -1~1
local function toward(c, t)
    if t >= 0 then
        return { c[1] + (1 - c[1]) * t, c[2] + (1 - c[2]) * t, c[3] + (1 - c[3]) * t }
    end
    local k = 1 + t
    return { c[1] * k, c[2] * k, c[3] * k }
end

local function clamp01(v)
    if v < 0 then return 0 elseif v > 1 then return 1 else return v end
end

-- 提饱和：把颜色往它最亮的通道推，用于发光与宝石
-- 必须夹紧到 0~1：超出后写进 uint8 会回绕，橙红会变成青色
local function saturate(c, t)
    local mx = math.max(c[1], c[2], c[3])
    if mx <= 0 then return { c[1], c[2], c[3] } end
    return {
        clamp01(c[1] + (c[1] / mx - c[1]) * t),
        clamp01(c[2] + (c[2] / mx - c[2]) * t),
        clamp01(c[3] + (c[3] / mx - c[3]) * t),
    }
end

-- 材质表：key 就是游戏里材料的 id，一一对应设计文档 6.2 的材料分层
local RAW = {
    -- 9 种基础材料
    wood    = "#8a5a34",
    stone   = "#6b7078",
    copper  = "#c07a3c",
    iron    = "#9aa4b2",
    crystal = "#4fc4dd",
    rot     = "#7fb04a",
    ember   = "#e0603a",
    void    = "#9a6ae0",
    endgame = "#f0cf60",

    -- 生物与角色
    flesh   = "#e0a888",
    bone    = "#ded6c0",
    cloth   = "#3f6fa8",
    leather = "#7a5230",
    chitin  = "#8d5a4a",
    slime   = "#63c07a",
    blood   = "#b83040",

    -- 界面与通用
    ink     = "#14161c",
    smoke   = "#2a2f3a",
    sun     = "#ffd27a",
    ice     = "#a8e0f0",
}

-- 五阶派生。系数刻意做窄（0.62 ~ 1.35），避免出现刺眼的极端色
local STEPS = {
    dark  = -0.52,
    base  = 0,
    light = 0.28,
    edge  = -0.78,   -- 描边
    glow  = 0.10,    -- 发光核心
}

local cache = {}
local ambient = 1.0   -- 全局亮度：血月 0.85、熔核 1.1、深渊 0.92

function P.material(key)
    local hit = cache[key]
    if hit then return hit end
    local base = RAW[key]
    if not base then base = RAW.stone end
    base = hex(base)

    local m = {}
    for name, t in pairs(STEPS) do
        local c = toward(base, t)
        if name == "glow" then c = saturate(c, 1.15) end
        m[name] = c
    end
    m.base = base
    cache[key] = m
    return m
end

-- 取色：P.get("iron", "dark") → {r,g,b}
function P.get(key, step)
    local m = P.material(key)
    local c = m[step or "base"]
    local a = ambient
    if a ~= 1 then
        return { c[1] * a, c[2] * a, c[3] * a }
    end
    return c
end

-- 带透明度地取色，省掉调用处每次手写 unpack
function P.rgba(key, step, alpha)
    local c = P.get(key, step)
    return c[1], c[2], c[3], alpha or 1
end

function P.setAmbient(a)
    ambient = a
end

function P.getAmbient()
    return ambient
end

-- 色相旋转：用于精英怪/异变体的同族不同色（保持明度与饱和，只换色相）
function P.rotate(key, deg)
    local c = P.material(key).base
    local a = math.rad(deg or 0)
    local cs, sn = math.cos(a), math.sin(a)
    -- YIQ 近似旋转，比 RGB-HSL 往返便宜且不会在灰阶处奇异
    local y = 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
    local i = 0.596 * c[1] - 0.274 * c[2] - 0.322 * c[3]
    local q = 0.211 * c[1] - 0.523 * c[2] + 0.312 * c[3]
    local i2 = i * cs - q * sn
    local q2 = i * sn + q * cs
    local r = y + 0.956 * i2 + 0.621 * q2
    local g = y - 0.272 * i2 - 0.647 * q2
    local b = y - 1.106 * i2 + 1.703 * q2
    local function clamp(v) if v < 0 then return 0 elseif v > 1 then return 1 else return v end end
    return { clamp(r), clamp(g), clamp(b) }
end

P.hex = hex

return P
