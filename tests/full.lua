--[[
    full.lua —— 纯 Lua 跑完整功能套件（不需要 LÖVE、不需要显卡）

    tests/run.lua 原本只能在真实 LÖVE 里跑（它直接读写 love.graphics），
    这里把 love 换成假后端后即可在 CI 的任何 Lua 解释器上验证全部断言。

    用法（项目根目录）：
        luajit  tests/full.lua
        lua5.4  tests/full.lua
    退出码 0 表示全部通过。
]]

local script = (arg and arg[0]) or "tests/full.lua"
local dir = script:match("^(.*)[/\\][^/\\]+$") or "."
package.path = dir .. "/../?.lua;" .. dir .. "/../?/init.lua;" .. package.path

local install = dofile(dir .. "/love_stub.lua")
install({ width = 800, height = 600 })

local failed = require("tests.run").run()
print(string.format("[FULL] %s", failed == 0 and "all passed" or (failed .. " failed")))
os.exit(failed == 0 and 0 or 1)
