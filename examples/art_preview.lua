--[[
    examples/art_preview.lua —— 素材管线预览（程序化美术）

    这个示例演示的是「美术不靠画，靠算」这条路能走多远：

        角色   一套人形骨架，五种状态，武器实时挂在手上
        怪物   四类骨架 × 皮肤参数，同一骨架能出普通/精英/异变
        武器   刃+柄+芯组装，点「重掷」就是一批全新的武器
        Boss   分节躯体，三个阶段的发光强度变化

    所有图形都由 game/art/ 下的模块用 love.graphics 画出来，
    没有任何贴图文件——所以它能在任意分辨率下保持清晰，
    也能被 tools/artsheet.lua 在没有显卡的机器上渲染成图片做回归。

    运行：love . art_preview
]]

local C = require("game.art.creature")
local Weapon = require("game.art.weapon")
local Boss = require("game.art.boss")
local Palette = require("game.art.palette")
local Rng = require("game.art.rng")

local M = { title = "素材管线", clear = false }

local state = {
    page = 1,
    t = 0,
    seed = 1,
    hit = 0,          -- 受击闪白计时
    swing = 0,        -- 挥砍进度 0~1
}

local PAGES = { "角色", "怪物", "武器", "Boss" }

-- 每页的骨架只建一次，切页不重建（建骨架有分配，别每帧做）
local rigs = {}
local function getRigs()
    if not rigs.hero then
        rigs.hero = C.humanoid({})
        rigs.skeleton = C.humanoid({ cloth = "rot", skin = "bone", helmet = true })
        rigs.crawler = C.crawler({ shell = "chitin", leg = "iron" })
        rigs.elite = C.crawler({ shell = "void", leg = "crystal", size = 1.25 })
        rigs.blob = C.blob({ body = "slime" })
        rigs.flyer = C.flyer({ body = "void" })
        rigs.boss = Boss.stoneMaw({})
        rigs.sword = Weapon.build({
            class = "sword", bladeTier = 3, hiltTier = 2, coreTier = 2,
            bladeMat = "iron", hiltMat = "leather", affixes = { "fire" },
        })
        rigs.great = Weapon.build({
            class = "great", bladeTier = 5, hiltTier = 4, coreTier = 4,
            bladeMat = "void", hiltMat = "iron", affixes = { "void", "crit" },
        })
    end
    return rigs
end

-- ---------------------------------------------------------------- 绘制

local function hline(g, x, y, w, a)
    g.setColor(1, 1, 1, a or 0.10)
    g.rectangle("fill", x, y, w, 1)
end

local function caption(g, x, y, w, h)
    -- 内容区底衬：只画一层很淡的框，不抢主体
    g.setColor(1, 1, 1, 0.03)
    g.rectangle("fill", x, y, w, h, 8)
    g.setColor(1, 1, 1, 0.06)
    g.rectangle("line", x, y, w, h, 8)
end

local function drawHeroPage(g, t)
    local r = getRigs()
    local x0, y0 = 300, 260
    local states = {
        { "idle", t * 0.5, 1, r.sword, -0.9 },
        { "run", t * 0.55, 1, r.sword, -0.9 },
        { "attack", state.swing, 1, r.great, -0.6 },
        { "hurt", math.min(1, state.hit * 3), 1, r.sword, -0.9 },
        { "run", t * 0.55, -1, r.great, -0.6 },
    }
    for i, s in ipairs(states) do
        local x = x0 + (i - 1) * 118
        C.draw(g, r.hero, x, y0, s[3], s[1], s[2], {
            scale = 3.4,
            weapon = s[4],
            weaponAngle = s[5],
            tint = (s[1] == "hurt" and state.hit > 0.05) and { 1, 0.55, 0.55 } or nil,
        })
        hline(g, x - 26, y0 + 34, 52, 0.08)
    end
end

local function drawMonsterPage(g, t)
    local r = getRigs()
    local y = 300
    C.draw(g, r.skeleton, 300, y, 1, "idle", t * 0.5, { scale = 3.4 })
    C.draw(g, r.crawler, 400, y, 1, "run", t * 0.6, { scale = 4.4 })
    C.draw(g, r.blob, 480, y + 6, 1, "idle", t * 0.7, { scale = 3.6 })
    C.draw(g, r.flyer, 560, y - 10, 1, "idle", t, { scale = 4.0 })
    C.draw(g, r.elite, 660, y, 1, "run", t * 0.8, { scale = 4.0 })

    hline(g, 270, y + 34, 430, 0.08)
end

local function drawWeaponPage(g, t)
    local classes = { "sword", "great", "axe", "spear", "hammer", "dagger" }
    local mats = { "copper", "iron", "crystal", "void", "endgame" }
    local affixes = { "fire", "frost", "void", "blood", "crit", "guard" }

    for i = 1, 12 do
        local cls = classes[(i - 1) % #classes + 1]
        local tier = (i - 1) % 5 + 1
        local rng = Rng.new(Rng.hash(state.seed, i))
        local spec = {
            class = cls,
            bladeTier = tier,
            hiltTier = math.min(5, tier + rng:int(-1, 1)),
            coreTier = tier,
            bladeMat = mats[tier],
            hiltMat = tier >= 3 and "iron" or "wood",
            affixes = { rng:pick(affixes) },
            seed = rng:next(),
        }
        local vis = Weapon.build(spec)

        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local x = 300 + col * 168
        local y = 190 + row * 130
        Weapon.draw(g, vis, x, y, -0.22, 2.6)
        hline(g, x - 60, y + 62, 120, 0.07)
    end
end

local function drawBossPage(g, t)
    local r = getRigs()
    -- 三个阶段：发光强度递减，甲壳变暗，玩家能看出"它变了"
    for phase = 1, 3 do
        local skel = Boss.stoneMaw({})
        Boss.applyPhase(skel, phase)
        local y = 180 + (phase - 1) * 130
        Boss.draw(g, skel, 330, y, 1, phase == 2 and "roar" or "idle", t * 0.6, { scale = 1.7 })
        hline(g, 280, y + 46, 420, 0.06)
    end
end

function M.drawWorld(t)
    local host = rawget(_G, "love")
    local g = host and host.graphics
    if not g then return end

    state.t = t
    local W = g.getWidth()

    g.clear(0.09, 0.09, 0.12)

    -- 背景网格
    g.setColor(1, 1, 1, 0.02)
    for x = 0, W, 40 do g.rectangle("fill", x, 0, 1, g.getHeight()) end
    for y = 0, g.getHeight(), 40 do g.rectangle("fill", 0, y, W, 1) end

    -- 内容区（左栏留给 UI）
    local cx, cy = 250, 96
    caption(g, cx, cy, W - cx - 40, 470)

    if state.page == 1 then
        drawHeroPage(g, t)
    elseif state.page == 2 then
        drawMonsterPage(g, t)
    elseif state.page == 3 then
        drawWeaponPage(g, t)
    else
        drawBossPage(g, t)
    end
end

-- ---------------------------------------------------------------- UI

function M.build(ui, ctx)
    state.page = 1
    state.seed = 1

    ui:root({ direction = "row", padding = 18, gap = 16, align = "start" })

    ui:box({
        direction = "column", gap = 8, padding = 14, w = 200,
        bg = "surface", radius = "medium", border = "border", elevation = 2,
    }, function(c)
        c:label("素材管线", { variant = "title" })
        c:label("程序化生成 · 零贴图", { variant = "caption", color = "muted" })

        for i, name in ipairs(PAGES) do
            c:button(name, {
                variant = (state.page == i) and "filled" or "text",
                onClick = function()
                    state.page = i
                    ctx.feedback("切换到「" .. name .. "」")
                end,
            })
        end

        c:box({ h = 1, bg = "border", w = "full" }, function() end)

        c:button("重掷武器种子", {
            variant = "tonal",
            onClick = function()
                state.seed = state.seed + 1
                ctx.feedback("第 " .. state.seed .. " 批武器")
            end,
        })
        c:button("演示挥砍", {
            variant = "tonal",
            onClick = function()
                state.swing = 0.02
            end,
        })
        c:button("演示受击", {
            variant = "outlined",
            onClick = function()
                state.hit = 1
            end,
        })
    end)

    ui:box({
        direction = "column", gap = 6, padding = 14, w = 260,
        bg = "surface", radius = "medium", border = "border",
    }, function(c)
        c:label("这套素材怎么来的", { variant = "subtitle" })
        c:label(
            "角色是「骨架 + 皮肤参数」，不是逐帧贴图。攻击的手感来自角度曲线，"
            .. "所以攻速词条改的是时间轴，不用重画动画。",
            { wrap = true, color = "muted" })
        c:label(
            "武器按「刃 + 柄 + 芯」当场算出来，同一种子必然得到同一把，"
            .. "存档只存几个数字。",
            { wrap = true, color = "muted" })
        c:label(
            "Boss 用独立节点拼躯体，尾节单独发光——那是它的弱点，"
            .. "也是三个阶段里唯一会变暗的部件。",
            { wrap = true, color = "muted" })
    end)
end

function M.update(dt)
    if state.swing > 0 then
        state.swing = state.swing + dt * 2.4
        if state.swing >= 1 then state.swing = 0 end
    end
    if state.hit > 0 then
        state.hit = math.max(0, state.hit - dt * 1.6)
    end
end

return M
