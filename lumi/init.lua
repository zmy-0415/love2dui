--[[
    LumiUI —— Love2D 保留模式 Material Design UI 框架
    使用：local lumi = require("lumi"); ui = lumi.new()
]]

local lumi = {}

lumi.version = "0.1.0"

-- 创建场景
function lumi.new()
    return require("lumi.context").new()
end

-- 注册自定义控件构造器（kind: "text" / "props" / "container"）
function lumi.register(name, ctor, kind)
    return require("lumi.context").register(name, ctor, kind)
end

lumi.theme = require("lumi.theme")
lumi.animate = require("lumi.animate")
lumi.font = require("lumi.font")
lumi.debug = require("lumi.debug")

return lumi
