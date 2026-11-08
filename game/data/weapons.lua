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

    M2 的改动只加了一个想法：**判定框的形状本身是玩法**。
    八种武器如果只是伤害数字不同，玩家会永远用最高 DPS 的那把。
    所以这里刻意让每类武器在「打得到哪」和「出刀时能不能动」上分家：

        reach/back/halfH   判定框的三条边，决定「打不打得到」
        mobility           出刀瞬间保留多少横向速度，决定「能不能边跑边打」
        falloff            每多命中一个目标衰减多少，决定「单体还是群体」

    数值单位：秒 / 像素 / 度。
]]

local Parts = require("game.data.parts")
local Affix = require("game.core.affix")

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

--[[
    八品类的差异设计。读这张表时请对照下面四条：
      1. 没有一把在「伤害/速度/范围」三项上都占优，否则其余七把就是装饰
      2. 每把至少有一个明确的场景（矿虫群、石傀儡、Boss 弱点、远程消耗）
      3. 后摇差得足够大，玩家会因为「这一刀空了很亏」而改变站位
      4. mobility 低的武器（战锤 0.20）出刀等于把自己钉住，这是有意的风险
]]
W.types = {
    -- 剑：起手快、判定短、后摇中等。全能，是玩家的默认答案
    sword = {
        name = "剑",
        windup = 0.085, active = 0.070, recovery = 0.200,
        damage = 13,
        reach = 34,        -- 从身体中心往前的判定长度
        back = 6,          -- 判定框往后延伸（贴身也能打到）
        halfH = 22,        -- 判定的上下半高。比视觉宽一圈，容错
        poise = 14,
        knock = 95,
        hitstop = 0.045,
        shake = 1.2,
        mobility = 0.35,   -- 出刀时保留的横向速度比例
        falloff = 0.88,    -- 第二个目标起每多一个的伤害系数
    },

    -- 大剑：慢、宽、破韧高。挥一次覆盖整个身位，适合被围住时开缺口
    great = {
        name = "大剑",
        windup = 0.190, active = 0.095, recovery = 0.290,
        damage = 30,
        reach = 40, back = 4, halfH = 30,
        poise = 34,
        knock = 195,
        hitstop = 0.085,
        shake = 2.8,
        mobility = 0.25,
        falloff = 0.80,
    },

    -- 战斧：破韧最高。打石傀儡这类高韧性目标，斧的效率是剑的两倍以上
    axe = {
        name = "战斧",
        windup = 0.165, active = 0.085, recovery = 0.270,
        damage = 24,
        reach = 30, back = 4, halfH = 28,
        poise = 40,
        knock = 210,
        hitstop = 0.075,
        shake = 2.4,
        mobility = 0.30,
        falloff = 0.82,
    },

    -- 长枪：back 是负的 —— 判定框从身体外侧 2 像素才开始，贴身完全打不到。
    -- 这是全表唯一「离得越近越打不中」的武器，逼玩家维持距离。
    -- 换来的是 56 的射程和前摇后摇都短，是唯一能安全拆 Boss 弱点的近战
    spear = {
        name = "长枪",
        windup = 0.140, active = 0.060, recovery = 0.150,
        damage = 18,
        reach = 56, back = -2, halfH = 12,
        poise = 20,
        knock = 120,
        hitstop = 0.050,
        shake = 1.4,
        mobility = 0.45,
        falloff = 0.92,
    },

    -- 战锤：击退 270，能把怪砸进墙里；代价是后摇 0.32 秒，空了就是白送
    hammer = {
        name = "战锤",
        windup = 0.230, active = 0.100, recovery = 0.320,
        damage = 34,
        reach = 32, back = 2, halfH = 31,
        poise = 52,
        knock = 270,
        hitstop = 0.100,
        shake = 3.6,
        mobility = 0.20,
        falloff = 0.78,
    },

    -- 匕首：伤害只有剑的六成，但总时长 0.20 秒，且 mobility 0.72——
    -- 它是唯一一把可以边跑边输出的武器。适合风筝与补刀
    dagger = {
        name = "匕首",
        windup = 0.045, active = 0.055, recovery = 0.100,
        damage = 8,
        reach = 24, back = 4, halfH = 16,
        poise = 8,
        knock = 55,
        hitstop = 0.030,
        shake = 0.8,
        mobility = 0.72,
        falloff = 0.90,
    },

    -- 镰刀：falloff = 1.00 意味着打三只和打一只的单体伤害完全一样。
    -- 它是唯一的群体武器，被矿虫围住时切出来能一次性清场
    sickle = {
        name = "镰刀",
        windup = 0.115, active = 0.110, recovery = 0.235,
        damage = 16,
        reach = 36, back = 10, halfH = 26,
        poise = 18,
        knock = 110,
        hitstop = 0.050,
        shake = 1.5,
        mobility = 0.40,
        falloff = 1.00,
    },

    -- 弓：唯一远程。判定框为空（reach=0），改成发射一支箭。
    -- 射程 520 让它能隔着半个屏幕消耗；代价是伤害低、且箭会被地形吃掉
    bow = {
        name = "弓",
        windup = 0.130, active = 0.040, recovery = 0.230,
        damage = 15,
        reach = 0, back = 0, halfH = 0,
        poise = 10,
        knock = 60,
        hitstop = 0.030,
        shake = 0.6,
        mobility = 0.85,
        falloff = 1.00,
        ranged = 520,      -- 箭初速
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

-- 结算伤害：基础值 × 材质系数（旧接口，保留给测试与简单调用）
function W.damage(kind, material)
    local d = W.types[kind]
    if not d then return 0 end
    local m = W.materials[material or "copper"] or W.materials.copper
    return d.damage * m.dmg
end

-- ---------------------------------------------------------------- 组装

--[[
    把「一把具体的武器」解析成这一刀要用的全部数字。

    这是 M2 的核心：玩家在铁砧前选的是**部件**，不是武器名。
        class   品类    决定动作结构与判定框形状
        bladeMat 刃材   决定伤害与破韧的基数
        hilt    柄      决定速度、击退、耐久（木头快、铁稳、虚空两头都强）
        core    芯      决定命中附加的元素状态
        affixes 词条    合成时随机滚出来的被动

    纯函数：同样的 spec 一定得到同样的结果，所以存档只存 spec，
    读档后重新 resolve 就能得到完全一致的数值。这一点有断言守着。

    为什么不用「预先算好一张全组合表」：8 品类 × 5 刃材 × 4 柄 × 5 芯 × 词条
    是几万种组合，全展开既吃内存又会在改一个数字时全部失效。
    每次出刀时 resolve 一次（几十次浮点运算）比维护缓存便宜得多。
]]
function W.resolve(spec)
    spec = spec or {}
    local kind = spec.class or "sword"
    local d = W.types[kind] or W.types.sword
    local mat = W.materials[spec.bladeMat or "copper"] or W.materials.copper
    local hilt = Parts.hilt(spec.hilt or spec.hiltMat or "wood")
    local core = Parts.core(spec.core or "none")

    -- 柄的档位：同一套柄材质，越高阶手感越稳。这里用乘数而不是加数，
    -- 保证「越强的武器换柄收益越大」，而不是弱武器换个好柄就飞起来
    local ht = math.max(1, math.min(5, spec.hiltTier or 1))
    local hiltScale = 0.86 + ht * 0.07      -- 1 档 0.93，5 档 1.21

    local r = {
        kind = kind,
        name = d.name,
        -- 伤害：品类基数 × 刃材 × 柄材，柄的贡献故意做小（0.9~1.2），
        -- 否则玩家会发现「换柄比换刃划算」，跳过整个挖矿循环
        damage = d.damage * mat.dmg * hilt.dmg,
        poise = d.poise * mat.poise * hilt.poise,
        knock = d.knock * hilt.knock,
        -- 时间：只有柄影响，刃不影响。刃决定「打多重」，柄决定「打多快」
        windup = d.windup * hilt.windup,
        active = d.active,
        recovery = d.recovery * hilt.recovery,
        reach = d.reach + hilt.reach,
        back = d.back,
        halfH = d.halfH,
        hitstop = d.hitstop,
        shake = d.shake * (0.85 + ht * 0.05),
        mobility = d.mobility,
        falloff = d.falloff,
        ranged = d.ranged,
        element = core.element,
        elementLv = core.lv or 1,
        affixes = {},
        crit = 0,
        leech = 0,
        spec = spec,
    }

    -- 词条叠加。放在最后，这样词条可以乘在已经算好的基数上，
    -- 而不是和材质乘在一起（否则「+18%」会随材质放大成 +40%）
    for _, id in ipairs(spec.affixes or {}) do
        local a = Affix.get(id)
        if a and a.apply then a.apply(r) end
        r.affixes[#r.affixes + 1] = id
    end

    r.dur = r.windup + r.active + r.recovery
    return r
end

-- 给 UI 用的一句话描述：「铁·长枪（骨柄/炎芯）」
function W.label(r)
    local parts = { "粗制", "精制", "淬火", "裂变", "终焉" }
    local tier = r.spec and r.spec.bladeTier or 1
    local h = Parts.hilt(r.spec and (r.spec.hilt or r.spec.hiltMat) or "wood")
    local c = Parts.core(r.spec and r.spec.core or "none")
    local head = string.format("%s%s", parts[tier] or "粗制", r.name)
    if c.element then
        return string.format("%s（%s/%s）", head, h.name, c.name)
    end
    return string.format("%s（%s）", head, h.name)
end

return W
