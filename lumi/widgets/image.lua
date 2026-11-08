--[[
    image.lua —— 图片显示
    fit: contain（完整放入）/ cover（铺满裁剪）/ stretch（拉伸）/ center（原始尺寸居中）
    支持圆角裁剪（radius）、染色（tint）、点击回调（onClick）、加载失败占位。
    用法：ui:image({ src = "assets/a.png", w = 200, h = 120, fit = "cover", radius = "medium" })
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local draw = require("lumi.draw")
local res = require("lumi.image")
local Icon = require("lumi.widgets.icon")

local Image = setmetatable({}, { __index = Widget })
Image.__index = Image

function Image.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Image)
    return self
end

-- 获取图片资源（可能为 nil：未设置 src 或加载失败）
function Image:getImage()
    if self._src ~= self.props.src then
        self._src = self.props.src
        self._img = res.load(self.props.src)
    end
    return self._img
end

function Image:getSize()
    local img = self:getImage()
    if not img then return 0, 0 end
    return img:getDimensions()
end

function Image:measureContent(availW, availH)
    local iw, ih = self:getSize()
    if iw <= 0 or ih <= 0 then
        local s = self.props.placeholderSize or 96
        return self.props.w or self.props.width or s, self.props.h or self.props.height or s
    end
    -- 显式单边时按图片比例推导另一边
    local pw = self.props.w or self.props.width
    local ph = self.props.h or self.props.height
    if pw and not ph then
        return pw, pw * ih / iw
    end
    if ph and not pw then
        return ph * iw / ih, ph
    end
    if (not pw) and (not ph) and availW and availW > 0 then
        local s = math.min(1, availW / iw)
        return iw * s, ih * s
    end
    return iw, ih
end

function Image:isInteractive()
    return not self.state.disabled and type(self.props.onClick) == "function"
end

function Image:isFocusable()
    return self:isInteractive()
end

function Image:mousereleased(x, y, button, ctx, hit)
    if button ~= 1 or self.state.disabled then return end
    if self.state.pressed and hit == self then
        self:emit("onClick")
    end
end

-- 绘制占位内容（无图或加载失败）
function Image:drawFallback(radius)
    local p = self.props
    draw.roundRect(self.x, self.y, self.w, self.h, radius, self:resolveColor(p.bg or "surface2"))
    local s = math.min(self.w, self.h) * 0.4
    if s >= 10 then
        Icon.drawIcon("image", self.x + (self.w - s) / 2, self.y + (self.h - s) / 2, s, theme.color("muted"))
    end
end

function Image:drawContent()
    local p = self.props
    local fit = p.fit or "cover"
    local radius = self:resolveRadius(p.radius, 0)
    local img = self:getImage()
    if not img then
        self:drawFallback(radius)
        return
    end

    -- 可点击时 hover 提亮
    local tint = p.tint and self:resolveColor(p.tint) or nil
    if self:isInteractive() and self.state.hovered then
        local base = tint or { 1, 1, 1 }
        tint = { math.min(1, base[1] + 0.08), math.min(1, base[2] + 0.08), math.min(1, base[3] + 0.08), base[4] or 1 }
    end

    local function paint()
        draw.image(img, self.x, self.y, self.w, self.h, { fit = fit, tint = tint })
    end

    if fit == "cover" or radius > 0 then
        -- 超出部分需裁剪：cover 用 scissor，圆角用 stencil（二者都开时 stencil 内再叠 scissor）
        draw.pushClip(self.x, self.y, self.w, self.h)
        if radius > 0 then
            draw.inRound(self.x, self.y, self.w, self.h, radius, paint)
        else
            paint()
        end
        draw.popClip()
    else
        paint()
    end

    -- 键盘焦点环
    if self.state.focusVisible then
        draw.roundRectLine(self.x - 2, self.y - 2, self.w + 4, self.h + 4, radius + 2, theme.alpha("primary", 0.6), 2)
    end
end

return Image
