-- luacheck 配置（https://github.com/lunarmodules/luacheck）
-- 用法：luacheck lumi tests demo main.lua
std = "lua51"
globals = { "love" }

-- 中文注释常常超过默认 120 列
max_line_length = false
