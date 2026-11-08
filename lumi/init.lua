--[[
    LumiUI —— Love2D 保留模式 Material Design UI 框架
    使用：local lumi = require("lumi"); ui = lumi.new()
]]

local platform = require("lumi.platform")

local lumi = {}

lumi.version = "0.8.0"

--- 创建场景
--  @param opts table 可选：
--         { backend = <表>, width = <数>, height = <数>, clear = <布尔> }
--         backend 用于替换 LÖVE 后端（测试/移植），省略时使用全局 love；
--         clear = false 时 draw() 不清屏，用于把 UI 叠在游戏画面之上
function lumi.new(opts)
    opts = opts or {}
    if opts.backend then
        platform.install(opts.backend)
    else
        platform.ensure()
    end
    local scene = require("lumi.context").new()
    if opts.clear ~= nil then
        scene.clearBackground = opts.clear and true or false
    end
    if opts.width or opts.height then
        scene:resize(opts.width or scene.width, opts.height or scene.height)
    end
    return scene
end

-- 注册自定义控件构造器（kind: "text" / "props" / "container"）
function lumi.register(name, ctor, kind)
    return require("lumi.context").register(name, ctor, kind)
end

lumi.theme = require("lumi.theme")
lumi.animate = require("lumi.animate")
lumi.font = require("lumi.font")
lumi.image = require("lumi.image")
lumi.debug = require("lumi.debug")
lumi.wheel = require("lumi.wheel")
lumi.platform = platform

return lumi
