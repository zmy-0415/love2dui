--[[
    LumiUI 启动器

        love .              完整展示（默认，覆盖全部控件）
        love . minimal      最小应用
        love . layout       布局系统（Flex / Grid / 绝对定位 / 响应式）
        love . forms        表单控件
        love . editor       多行编辑器
        love . data         表格 / 树 / 图片轮播
        love . theme        主题与视觉定制

    各示例的实现都在 examples/ 下，见 examples/boot.lua 的说明。

    无头自检：在项目根目录创建 verify.flag 后运行（或设置 LUMI_VERIFY=1），
    会构建界面、跑一遍交互冒烟与完整测试套件，然后按结果退出。
]]

local boot = require("examples.boot")

local DEFAULT = "showcase"

-- 可用示例（顺序即帮助输出顺序）
local EXAMPLES = { "showcase", "minimal", "layout", "forms", "editor", "data", "theme" }

local function resolve(args)
    local want = type(args) == "table" and args[1] or nil
    -- LÖVE 会把 --xxx 之类的选项也放进 args，忽略以 - 开头的
    if type(want) ~= "string" or want:sub(1, 1) == "-" then return DEFAULT end
    for _, name in ipairs(EXAMPLES) do
        if name == want then return name end
    end
    print("[LumiUI] 未知示例: " .. tostring(want))
    print("[LumiUI] 可用示例: " .. table.concat(EXAMPLES, " / "))
    return DEFAULT
end

local function verifyMode()
    local fs = love.filesystem
    local flag = fs and fs.getInfo and fs.getInfo("verify.flag")
    return (flag ~= nil) or os.getenv("LUMI_VERIFY") == "1"
end

function love.load(args)
    local name = resolve(args)
    local def = require("examples." .. name)
    local ui = boot.start(def, name)

    if verifyMode() then
        require("tests.selfcheck").run(ui)
    end
end
