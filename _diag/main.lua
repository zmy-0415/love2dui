function love.load()
    print("hello from self-built lovec")
    local fok, ffi = pcall(require, "ffi")
    local bok, bit = pcall(require, "bit")
    print("ffi:", fok, "bit:", bok)
    print("_VERSION:", _VERSION)
    love.event.quit(0)
end
