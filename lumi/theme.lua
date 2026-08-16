--[[
    theme.lua —— Material Design 主题模块
    提供深/浅两套配色与样式 tokens，全局单例 theme.current 供所有控件读取。
]]

local theme = {}

-- 十六进制颜色转 {r,g,b}（0~1 浮点，LÖVE 默认格式）
local function hex(s)
    s = s:gsub("^#", "")
    local r = tonumber(s:sub(1, 2), 16) or 0
    local g = tonumber(s:sub(3, 4), 16) or 0
    local b = tonumber(s:sub(5, 6), 16) or 0
    return { r / 255, g / 255, b / 255 }
end

-- 在颜色上叠加透明度，返回新表
local function withAlpha(c, a)
    return { c[1], c[2], c[3], a }
end

-- 两套 Material 风格配色
local palettes = {
    dark = {
        background = "#121212",
        surface    = "#1E1E1E",
        surface2   = "#2A2A2A",
        border     = "#3A3A3A",
        primary    = "#8AB4F8",
        primaryDim = "#3C5A8A",
        onPrimary  = "#1A1A1A",
        text       = "#E8EAED",
        muted      = "#9AA0A6",
        error      = "#F28B82",
        success    = "#81C995",
        warning    = "#FDD663",
        overlay    = "#000000",
    },
    light = {
        background = "#F4F6F8",
        surface    = "#FFFFFF",
        surface2   = "#EDEFF2",
        border     = "#DADCE0",
        primary    = "#1A73E8",
        primaryDim = "#A8C7FA",
        onPrimary  = "#FFFFFF",
        text       = "#202124",
        muted      = "#5F6368",
        error      = "#D93025",
        success    = "#188038",
        warning    = "#F9AB00",
        overlay    = "#000000",
    },
}

function theme.build(mode)
    mode = (mode == "light") and "light" or "dark"
    local src = palettes[mode]

    local t = {
        mode = mode,
        colors = {},
        -- 圆角规格
        shape = { small = 4, medium = 8, large = 14, pill = 999 },
        -- 字号阶梯
        font = { caption = 12, body = 14, subtitle = 16, title = 18, headline = 24, display = 32 },
        -- 动画时长（秒）
        motion = { fast = 0.15, normal = 0.22, slow = 0.32 },
        -- 控件基准尺寸
        control = { height = 40, minWidth = 88, padX = 16, padY = 10 },
    }

    for k, v in pairs(src) do
        t.colors[k] = hex(v)
    end

    -- 便捷取色
    t.color = function(name)
        return t.colors[name] or t.colors.text
    end
    t.alpha = function(name, a)
        return withAlpha(t.color(name), a)
    end

    return t
end

-- 同步模块级 tokens，供控件直接通过 theme.font / theme.shape / theme.color 访问
local function sync()
    local t = theme.current
    theme.colors = t.colors
    theme.shape = t.shape
    theme.font = t.font
    theme.motion = t.motion
    theme.control = t.control
    theme.mode = t.mode
end

function theme.color(name)
    return theme.current.color(name)
end

function theme.alpha(name, a)
    return theme.current.alpha(name, a)
end

function theme.set(mode)
    theme.current = theme.build(mode)
    sync()
    return theme.current
end

-- 颜色归一化：接受十六进制字符串或 {r,g,b} 表
local function toColor(v)
    if type(v) == "table" then
        return { v[1] or 1, v[2] or 1, v[3] or 1, v[4] }
    end
    return hex(v)
end

local function merge(dst, src)
    if not src then return dst end
    for k, v in pairs(src) do dst[k] = v end
    return dst
end

-- 基于 mode 构建自定义主题：覆盖颜色/圆角/字号/动画/控件尺寸，并立即应用
-- 例：theme.custom("dark", { colors = { primary = "#FF7A45" }, shape = { medium = 12 } })
function theme.custom(mode, overrides)
    overrides = overrides or {}
    local t = theme.build(mode)
    if overrides.colors then
        for k, v in pairs(overrides.colors) do
            t.colors[k] = toColor(v)
        end
    end
    merge(t.shape, overrides.shape)
    merge(t.font, overrides.font)
    merge(t.motion, overrides.motion)
    merge(t.control, overrides.control)
    theme.current = t
    sync()
    return t
end

-- 应用一个已构建好的主题表（theme.build 或 theme.custom 的返回值）
function theme.apply(t)
    if not t.color then
        t.color = function(name) return t.colors[name] or t.colors.text end
    end
    if not t.alpha then
        t.alpha = function(name, a) return withAlpha(t.color(name), a) end
    end
    theme.current = t
    sync()
    return t
end

-- 默认深色主题
theme.current = theme.build("dark")
sync()

return theme
