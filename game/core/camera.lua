--[[
    game/core/camera.lua —— 跟随相机

    两个要求：跟随要平滑（硬跟着角色，画面会随每一次小位移抖），
    但又不能太软（打 Boss 时画面滞后会让人判断错距离）。
    用指数衰减：每帧补上剩余距离的固定比例，且这个比例与帧率无关。

    相机还要限在世界边界内。不限的话走到地图边缘会看到一大片空白，
    而且「世界有多大」这个信息会立刻暴露。
]]

local World = require("game.core.world")

local Cam = {}
Cam.__index = Cam

-- 跟随强度：越大越硬。7 大概是「跟手但有一点点余韵」的档位
local FOLLOW = 7.0
-- 玩家在屏幕上的纵向位置：略低于中线，上方留更多空间看地形
local ANCHOR_Y = 0.58

function Cam.new(w, h)
    return setmetatable({ x = 0, y = 0, w = w, h = h, shake = 0, shakeT = 0 }, Cam)
end

function Cam:resize(w, h)
    self.w, self.h = w, h
end

function Cam:target(px, py)
    return px - self.w * 0.5, py - self.h * ANCHOR_Y
end

function Cam:clampTo(world)
    local maxX = world.w * World.TILE - self.w
    local maxY = world.h * World.TILE - self.h
    if maxX < 0 then
        self.x = maxX * 0.5      -- 世界比屏幕窄就居中
    else
        if self.x < 0 then self.x = 0 elseif self.x > maxX then self.x = maxX end
    end
    if maxY < 0 then
        self.y = maxY * 0.5
    else
        if self.y < 0 then self.y = 0 elseif self.y > maxY then self.y = maxY end
    end
end

-- 立刻对准（出生、传送用，避免开局从天空滑下来）
function Cam:snap(px, py, world)
    local tx, ty = self:target(px, py)
    self.x, self.y = tx, ty
    self:clampTo(world)
end

function Cam:follow(px, py, world, dt)
    local tx, ty = self:target(px, py)
    -- 1 - e^(-k·dt)：与帧率无关的指数插值。
    -- 写成 x = x + (t-x)*0.1 的版本在 30fps 和 144fps 下手感完全不同
    local k = 1 - math.exp(-FOLLOW * dt)
    self.x = self.x + (tx - self.x) * k
    self.y = self.y + (ty - self.y) * k
    self:clampTo(world)
end

-- 屏幕震动：加在相机上的偏移，不影响 clamp
function Cam:kick(amount, dur)
    self.shake = math.max(self.shake, amount)
    self.shakeT = math.max(self.shakeT, dur or 0.18)
end

function Cam:updateShake(dt)
    if self.shakeT > 0 then
        self.shakeT = self.shakeT - dt
        if self.shakeT <= 0 then
            self.shake = 0
            self.ox, self.oy = 0, 0
        else
            -- 用两个不同频率的正弦代替随机数：抖动可复现，录制回放不会漂
            local a = self.shake
            self.ox = math.sin(self.shakeT * 97) * a
            self.oy = math.cos(self.shakeT * 131) * a
        end
    end
end

function Cam:offsetX() return self.ox or 0 end
function Cam:offsetY() return self.oy or 0 end

return Cam
