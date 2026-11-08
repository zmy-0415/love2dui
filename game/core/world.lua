--[[
    game/core/world.lua —— 方块世界

    两层网格：
      前景层  会碰撞、能挖、能放，玩家实际接触的世界
      背景层  不碰撞、不可挖，只在洞穴里露出一层暗色洞壁
    挖掉一块前景方块，背景砖还在——所以挖出来的洞是「洞」而不是天空。
    这是 Terraria 的做法，比单层好画太多。

    整张图由一个确定性种子生成：同样的种子必然得到同样的地形。
    这不是为了好看，是为了「存档只存种子 + 被玩家改动过的方块」，
    以及测试里可以断言「同种子地形哈希一致」。

    坐标系：
      tile 坐标 (tx, ty)，ty 向下增长
      像素坐标 = tile * TILE
]]

local Tiles = require("game.core.tiles")

local W = {}
W.__index = W

W.TILE = 16

-- ---------------------------------------------------------------- 噪声
-- 纯算术哈希：不依赖 bit 库，LuaJIT 与 Lua 5.4 都能跑
local function hash2(x, y, s)
    local n = x * 73856093 + y * 19349663 + s * 83492791
    n = n % 2147483647
    if n < 0 then n = n + 2147483647 end
    n = (n * 1103515245 + 12345) % 2147483647
    n = n % 65536
    return n / 65535
end

local function smooth(t)
    return t * t * (3 - 2 * t)
end

local function noise2(x, y, seed)
    local x0, y0 = math.floor(x), math.floor(y)
    local tx, ty = smooth(x - x0), smooth(y - y0)
    local a = hash2(x0, y0, seed)
    local b = hash2(x0 + 1, y0, seed)
    local c = hash2(x0, y0 + 1, seed)
    local d = hash2(x0 + 1, y0 + 1, seed)
    local top = a + (b - a) * tx
    local bot = c + (d - c) * tx
    return top + (bot - top) * ty
end

-- 分形叠加：三层，每层频率翻倍、振幅减半
local function fbm(x, y, seed, freq, octaves)
    local sum, amp, f, norm = 0, 1, freq, 0
    for i = 1, octaves or 3 do
        sum = sum + noise2(x * f, y * f, seed + i * 977) * amp
        norm = norm + amp
        amp = amp * 0.5
        f = f * 2
    end
    return sum / norm
end

-- ---------------------------------------------------------------- 构造
function W.new(w, h, seed)
    local self = setmetatable({}, W)
    self.w = w
    self.h = h
    self.seed = seed or 1
    -- +1：Lua 数组从 1 开始，这里保留 0 号槽的空位会让所有索引运算都多一次 +1，
    -- 反而更容易写错。统一用 (y * w + x + 1)。
    self.fg = {}
    self.bg = {}
    self.damage = {}     -- index -> 0~1 累积挖掘进度
    self.dirty = {}      -- index -> true，渲染层可据此重绘局部
    -- 玩家改动过的格子。存档只需要这一张表 + 种子，不必存整张地图：
    -- 生成是确定性的，同种子必然复现同一张图
    self.edits = {}
    self.tracking = false   -- 生成期间关掉，避免把地形本身记成「改动」
    for i = 1, w * h do
        self.fg[i] = 0
        self.bg[i] = 0
    end
    return self
end

function W:index(tx, ty)
    if tx < 0 or ty < 0 or tx >= self.w or ty >= self.h then return nil end
    return ty * self.w + tx + 1
end

function W:inBounds(tx, ty)
    return tx >= 0 and ty >= 0 and tx < self.w and ty < self.h
end

function W:get(tx, ty)
    local i = self:index(tx, ty)
    return i and self.fg[i] or 0
end

function W:getBg(tx, ty)
    local i = self:index(tx, ty)
    return i and self.bg[i] or 0
end

function W:set(tx, ty, id)
    local i = self:index(tx, ty)
    if not i then return false end
    self.fg[i] = id
    self.dirty[i] = true
    self.damage[i] = nil
    if self.tracking then
        self.edits[tx .. "," .. ty] = id
    end
    return true
end

function W:setBg(tx, ty, id)
    local i = self:index(tx, ty)
    if not i then return false end
    self.bg[i] = id
    self.dirty[i] = true
    return true
end

-- 世界边界外一律当作实心，避免玩家从地图边缘掉出去
-- 这格是否有任何方块（不等于「实心」）。
-- 树叶和树干都不碰撞，但它们仍然占据空间，画明暗边时必须算作相邻，
-- 否则每片叶子都会被当成暴露面描一圈，整棵树变成绿色网格。
function W:filled(tx, ty)
    if not self:inBounds(tx, ty) then return true end
    return self.fg[ty * self.w + tx + 1] ~= 0
end

function W:solidAt(tx, ty)
    if not self:inBounds(tx, ty) then return true end
    return Tiles.solid(self:get(tx, ty))
end

function W:tileOfPixel(px, py)
    return math.floor(px / W.TILE), math.floor(py / W.TILE)
end

function W:solidAtPixel(px, py)
    local tx, ty = self:tileOfPixel(px, py)
    return self:solidAt(tx, ty)
end

-- ---------------------------------------------------------------- 挖掘
-- 累加进度，返回是否刚好挖穿。调用方负责在挖穿时发掉落。
function W:dig(tx, ty, dt, efficiency, tier)
    local i = self:index(tx, ty)
    if not i then return false end
    local id = self.fg[i]
    if not Tiles.canMine(id, tier) then return false end
    local need = Tiles.mineTime(id, efficiency)
    local d = (self.damage[i] or 0) + dt / need
    if d >= 1 then
        self.damage[i] = nil
        self:set(tx, ty, 0)       -- 走 set 而不是直接写数组，否则这次改动进不了存档
        return true, id
    end
    self.damage[i] = d
    return false
end

-- 松手后进度回退。回退比累积慢，这样断续点击也能推进，但换目标不会残留
function W:relaxDamage(tx, ty, dt)
    local i = self:index(tx, ty)
    if not i then return end
    local d = self.damage[i]
    if not d then return end
    d = d - dt * 1.6
    if d <= 0 then self.damage[i] = nil else self.damage[i] = d end
end

function W:damageAt(tx, ty)
    local i = self:index(tx, ty)
    return i and self.damage[i] or nil
end

function W:clearDamage()
    for k in pairs(self.damage) do self.damage[k] = nil end
end

-- ---------------------------------------------------------------- 生成
-- 地表高度曲线。越低越靠上（ty 小 = 高）
function W:surfaceAt(tx)
    local base = self.h * 0.26
    return math.floor(base + (fbm(tx, 0, self.seed, 0.018, 3) - 0.5) * 9)
end

function W:generate()
    local w, h = self.w, self.h
    local Dirt, Grass, Stone, Deep = Tiles.id("dirt"), Tiles.id("grass"), Tiles.id("stone"), Tiles.id("deep")

    -- 1) 基础分层
    local surf = {}
    for x = 0, w - 1 do
        local sy = self:surfaceAt(x)
        surf[x] = sy
        local stoneLine = sy + 10 + math.floor(fbm(x, 0, self.seed + 51, 0.03, 2) * 6)
        local deepLine = stoneLine + 26 + math.floor(fbm(x, 0, self.seed + 77, 0.025, 2) * 10)
        for y = sy, h - 1 do
            local id
            if y == sy then
                id = Grass
            elseif y < stoneLine then
                id = Dirt
            elseif y < deepLine then
                id = Stone
            else
                id = Deep
            end
            self.fg[y * w + x + 1] = id

            -- 背景：比地表低一格才有，形成「洞口能看到岩壁」的效果
            if y > sy + 1 then
                local bgId = (y < stoneLine) and Tiles.id("bg_dirt")
                    or (y < deepLine) and Tiles.id("bg_stone")
                    or Tiles.id("bg_deep")
                self.bg[y * w + x + 1] = bgId
            end
        end
    end

    -- 2) 洞穴：两个系统叠加
    --    团块洞（噪声阈值）+ 蜿蜒隧道（等值线带）
    --    只挖地下，地表不能破，否则出生点可能悬空
    for x = 0, w - 1 do
        for y = surf[x] + 4, h - 2 do
            local blob = fbm(x, y, self.seed + 301, 0.055, 3)
            local worm = math.abs(fbm(x, y, self.seed + 909, 0.030, 2) - 0.5)
            -- 越深洞越大：浅层零碎小洞，深层连成大空腔
            local depth = (y - surf[x]) / (h - surf[x])
            local blobCut = 0.62 - depth * 0.06
            local wormCut = 0.030 + depth * 0.012
            if blob > blobCut or worm < wormCut then
                self.fg[y * w + x + 1] = 0
            end
        end
    end

    -- 3) 矿脉。按深度分带，越深越值钱
    self:scatterOre("copper", surf, 6, 34, 0.020, self.seed + 11)
    self:scatterOre("iron", surf, 22, 70, 0.018, self.seed + 22)
    self:scatterOre("crystal", surf, 50, 999, 0.012, self.seed + 33)

    -- 4) 主竖井：从出生点往下切一条带台阶的通道。
    --    纯靠噪声，玩家可能找半天找不到下矿的路；这条井保证「往下走一定有东西」。
    local spawnX = math.floor(w * 0.5)
    self:carveShaft(spawnX, surf[spawnX], math.floor(h * 0.78))

    -- 4b) 沿竖井挂几处露头矿。
    --     随机撒矿有可能让玩家下去半天只看到石头，第一次下矿的体验就废了。
    --     这三处是「保证能看到」的教学矿，位置固定、种类按深度推进。
    local shaftBottom = math.floor(h * 0.78)
    local y1 = surf[spawnX] + 12
    local y2 = math.floor((surf[spawnX] + shaftBottom) * 0.55)
    self:vein(spawnX - 4, y1, "copper", 2)
    self:vein(spawnX + 4, y1 + 6, "copper", 2)
    self:vein(spawnX - 5, y2, "iron", 2)
    self:vein(spawnX + 5, y2 + 8, "iron", 2)
    self:vein(spawnX - 6, shaftBottom - 10, "crystal", 1)

    -- 4c) 脉动矿核：石喉的唤醒器。放在竖井底部正中央，玩家挖下去一定会碰到。
    --     挖掉它就是「我准备好打 Boss 了」的主动表示，而不是走进区域被动开战
    self.coreX = spawnX + 3
    self.coreY = shaftBottom - 6
    self:set(self.coreX, self.coreY, Tiles.id("ore_core"))
    -- 矿核周围留一小块空腔，否则它被岩层包住，玩家看不到光
    for dy = -1, 1 do
        for dx = -2, 1 do
            if dx ~= 0 or dy ~= 0 then
                if self:get(self.coreX + dx, self.coreY + dy) ~= Tiles.AIR then
                    self:set(self.coreX + dx, self.coreY + dy, Tiles.id("stone"))
                end
            end
        end
    end

    -- 5) 树木：只在草地上，且必须留间距。
    --    不加间距的话相邻几棵会连成一片，看起来像一排栅栏而不是树。
    local lastTree = -99
    for x = 3, w - 4 do
        if self.fg[surf[x] * w + x + 1] == Grass
            and x - lastTree >= 6
            and hash2(x, 7, self.seed) > 0.70 then
            self:growTree(x, surf[x] - 1)
            lastTree = x
        end
    end

    -- 6) 基岩封底
    for x = 0, w - 1 do
        self.fg[(h - 1) * w + x + 1] = Tiles.id("bedrock")
        self.fg[(h - 2) * w + x + 1] = Tiles.id("bedrock")
    end

    -- 出生点：地表上方两格，转成像素坐标（角色原点在脚底，见 player.lua）
    local sx = spawnX
    self.spawn = {
        x = (sx + 0.5) * W.TILE,
        y = (surf[sx]) * W.TILE,
    }

    -- 生成结束，从这里开始记录玩家的每一次改动
    self.tracking = true
    return self.spawn
end

-- 在指定深度区间撒矿。
--
-- 一开始写的是「噪声阈值筛格子」，结果是 0 块矿：fbm 归一化后值挤在 0.4~0.6，
-- 阈值 0.885 永远达不到。这类「分布看起来对、实际筛不出东西」的错很难靠读代码发现，
-- 所以改成「种子点 + 簇扩张」：先在粗网格上摇少量种子，再在种子周围生成一个圆簇。
-- 数量由 density 直接决定，成簇也不依赖噪声的分布形状。
function W:scatterOre(key, surf, depthMin, depthMax, density, seed)
    local id = Tiles.id(key)
    local Stone, Deep = Tiles.id("stone"), Tiles.id("deep")
    local w, h = self.w, self.h
    local cell = 5
    local placed = 0
    for cy = 0, math.floor(h / cell) do
        for cx = 0, math.floor(w / cell) do
            if hash2(cx, cy, seed) < density then
                local x = cx * cell + math.floor(hash2(cx, cy, seed + 1) * cell)
                if x >= 1 and x < w - 1 then
                    -- 深度按这一列自己的地表算，否则地表起伏会让矿跑出层
                    local d0 = surf[x] + depthMin
                    local d1 = math.min(h - 4, surf[x] + depthMax)
                    if d1 > d0 then
                        local y = d0 + math.floor(hash2(cx, cy, seed + 2) * (d1 - d0))
                        local r = 1 + math.floor(hash2(cx, cy, seed + 3) * 2)
                        for dy = -r, r do
                            for dx = -r, r do
                                if dx * dx + dy * dy <= r * r then
                                    local tx, ty = x + dx, y + dy
                                    local i = self:index(tx, ty)
                                    if i then
                                        local cur = self.fg[i]
                                        -- 只替换石头类：矿脉长在岩层里，不该出现在泥土和空气中
                                        if cur == Stone or cur == Deep then
                                            self.fg[i] = id
                                            placed = placed + 1
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return placed
end

-- 竖井：左右交替留台阶，玩家能走下去而不是摔下去
function W:carveShaft(cx, top, bottom)
    local step = 3
    for y = top + 1, bottom do
        -- 每 3 格换一次偏移，形成之字形台阶
        local shift = (math.floor((y - top) / step) % 2 == 0) and 0 or 1
        for dx = 0, 1 do
            local x = cx + dx + shift
            local i = y * self.w + x + 1
            if i and y < self.h - 2 then
                self.fg[i] = 0
            end
        end
    end
end

-- 在 (cx, cy) 处放一小簇矿，只替换岩层。返回实际放了几格
function W:vein(cx, cy, key, r)
    local id = Tiles.id(key)
    local Stone, Deep = Tiles.id("stone"), Tiles.id("deep")
    local n = 0
    for dy = -r, r do
        for dx = -r, r do
            if dx * dx + dy * dy <= r * r + 1 then
                local i = self:index(cx + dx, cy + dy)
                if i then
                    local cur = self.fg[i]
                    if cur == Stone or cur == Deep then
                        self.fg[i] = id
                        n = n + 1
                    end
                end
            end
        end
    end
    return n
end

function W:growTree(x, groundY)
    local height = 5 + math.floor(hash2(x, 3, self.seed) * 4)
    local wood, leaves = Tiles.id("wood"), Tiles.id("leaves")
    for i = 1, height do
        local y = groundY - i
        local idx = y * self.w + x + 1
        if idx and y > 0 then self.fg[idx] = wood end
    end
    -- 树冠：中间宽、上下收，接近圆而不是方块，方块树冠一眼假
    local cy = groundY - height
    for dy = -2, 2 do
        local span = 2 - math.floor(math.abs(dy) * 0.8)
        for dx = -span, span do
            local tx, ty = x + dx, cy + dy
            local idx = ty * self.w + tx + 1
            if idx and ty > 0 and self.fg[idx] == 0 then
                self.fg[idx] = leaves
            end
        end
    end
end

-- 应用存档里的改动。调用前必须已经用同一个种子生成过一次
function W:applyEdits(edits)
    if not edits then return end
    local saved = self.tracking
    self.tracking = false
    for key, id in pairs(edits) do
        local tx, ty = key:match("^(-?%d+),(-?%d+)$")
        if tx then
            self:set(tonumber(tx), tonumber(ty), id)
        end
    end
    self.tracking = saved
    -- 保留这份表：下次存档要把它原样带出去
    self.edits = edits
end

-- ---------------------------------------------------------------- 统计
-- 用于测试断言与调试面板：某类方块的总数
function W:count(key)
    local id = Tiles.id(key)
    local n = 0
    for i = 1, self.w * self.h do
        if self.fg[i] == id then n = n + 1 end
    end
    return n
end

-- 地形指纹：改动生成逻辑后，能立刻看出「整张图都变了」还是「只变了局部」
function W:hash()
    local h = 5381
    for i = 1, self.w * self.h do
        h = (h * 33 + self.fg[i]) % 2147483647
    end
    return h
end

return W
