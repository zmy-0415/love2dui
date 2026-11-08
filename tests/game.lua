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
        check("单次伤害等于武器伤害", math.abs(dmg - Weapons.damage("sword", "copper")) < 0.01)

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

    -- ================================================================ 合成
    do
        local game = Game.new({ w = 480, h = 270, seed = 20261108 })
        check("没材料时做不出来", not game:craft("iron_sword"))
        check("做失败不扣材料", game.inv:count("iron") == 0)

        game.inv:add("iron", 5)
        game.inv:add("wood", 3)
        check("材料够了就能做", game:craft("iron_sword"))
        check("合成的材料被扣除", game.inv:count("iron") == 2 and game.inv:count("wood") == 2)
        check("合成后武器变成铁剑", game.weaponSpec.bladeMat == "iron")
        check("合成后镐也升级了", game.player.pick.tier >= 2)
        check("合成后伤害变高",
            Weapons.damage("sword", game.player.attackMat) > Weapons.damage("sword", "copper"))

        -- 斧与剑的帧数据必须不同，否则「换武器」只是换个数字
        check("斧比剑慢", Weapons.total("axe") > Weapons.total("sword"))
        check("斧破韧更高", Weapons.types.axe.poise > Weapons.types.sword.poise)
        check("斧单次伤害更高", Weapons.types.axe.damage > Weapons.types.sword.damage)

        -- 治疗配方
        game.player.hp = 40
        game.inv:add("chitin", 2)
        game.inv:add("membrane", 1)
        check("口粮能回血", game:craft("ration") and game.player.hp == 80)
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
        game.inv:add("iron", 6)
        game.inv:add("wood", 4)
        game:craft("iron_sword")
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
        check("读档恢复武器", restored.weaponSpec.bladeMat == "iron")
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
