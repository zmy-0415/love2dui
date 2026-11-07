--[[
    headless.lua —— 无 LÖVE 环境的冒烟测试

    作用：证明框架不再依赖全局 `love`。注入一个纯 Lua 后端即可构建界面、
    跑事件、绘制，因此核心逻辑可以在 CI（或任何装了 Lua 的机器）上验证。

    用法（项目根目录）：
        luajit tests/headless.lua
        lua5.4  tests/headless.lua
    退出码 0 表示全部通过。
]]

-- 把项目根目录加入 package.path（脚本可能从任意目录调用）
local script = (arg and arg[0]) or "tests/headless.lua"
local dir = script:match("^(.*)[/\\][^/\\]+$") or "."
package.path = dir .. "/../?.lua;" .. dir .. "/../?/init.lua;" .. package.path

-- ---------------- 记录型后端 ----------------

local calls = {}
local function rec(name)
    calls[name] = (calls[name] or 0) + 1
end

local G = {}
for _, name in ipairs({
    "setColor", "setFont", "setLineWidth", "setLineJoin", "setLineStyle",
    "setScissor", "setStencilTest", "clear", "print", "printf", "rectangle",
    "circle", "arc", "line", "polygon", "points", "push", "pop", "origin",
    "translate", "rotate", "scale", "setCanvas", "draw",
}) do
    G[name] = function(...) rec(name) end
end

G.getWidth = function() return 800 end
G.getHeight = function() return 600 end
G.getScissor = function() return 0, 0, 800, 600 end
G.stencil = function(fn) rec("stencil"); if fn then fn() end end

G.newFont = function()
    return {
        getWidth = function(_, s) return #tostring(s) * 7 end,
        getWrap = function(_, s) return 1000, { tostring(s) } end,
        getHeight = function() return 16 end,
        setFilter = function() end,
    }
end

G.newCanvas = function(w, h)
    return {
        getWidth = function() return w end,
        getHeight = function() return h end,
        getDimensions = function() return w, h end,
        setFilter = function() end,
        release = function() end,
        draw = function() end,
        typeOf = function() return "Canvas" end,
    }
end

local clipboard = ""
local clock = 100
local keysDown = {}

local backend = {
    graphics = G,
    keyboard = {
        isDown = function(k) return keysDown[k] == true end,
        setTextInput = function() rec("setTextInput") end,
    },
    system = {
        getClipboardText = function() return clipboard end,
        setClipboardText = function(t) clipboard = t end,
    },
    timer = { getTime = function() return clock end },
    filesystem = { newFileData = function() error("no filesystem") end },
}

-- ---------------- 断言 ----------------

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

-- ---------------- 用例 ----------------

-- 1. 没有全局 love 也能加载并建树
ok("环境中没有全局 love", rawget(_G, "love") == nil)

local lumi = require("lumi")
local platform = require("lumi.platform")

local clicked = 0
local ui = lumi.new({ backend = backend, width = 400, height = 300 })

ui:root({ direction = "column", padding = 16, gap = 8 }, function(c)
    c:label("无 LÖVE 环境")
    c:button("点我", { w = 120, h = 40, onClick = function() clicked = clicked + 1 end })
    c:input({ placeholder = "输入" })
end)

ok("注入后端后可以创建场景", ui ~= nil and ui.root ~= nil)
ok("窗口尺寸来自注入后端", ui.width == 400 and ui.height == 300)

-- 2. 布局 + 绘制走注入后端
ui:update(0)
ok("标签与按钮完成布局", ui.root.children[2].w > 0 and ui.root.children[2].h > 0)

ui:draw()
ok("绘制产生真实调用", (calls.rectangle or 0) + (calls.print or 0) + (calls.polygon or 0) > 0)

-- 3. 交互：点按钮触发回调
local btn = ui.root.children[2]
local bx, by = btn.x + btn.w / 2, btn.y + btn.h / 2
ui:mousemoved(bx, by)
ui:mousepressed(bx, by, 1)
ui:mousereleased(bx, by, 1)
ok("点击命中按钮并触发 onClick", clicked == 1)

-- 4. 输入：文本输入 + 剪贴板往返
local inp = ui.root.children[3]
ui:mousepressed(inp.x + 10, inp.y + inp.h / 2, 1)
ui:mousereleased(inp.x + 10, inp.y + inp.h / 2, 1)
ui:textinput("你好")
ok("文本输入写入控件", inp._text == "你好")

-- 选中全部（Input 的选区是 cursor + _selAnchor 两个字节位置）
inp.cursor = #inp._text
inp._selAnchor = 0
inp:copy()
ok("复制走注入后端剪贴板", clipboard == "你好")

inp:setText("")
inp:paste()
ok("粘贴读回注入后端剪贴板", inp._text == "你好")

-- 5. 时钟：假时钟可复现光标闪烁
ui:setFocus(inp)
platform.freezeTime(0)      -- 0 % 1 = 0 < 0.55，光标可见
local r0 = calls.rectangle or 0
inp:draw()
local shown = (calls.rectangle or 0) - r0

platform.advance(0.6)       -- 0.6 % 1 > 0.55，光标隐藏
local r1 = calls.rectangle or 0
inp:draw()
local hidden = (calls.rectangle or 0) - r1

ok("光标在闪烁周期前半段绘制", shown == 1)
ok("假时钟推进到后半段后光标隐藏", hidden == 0)
platform.resumeTime()

print(string.format("[HEADLESS] %d total, %d passed, %d failed", total, total - failed, failed))
os.exit(failed == 0 and 0 or 1)
