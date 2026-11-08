--[[
    game/core/save.lua —— 存档

    只存三样东西：种子、玩家改动过的方块、玩家状态。
    世界本身不存——它是种子的确定性函数，同样的种子必然生成同一张图。
    这不只是省空间：它让「存档」和「世界生成」保持单一事实来源，
    以后改生成算法，老存档也只是地形变了，不会出现半新半旧的缝合地图。

    序列化用 Lua 源码字面量（"return {...}"），读取时 load 回来。
    不是 JSON 是因为 Lua 表能直接表达稀疏表、整数键和混合键，
    而这正是 edits 表要的东西。
]]

local Save = {}

Save.VERSION = 2

-- ---------------------------------------------------------------- 序列化
local function encode(v, out)
    local t = type(v)
    if t == "number" then
        -- %.14g 足够精确地往返 double，又不会写出 0.30000000000000004
        out[#out + 1] = string.format("%.14g", v)
    elseif t == "string" then
        out[#out + 1] = string.format("%q", v)
    elseif t == "boolean" then
        out[#out + 1] = tostring(v)
    elseif t == "table" then
        out[#out + 1] = "{"
        local n = #v
        for i = 1, n do
            if i > 1 then out[#out + 1] = "," end
            encode(v[i], out)
        end
        for k, val in pairs(v) do
            local isArr = type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)
            if not isArr then
                out[#out + 1] = "["
                encode(k, out)
                out[#out + 1] = "]="
                encode(val, out)
                out[#out + 1] = ","
            end
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "nil"
    end
end

function Save.encode(tbl)
    local out = { "return " }
    encode(tbl, out)
    return table.concat(out)
end

function Save.decode(text)
    if not text or text == "" then return nil end
    local chunk = (loadstring or load)(text, "save")
    if not chunk then return nil end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

-- ---------------------------------------------------------------- 存储
-- 真机走 love.filesystem（会被写进 LÖVE 的存档目录，跨平台一致），
-- 无 love 时退到普通文件，这样测试里也能完整验证存档往返
local function fs()
    local lv = rawget(_G, "love")
    return lv and lv.filesystem
end

function Save.write(name, text)
    local f = fs()
    if f and f.write then
        local ok = pcall(f.write, name, text)
        return ok
    end
    local file = io.open(name, "wb")
    if not file then return false end
    file:write(text)
    file:close()
    return true
end

function Save.read(name)
    local f = fs()
    if f and f.read then
        local ok, data = pcall(f.read, name)
        if ok then return data end
        return nil
    end
    local file = io.open(name, "rb")
    if not file then return nil end
    local data = file:read("*a")
    file:close()
    return data
end

function Save.exists(name)
    local f = fs()
    if f and f.getInfo then
        return f.getInfo(name, "size") ~= nil
    end
    local file = io.open(name, "rb")
    if file then file:close() return true end
    return false
end

return Save
