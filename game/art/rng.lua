--[[
    game/art/rng.lua —— 兼容层

    确定性伪随机最初写在这里（因为第一个用它的模块是程序化美术），
    但 M2 起词条、掉落、精英词缀都要用，它显然属于 core。
    文件已经搬到 game/core/rng.lua，这里只留一行转发，
    免得回头去改 art/ 下面五六个 require。
]]

return require("game.core.rng")
