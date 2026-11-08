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

    -- scissor 必须是有状态的：draw.pushClip 依赖 getScissor 读回上一层裁剪区，
    -- 恒返回整窗会让嵌套裁剪的交集算错（剔除逻辑因此失真）
    local scissor = nil
    G.setScissor = function(x, y, w, h)
        rec("setScissor")
        if x == nil then
            scissor = nil
        else
            scissor = { x, y, w, h }
        end
    end
    G.getScissor = function()
        if not scissor then return nil end
        return scissor[1], scissor[2], scissor[3], scissor[4]
    end

    G.stencil = function(fn)
        rec("stencil")
        if fn then fn() end
    end

    -- 字体：每字符 7px。getWrap 按宽度硬切（近似真实折行），
    -- 否则依赖换行的测量逻辑在无头环境里永远得到单行高度。
    local CHAR_W = 7
    G.newFont = function()
        return {
            getWidth = function(_, s) return #tostring(s) * CHAR_W end,
            getWrap = function(_, s, limit)
                s = tostring(s)
                local per = math.max(1, math.floor((limit or 1000) / CHAR_W))
                local lines = {}
                local i = 1
                while i <= #s do
                    lines[#lines + 1] = s:sub(i, i + per - 1)
                    i = i + per
                end
                if #lines == 0 then lines[1] = "" end
                return #lines[1] * CHAR_W, lines
            end,
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
