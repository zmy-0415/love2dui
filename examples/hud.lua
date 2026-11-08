--[[
    examples/hud.lua —— 游戏内 HUD（UI 叠在游戏画面之上）

    这是「把 LumiUI 用进游戏」的最小样板，关键只有两条：
        lumi.new({ clear = false })   -- draw 时不清屏，否则游戏画面会被擦掉
        根容器不设 bg                  -- 不铺底色，游戏画面直接透出来

    游戏世界由 drawWorld 用 love.graphics 直接画（与框架无关），
    HUD 则完全是普通控件，事件转发、主题切换、弹窗遮罩都照常工作。

    运行：love . hud
]]

local Label = require("lumi.widgets.label")
local Progress = require("lumi.widgets.progress")

local M = { title = "游戏 HUD", clear = false }

-- ---------------- 假游戏世界：纯 LÖVE 绘制，不依赖框架 ----------------

local STAR_SEED = 7919

function M.drawWorld(t)
    local host = rawget(_G, "love")
    local g = host and host.graphics
    if not g then return end

    -- 天空
    g.clear(0.05, 0.06, 0.10)

    -- 星点：用固定种子算出位置，避免每帧分配表
    for i = 1, 140 do
        local x = (i * STAR_SEED) % 1000
        local y = (i * 137) % 700
        g.setColor(1, 1, 1, 0.10 + (i % 5) * 0.05)
        g.rectangle("fill", x, y, 2, 2)
    end

    -- 敌人：绕中心缓慢公转的三角
    for i = 1, 5 do
        local a = t * 0.6 + i * (math.pi * 2 / 5)
        local ex = 500 + math.cos(a) * (180 + i * 22)
        local ey = 350 + math.sin(a) * (110 + i * 12)
        g.setColor(1, 0.42, 0.42, 0.9)
        g.push()
        g.translate(ex, ey)
        g.rotate(a * 2)
        g.polygon("fill", 0, -12, 10, 9, -10, 9)
        g.pop()
    end

    -- 玩家：屏幕中央旋转的方块
    g.setColor(0.35, 0.85, 1)
    g.push()
    g.translate(500, 350)
    g.rotate(t * 1.2)
    g.rectangle("fill", -34, -34, 68, 68, 10, 10)
    g.pop()
end

-- ---------------- HUD ----------------

local state

function M.build(ui, ctx)
    state = { hp = 48, maxHp = 100, score = 1234, t = 0, shown = 48 }

    ui:root({ direction = "row", padding = 18, justify = "space-between", align = "start" })

    -- 左上：状态面板（局部容器才设 bg，根容器保持透明）
    ui:box({
        direction = "column", gap = 10, padding = 14, w = 300,
        bg = "surface", radius = "medium", border = "border", elevation = 2,
    }, function(c)
        c:label("STATUS", { variant = "caption", color = "muted" })
        -- 需要保留引用的控件自己 new 出来再 c:add，链式调用返回的是场景而不是节点
        state.hpText = Label.new({ text = "HP 48 / 100", variant = "subtitle" })
        c:add(state.hpText)
        state.hpBar = Progress.new({ value = state.hp, max = state.maxHp, color = "success" })
        c:add(state.hpBar)
        c:label("SCORE 1234", { variant = "title" })
    end)

    -- 右下：操作区
    ui:box({ direction = "column", gap = 10, align = "end" }, function(c)
        c:box({ direction = "row", gap = 8, padding = 10, bg = "surface", radius = "medium" }, function(r)
            r:button("治疗 +20", {
                variant = "tonal",
                onClick = function()
                    state.hp = math.min(state.maxHp, state.hp + 20)
                    ctx.feedback("恢复 20 点生命")
                end,
            })
            r:button("受伤 -15", {
                variant = "outlined",
                onClick = function()
                    state.hp = math.max(0, state.hp - 15)
                    if state.hp <= 0 then ui:toast("你已阵亡", "error") end
                end,
            })
            r:button("设置", {
                variant = "filled",
                onClick = function()
                    -- 弹窗是模态浮层，遮罩会盖在游戏画面上；关掉后 HUD 继续叠在游戏上
                    ui:dialog({ title = "游戏设置", closable = true }, function(p)
                        p:label("HUD 场景里弹窗、Toast、下拉都照常工作。", { wrap = true, color = "muted" })
                        p:box({ direction = "row", gap = 8, justify = "end" }, function(x)
                            x:button("取消", {
                                variant = "text",
                                onClick = function() ui:closeAllOverlays() end,
                            })
                            x:button("确定", {
                                variant = "filled",
                                onClick = function()
                                    ui:closeAllOverlays()
                                    ui:toast("设置已保存", "success")
                                end,
                            })
                        end)
                    end)
                end,
            })
        end)
        c:label("UI 层独立于游戏世界，F1 切主题", { variant = "caption", color = "muted" })
    end)
end

function M.update(dt)
    if not state then return end
    state.t = state.t + dt

    -- 每帧回调：血量缓慢自然恢复
    if state.hp < state.maxHp then
        state.hp = math.min(state.maxHp, state.hp + dt * 2.5)
        state.hpBar:setValue(state.hp)
    end

    -- 数值只在整数变化时才改文本，避免每帧 setProp 触发重排
    local shownNow = math.floor(state.hp)
    if shownNow ~= state.shown then
        state.shown = shownNow
        state.hpText:setProp("text", string.format("HP %d / %d", shownNow, state.maxHp))
    end
end

return M
