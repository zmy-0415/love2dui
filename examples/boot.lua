--[[
    examples/boot.lua —— 示例公共外壳

    所有示例只导出一张描述表，窗口与事件转发由本模块统一处理：

        return {
            title = "布局",                     -- 窗口标题后缀
            build = function(ui, ctx) ... end,  -- 在 ui:root 内构建界面
        }

    ctx 提供：
        ctx.name          示例标识（如 "layout"）
        ctx.feedback(msg) 控制台 + Toast 双通道反馈

    全局快捷键（与具体示例无关）：
        F1  深/浅主题切换
        F2  调试面板（FPS / 节点数）

    注意：本模块不在 require 时写全局 love.*，而是等 boot.start 被调用
    才安装回调，这样纯 Lua 测试可以安全 require 它。
]]

local lumi = require("lumi")

local boot = {}

local scene           -- 当前场景
local installed = false

local function setTitle(text)
    local w = rawget(_G, "love")
    w = w and w.window
    if w and w.setTitle then pcall(w.setTitle, text) end
end

local function toggleTheme()
    local mode = lumi.theme.current.mode
    local nextMode = (mode == "dark") and "light" or "dark"
    scene:setTheme(nextMode)
    return nextMode
end

-- 把 LÖVE 事件转发到场景；只安装一次
local function install()
    if installed then return end
    installed = true

    function love.update(dt)
        if not scene then return end
        scene:update(dt)
        lumi.debug.update(dt)
    end

    function love.draw()
        if not scene then return end
        scene:draw()
        lumi.debug.draw(scene)
    end

    function love.mousepressed(x, y, button)
        if scene then scene:mousepressed(x, y, button) end
    end

    function love.mousereleased(x, y, button)
        if scene then scene:mousereleased(x, y, button) end
    end

    function love.mousemoved(x, y)
        if scene then scene:mousemoved(x, y) end
    end

    function love.wheelmoved(x, y)
        if scene then scene:wheelmoved(x, y) end
    end

    function love.textinput(text)
        if scene then scene:textinput(text) end
    end

    function love.textedited(text, start, length)
        if scene then scene:textedited(text, start, length) end
    end

    function love.resize(w, h)
        if scene then scene:resize(w, h) end
    end

    function love.keypressed(key)
        if key == "f1" then
            local mode = toggleTheme()
            scene:toast("主题：" .. (mode == "dark" and "深色" or "浅色"))
            return
        elseif key == "f2" then
            lumi.debug.toggle()
            return
        end
        if scene then scene:keypressed(key) end
    end
end

--- 启动示例
--  @param def table  { title = <string>, build = <function(ui, ctx)> }
--  @param name string 示例标识，用于窗口标题
function boot.start(def, name)
    install()
    scene = lumi.new()

    local ctx = {
        name = name,
        feedback = function(msg)
            print("[LumiUI] " .. msg)
            if scene then scene:toast(msg) end
        end,
    }

    setTitle("LumiUI · " .. (def.title or name))
    def.build(scene, ctx)
    return scene
end

--- 当前场景（供自检/调试取用）
function boot.scene()
    return scene
end

return boot
