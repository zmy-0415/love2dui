--[[
    examples/rift.lua —— 《裂界》垂直切片

    这是 game/ 那一套代码在真机上的入口。它只做三件事：
        1. 把 love 的键盘/鼠标状态采集成本帧输入表
        2. 每帧推进 Game
        3. 用 LumiUI 画 HUD（血条、耐力、背包）

    关键点：游戏世界由 drawWorld 用 love.graphics 直接画，清屏关掉（clear = false），
    HUD 是普通 LumiUI 控件叠在上面。UI 的布局、主题、弹窗全部照常工作，
    和游戏逻辑没有任何耦合——这正是把 UI 框架和游戏分开的意义。

    运行：love . rift

    操作：
        A / D 或 ← / →   移动
        空格             跳跃（按住跳更高）
        鼠标左键按住      挖掘
        鼠标右键         放置方块
        R                重开
]]

local Label = require("lumi.widgets.label")
local Progress = require("lumi.widgets.progress")

local Game = require("game.game")
local Recipes = require("game.data.recipes")
local Forge = require("game.core.forge")
local Parts = require("game.data.parts")
local Weapons = require("game.data.weapons")
local Affix = require("game.core.affix")

local M = { title = "裂界 · 垂直切片", clear = false }

local game
local hud = {}
local prevJump = false
local prevPlace = false
local prevReset = false
local prevCraft = false
local prevForge = false
local uiRef
local wasDead = false
local wasVictory = false
local saveTimer = 0

-- 锻造台的选择状态。放在模块级而不是 dialog 里：
-- 玩家关掉弹窗再打开，应该还停在上次选的位置，而不是被重置成铜剑
local forgeSpec = { class = "sword", bladeMat = "copper", hilt = "wood", core = "none" }

-- ---------------- 输入采集 ----------------

local function host()
    return rawget(_G, "love")
end

local function anyKeyDown(...)
    local lv = host()
    local kb = lv and lv.keyboard
    if not kb or not kb.isDown then return false end
    for i = 1, select("#", ...) do
        if kb.isDown((select(i, ...))) then return true end
    end
    return false
end

local function readInput()
    local lv = host()
    local mx, my = game.vw * 0.5, game.vh * 0.5
    local dig, place = false, false

    local m = lv and lv.mouse
    if m then
        if m.getPosition then
            local x, y = m.getPosition()
            if x then mx, my = x, y end
        end
        dig = m.isDown and m.isDown(1) or false
        place = m.isDown and m.isDown(2) or false
    end

    local jump = anyKeyDown("space", "w", "up")
    local reset = anyKeyDown("r")

    local input = {
        left = anyKeyDown("a", "left"),
        right = anyKeyDown("d", "right"),
        jump = jump,
        jumpPressed = jump and not prevJump,
        dig = dig,
        place = place and not prevPlace,
        mouseX = mx,
        mouseY = my,
    }
    local shouldReset = reset and not prevReset
    prevJump, prevPlace, prevReset = jump, place, reset
    return input, shouldReset
end

-- ---------------- 合成面板 ----------------

local function costText(r)
    local parts = {}
    for k, n in pairs(r.cost) do
        parts[#parts + 1] = string.format("%s×%d", k, n)
    end
    table.sort(parts)
    return table.concat(parts, " ")
end

local openCraft

openCraft = function()
    local ui = uiRef
    if not ui then return end
    ui:dialog({ title = "合成台", closable = true }, function(p)
        p:label("挖到的材料在这里变成战斗力。C 键随时打开。",
            { variant = "caption", color = "muted", wrap = true })

        for _, r in ipairs(Recipes.list) do
            local ok = game:canCraft(r.id)
            p:box({
                direction = "row", gap = 10, align = "center", padding = 10,
                bg = "surface", radius = "small", border = "border",
            }, function(row)
                row:box({ direction = "column", gap = 2 }, function(col)
                    col:label(r.name, { variant = "subtitle" })
                    col:label(r.desc, { variant = "caption", color = "muted" })
                    col:label(costText(r) .. (ok and "" or ("  缺 " .. Recipes.missing(r, game.inv))),
                        { variant = "caption", color = ok and "success" or "danger" })
                end)
                row:button(ok and "制作" or "不足", {
                    variant = ok and "filled" or "text",
                    onClick = function()
                        local done, err = game:craft(r.id)
                        if done then
                            ui:toast("制作成功：" .. r.name, "success")
                            ui:closeAllOverlays()
                            openCraft()
                        else
                            ui:toast(err or "制作失败", "error")
                        end
                    end,
                })
            end)
        end
    end)
end

-- ---------------- 锻造台 ----------------

local function fmtCost(cost)
    local parts = {}
    for k, n in pairs(cost or {}) do
        parts[#parts + 1] = string.format("%s×%d", k, n)
    end
    if #parts == 0 then return "无" end
    table.sort(parts)
    return table.concat(parts, "  ")
end

-- 一排可选项。选中的用 filled，其余 outlined——
-- 这样「现在选的是哪个」在扫一眼时就能看出来，不用去读文字
local function pickChips(p, title, items, cur, onPick, nameOf)
    p:label(title, { variant = "caption", color = "muted" })
    p:box({ direction = "row", gap = 6, wrap = true }, function(row)
        for _, it in ipairs(items) do
            local sel = (it.id == cur)
            row:button(nameOf(it), {
                variant = sel and "filled" or "outlined",
                onClick = function() onPick(it.id) end,
            })
        end
    end)
end

local openForge

openForge = function()
    local ui = uiRef
    if not ui then return end
    local pv = game:previewForge(forgeSpec)
    -- 每次选择都重建弹窗。这看着笨，但比手动改 30 个按钮的状态可靠得多，
    -- 而且弹窗重建的成本在这个量级下完全感觉不到
    local function rebind()
        ui:closeAllOverlays()
        openForge()
    end

    ui:dialog({ title = "锻造台", closable = true }, function(p)
        p:label("左侧选部件，右侧是这一刀的全部数值。同一套部件可以反复重铸刷词条。",
            { variant = "caption", color = "muted", wrap = true })

        p:box({ direction = "row", gap = 18, align = "start" }, function(row)
            -- ---------------- 左：选部件 ----------------
            row:box({ direction = "column", gap = 10, w = 460 }, function(col)
                pickChips(col, "刃材 · 决定伤害与破韧（挖矿换）", Forge.blades, forgeSpec.bladeMat,
                    function(id) forgeSpec.bladeMat = id rebind() end,
                    function(it) return it.name end)

                pickChips(col, "品类 · 决定判定框与节奏", Forge.classes, forgeSpec.class,
                    function(id) forgeSpec.class = id rebind() end,
                    function(it) return it.name end)

                -- 当前品类的定位提示。八把武器的差别不在数字上，
                -- 所以必须有一句话把它讲出来，否则玩家只会照着伤害选
                do
                    local cur
                    for _, c in ipairs(Forge.classes) do
                        if c.id == forgeSpec.class then cur = c break end
                    end
                    if cur then
                        col:label("　" .. cur.hint, { variant = "caption", color = "accent" })
                    end
                end

                pickChips(col, "柄 · 决定速度与击退（打怪换）", Parts.hilts, forgeSpec.hilt,
                    function(id) forgeSpec.hilt = id rebind() end,
                    function(it) return it.name end)

                pickChips(col, "芯 · 决定命中附加（交叉换）", Parts.cores, forgeSpec.core,
                    function(id) forgeSpec.core = id rebind() end,
                    function(it) return it.name end)

                do
                    local core = Parts.core(forgeSpec.core)
                    if core.desc then
                        col:label("　" .. core.desc, { variant = "caption", color = "muted", wrap = true })
                    end
                end
            end)

            -- ---------------- 右：预览 ----------------
            row:box({
                direction = "column", gap = 6, w = 310, padding = 14,
                bg = "surface", radius = "medium", border = "border",
            }, function(col)
                col:label(Weapons.label(pv), { variant = "subtitle" })

                local function stat(name, val)
                    col:box({ direction = "row", justify = "space-between" }, function(r)
                        r:label(name, { variant = "caption", color = "muted" })
                        r:label(val, { variant = "caption" })
                    end)
                end

                stat("伤害", string.format("%.1f", pv.damage))
                stat("前摇", string.format("%d ms", math.floor(pv.windup * 1000)))
                stat("后摇", string.format("%d ms", math.floor(pv.recovery * 1000)))
                stat("总时长", string.format("%d ms", math.floor(pv.dur * 1000)))
                if pv.ranged then
                    stat("射程", string.format("远程 %d", pv.ranged))
                else
                    stat("判定", string.format("%d ~ %d", pv.back, pv.reach))
                end
                stat("破韧", string.format("%.0f", pv.poise))
                stat("击退", string.format("%.0f", pv.knock))
                stat("出刀机动", string.format("%.0f%%", pv.mobility * 100))
                if pv.element then
                    stat("元素", pv.element)
                end
                stat("词条位", tostring(pv.affixCount))

                col:divider()

                col:label("材料：" .. fmtCost(pv.cost), { variant = "caption", wrap = true })
                if not pv.canMake then
                    col:label("缺 " .. pv.missing, { variant = "caption", color = "danger", wrap = true })
                end

                col:button(pv.canMake and "锻造" or "材料不足", {
                    variant = pv.canMake and "filled" or "outlined",
                    color = pv.canMake and "primary" or "muted",
                    onClick = function()
                        if not pv.canMake then
                            ui:toast("缺 " .. pv.missing, "error")
                            return
                        end
                        local ok, err, affixes = game:forge(forgeSpec)
                        if not ok then
                            ui:toast(err or "锻造失败", "error")
                            return
                        end
                        local names = {}
                        for _, id in ipairs(affixes or {}) do
                            names[#names + 1] = Affix.name(id)
                        end
                        if #names > 0 then
                            ui:toast("锻造成功 · " .. table.concat(names, " / "), "success")
                        else
                            ui:toast("锻造成功（这套部件没有词条位）", "success")
                        end
                        rebind()
                    end,
                })
            end)
        end)
    end)
end

-- 暴露给测试与外部宿主：可以不按键、直接打开锻造台。
-- 这不是为了测试硬塞的口子——宿主完全可能想在暂停菜单里挂一个「锻造」按钮
M.openForge = function() return openForge() end
M.openCraft = function() return openCraft() end

-- ---------------- 构建 ----------------

local function screenSize()
    local lv = host()
    local g = lv and lv.graphics
    if g and g.getDimensions then
        local w, h = g.getDimensions()
        if w and w > 0 then return w, h end
    end
    return 1280, 720
end

function M.build(ui, ctx)
    uiRef = ui
    local w, h = screenSize()
    -- 有存档就接着玩，没有就开新局。自动读档比「按一下继续」更适合这个品类：
    -- 玩家关窗口时并没有「退出游戏」的心理动作
    local loaded
    game, loaded = Game.loadOrNew({ w = w, h = h })
    saveTimer = 0
    if loaded and ui then ui:toast("已读取存档", "success") end

    ui:root({ direction = "row", padding = 16, justify = "space-between", align = "end" })

    -- 左下：状态
    ui:box({
        direction = "column", gap = 8, padding = 12, w = 236,
        bg = "surface", radius = "medium", border = "border", elevation = 2,
    }, function(c)
        c:label("裂界 · 洞穴表层", { variant = "caption", color = "muted" })
        hud.hpText = Label.new({ text = "生命 100 / 100", variant = "subtitle" })
        c:add(hud.hpText)
        hud.hpBar = Progress.new({ value = 100, max = 100, color = "danger" })
        c:add(hud.hpBar)
        hud.stText = Label.new({ text = "耐力", variant = "caption", color = "muted" })
        c:add(hud.stText)
        hud.stBar = Progress.new({ value = 100, max = 100, color = "accent" })
        c:add(hud.stBar)
        hud.invText = Label.new({ text = "背包 0 / 40", variant = "caption", color = "muted" })
        c:add(hud.invText)
    end)

    -- 右下：操作与当前武器
    ui:box({ direction = "column", gap = 6, align = "end" }, function(c)
        hud.weaponText = Label.new({ text = "武器", variant = "caption", color = "accent" })
        c:add(hud.weaponText)
        hud.pickText = Label.new({ text = "背包空", variant = "caption", color = "muted" })
        c:add(hud.pickText)
        c:label("A/D 移动 · 空格跳 · 左键挖/砍 · 右键放 · F 锻造 · C 合成 · R 重开",
            { variant = "caption", color = "muted" })
    end)
end

-- 当前武器的说明：名字 + 词条。玩家得随时知道自己手里是什么，
-- 否则「刷到一把好的」这件事他自己都不知道
local function weaponLine()
    local r = game.resolved
    local s = Weapons.label(r)
    local affixes = game.weaponSpec and game.weaponSpec.affixes or {}
    if #affixes > 0 then
        local names = {}
        for _, id in ipairs(affixes) do names[#names + 1] = Affix.name(id) end
        s = s .. " · " .. table.concat(names, "/")
    end
    return s
end

-- ---------------- 每帧 ----------------

local function fmtInv()
    local parts = {}
    local slots = game.inv.slots
    for i = 1, game.inv.size do
        local s = slots[i]
        if s then
            parts[#parts + 1] = string.format("%s×%d", s.key, s.n)
            if #parts >= 5 then break end
        end
    end
    if #parts == 0 then return "背包空" end
    return table.concat(parts, "  ")
end

local lastHud = { hp = -1, st = -1, inv = -1 }

function M.update(dt)
    if not game then return end

    local w, h = screenSize()
    if w ~= game.vw or h ~= game.vh then game:resize(w, h) end

    local input, shouldReset = readInput()

    -- 合成面板（消耗品）
    local craftKey = anyKeyDown("c")
    if craftKey and not prevCraft then openCraft() end
    prevCraft = craftKey

    -- 锻造台（武器）
    local forgeKey = anyKeyDown("f")
    if forgeKey and not prevForge then openForge() end
    prevForge = forgeKey

    if shouldReset then
        game = Game.new({ w = game.vw, h = game.vh })
        saveTimer = 0
        game:save()
        if uiRef then uiRef:toast("世界已重开", "success") end
    end

    game:update(dt, input)

    -- 自动存档：20 秒一次。存档只有几百字节，频繁写也不心疼，
    -- 但间隔太短会让「刚死就读档」变成一种玩法，所以留一点窗口
    saveTimer = saveTimer + dt
    if saveTimer > 20 then
        saveTimer = 0
        game:save()
    end

    -- 死亡与胜利：只在状态翻转的那一帧提示一次，否则会每帧刷屏
    local p0 = game.player
    if p0.dead and not wasDead then
        wasDead = true
        if uiRef then uiRef:toast("你死了 · 按 R 重开", "error") end
    elseif not p0.dead then
        wasDead = false
    end
    if game.bossDefeated and not wasVictory then
        wasVictory = true
        if uiRef then uiRef:toast("石喉被击败", "success") end
    end

    -- HUD：只在整数变化时改控件，避免每帧触发重排
    local p = game.player
    local hp = math.floor(p.hp + 0.5)
    local st = math.floor(p.stamina + 0.5)
    local used = game.inv:used()
    if hp ~= lastHud.hp then
        lastHud.hp = hp
        hud.hpText:setProp("text", string.format("生命 %d / %d", hp, p.maxHp))
        hud.hpBar:setValue(hp)
    end
    if st ~= lastHud.st then
        lastHud.st = st
        hud.stBar:setValue(st)
        hud.stText:setProp("text", string.format("耐力 %d", st))
    end
    if used ~= lastHud.inv then
        lastHud.inv = used
        hud.invText:setProp("text", string.format("背包 %d / %d", used, game.inv.size))
        hud.pickText:setProp("text", fmtInv())
    end

    -- 武器名只在真的换了武器时更新（锻造/读档），避免每帧拼字符串
    local wline = weaponLine()
    if wline ~= lastHud.weapon then
        lastHud.weapon = wline
        if hud.weaponText then hud.weaponText:setProp("text", wline) end
    end
end

function M.drawWorld(t)
    local lv = host()
    local g = lv and lv.graphics
    if not g or not game then return end
    game:draw(g)
end

return M
