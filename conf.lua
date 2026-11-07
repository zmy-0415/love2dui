function love.conf(t)
    t.identity = "lumiui"
    -- 目标 LÖVE 版本；本机构建为 12.0，设为一致可避免启动时的兼容性警告
    t.version = "12.0"

    t.window.title = "LumiUI 演示"
    t.window.width = 1280
    t.window.height = 800
    t.window.resizable = true
    t.window.vsync = 1
    t.window.msaa = 4
    -- LÖVE 12 写法（t.highdpi）；LÖVE 11 为 t.window.highdpi
    t.highdpi = true
end
