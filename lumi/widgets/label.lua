--[[
    label.lua —— 文本标签
    支持 variant 字号、color、align、wrap（换行）、超长省略号。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local Label = setmetatable({}, { __index = Widget })
Label.__index = Label

function Label.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, Label)
    return self
end

function Label:getFont()
    local v = self.props.variant or "body"
    local size = (type(v) == "number") and v or (theme.font[v] or theme.font.body)
    return font.get(size)
end

function Label:measureContent(availW, availH)
    local f = self:getFont()
    local text = self.props.text or ""
    if self.props.wrap and availW and availW > 0 then
        local _, lines = f:getWrap(text, availW)
        local w = 0
        for _, l in ipairs(lines) do
            w = math.max(w, f:getWidth(l))
        end
        return w, #lines * f:getHeight()
    end
    return f:getWidth(text), f:getHeight()
end

function Label:drawContent()
    local f = self:getFont()
    local text = self.props.text or ""
    local color = self.props.color and self:resolveColor(self.props.color) or theme.color("text")
    if self.state.disabled then
        color = theme.color("muted")
    end
    if self.props.wrap then
        draw.text(text, self.x, self.y, self.w, { font = f, color = color, limit = self.w, align = self.props.align or "left" })
    else
        draw.text(text, self.x, self.y, self.w, { font = f, color = color, align = self.props.align or "left", ellipsis = true })
    end
end

return Label
