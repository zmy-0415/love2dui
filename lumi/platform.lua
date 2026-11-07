--[[
    platform.lua —— 后端适配层

    目的：
    1. **单一耦合点**。除本文件外，lumi/ 下不再直接引用全局 `love`，所有 LÖVE 调用
       都经过这里。换后端（或做纯 Lua 单测）只需要换一个 backend 表。
    2. **可注入**。`platform.install(b)` 接受任何形状兼容 `love` 的表（哪怕只有
       `graphics` 一个子表），因此测试可以给假时钟、假剪贴板、只记录调用的绘制后端。
    3. **延迟解析**。模块加载时不强制要求 `love` 存在：先 require 框架、后 install 也能用。

    用法：
        local platform = require("lumi.platform")

        platform.install(love)                -- 默认后端；lumi.new() 会自动调用
        platform.freezeTime(10)               -- 测试：冻结时钟，让动画/光标闪烁可复现
        platform.advance(0.5)
        platform.resumeTime()

    说明：绘制原语（rectangle/polygon/print…）通过 `platform.graphics` 直接转发，
    不做语义包装 —— 它们的签名与 LÖVE 一致，再包一层只会增加开销与维护成本。
]]

local platform = {}

-- 当前后端（可能为 nil：纯 Lua 环境且未 install）
local backend = nil
-- 假时钟（非 nil 时 now() 返回它，便于确定性测试）
local clock = nil

-- 后端缺失时的占位表：调用即刻报出明确错误，而不是 "attempt to index nil"
local MISSING = setmetatable({}, {
    __index = function(_, key)
        error("lumi.platform: 没有可用的图形后端（缺少 graphics." .. tostring(key)
            .. "）。请在启动时调用 platform.install(backend)。", 2)
    end,
})

local installListeners = {}

-- 解析全局 love（LÖVE 程序里它总是先于用户代码存在）
local function detect()
    return rawget(_G, "love")
end

--- 安装/替换后端。传 nil 表示重新探测全局 love。
--  backend 可以是 love 本身，也可以是只含部分子表的桩。
function platform.install(b)
    backend = b or detect()
    platform.graphics = (backend and backend.graphics) or MISSING
    platform.keyboard = (backend and backend.keyboard) or nil
    platform.system = (backend and backend.system) or nil
    platform.timer = (backend and backend.timer) or nil
    platform.filesystem = (backend and backend.filesystem) or nil
    for _, fn in ipairs(installListeners) do
        fn(backend)
    end
    return platform
end

--- 注册"后端变更"回调（例如 draw 借此丢弃颜色/字体缓存）
function platform.onInstall(fn)
    installListeners[#installListeners + 1] = fn
end

--- 确保后端已就绪（模块在纯 Lua 环境下被 require 时兜底）
function platform.ensure()
    if not backend then platform.install(nil) end
    return backend
end

function platform.backend()
    return platform.ensure()
end

-- ---------------- 时间（动画、光标闪烁、Toast 生命周期） ----------------

--- 当前时间（秒）。被 freezeTime 冻结时返回假时钟。
function platform.now()
    if clock ~= nil then return clock end
    local b = platform.ensure()
    if b and b.timer and b.timer.getTime then return b.timer.getTime() end
    return 0
end

--- 冻结时钟到指定时刻（测试用）
function platform.freezeTime(t)
    clock = t or 0
    return clock
end

--- 推进假时钟；未冻结时退化为真实时间
function platform.advance(dt)
    clock = (clock or platform.now()) + (dt or 0)
    return clock
end

--- 解除冻结，回到真实时间
function platform.resumeTime()
    clock = nil
end

-- ---------------- 键鼠 / 文本输入 ----------------

function platform.isDown(key)
    local b = platform.ensure()
    if b and b.keyboard and b.keyboard.isDown then
        return b.keyboard.isDown(key) and true or false
    end
    return false
end

--- 开关 IME 文本输入；带矩形时 LÖVE 用它在光标附近弹出候选框
function platform.setTextInput(on, x, y, w, h)
    local b = platform.ensure()
    local kb = b and b.keyboard
    if not (kb and kb.setTextInput) then return end
    if x then
        kb.setTextInput(on, x, y, w, h)
    else
        kb.setTextInput(on)
    end
end

-- ---------------- 剪贴板 ----------------

function platform.clipboardGet()
    local b = platform.ensure()
    if b and b.system and b.system.getClipboardText then
        return b.system.getClipboardText() or ""
    end
    return ""
end

function platform.clipboardSet(text)
    local b = platform.ensure()
    if b and b.system and b.system.setClipboardText then
        b.system.setClipboardText(text or "")
    end
end

-- ---------------- 窗口 ----------------

function platform.windowSize()
    local g = platform.graphics
    if g == MISSING or not g.getWidth then return 0, 0 end
    return g.getWidth(), g.getHeight()
end

-- ---------------- 资源创建 ----------------

function platform.newFont(size)
    return platform.graphics.newFont(size)
end

--- 从内存中的字体文件创建字体（CJK 字体探测用）
function platform.newFontFromData(data, size)
    return platform.graphics.newFont(data, size)
end

function platform.newFileData(data, name)
    local b = platform.ensure()
    if b and b.filesystem and b.filesystem.newFileData then
        return b.filesystem.newFileData(data, name)
    end
    return nil
end

function platform.newCanvas(w, h)
    return platform.graphics.newCanvas(w, h)
end

--- 返回 image 或 nil（路径无效时不抛异常）
function platform.newImage(path)
    local g = platform.graphics
    if not (g and g.newImage) then return nil end
    local ok, img = pcall(g.newImage, path)
    return ok and img or nil
end

-- 模块加载时尽力探测一次；失败也不报错，等首次调用时再试
platform.install(detect())

return platform
