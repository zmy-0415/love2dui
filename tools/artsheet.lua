--[[
    tools/artsheet.lua —— 素材图鉴 / 视觉回归出图

    这个工具解决一个很实际的问题：开发机没有 OpenGL，`love .` 起不来，
    但美术效果必须能看、能比对、能回归。所以图鉴用软光栅渲染，
    直接吐一张 BMP，既能肉眼看，也能在 CI 里比 checksum。

    用法：
        luajit tools/artsheet.lua                 -- 输出 art_sheet.bmp
        luajit tools/artsheet.lua out.bmp 2       -- 指定路径与放大倍数

    版式：
        第 1 行  玩家 6 种状态（含持武器）
        第 2 行  四类怪物 + 石喉 Boss
        第 3 行  六类武器 × 三档
        第 4 行  调色板（材质色阶，确认整体色域没跑偏）
]]

local sr = require("tools.softraster")
local C = require("game.art.creature")
local Weapon = require("game.art.weapon")
local Boss = require("game.art.boss")
local Palette = require("game.art.palette")

local Sheet = {}

local W, H = 800, 500

local function label(g, x, y, w)
    -- 软光栅没有字体：用一道细线当作分组标记，保证版式可读
    g.setColor(1, 1, 1, 0.16)
    g.rectangle("fill", x, y, w, 1)
end

--[[ 画整张图鉴。g 可以是软光栅，也可以是 love.graphics（真机上直接复用） ]]
function Sheet.draw(g)
    g.clear(0.10, 0.10, 0.13)

    -- 背景网格：微弱的方格，方便判断物体在场景里的实际尺寸
    g.setColor(1, 1, 1, 0.022)
    for x = 0, W, 32 do g.rectangle("fill", x, 0, 1, H) end
    for y = 0, H, 32 do g.rectangle("fill", 0, y, W, 1) end

    -- ---------------- 第 1 行：玩家
    label(g, 16, 108, W - 32)

    local hero = C.humanoid({})
    local sword = Weapon.build({
        class = "sword", bladeTier = 3, hiltTier = 2, coreTier = 2,
        bladeMat = "iron", hiltMat = "leather", affixes = { "fire" },
    })
    local great = Weapon.build({
        class = "great", bladeTier = 5, hiltTier = 4, coreTier = 4,
        bladeMat = "void", hiltMat = "iron", affixes = { "void", "crit" },
    })

    local states = {
        { "idle", 0.4, { weapon = sword, weaponAngle = -0.9 } },
        { "run", 0.13, { weapon = sword, weaponAngle = -0.9 } },
        { "attack", 0.34, { weapon = great, weaponAngle = -0.6 } },
        { "attack", 0.50, { weapon = great, weaponAngle = -0.2 } },
        { "hurt", 0.22, { weapon = sword, weaponAngle = -0.9 } },
        { "run", 0.4, { weapon = sword, weaponAngle = -0.9, facing = -1 } },
    }
    for i, s in ipairs(states) do
        C.draw(g, hero, 50 + (i - 1) * 58, 88, s[3].facing or 1, s[1], s[2],
            { scale = 1.9, weapon = s[3].weapon, weaponAngle = s[3].weaponAngle })
    end

    -- ---------------- 第 2 行：怪物
    label(g, 16, 216, W - 32)

    C.draw(g, C.humanoid({ cloth = "rot", skin = "bone", helmet = true }),
        50, 200, 1, "idle", 0.5, { scale = 1.9 })
    C.draw(g, C.crawler({ shell = "chitin", leg = "iron" }), 132, 196, 1, "run", 0.3, { scale = 2.8 })
    C.draw(g, C.blob({ body = "slime" }), 215, 200, 1, "idle", 0.6, { scale = 2.4 })
    C.draw(g, C.flyer({ body = "void" }), 290, 188, 1, "idle", 0.4, { scale = 2.6 })

    -- 精英变体：同一骨架换色，验证「一只怪三种皮肤」这条路走不走得通
    C.draw(g, C.crawler({ shell = "void", leg = "crystal", size = 1.25 }), 370, 200, 1, "run", 0.9, { scale = 2.4 })

    -- Boss
    local maw = Boss.stoneMaw({})
    Boss.draw(g, maw, 500, 190, 1, "idle", 0.8, { scale = 1.5 })
    Boss.draw(g, maw, 660, 196, -1, "roar", 0, { scale = 1.1 })

    -- ---------------- 第 3 行：武器（M2 八品类）
    -- 八把 × 两档 = 16 件，挤在一行里每件只剩 48px，长枪和匕首会糊成一片。
    -- 所以拆成两行、每行四把，宁可多占 50px 也要让轮廓能分辨——
    -- 这张图存在的意义就是「一眼看出八把不是同一把武器」
    label(g, 16, 288, W - 32)

    local classes = { "sword", "dagger", "spear", "sickle", "great", "axe", "hammer", "bow" }
    local mats = { "copper", "iron", "crystal", "void", "endgame" }

    local function drawClassRow(list, y)
        local i = 0
        for _, cls in ipairs(list) do
            for _, tier in ipairs({ 2, 5 }) do
                i = i + 1
                local vis = Weapon.build({
                    class = cls, bladeTier = tier, hiltTier = tier, coreTier = tier,
                    bladeMat = mats[tier], hiltMat = tier >= 3 and "iron" or "wood",
                    -- 用真实词条 id，这样出图同时也验证了「词条 → 外观」这条链
                    affixes = tier >= 4 and { "kindle" } or {},
                })
                Weapon.draw(g, vis, 26 + (i - 1) * 92, y, -0.10, 2.4)
            end
        end
    end

    drawClassRow({ "sword", "dagger", "spear", "sickle" }, 300)
    label(g, 16, 364, W - 32)
    drawClassRow({ "great", "axe", "hammer", "bow" }, 378)

    -- ---------------- 第 4 行：调色板
    label(g, 16, 452, W - 32)
    local keys = { "wood", "stone", "copper", "iron", "crystal", "rot",
                   "ember", "void", "endgame", "chitin", "slime", "bone" }
    local steps = { "edge", "dark", "base", "light", "glow" }
    for ki, k in ipairs(keys) do
        for si, st in ipairs(steps) do
            g.setColor(Palette.rgba(k, st))
            g.rectangle("fill", 20 + (ki - 1) * 64 + (si - 1) * 12, 462, 10, 10, 1.5)
        end
    end
end

-- 放大保存：整数倍最近邻放大，保持像素边缘干净
function Sheet.save(g, path, factor)
    factor = factor or 2
    if factor == 1 then
        g.saveBMP(path)
        return path
    end
    local big = sr.new(g.w * factor, g.h * factor)
    for y = 0, g.h - 1 do
        for x = 0, g.w - 1 do
            local r, gg, b = g.getPixel(x, y)
            big.setColor(r / 255, gg / 255, b / 255, 1)
            big.rectangle("fill", x * factor, y * factor, factor, factor)
        end
    end
    big.saveBMP(path)
    return path
end

function Sheet.render(path, factor)
    local g = sr.new(W, H)
    Sheet.draw(g)
    return Sheet.save(g, path or "art_sheet.bmp", factor)
end

Sheet.W, Sheet.H = W, H

if arg and arg[0] and arg[0]:find("artsheet") then
    local out = Sheet.render(arg[1], tonumber(arg[2]) or 2)
    print("wrote " .. out)
end

return Sheet
