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

local M = { title = "裂界 · 垂直切片", clear = false }

local game
local hud = {}
local prevJump = false
local prevPlace = false
local prevReset = false
local prevCraft = false
local uiRef
local wasDead = false
local wasVictory = false
local saveTimer = 0

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

    -- 右下：操作与矿脉摘要
    ui:box({ direction = "column", gap = 6, align = "end" }, function(c)
        hud.pickText = Label.new({ text = "背包空", variant = "caption", color = "muted" })
        c:add(hud.pickText)
        c:label("A/D 移动 · 空格跳 · 左键挖/砍 · 右键放 · C 合成 · R 重开",
            { variant = "caption", color = "muted" })
    end)
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

    -- 合成面板
    local craftKey = anyKeyDown("c")
    if craftKey and not prevCraft then openCraft() end
    prevCraft = craftKey

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
end

function M.drawWorld(t)
    local lv = host()
    local g = lv and lv.graphics
    if not g or not game then return end
    game:draw(g)
end

return M
