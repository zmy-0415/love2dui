--[[
    syntax.lua —— 语法高亮引擎
    按文件扩展名检测语言，逐行返回 {from, to, color} 分段（0 基字节，半开区间），
    供 lumi.widgets.editor 的 highlight 回调直接使用。

    高亮为逐行进行（框架 highlight 回调按行调用），跨行块注释 / 多行字符串
    仅对起始行生效，属于 v1 已知取舍。
]]

local M = {}

-- 高亮色映射：使用主题色名，可随深/浅主题自动适配
local COLORS = {
    keyword = "primary",
    string = "success",
    comment = "muted",
    number = "warning",
    builtin = "primaryDim",
    tag = "primary",
    attr = "warning",
    heading = "primary",
    code = "success",
}

-- 将 1 基闭区间 [a, b] 转换为 editor 期望的 0 基半开 {from, to}
local function seg(segs, a, b, color)
    if b >= a then
        segs[#segs + 1] = { from = a - 1, to = b, color = color }
    end
end

local function isKw(t, w)
    return t[w] ~= nil
end

-- ---------------- 通用词法扫描 ----------------
-- def: { keywords=set, builtins=set, lineComment=str, blockComment={open,close},
--        quotes={...}, preprocessor=bool }
local function scan(line, def)
    local segs = {}
    local n = #line
    local i = 1

    -- 预处理器指令（C/C++：#include ...）：整行按 keyword 着色
    if def.preprocessor then
        local lead = line:match("^%s*()")
        if lead and line:sub(lead, lead) == "#" then
            local space = line:find("%s", lead + 1)
            local e = (space and space - 1) or n
            seg(segs, lead, e, COLORS.keyword)
            return segs
        end
    end

    while i <= n do
        local advanced = false
        local c = line:sub(i, i)

        -- 块注释优先于行注释（--[[ 与 -- 同前缀；/* 与 // 独立）
        if def.blockComment then
            local op, cl = def.blockComment[1], def.blockComment[2]
            if line:sub(i, i + #op - 1) == op then
                local closeAt = line:find(cl, i + #op, true)
                local e = (closeAt and (closeAt + #cl - 1)) or n
                seg(segs, i, e, COLORS.comment)
                i = e + 1
                advanced = true
            end
        end

        if not advanced and def.lineComment
            and line:sub(i, i + #def.lineComment - 1) == def.lineComment then
            seg(segs, i, n, COLORS.comment)
            break
        end

        if not advanced and def.quotes then
            local q
            for _, ch in ipairs(def.quotes) do
                if c == ch then q = ch; break end
            end
            if q then
                local j = i + 1
                while j <= n do
                    if line:sub(j, j) == q and line:sub(j - 1, j - 1) ~= "\\" then
                        break
                    end
                    j = j + 1
                end
                if j > n then j = n end
                seg(segs, i, j, COLORS.string)
                i = j + 1
                advanced = true
            end
        end

        if not advanced and c:match("%d") then
            local j = i
            while j <= n and line:sub(j, j):match("[%d%.xXa-fA-F_]") do
                j = j + 1
            end
            seg(segs, i, j - 1, COLORS.number)
            i = j
            advanced = true
        end

        if not advanced and c:match("[%a_]") then
            local j = i
            while j <= n and line:sub(j, j):match("[%w_]") do
                j = j + 1
            end
            local word = line:sub(i, j - 1)
            if def.keywords and def.keywords[word] then
                seg(segs, i, j - 1, COLORS.keyword)
            elseif def.builtins and def.builtins[word] then
                seg(segs, i, j - 1, COLORS.builtin)
            end
            i = j
            advanced = true
        end

        if not advanced then
            i = i + 1
        end
    end

    return segs
end

-- ---------------- XML / HTML ----------------
local function scanXML(line)
    local segs = {}
    local n = #line
    local i = 1
    while i <= n do
        if line:sub(i, i + 3) == "<!--" then
            local closeAt = line:find("-->", i + 4, true)
            local e = (closeAt and (closeAt + 2)) or n
            seg(segs, i, e, COLORS.comment)
            i = e + 1
        elseif line:sub(i, i) == "<" then
            local closeAt = line:find(">", i + 1, true)
            local e = closeAt or n
            -- 标签内部非重叠着色：< / > 括号、标签名、属性名、属性值
            local j = i
            local firstIdent = true
            while j <= e do
                local ch = line:sub(j, j)
                if ch == "<" then
                    seg(segs, j, j, COLORS.tag)
                    j = j + 1
                    if line:sub(j, j) == "/" then
                        seg(segs, j, j, COLORS.tag)
                        j = j + 1
                    end
                    firstIdent = true
                elseif ch == ">" then
                    seg(segs, j, j, COLORS.tag)
                    j = j + 1
                elseif ch == '"' or ch == "'" then
                    local k = j + 1
                    while k <= e and line:sub(k, k) ~= ch do k = k + 1 end
                    if k > e then k = e end
                    seg(segs, j, k, COLORS.string)
                    j = k + 1
                elseif ch:match("[%a_]") then
                    local k = j
                    while k <= e and line:sub(k, k):match("[%w_%-:]") do k = k + 1 end
                    seg(segs, j, k - 1, firstIdent and COLORS.tag or COLORS.attr)
                    firstIdent = false
                    j = k
                else
                    j = j + 1
                end
            end
            i = e + 1
        else
            i = i + 1
        end
    end
    return segs
end

-- ---------------- Markdown ----------------
local function scanMarkdown(line)
    local segs = {}
    local n = #line
    -- 标题
    local heading = line:match("^(#+%s)")
    if heading then
        seg(segs, 1, #heading, COLORS.heading)
        -- 标题整行着色
        seg(segs, 1, n, COLORS.heading)
        return segs
    end
    -- 行内代码
    local i = 1
    while true do
        local a = line:find("`", i, true)
        if not a then break end
        local b = line:find("`", a + 1, true)
        if not b then
            seg(segs, a, n, COLORS.code)
            break
        end
        seg(segs, a, b, COLORS.code)
        i = b + 1
    end
    -- 加粗 **...**
    i = 1
    while true do
        local a = line:find("**", i, true)
        if not a then break end
        local b = line:find("**", a + 2, true)
        if not b then break end
        seg(segs, a, b + 1, COLORS.keyword)
        i = b + 2
    end
    return segs
end

-- ---------------- 语言定义 ----------------

local function set(t)
    local s = {}
    for _, w in ipairs(t) do s[w] = true end
    return s
end

local DEFS = {
    lua = {
        keywords = set({ "and", "break", "do", "else", "elseif", "end", "false", "for",
            "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat",
            "return", "then", "true", "until", "while" }),
        builtins = set({ "print", "require", "pairs", "ipairs", "type", "tostring",
            "tonumber", "setmetatable", "getmetatable", "select", "pcall", "xpcall",
            "error", "assert", "math", "string", "table", "io", "os", "coroutine",
            "love", "self" }),
        lineComment = "--",
        blockComment = { "--[[", "]]" },
        quotes = { '"', "'" },
    },
    python = {
        keywords = set({ "and", "as", "assert", "break", "class", "continue", "def",
            "del", "elif", "else", "except", "finally", "for", "from", "global",
            "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass",
            "raise", "return", "try", "while", "with", "yield", "None", "True", "False" }),
        builtins = set({ "print", "len", "range", "str", "int", "float", "list", "dict",
            "set", "tuple", "open", "input", "super", "self", "cls" }),
        lineComment = "#",
        quotes = { '"', "'" },
    },
    js = {
        keywords = set({ "var", "let", "const", "function", "return", "if", "else",
            "for", "while", "do", "switch", "case", "break", "continue", "new",
            "delete", "typeof", "instanceof", "in", "of", "class", "extends",
            "super", "this", "null", "undefined", "true", "false", "try", "catch",
            "finally", "throw", "async", "await", "import", "export", "default",
            "from", "static", "get", "set", "yield", "void" }),
        builtins = set({ "console", "Math", "JSON", "Object", "Array", "String",
            "Number", "Promise", "window", "document", "require", "module" }),
        lineComment = "//",
        blockComment = { "/*", "*/" },
        quotes = { '"', "'", "`" },
    },
    c = {
        keywords = set({ "auto", "break", "case", "char", "const", "continue",
            "default", "do", "double", "else", "enum", "extern", "float", "for",
            "goto", "if", "inline", "int", "long", "register", "restrict", "return",
            "short", "signed", "sizeof", "static", "struct", "switch", "typedef",
            "union", "unsigned", "void", "volatile", "while", "bool", "true", "false",
            "class", "namespace", "public", "private", "protected", "template",
            "typename", "virtual", "new", "delete", "this", "using" }),
        builtins = set({ "printf", "scanf", "malloc", "free", "memcpy", "strlen",
            "std", "cout", "cin", "endl", "NULL", "size_t" }),
        lineComment = "//",
        blockComment = { "/*", "*/" },
        quotes = { '"', "'" },
        preprocessor = true,
    },
    json = {
        keywords = set({ "true", "false", "null" }),
        quotes = { '"' },
    },
}

-- 扩展名 → 语言
local EXT_MAP = {
    lua = "lua",
    json = "json",
    xml = "xml", html = "xml", htm = "xml", svg = "xml", xaml = "xml",
    js = "js", mjs = "js", cjs = "js", jsx = "js", ts = "js", tsx = "js",
    py = "python", pyw = "python",
    c = "c", h = "c", cpp = "c", hpp = "c", cc = "c", cxx = "c", cs = "c",
    md = "markdown", markdown = "markdown",
}

function M.detect(path)
    local ext = path and path:match("%.([%w]+)$") or ""
    ext = ext and ext:lower() or ""
    return EXT_MAP[ext] or "text"
end

-- 返回语言名（未知返回 "text"）
function M.langOf(path)
    return M.detect(path)
end

function M.highlight(lang, lineText)
    lineText = lineText or ""
    if lang == "xml" then
        return scanXML(lineText)
    elseif lang == "markdown" then
        return scanMarkdown(lineText)
    end
    local def = DEFS[lang]
    if not def then
        return nil
    end
    local segs = scan(lineText, def)
    return (#segs > 0) and segs or nil
end

return M
