--[[
    font.lua —— 字体管理
    LÖVE 内置字体不含 CJK 字形，中文界面需要系统字体。
    启动时探测常见中文字体（等线/雅黑/黑体），找不到则回退默认字体。
]]

local platform = require("lumi.platform")
local font = {}

local cjkData = nil
local detected = false
local cache = {}

-- 候选中文字体（按优先级，优先 .ttf，兼容性更好）
local candidates = {
    "C:/Windows/Fonts/Deng.ttf",            -- 等线
    "C:/Windows/Fonts/msyh.ttf",            -- 微软雅黑（单文件）
    "C:/Windows/Fonts/simhei.ttf",          -- 黑体
    "C:/Windows/Fonts/simsun.ttc",          -- 宋体
    "C:/Windows/Fonts/msyh.ttc",            -- 微软雅黑（集合）
    "C:/Windows/Fonts/NotoSansCJK-Regular.ttc",
}

local function detect()
    for _, path in ipairs(candidates) do
        local f = io.open(path, "rb")
        if f then
            local data = f:read("*a")
            f:close()
            local ok = pcall(function()
                cjkData = platform.newFileData(data, "cjk")
            end)
            if ok and cjkData then
                return true
            end
        end
    end
    return false
end

function font.load(size)
    if not detected then
        detected = true
        detect()
    end
    if cjkData then
        return platform.newFontFromData(cjkData, size)
    end
    return platform.newFont(size)
end

-- 带缓存的字号获取
function font.get(size)
    size = math.floor(size or 14)
    if not cache[size] then
        cache[size] = font.load(size)
    end
    return cache[size]
end

-- 判断是否加载了中文字体
function font.hasCJK()
    if not detected then
        detected = true
        detect()
    end
    return cjkData ~= nil
end

return font
