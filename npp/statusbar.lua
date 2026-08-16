--[[
    statusbar.lua —— 底部状态栏
    实时显示光标行列、文档长度/行数、语言、编码、缩放与文件路径。
]]

local Widget = require("lumi.widget")
local theme = require("lumi.theme")
local font = require("lumi.font")
local draw = require("lumi.draw")

local StatusBar = setmetatable({}, { __index = Widget })
StatusBar.__index = StatusBar

local H = 24

function StatusBar.new(props)
    local self = Widget.new(props or {})
    setmetatable(self, StatusBar)
    return self
end

function StatusBar:measureContent(availW, availH)
    return (availW and availW > 0) and availW or 400, H
end

function StatusBar:drawContent()
    local app = self.props.app
    local cf = font.get(theme.font.caption)

    draw.roundRect(self.x, self.y, self.w, self.h, 0, theme.color("surface"))
    draw.roundRect(self.x, self.y, self.w, 1, 0, theme.color("border"))

    local d = app.docs[app.active]
    local name = d and (d.path or d.name or "未命名") or ""
    local left = ""

    local e = app.editor
    if e and d then
        local row, col = e:getCursorRowCol()
        local bytes = #(e:getText())
        local lines = e:lineCount()
        local dirty = d.dirty and "●" or ""
        left = string.format("行 %d, 列 %d    %s长度 %d    行数 %d    %s    UTF-8    缩放 %d%%",
            row, col + 1, dirty, bytes, lines, d.lang, app.zoom)
    end

    local y = self.y + (self.h - cf:getHeight()) / 2
    draw.text(left, self.x + 10, y, 0, { font = cf, color = theme.color("muted") })

    local nw = cf:getWidth(name)
    draw.text(name, self.x + self.w - 10 - nw, y, 0, { font = cf, color = theme.color("text") })
end

return StatusBar
