--[[
    examples.lua —— 示例构建冒烟测试

    遍历 examples/ 下的每个示例，在假后端上完成「建树 → 布局 → 绘制」，
    确保拆分后的示例不会因为 API 变更而静默失效。不需要 LÖVE。

    用法（项目根目录）：
        luajit tests/examples.lua
    退出码 0 表示全部通过。
]]

local script = (arg and arg[0]) or "tests/examples.lua"
local dir = script:match("^(.*)[/\\][^/\\]+$") or "."
package.path = dir .. "/../?.lua;" .. dir .. "/../?/init.lua;" .. package.path

local newBackend = dofile(dir .. "/fake_backend.lua")

local lumi = require("lumi")

-- 与 main.lua 中的列表保持一致
local EXAMPLES = { "minimal", "layout", "forms", "editor", "data", "theme", "showcase" }

local total, failed = 0, 0
local function ok(desc, cond)
    total = total + 1
    if cond then
        print("  [PASS] " .. desc)
    else
        failed = failed + 1
        print("  [FAIL] " .. desc)
    end
end

for _, name in ipairs(EXAMPLES) do
    print("[EXAMPLES] " .. name)
    local loaded, def = pcall(require, "examples." .. name)
    ok(name .. " 模块可加载", loaded and type(def) == "table")
    if not loaded then
        print("         " .. tostring(def))
    else
        ok(name .. " 声明了 build", type(def.build) == "function")
        ok(name .. " 声明了 title", type(def.title) == "string")

        local backend = newBackend({ width = 1000, height = 700 })
        local ui = lumi.new({ backend = backend, width = 1000, height = 700 })
        local ctx = { name = name, feedback = function() end }

        local built, err = pcall(def.build, ui, ctx)
        ok(name .. " 构建不抛异常", built)
        if not built then print("         " .. tostring(err)) end

        ok(name .. " 产生了根节点", ui.root ~= nil)
        ok(name .. " 根节点有子节点", ui.root ~= nil and #ui.root.children > 0)

        -- 布局 + 两帧绘制：捕获绘制阶段的错误（例如属性拼写错误导致 nil 下标）
        local stepped, stepErr = pcall(function()
            ui:update(1 / 60)
            ui:draw()
            ui:update(1 / 60)
            ui:draw()
        end)
        ok(name .. " 布局与绘制不抛异常", stepped)
        if not stepped then print("         " .. tostring(stepErr)) end
    end
end

print(string.format("[EXAMPLES] %d total, %d passed, %d failed", total, total - failed, failed))
os.exit(failed == 0 and 0 or 1)
