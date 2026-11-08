--[[
    game/data/weapons.lua —— 武器帧数据

    这个表就是设计文档里「手感调参成本高」的解药：所有能影响手感的时间与距离
    都外置在这里，改一个数字就能试，不用翻代码。

    三段式结构（动作游戏的标准做法）：
        windup  前摇。抬刀蓄力，玩家在这段时间里还能取消，代价是被打断
        active  判定。只有这一段会造成伤害。这一段越短，武器越"重"
        recovery 后摇。收势，不能动。这一段的长度决定了"一次失误有多贵"

    为什么不用「攻击动画播完就造成伤害」：那样命中时刻由动画决定，
    玩家永远学不会「提前量」。帧数据独立出来之后，判定窗口可以调到
    比动画长，玩家看着差一点也能打中，手感立刻好一档。

    数值单位：秒 / 像素 / 度。
]]

local W = {}

-- 材质系数：同一种武器，换材质只改伤害和少量速度，不改动作结构。
-- 这样玩家的肌肉记忆在换装后仍然成立，这是「刷装备」能持续的前提。
W.materials = {
    wood    = { dmg = 0.72, poise = 0.7 },
    copper  = { dmg = 1.00, poise = 1.0 },
    iron    = { dmg = 1.38, poise = 1.2 },
    crystal = { dmg = 1.82, poise = 1.5 },
    void    = { dmg = 2.40, poise = 1.9 },
}

W.types = {
    -- 剑：起手快、判定短、后摇中等。全能，是玩家的默认答案
    sword = {
        name = "剑",
        windup = 0.085,
        active = 0.070,
        recovery = 0.200,
        damage = 13,
        reach = 34,        -- 从身体中心往前的判定长度
        back = 6,          -- 判定框往后延伸（贴身也能打到）
        halfH = 22,        -- 判定的上下半高。比视觉宽一圈，容错
        poise = 14,
        knock = 95,
        hitstop = 0.045,
        shake = 1.2,
    },

    -- 斧：慢、重、破韧高。打石傀儡这类高韧性目标比剑快一倍
    axe = {
        name = "斧",
        windup = 0.165,
        active = 0.085,
        recovery = 0.270,
        damage = 24,
        reach = 30,
        back = 4,
        halfH = 28,
        poise = 30,
        knock = 165,
        hitstop = 0.075,
        shake = 2.4,
    },
}

-- 攻击总时长
function W.total(kind)
    local d = W.types[kind]
    if not d then return 0 end
    return d.windup + d.active + d.recovery
end

function W.get(kind)
    return W.types[kind]
end

-- 结算伤害：基础值 × 材质系数
function W.damage(kind, material)
    local d = W.types[kind]
    if not d then return 0 end
    local m = W.materials[material or "copper"] or W.materials.copper
    return d.damage * m.dmg
end

return W
