--[[
    LumiUI 启动器

        love .              完整展示（默认，覆盖全部控件）
        love . minimal      最小应用
        love . layout       布局系统（Flex / Grid / 绝对定位 / 响应式）
        love . forms        表单控件
        love . editor       多行编辑器
        love . data         表格 / 树 / 图片轮播
        love . theme        主题与视觉定制
        love . hud          游戏内 HUD（UI 叠在游戏画面上）
        love . rift         《裂界》垂直切片（可挖可建的沙盒动作）

    各示例的实现都在 examples/ 下，见 examples/boot.lua 的说明。

    无头自检：在项目根目录创建 verify.flag 后运行（或设置 LUMI_VERIFY=1），
    会构建界面、跑一遍交互冒烟与完整测试套件，然后按结果退出。
]]

local boot = require("examples.boot")

local DEFAULT = "showcase"

-- 可用示例（顺序即帮助输出顺序）
local EXAMPLES = { "showcase", "minimal", "layout", "forms", "editor", "data", "theme", "hud", "art_preview", "rift" }

local function resolve(args)
    if type(args) ~= "table" then return DEFAULT end
    local unknown
    for _, v in ipairs(args) do
        -- 跳过 --xxx 之类的选项
        if type(v) == "string" and v:sub(1, 1) ~= "-" then
            for _, name in ipairs(EXAMPLES) do
                if v == name then return name end
            end
            -- 不同 LÖVE 版本的 arg 表可能把游戏路径放在前面（"." 或 "xxx.love"），跳过它
            if v ~= "." and v ~= ".." and not v:lower():match("%.love$") then
                unknown = unknown or v
            end
        end
    end
    if unknown then
        print("[LumiUI] 未知示例: " .. unknown)
        print("[LumiUI] 可用示例: " .. table.concat(EXAMPLES, " / "))
    end
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
