--[[
    love_stub.lua —— 用假后端拼出一个最小可用的全局 love

    框架本身只经过 lumi/platform 访问 LÖVE，所以「跑框架」不需要真 LÖVE；
    但 tests/run.lua 里有几处直接读写 love.graphics（字体状态、polygon 计数），
    这些用例只有在全局存在 love 时才有意义。本文件把那层接口补上：

        local install = dofile(dir .. "/love_stub.lua")
        local backend = install({ width = 800, height = 600 })
        require("tests.run").run()

    注意：love.graphics 就是假后端里的同一个表，因此测试里改写
    love.graphics.setColor 之类的钩子能真正拦到框架的绘制调用。
]]

return function(opts)
    local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or "."
    local newBackend = dofile(dir .. "/fake_backend.lua")

    local backend, calls, state = newBackend(opts)
    local G = backend.graphics

    -- 字体状态：draw.setFont 之后能读回当前字体（真实 LÖVE 的 getFont 语义）
    local currentFont = nil
    local rawSetFont = G.setFont
    G.setFont = function(f)
        currentFont = f
        return rawSetFont(f)
    end
    G.getFont = function() return currentFont end

    _G.love = {
        graphics = G,
        keyboard = backend.keyboard,
        system = backend.system,
        timer = backend.timer,
        filesystem = backend.filesystem,
    }

    return backend, calls, state
end
