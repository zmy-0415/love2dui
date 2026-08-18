--[[
    avatar.lua —— 头像
    圆形裁剪显示图片；无图时以文字回退（取首字符，按内容哈希选背景色）；
    支持状态角标（badge：true 显示圆点 / 数字显示计数）与点击回调。
    用法：ui:avatar({ src = "a.png", size = 44, badge = 3, onClick = function() end })
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")
local res = require("lumi.image")

local Avatar = setmetatable({}, { __index = Widget })
Avatar.__index = Avatar

-- 背景色轮换池（未指定 color 时按文字哈希选择）
local paletteNames = { "primary", "success", "warning", "error" }

-- 取第一个 UTF-8 字符
local function firstChar(s)
    if not s or s == "" then return "" end
    local nxt = draw.utf8Next(s, 0)
    return nxt and s:sub(1, nxt) or s:sub(1, 1)
end

-- 简单字符串哈希
local function hash(s)
    local h = 0
    for i = 1, #s do
        h = (h * 31 + s:byte(i)) % 1000000007
    end
    return h
end

function Avatar.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Avatar)
    return self
end

function Avatar:getSize()
    return self.props.size or 40
end

function Avatar:measureContent()
    local s = self:getSize()
    return s, s
end

-- 解析文字回退内容（优先 text，其次 name，取首字符）
function Avatar:getFallbackText()
    local src = self.props.text or self.props.name or ""
    if type(src) == "string" then return firstChar(src) end
    return ""
end

function Avatar:getBgColor()
    local p = self.props
    if p.color then
        return self:resolveColor(p.color)
    end
    local name = paletteNames[(hash(self:getFallbackText()) % #paletteNames) + 1]
    return theme.color(name)
end

function Avatar:isInteractive()
    return not self.state.disabled and type(self.props.onClick) == "function"
end

function Avatar:mousereleased(x, y, button, ctx, hit)
    if button ~= 1 or self.state.disabled then return end
    if self.state.pressed and hit == self then
        self:emit("onClick")
    end
end

function Avatar:drawContent()
    local p = self.props
    local size = self:getSize()
    local cx, cy = self.x + size / 2, self.y + size / 2
    local r = size / 2
    local img = res.load(p.src)

    -- hover 光环（可点击时）
    if self:isInteractive() and self.state.hovered then
        love.graphics.setLineWidth(2.5)
        love.graphics.setColor(theme.alpha("primary", 0.55))
        love.graphics.circle("line", cx, cy, r + 3)
    end

    if img then
        local iw, ih = img:getDimensions()
        local s = math.max((size * 1.02) / iw, (size * 1.02) / ih) -- cover
        local dw, dh = iw * s, ih * s
        draw.inCircle(cx, cy, r, function()
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(img, cx - dw / 2, cy - dh / 2, 0, s, s)
        end)
    else
        -- 文字回退
        draw.inCircle(cx, cy, r, function()
            love.graphics.setColor(self:getBgColor())
            love.graphics.circle("fill", cx, cy, r)
        end)
        local text = self:getFallbackText()
        if text ~= "" then
            local f = font.get(math.max(10, math.floor(size * 0.42)))
            local color = self.props.textColor and self:resolveColor(self.props.textColor) or theme.color("onPrimary")
            draw.text(text, cx - f:getWidth(text) / 2, cy - f:getHeight() / 2, 0, { font = f, color = color })
        end
    end

    -- 角标：true 显示圆点，数字显示计数（99+ 封顶）
    local badge = p.badge
    if badge == true then
        love.graphics.setColor(theme.color("error"))
        love.graphics.circle("fill", self.x + size - 5, self.y + 5, 4.5)
    elseif badge and tonumber(badge) then
        local n = math.floor(tonumber(badge))
        if n > 0 then
            local label = (n > 99) and "99+" or tostring(n)
            local f = font.get(math.max(9, math.floor(size * 0.26)))
            local bw = math.max(f:getWidth(label) + 8, 16)
            local bh = math.max(f:getHeight() + 4, 16)
            local bx = self.x + size - bw / 2
            local by = self.y + bh / 2
            if bx + bw / 2 > self.x + size + 4 then bx = self.x + size + 4 - bw / 2 end
            if by - bh / 2 < self.y - 4 then by = self.y - 4 + bh / 2 end
            draw.roundRect(bx - bw / 2, by - bh / 2, bw, bh, bh / 2, theme.color("error"))
            draw.text(label, bx - f:getWidth(label) / 2, by - f:getHeight() / 2, 0, { font = f, color = { 1, 1, 1 } })
        end
    end

    -- 键盘焦点环
    if self.state.focused then
        love.graphics.setLineWidth(2)
        love.graphics.setColor(theme.alpha("primary", 0.6))
        love.graphics.circle("line", cx, cy, r + 2)
    end
end

return Avatar
