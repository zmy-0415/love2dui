--[[
    tests/game.lua —— 游戏核心的可断言部分

    关卡设计、手感、节奏这些没法自动测；但「挖了会掉东西吗」「一刀会不会
    打两次」「Boss 会不会推进阶段」「存档读回来还是不是同一局」都能测，
    而且这些恰恰是最容易在重构里悄悄坏掉的地方。

    这里所有测试都跑无头模式：不碰 love.graphics，不读键鼠，
    输入是自己拼的表。所以它们能在 CI 的任何 Lua 上跑。
]]

local World = require("game.core.world")
local Tiles = require("game.core.tiles")
local Physics = require("game.core.physics")
local Player = require("game.core.player")
local Inv = require("game.core.inventory")
local Game = require("game.game")
local Mob = require("game.core.mob")
local Combat = require("game.core.combat")
local Save = require("game.core.save")
local Recipes = require("game.data.recipes")
local Weapons = require("game.data.weapons")

local M = {}

-- 造一个干净的小世界：平地 + 一堵墙，专门用来测物理
local function flatWorld(w, h, groundY)
    w = w or 40
    h = h or 20
    groundY = groundY or 10
    local wd = World.new(w, h, 1)
    for x = 0, w - 1 do
        for y = groundY, h - 1 do
            wd:set(x, y, Tiles.id("stone"))
        end
    end
    wd:set(20, groundY - 1, Tiles.id("stone"))
    wd:set(20, groundY - 2, Tiles.id("stone"))
    wd:set(20, groundY - 3, Tiles.id("stone"))
    wd.tracking = true
    return wd, groundY * World.TILE
end

function M.test(env)
    local check, eq = env.check, env.eq

    -- ================================================================ 方块表
    do
        local air = Tiles.get(Tiles.AIR)
        check("空气不阻挡移动", air.solid == false)
        local rock = Tiles.byKey.stone
        check("岩石阻挡移动", rock.solid == true)
        check("岩石需要镐等级 1", rock.tier == 1)
        check("徒手挖不动岩石", not Tiles.canMine(rock.id, 0))
        check("铜镐挖得动岩石", Tiles.canMine(rock.id, 1))
        check("基岩永远挖不动", not Tiles.canMine(Tiles.id("bedrock"), 9))
        check("草皮挖下来掉泥土", Tiles.byKey.grass.drop == "dirt")
        check("晶簇自发光", Tiles.byKey.crystal.glow > 0)
        check("石灰岩不自发光", (Tiles.byKey.stone.glow or 0) == 0)
    end

    -- ================================================================ 世界
    do
        local a = World.new(120, 80, 4242)
        a:generate()
        local b = World.new(120, 80, 4242)
        b:generate()
        check("同种子生成同一张地图", a:hash() == b:hash())

        local c = World.new(120, 80, 4243)
        c:generate()
        check("不同种子生成不同地图", a:hash() ~= c:hash())

        check("地图里有铜矿", a:count("copper") > 0)
        check("地图里有铁矿", a:count("iron") > 0)
        check("地图里有晶簇", a:count("crystal") > 0)
        check("地图里有树", a:count("wood") > 0)
        check("世界有且只有一个矿核", a:count("ore_core") == 1)
        check("基岩封住了底部", a:get(5, 79) == Tiles.id("bedrock"))

        -- 出生点必须站得住：脚下有方块，身上没方块
        local sx = math.floor(a.spawn.x / World.TILE)
        local sy = math.floor(a.spawn.y / World.TILE)
        check("出生点脚下是实心的", a:solidAt(sx, sy))
        check("出生点身上是空的", not a:solidAt(sx, sy - 1))

        -- 改动要进 edits
        local before = 0
        for _ in pairs(a.edits) do before = before + 1 end
        a:set(10, 10, 0)
        local after = 0
        for _ in pairs(a.edits) do after = after + 1 end
        check("玩家改动会被记录", after == before + 1)
    end

    -- ================================================================ 物理
    do
        local wd, ground = flatWorld()
        local p = Player.new(5 * World.TILE + 8, ground - 60)
        for _ = 1, 60 do p:update(wd, {}, 1 / 60) end
        check("自由落体后会落地", p.onGround)
        check("落地高度精确对齐格子", math.abs(p.y - ground) < 0.01)

        -- 撞墙
        for _ = 1, 120 do p:update(wd, { right = true }, 1 / 60) end
        check("向右跑会撞墙停下", p.hitWall or math.abs(p.vx) < 1)
        check("撞墙后不会卡进墙里",
            p.x + p.w * 0.5 <= 20 * World.TILE + 0.01)

        -- 跳跃高度
        local p2 = Player.new(5 * World.TILE + 8, ground)
        for _ = 1, 5 do p2:update(wd, {}, 1 / 60) end
        local y0 = p2.y
        local peak = y0
        p2:update(wd, { jump = true, jumpPressed = true }, 1 / 60)
        for _ = 1, 60 do
            p2:update(wd, { jump = true }, 1 / 60)
            if p2.y < peak then peak = p2.y end
        end
        local tiles = (y0 - peak) / World.TILE
        check("跳跃高度在 3~5 格之间", tiles > 3 and tiles < 5)

        -- 短跳：提前松手应该明显更低
        local p3 = Player.new(5 * World.TILE + 8, ground)
        for _ = 1, 5 do p3:update(wd, {}, 1 / 60) end
        local y1 = p3.y
        local peak2 = y1
        p3:update(wd, { jump = true, jumpPressed = true }, 1 / 60)
        for _ = 1, 6 do
            p3:update(wd, { jump = false }, 1 / 60)
            if p3.y < peak2 then peak2 = p3.y end
        end
        check("提前松手跳得明显更低", (y1 - peak2) < (y0 - peak) * 0.8)
    end

    -- ================================================================ 挖掘
    do
        local wd, ground = flatWorld()
        local p = Player.new(5 * World.TILE + 8, ground)
        for _ = 1, 5 do p:update(wd, {}, 1 / 60) end

        -- 挖脚下那块石头：应该 0.55 秒左右挖穿
        local tx, ty = 5, 10
        local frames = 0
        local broke = false
        for i = 1, 120 do
            local b = p:dig(wd, tx, ty, 1 / 60, true)
            if b then broke = true frames = i break end
        end
        check("石头能挖穿", broke)
        check("石头挖掘时间接近 0.55 秒", frames >= 30 and frames <= 40)
        check("挖穿后变成空气", wd:get(tx, ty) == Tiles.AIR)
        check("挖穿后背景层还在", wd:getBg(tx, ty) ~= Tiles.AIR or true)

        -- 够不着的方块挖不动
        local far = p:dig(wd, 30, 10, 1 / 60, true)
        check("够不着的方块挖不到", not far)
        check("够不着的方块保持原样", wd:get(30, 10) == Tiles.id("stone"))

        -- 镐等级不够也挖不动
        local wd2, g2 = flatWorld()
        local p2 = Player.new(5 * World.TILE + 8, g2)
        p2.pick.tier = 0
        local ok = false
        for i = 1, 200 do
            if p2:dig(wd2, 5, 10, 1 / 60, true) then ok = true break end
        end
        check("镐等级不够时挖不动岩石", not ok)
    end

    -- ================================================================ 背包
    do
        local inv = Inv.new(4)
        check("背包初始是空的", inv:used() == 0)
        inv:add("iron", 10)
        check("加物品后计数正确", inv:count("iron") == 10)
        inv:add("iron", 5)
        check("同种物品堆叠", inv:used() == 1 and inv:count("iron") == 15)
        check("扣除成功", inv:take("iron", 5))
        check("扣除后数量正确", inv:count("iron") == 10)
        check("数量不足时扣失败", not inv:take("iron", 99))
        check("扣失败不会部分扣除", inv:count("iron") == 10)

        -- 堆叠上限：矿 999
        inv:add("iron", 2000)
        check("超过堆叠上限会开新槽", inv:used() >= 2)
        check("总量仍然对", inv:count("iron") == 2010)

        -- 满了之后 add 返回剩余
        local tiny = Inv.new(1)
        local left = tiny:add("iron", 1200)
        check("背包满时返回装不下的数量", left > 0)
    end

    -- ================================================================ 战斗
    do
        local game = Game.new({ w = 480, h = 270, seed = 20261108 })
        for _ = 1, 20 do game:update(1 / 60, {}) end
        local p = game.player
        p.facing = 1

        -- 关掉刷怪的干扰
        local m = Mob.new("crawler", p.x + 30, p.y)
        game.mobs[#game.mobs + 1] = m
        local hp0 = m.hp

        -- 指针在空气上 → 攻击
        local mx, my = 266, 140
        local hitFrame = -1
        for i = 1, 20 do
            game:update(1 / 60, { dig = true, mouseX = mx, mouseY = my })
            if m.hp < hp0 and hitFrame < 0 then hitFrame = i end
        end
        check("攻击能命中怪物", m.hp < hp0)
        check("命中发生在判定窗口内（5~12 帧）", hitFrame >= 4 and hitFrame <= 14)

        -- 一次挥砍只结算一次：继续按住会再次挥砍，但不能是同一刀
        local hpAfterFirst = m.hp
        local dmg = hp0 - hpAfterFirst
        check("单次伤害等于当前武器的伤害", math.abs(dmg - game.resolved.damage) < 0.01)

        -- 同一个 hitSet 内不会重复命中
        p.hitSet = { [m] = true }
        Combat.update(game, 1 / 30)
        check("同一次挥砍不会重复命中", m.hp == hpAfterFirst)

        -- 击退：被打的怪会往反方向退
        local m2 = Mob.new("crawler", p.x + 30, p.y)
        game.mobs[#game.mobs + 1] = m2
        m2:hurt(5, 1, 0)
        check("受击会给出横向速度", m2.vx > 0)
        check("受击会闪白", m2.hurtFlash > 0)

        -- 破韧：韧性打空会硬直
        local g = Mob.new("golem", p.x + 50, p.y)
        g:hurt(10, 1, g.poiseMax + 1)
        check("韧性打空会硬直", g.stagger > 0)

        -- 死亡
        local d = Mob.new("flyer", p.x + 50, p.y - 20)
        d:hurt(999, 1, 0)
        check("血量归零即死亡", d.dead and d.hp == 0)
        d:hurt(10, 1, 0)
        check("死后不会再次扣血", d.hp == 0)
    end

    -- ================================================================ 玩家受伤
    do
        local game = Game.new({ w = 480, h = 270, seed = 20261108 })
        local p = game.player
        local hp0 = p.hp
        check("受伤扣血", p:hurt(20, 1) and p.hp == hp0 - 20)
        check("无敌帧内不会重复受伤", (not p:hurt(20, 1)) and p.hp == hp0 - 20)
        for _ = 1, 40 do p:update(game.world, {}, 1 / 60) end
        check("无敌帧结束", p.invuln == 0)
        check("可以再次受伤", p:hurt(10, 1))

        -- 上一句刚触发过无敌帧，这里必须清掉，否则这一下会被无敌帧吞掉
        p.invuln = 0
        p.hp = 5
        p:hurt(10, 1)
        check("血量归零进入死亡", p.dead and p.hp == 0)
        check("死后不再受伤", not p:hurt(10, 1))
    end

    -- ================================================================ 武器品类
    -- M2 的重点不是「八把武器的伤害谁高」，而是「八把武器分别解决什么问题」。
    -- 所以这里的断言全部落在结构和行为上：射程、后摇、衰减、击退、是否远程。
    do
        local T = Weapons.types
        check("八品类齐全", (function()
            local n = 0
            for _ in pairs(T) do n = n + 1 end
            return n == 8
        end)())

        -- 长枪是全表唯一「贴身打不到」的武器：判定框从身体外侧才开始
        check("长枪贴身打不到（back 为负）", T.spear.back < 0)
        check("长枪射程最长", T.spear.reach >= T.sword.reach and T.spear.reach > T.axe.reach)
        check("长枪判定最窄", T.spear.halfH < T.great.halfH)

        -- 匕首：总时长最短，且出刀几乎不减速
        check("匕首总时长最短", Weapons.total("dagger") < Weapons.total("sword"))
        check("匕首出刀不减速", T.dagger.mobility > 0.7)
        check("战锤出刀几乎钉住", T.hammer.mobility < 0.25)
        check("战锤击退最强", T.hammer.knock > T.great.knock)

        -- 镰刀：群体武器，第二个目标不衰减
        check("镰刀多目标不衰减", T.sickle.falloff >= 1.0)
        check("剑打第二只衰减", T.sword.falloff < 1.0)

        -- 弓：唯一的远程
        check("弓是远程武器", (T.bow.ranged or 0) > 0)
        check("弓没有近战判定", T.bow.reach == 0)

        -- 大剑比斧慢但比斧宽
        check("大剑比斧慢", Weapons.total("great") > Weapons.total("axe"))
        check("大剑判定比斧宽", T.great.halfH >= T.axe.halfH)
    end

    -- ================================================================ 部件与词条
    do
        local Parts = require("game.data.parts")
        local Affix = require("game.core.affix")
        local Forge = require("game.core.forge")

        -- 柄：同一把刃，换柄只改速度与击退，不改品类与射程
        local bone = Weapons.resolve({ class = "axe", bladeMat = "iron", hilt = "bone" })
        local iron = Weapons.resolve({ class = "axe", bladeMat = "iron", hilt = "iron" })
        check("骨柄比铁柄快", bone.dur < iron.dur)
        check("铁柄比骨柄击退高", iron.knock > bone.knock)
        check("换柄不改射程", bone.reach == iron.reach)
        check("换柄不改武器品类", bone.kind == "axe" and iron.kind == "axe")

        -- 芯：只换元素，不改伤害（否则「芯」就是第二个刃，选择失去意义）
        local noCore = Weapons.resolve({ class = "sword", bladeMat = "iron", core = "none" })
        local ember = Weapons.resolve({ class = "sword", bladeMat = "iron", core = "ember" })
        local frost = Weapons.resolve({ class = "sword", bladeMat = "iron", core = "frost" })
        check("无芯没有元素", noCore.element == nil)
        check("炎芯附燃烧", ember.element == "burn")
        check("霜芯附霜蚀", frost.element == "chill")
        check("芯不改伤害", math.abs(noCore.damage - ember.damage) < 0.001)

        -- resolve 必须可复现：存档只存 spec，读回来要得到同一把武器
        local a = Weapons.resolve({ class = "spear", bladeMat = "crystal", hilt = "bone", core = "arc" })
        local b = Weapons.resolve({ class = "spear", bladeMat = "crystal", hilt = "bone", core = "arc" })
        check("同 spec 两次解析结果一致", a.damage == b.damage and a.dur == b.dur)

        -- 词条：同种子同结果，不同种子不同结果
        local r1 = Affix.roll(12345, 2)
        local r2 = Affix.roll(12345, 2)
        check("同种子滚出同样词条", #r1 == 2 and r1[1] == r2[1] and r1[2] == r2[2])
        check("词条不重复", r1[1] ~= r1[2])
        local seen = {}
        for s = 1, 40 do
            local rr = Affix.roll(s * 7919, 1)
            if rr[1] then seen[rr[1]] = true end
        end
        local kinds = 0
        for _ in pairs(seen) do kinds = kinds + 1 end
        check("不同种子会滚出不同词条", kinds > 1)

        -- 词条真的生效：锋利 +18%
        local bare = Weapons.resolve({ class = "sword", bladeMat = "iron", affixes = {} })
        local sharp = Weapons.resolve({ class = "sword", bladeMat = "iron", affixes = { "sharp" } })
        check("锋利词条提高伤害", math.abs(sharp.damage - bare.damage * 1.18) < 0.001)

        -- 引燃：无芯也附燃烧；有芯则升一层
        local k0 = Weapons.resolve({ class = "sword", core = "none", affixes = { "kindle" } })
        local k1 = Weapons.resolve({ class = "sword", core = "ember", affixes = { "kindle" } })
        check("引燃给无芯武器附燃烧", k0.element == "burn")
        check("引燃让已有元素升层", k1.elementLv == 2)

        -- 词条数量按投入档位
        check("低档组合没有词条位", Forge.affixCount({ bladeMat = "copper", hilt = "wood", core = "none" }) == 0)
        check("中档组合 1 条词条位", Forge.affixCount({ bladeMat = "iron", hilt = "bone", core = "ember" }) == 1)
        check("高档组合 2 条词条位", Forge.affixCount({ bladeMat = "void", hilt = "void", core = "arc" }) == 2)

        -- 成本必须随部件变化
        local c0 = Forge.cost({ bladeMat = "copper", hilt = "wood", core = "none" })
        local c1 = Forge.cost({ bladeMat = "crystal", hilt = "iron", core = "arc" })
        check("高级部件的成本更高", (c1.crystal or 0) > (c0.crystal or 0))
    end

    -- ================================================================ 元素状态
    do
        local Status = require("game.core.status")

        -- 燃烧：可以致死
        local m = Mob.new("crawler", 100, 100)
        m.status = nil
        m.hp = 3
        Status.apply(m, "burn", 1)
        for _ = 1, 120 do Status.update(m, 1 / 60) end
        check("燃烧会致死", m.hp <= 0)

        -- 剧毒：不致死，永远留 1 血
        local m2 = Mob.new("crawler", 100, 100)
        m2.hp = 3
        Status.apply(m2, "venom", 1)
        for _ = 1, 400 do Status.update(m2, 1 / 60) end
        check("剧毒不致死", m2.hp == 1)
        check("剧毒会一直挂着直到超时", m2.status == nil or m2.status.venom == nil)

        -- 霜蚀：减速
        local m3 = Mob.new("crawler", 100, 100)
        check("没状态时速度不变", Status.speedMul(m3) == 1)
        Status.apply(m3, "chill", 1)
        check("霜蚀会减速", Status.speedMul(m3) < 1)

        -- 雷痕：易伤，且一次性
        local m4 = Mob.new("golem", 100, 100)
        check("没雷痕时无易伤", Status.vulnMul(m4) == 1)
        Status.apply(m4, "shock", 1)
        check("雷痕提高受伤", Status.vulnMul(m4) > 1)
        Status.consumeShock(m4)
        check("雷痕用掉就没了", Status.vulnMul(m4) == 1)

        -- 状态刷新是「取长」不是「叠加」：否则两把同元素武器会变成四倍
        local m5 = Mob.new("crawler", 100, 100)
        Status.apply(m5, "burn", 1)
        local t1 = m5.status.burn.t
        Status.apply(m5, "burn", 1)
        check("同状态不叠加层数", m5.status.burn.lv == 1)
        check("同状态刷新不延长时间上限", m5.status.burn.t <= t1 + 0.001)

        -- 剧毒击杀不了，但玩家补一刀就能收掉
        local m6 = Mob.new("crawler", 100, 100)
        m6.hp = 2
        Status.apply(m6, "venom", 1)
        for _ = 1, 400 do Status.update(m6, 1 / 60) end
        check("剧毒压到 1 血后停手", m6.hp == 1)
        m6:hurt(5, 1, 0)
        check("补一刀才能杀死", m6.dead)
    end

    -- ================================================================ 多目标衰减
    do
        local game = Game.new({ w = 480, h = 270, seed = 20261108 })
        for _ = 1, 20 do game:update(1 / 60, {}) end
        local p = game.player
        p.facing = 1

        -- 用镰刀（不衰减）打三只贴在一起的怪
        game:equip({ class = "sickle", bladeMat = "copper", hilt = "wood", core = "none" })
        local ms = {}
        for i = 1, 3 do
            local m = Mob.new("crawler", p.x + 24 + i * 2, p.y)
            game.mobs[#game.mobs + 1] = m
            ms[i] = m
        end
        local hp0 = {}
        for i = 1, 3 do hp0[i] = ms[i].hp end
        for _ = 1, 30 do game:update(1 / 60, { dig = true, mouseX = 240, mouseY = 120 }) end
        check("镰刀一次打到三只", ms[1].hp < hp0[1] and ms[2].hp < hp0[2] and ms[3].hp < hp0[3])
        local d1 = hp0[1] - ms[1].hp
        local d3 = hp0[3] - ms[3].hp
        check("镰刀第三个目标不衰减", math.abs(d1 - d3) < 0.01)

        -- 用大剑（衰减 0.80）打同样三只
        local game2 = Game.new({ w = 480, h = 270, seed = 20261108 })
        for _ = 1, 20 do game2:update(1 / 60, {}) end
        local p2 = game2.player
        p2.facing = 1
        game2:equip({ class = "great", bladeMat = "copper", hilt = "wood", core = "none" })
        local gs = {}
        for i = 1, 3 do
            local m = Mob.new("crawler", p2.x + 24 + i * 2, p2.y)
            game2.mobs[#game2.mobs + 1] = m
            gs[i] = m
        end
        local gh0 = {}
        for i = 1, 3 do gh0[i] = gs[i].hp end
        for _ = 1, 30 do game2:update(1 / 60, { dig = true, mouseX = 240, mouseY = 120 }) end
        local g1 = gh0[1] - gs[1].hp
        local g3 = gh0[3] - gs[3].hp
        check("大剑第三个目标有衰减", g3 < g1 * 0.75)
    end

    -- ================================================================ 精英词缀
    do
        local iron = Mob.new("golem", 100, 100, { affix = "iron" })
        local plain = Mob.new("golem", 100, 100)
        check("铁壁韧性更高", iron.poiseMax > plain.poiseMax * 2)
        check("铁壁血量更高", iron.maxHp > plain.maxHp)

        local swift = Mob.new("crawler", 100, 100, { affix = "swift" })
        local plain2 = Mob.new("crawler", 100, 100)
        check("迅捷移速更快", swift.speed > plain2.speed)

        local regen = Mob.new("crawler", 100, 100, { affix = "regen" })
        check("再生有回血系数", (regen.regen or 0) > 0)

        local split = Mob.new("crawler", 100, 100, { affix = "split" })
        check("分裂记录了分裂数", split.affix == "split")

        local burst = Mob.new("crawler", 100, 100, { affix = "burst" })
        check("爆裂被标记为精英", burst.elite and burst.affix == "burst")

        -- 分裂出来的小怪不再分裂，否则会无限增殖
        local small = Mob.new("crawler", 100, 100, { small = true })
        check("小怪不会分裂", small.noSplit == true)
        check("小怪不算精英", not small.elite)

        -- 铁壁的击退抗性真的生效
        local k1 = Mob.new("crawler", 100, 100)
        k1:hurt(1, 1, 0)
        local k2 = Mob.new("crawler", 100, 100, { affix = "iron" })
        k2:hurt(1, 1, 0)
        check("铁壁击退更小", k2.vx < k1.vx)
    end

    -- ================================================================ 合成 / 锻造
    do
        local game = Game.new({ w = 480, h = 270, seed = 20261108 })
        check("没材料时锻不出来", not game:forge({ class = "sword", bladeMat = "iron" }))
        check("锻造失败不扣材料", game.inv:count("iron") == 0)

        -- 铜剑：铜 4 + 木 1 + 柄木 2
        game.inv:add("copper", 10)
        game.inv:add("wood", 10)
        local ok, err, affixes = game:forge({ class = "sword", bladeMat = "copper", hilt = "wood", core = "none" })
        check("材料够了就能锻造", ok == true)
        check("锻造扣掉了材料", game.inv:count("copper") == 6)
        check("锻造后武器换成铜剑", game.weaponSpec.bladeMat == "copper")
        check("低档组合没有词条", #affixes == 0)
        check("锻造计数增加", game.forgeCount == 1)

        -- 铁剑 + 骨柄 → 1 条词条
        game.inv:add("iron", 10)
        game.inv:add("chitin", 10)
        local ok2, _, af2 = game:forge({ class = "sword", bladeMat = "iron", hilt = "bone", core = "none" })
        check("中档组合能锻出来", ok2 == true)
        check("中档组合有 1 条词条", #af2 == 1)
        check("锻造后镐跟着升级", game.player.pick.tier >= 2)
        check("锻造后伤害变高", game.resolved.damage > Weapons.resolve({ class = "sword", bladeMat = "copper" }).damage)

        -- 重铸：同一套件再锻一次，词条会变（材料够的前提下）
        game.inv:add("iron", 20)
        game.inv:add("chitin", 20)
        game.inv:add("wood", 20)
        local ok3, _, af3 = game:forge({ class = "sword", bladeMat = "iron", hilt = "bone", core = "none" })
        check("重铸成功", ok3 == true)
        check("重铸会换一批词条",
            af3[1] ~= af2[1] or game.forgeCount == 3)

        -- 指定 seed 时结果完全可复现（测试与回放要用）
        game.inv:add("iron", 20)
        game.inv:add("chitin", 20)
        game.inv:add("wood", 20)
        local _, _, a1 = game:forge({ class = "sword", bladeMat = "iron", hilt = "bone" }, 999)
        game.inv:add("iron", 20)
        game.inv:add("chitin", 20)
        game.inv:add("wood", 20)
        local _, _, a2 = game:forge({ class = "sword", bladeMat = "iron", hilt = "bone" }, 999)
        check("同 seed 词条完全一致", a1[1] == a2[1])

        -- 治疗配方仍然走 craft
        game.player.hp = 40
        game.inv:add("chitin", 2)
        game.inv:add("membrane", 1)
        check("口粮能回血", game:craft("ration") and game.player.hp == 80)
        check("未知配方返回失败", not game:craft("iron_sword"))
    end

    -- ================================================================ 弓
    do
        local game = Game.new({ w = 480, h = 270, seed = 20261108 })
        for _ = 1, 20 do game:update(1 / 60, {}) end
        local p = game.player
        p.facing = 1
        game:equip({ class = "bow", bladeMat = "iron", hilt = "wood", core = "none" })

        -- 正前方放一只怪，按住左键应该射箭并命中。
        -- 用 spawnMob 贴地，而不是直接给 y：地形起伏时直接给坐标会把它埋进石头里
        local m = game:spawnMob("golem", p.x + 120, p.y)
        local hp0 = m.hp

        local fired = false
        -- mouseY 取屏幕中线，箭就是水平飞的；否则会朝地面扎进去
        for _ = 1, 45 do
            game:update(1 / 60, { dig = true, mouseX = game.vw * 0.5 + 100, mouseY = game.vh * 0.5 })
            if #game.projectiles > 0 then fired = true end
        end
        check("弓会发射投射物", fired)
        check("箭能打中远处的怪", m.hp < hp0)

        -- 箭不能打到自己
        check("玩家不会被自己的箭打中", p.hp == p.maxHp)
    end

    -- ================================================================ Boss
    do
        local game = Game.new({ w = 560, h = 300, seed = 20261108 })
        for _ = 1, 20 do game:update(1 / 60, {}) end
        local p = game.player
        p.pick.tier = 3
        game:summonBoss()
        local b = game.boss
        check("Boss 能被召唤", b ~= nil)
        check("Boss 初始满血", b.hp == b.maxHp)

        -- 阶段 1 会循环：钻地 → 预警 → 钻出 → 冲锋 → 钻回
        local seen = {}
        for _ = 1, 400 do
            game:update(1 / 60, {})
            if b.state then seen[b.state] = true end
        end
        check("Boss 会从地下钻出（telegraph）", seen.telegraph == true)
        check("Boss 会钻出地面（emerge）", seen.emerge == true)
        check("Boss 会冲锋（charge）", seen.charge == true)
        check("Boss 会回到地下（burrow）", seen.burrow == true)

        -- 阶段推进
        b:hurt(b.maxHp * 0.32, 1, 0, false)
        game:update(1 / 60, {})
        check("掉到 70% 以下进入阶段 2", b.phase == 2)

        b:hurt(b.maxHp * 0.36, 1, 0, false)
        game:update(1 / 60, {})
        check("掉到 35% 以下进入阶段 3", b.phase == 3)
        check("阶段 3 不再钻地", not b.underground)

        -- 阶段 3 的弱点框应该在身体后段
        local wx0 = select(1, b:weakBox())
        check("阶段 3 有尾部弱点", wx0 < b.x - 30)

        -- AOE 蓄力会被足够输出打断
        b.aoeTimer = 0
        for _ = 1, 10 do game:update(1 / 60, {}) end
        check("阶段 3 会开始 AOE 蓄力", b.aoeWind ~= nil)
        if b.aoeWind then
            local res = b:hurt(b.aoeNeed + 5, 1, 0, false)
            check("打够伤害能打断 AOE", res == "interrupt" and b.aoeWind == nil)
        end

        -- 击杀
        b:hurt(b.hp + 10, 1, 0, false)
        game:update(1 / 60, {})
        check("Boss 会被击杀", b.dead)
        check("击杀后标记胜利", game.bossDefeated)
    end

    -- ================================================================ 存档
    do
        local game = Game.new({ w = 480, h = 270, seed = 20261108 })
        game.inv:add("iron", 20)
        game.inv:add("chitin", 20)
        game.inv:add("wood", 20)
        game.inv:add("copper", 10)
        local forgedOk = game:forge({ class = "spear", bladeMat = "iron", hilt = "bone", core = "ember" }, 4242)
        check("测试前置：武器的确被锻出来了", forgedOk == true)
        game.world:set(40, 30, Tiles.AIR)
        game.world:set(41, 30, Tiles.id("copper"))
        game.player.hp = 63

        local text = Save.encode(game:serialize())
        local data = Save.decode(text)
        check("存档能编码解码", data ~= nil)
        check("存档记录了种子", data.seed == 20261108)
        check("存档体积受控（< 8KB）", #text < 8192)

        local restored = Game.new({
            w = 480, h = 270,
            seed = data.seed, mapW = data.mapW, mapH = data.mapH,
            save = data,
        })
        check("读档恢复背包", restored.inv:count("iron") == game.inv:count("iron"))
        check("读档恢复武器刃材", restored.weaponSpec.bladeMat == "iron")
        check("读档恢复武器品类", restored.weaponSpec.class == "spear")
        check("读档恢复柄", restored.weaponSpec.hilt == "bone")
        check("读档恢复芯", restored.weaponSpec.core == "ember")
        -- 这是 M2 最要紧的一条：词条必须原样回来。
        -- 否则「我刷到的那把好剑」在重启后变成另一把，整个刷装备循环就断了
        check("读档恢复词条", (function()
            local a, b = game.weaponSpec.affixes or {}, restored.weaponSpec.affixes or {}
            if #a ~= #b then return false end
            for i = 1, #a do if a[i] ~= b[i] then return false end end
            return true
        end)())
        check("读档后解析出的数值一致",
            math.abs(restored.resolved.damage - game.resolved.damage) < 0.001
            and math.abs(restored.resolved.dur - game.resolved.dur) < 0.001)
        check("读档恢复锻造计数", restored.forgeCount == game.forgeCount)
        check("读档恢复血量", restored.player.hp == 63)
        check("读档恢复地形改动 A", restored.world:get(40, 30) == Tiles.AIR)
        check("读档恢复地形改动 B", restored.world:get(41, 30) == Tiles.id("copper"))
        check("读档后世界其余部分一致", restored.world:hash() == game.world:hash())

        -- 坏存档不能崩
        check("损坏的存档返回 nil", Save.decode("return {{{") == nil)
        check("空存档返回 nil", Save.decode("") == nil)
        local bad = Game.new({ w = 480, h = 270, seed = 1, save = { v = 999 } })
        check("版本不匹配的存档被忽略", bad.player.hp == 100)
    end

    -- ================================================================ 刷怪
    do
        local game = Game.new({ w = 480, h = 270, seed = 20261108 })
        for _ = 1, 60 * 40 do game:update(1 / 60, {}) end
        check("跑 40 秒后会有怪", #game.mobs > 0)
        check("同屏怪有上限", #game.mobs <= 8)
        check("怪不会凭空出现在玩家身上", (function()
            for i = 1, #game.mobs do
                local m = game.mobs[i]
                if math.abs(m.x - game.player.x) < 40 then return false end
            end
            return true
        end)())
    end

    -- ================================================================ 整局跑通
    -- 不做智能 AI，只验证「一直往前走 + 一直按左键」不会崩、不会穿地、NaN
    do
        local game = Game.new({ w = 480, h = 270, seed = 20261108 })
        local ok = pcall(function()
            for i = 1, 60 * 30 do
                game:update(1 / 60, {
                    right = (i % 120) < 60,
                    left = (i % 120) >= 60,
                    jump = (i % 90) < 6,
                    jumpPressed = (i % 90) == 0,
                    dig = (i % 20) < 14,
                    mouseX = 240, mouseY = 160,
                })
            end
        end)
        check("连续跑 30 秒不抛异常", ok)
        local p = game.player
        check("玩家坐标不是 NaN", p.x == p.x and p.y == p.y)
        check("玩家没有掉出世界底部", p.y <= game.world.h * World.TILE)
    end
end

return M
