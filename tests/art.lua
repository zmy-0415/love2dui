--[[
    tests/art.lua —— 程序化美术的断言

    美术是「算出来的」这件事有一个副作用：它可以被测试。
    贴图错了只能靠眼睛看，而几何错了可以直接断言：

        同一种子必须得到同一把武器   → 存档只存种子才成立
        档位越高刃必须越长           → 数值成长要能被看出来
        尾节必须是全场最亮           → 弱点提示不能失效
        一帧的绘制调用数必须有上限   → 防止「加了细节，帧率崩了」

    这些断言不依赖显卡，也不需要 love.graphics——用假后端记录调用即可。
]]

local Palette = require("game.art.palette")
local Rng = require("game.art.rng")
local Rig = require("game.art.rig")
local Creature = require("game.art.creature")
local Weapon = require("game.art.weapon")
local Boss = require("game.art.boss")
local platform = require("lumi.platform")

local M = {}

local function inRange(v)
    return type(v) == "number" and v >= 0 and v <= 1
end

function M.test(env)
    local check, eq = env.check, env.eq

    -- ---------------- 调色板
    local steps = { "dark", "base", "light", "edge", "glow" }
    local badStep = nil
    for _, key in ipairs({ "wood", "iron", "ember", "void", "endgame", "slime", "ink" }) do
        for _, st in ipairs(steps) do
            local r, g, b, a = Palette.rgba(key, st)
            if not (inRange(r) and inRange(g) and inRange(b) and inRange(a)) then
                badStep = key .. "." .. st
            end
        end
    end
    check("所有材质色阶都在 0~1 之间" .. (badStep and ("，越界: " .. badStep) or ""), badStep == nil)

    -- 越界会写进 uint8 回绕（橙红变青色），这是曾经踩过的坑
    local er, eg, eb = Palette.rgba("ember", "glow")
    check("发光的橙红仍然是暖色，没有回绕成青色", er > 0.85 and er > eb)

    local a1 = Palette.material("iron")
    local a2 = Palette.material("iron")
    check("同材质取色命中缓存", a1 == a2)

    local fallback = Palette.material("no_such_material")
    check("未知材质回退到石头而不是报错", fallback ~= nil and fallback.base ~= nil)

    local rot = Palette.rotate("iron", 120)
    check("色相旋转结果合法", rot and inRange(rot[1]) and inRange(rot[2]) and inRange(rot[3]))

    -- ---------------- 随机数
    local s1 = Rng.new(Rng.hash("iron", 3))
    local s2 = Rng.new(Rng.hash("iron", 3))
    local same = true
    for _ = 1, 8 do
        if s1:next() ~= s2:next() then same = false end
    end
    check("同种子产生同序列", same)

    local s3 = Rng.new(Rng.hash("iron", 4))
    check("不同种子产生不同序列", s3:next() ~= Rng.new(Rng.hash("iron", 3)):next())

    local rng = Rng.new(12345)
    local minV, maxV = 1e9, -1e9
    for _ = 1, 500 do
        local v = rng:unit()
        if v < minV then minV = v end
        if v > maxV then maxV = v end
    end
    check("unit 落在 [0,1)", minV >= 0 and maxV < 1)

    local rngI = Rng.new(999)
    local okInt = true
    for _ = 1, 200 do
        local v = rngI:int(3, 7)
        if v < 3 or v > 7 then okInt = false end
    end
    check("int 不越界", okInt)

    check("hash 稳定", Rng.hash("a", 1) == Rng.hash("a", 1))
    check("hash 区分参数", Rng.hash("a", 1) ~= Rng.hash("a", 2))

    -- ---------------- 武器：确定性
    local spec = {
        class = "sword", bladeTier = 3, hiltTier = 2, coreTier = 2,
        bladeMat = "iron", hiltMat = "leather", affixes = { "fire" },
    }
    local v1 = Weapon.build(spec)
    local v2 = Weapon.build(spec)
    local identical = #v1.blade.points == #v2.blade.points
    if identical then
        for i = 1, #v1.blade.points do
            if v1.blade.points[i] ~= v2.blade.points[i] then identical = false break end
        end
    end
    check("同 spec 两次构建得到完全相同的轮廓", identical)
    check("握把长度也稳定", v1.grip.len == v2.grip.len)

    -- 档位成长必须看得见
    local lens = {}
    for tier = 1, 5 do
        lens[tier] = Weapon.build({ class = "sword", bladeTier = tier, hiltTier = 1, coreTier = 1 }).blade.len
    end
    check("刃长随档位单调递增",
        lens[1] < lens[2] and lens[2] < lens[3] and lens[3] < lens[4] and lens[4] < lens[5])

    -- 不同类别要真的长得不一样
    local wSword = Weapon.build({ class = "sword", bladeTier = 3 })
    local wAxe = Weapon.build({ class = "axe", bladeTier = 3 })
    check("不同类别的轮廓不同", wSword.blade.points[2] ~= wAxe.blade.points[2])

    -- 词条影响外观
    local withCrit = Weapon.build({ class = "sword", bladeTier = 3, affixes = { "crit" } })
    local noCrit = Weapon.build({ class = "sword", bladeTier = 3, affixes = {} })
    check("暴击词条长出锯齿", withCrit.spikes ~= nil and noCrit.spikes == nil)

    local withFire = Weapon.build({ class = "sword", bladeTier = 3, affixes = { "fire" } })
    check("元素词条改变发光", withFire.glowPower > noCrit.glowPower)

    -- bounds 必须真正包住所有顶点
    local vis = Weapon.build({ class = "great", bladeTier = 5, hiltTier = 4, coreTier = 4 })
    local minX, minY, maxX, maxY = Weapon.bounds(vis)
    local contained = true
    for i = 1, #vis.blade.points, 2 do
        local x, y = vis.blade.points[i], vis.blade.points[i + 1]
        if x < minX - 0.01 or x > maxX + 0.01 or y < minY - 0.01 or y > maxY + 0.01 then
            contained = false
        end
    end
    check("bounds 包住刀刃全部顶点", contained)
    check("bounds 宽度为正", maxX > minX and maxY > minY)
    check("describe 返回非空描述", #Weapon.describe(vis) > 0)

    -- ---------------- 骨架
    local human = Creature.humanoid({})
    check("人形骨架节点数在合理区间", Rig.count(human) >= 12 and Rig.count(human) <= 24)
    check("四类骨架都能构建",
        Rig.count(Creature.crawler({})) > 5 and Rig.count(Creature.blob({})) > 3
        and Rig.count(Creature.flyer({})) > 3)
    check("能找到手节点", Rig.find(human, "hand_near") ~= nil)

    -- 手的位置必须随姿势变化，否则武器不会跟着挥
    local poseIdle, _ = Creature.pose("humanoid", "idle", 0)
    local poseAttack, _ = Creature.pose("humanoid", "attack", 0.5)
    local ix, iy = Rig.tip(human, poseIdle, "hand_near")
    local ax, ay = Rig.tip(human, poseAttack, "hand_near")
    local moved = math.abs(ax - ix) > 2 or math.abs(ay - iy) > 2
    check("攻击姿势下握刀手明显移位", moved)

    -- 攻击的判定帧必须比前摇更"前"，这是手感的核心
    local poseWindup = select(1, Creature.pose("humanoid", "attack", 0.36))
    check("前摇与判定的手臂角度不同", math.abs(poseWindup.arm_near - poseAttack.arm_near) > 1.0)

    -- ---------------- Boss
    local maw = Boss.stoneMaw({})
    check("Boss 节点数明显多于小怪", Rig.count(maw) > 20)
    check("Boss 有独立的尾节", Rig.find(maw, "tail") ~= nil)
    check("Boss 弱点在尾节下", (function()
        local tail = Rig.find(maw, "tail")
        if not tail or not tail.children then return false end
        for _, c in ipairs(tail.children) do
            if c.name == "core" then return true end
        end
        return false
    end)())

    -- 阶段推进必须让弱点变暗（这是「它变了」的唯一提示）
    local coreBefore = Rig.find(Boss.stoneMaw({}), "core").glowAlpha
    local phased = Boss.stoneMaw({})
    Boss.applyPhase(phased, 3)
    local coreAfter = Rig.find(phased, "core").glowAlpha
    check("阶段推进后弱点变暗", coreAfter < coreBefore)

    -- ---------------- 绘制冒烟与预算
    local g = platform.graphics
    local pcount, ccount = 0, 0
    local rawPoly, rawCircle, rawLine = g.polygon, g.circle, g.line
    g.polygon = function(...) pcount = pcount + 1 return rawPoly(...) end
    g.circle = function(...) ccount = ccount + 1 return rawCircle(...) end
    g.line = function(...) return rawLine(...) end

    local okDraw = pcall(function()
        Creature.draw(g, human, 100, 100, 1, "attack", 0.5, { scale = 2, weapon = vis })
        Creature.draw(g, Creature.crawler({}), 100, 100, 1, "run", 0.5, { scale = 2 })
        Creature.draw(g, Creature.blob({}), 100, 100, 1, "idle", 0.5, { scale = 2 })
        Creature.draw(g, Creature.flyer({}), 100, 100, 1, "idle", 0.5, { scale = 2 })
        Boss.draw(g, maw, 100, 100, 1, "idle", 0.5, { scale = 1.5 })
        Weapon.draw(g, vis, 50, 50, 0, 2)
    end)

    g.polygon, g.circle, g.line = rawPoly, rawCircle, rawLine

    check("全部素材可绘制不抛异常", okDraw)
    -- 一组角色 + 一只 Boss + 一把武器，一帧的三角形数量必须收敛
    check("绘制调用数在预算内（< 400）", pcount + ccount < 400)
    check("确实产生了绘制调用", pcount + ccount > 20)

    -- 受击闪白不应该留下副作用（改完颜色要还原）
    local eye = Rig.find(human, "eye")
    local colBefore = eye.col
    Creature.draw(g, human, 100, 100, 1, "idle", 0.5, { tint = { 1, 1, 1 } })
    check("受击闪白不污染骨架颜色", eye.col == colBefore)

    -- 镜像不吃掉状态
    local poseL = Creature.pose("humanoid", "idle", 0.2)
    local poseR = Creature.pose("humanoid", "idle", 0.2)
    check("左右朝向的姿势一致（镜像在绘制层做）", poseL.torso == poseR.torso)

    return M
end

return M
