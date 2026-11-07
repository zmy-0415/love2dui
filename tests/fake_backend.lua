--[[
    fake_backend.lua —— 纯 Lua 的记录型 LÖVE 后端

    供 headless.lua 与 examples.lua 复用：不依赖任何图形库，只记录绘制调用。
    返回 (backend, calls, state)：
        backend  可直接传给 lumi.new({ backend = ... })
        calls    各绘制函数的调用计数（calls.rectangle 等）
        state    可观察/可改的内部状态（clipboard、clock、keys）
]]

return function(opts)
    opts = opts or {}
    local calls = {}
    local function rec(name)
        calls[name] = (calls[name] or 0) + 1
    end

    local G = {}
    for _, name in ipairs({
        "setColor", "setFont", "setLineWidth", "setLineJoin", "setLineStyle",
        "setScissor", "setStencilTest", "clear", "print", "printf", "rectangle",
        "circle", "arc", "line", "polygon", "points", "push", "pop", "origin",
        "translate", "rotate", "scale", "setCanvas", "draw",
    }) do
        G[name] = function() rec(name) end
    end

    local W, H = opts.width or 800, opts.height or 600
    G.getWidth = function() return W end
    G.getHeight = function() return H end
    G.getScissor = function() return 0, 0, W, H end
    G.stencil = function(fn)
        rec("stencil")
        if fn then fn() end
    end

    G.newFont = function()
        return {
            getWidth = function(_, s) return #tostring(s) * 7 end,
            getWrap = function(_, s) return 1000, { tostring(s) } end,
            getHeight = function() return 16 end,
            setFilter = function() end,
        }
    end

    G.newCanvas = function(w, h)
        return {
            getWidth = function() return w end,
            getHeight = function() return h end,
            getDimensions = function() return w, h end,
            setFilter = function() end,
            release = function() end,
            draw = function() end,
            typeOf = function() return "Canvas" end,
        }
    end

    local state = {
        clipboard = "",
        clock = opts.clock or 100,
        keys = {},
    }

    local backend = {
        graphics = G,
        keyboard = {
            isDown = function(k) return state.keys[k] == true end,
            setTextInput = function() rec("setTextInput") end,
        },
        system = {
            getClipboardText = function() return state.clipboard end,
            setClipboardText = function(t) state.clipboard = t or "" end,
        },
        timer = { getTime = function() return state.clock end },
        filesystem = { newFileData = function() error("no filesystem") end },
    }

    return backend, calls, state
end
