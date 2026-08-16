--[[
    fs.lua —— 文件系统操作（Unicode 路径）
    优先用 LuaJIT FFI 调 Win32 W 系列 API（不启动子进程、原生 Unicode），
    FFI 不可用或失败时回退到 io / io.popen。

    fs.listDir(dir)        -> dirs, files   （两个 UTF-8 文件名表，已排序）
    fs.readFile(path)      -> data 或 nil, err
    fs.writeFile(path, data) -> true 或 nil, err
    fs.getAttributes(path) -> 属性位 或 nil
    fs.isDir(attrs)        -> boolean
]]

local fs = {}
local bit = require("bit")

local band = bit.band
local bor = bit.bor
local lshift = bit.lshift

local ffi = nil
do
    local ok, mod = pcall(require, "ffi")
    if ok and mod then
        ffi = mod
        local okDef = pcall(function()
            ffi.cdef([[
            typedef struct {
                uint32_t dwFileAttributes;
                uint32_t ftCreationTime[2];
                uint32_t ftLastAccessTime[2];
                uint32_t ftLastWriteTime[2];
                uint32_t nFileSizeHigh;
                uint32_t nFileSizeLow;
                uint32_t dwReserved0;
                uint32_t dwReserved1;
                uint16_t cFileName[260];
                uint16_t cAlternateFileName[14];
            } LUMI_WIN32_FIND_DATAW;
            void* FindFirstFileW(const uint16_t* lpFileName, LUMI_WIN32_FIND_DATAW* lpFindFileData);
            int32_t FindNextFileW(void* hFindFile, LUMI_WIN32_FIND_DATAW* lpFindFileData);
            int32_t FindClose(void* hFindFile);
            void* CreateFileW(const uint16_t* lpFileName, uint32_t dwDesiredAccess, uint32_t dwShareMode,
                void* lpSecurityAttributes, uint32_t dwCreationDisposition,
                uint32_t dwFlagsAndAttributes, void* hTemplateFile);
            int32_t ReadFile(void* hFile, void* lpBuffer, uint32_t nNumberOfBytesToRead,
                uint32_t* lpNumberOfBytesRead, void* lpOverlapped);
            int32_t WriteFile(void* hFile, const void* lpBuffer, uint32_t nNumberOfBytesToWrite,
                uint32_t* lpNumberOfBytesWritten, void* lpOverlapped);
            int32_t CloseHandle(void* hObject);
            uint32_t GetFileAttributesW(const uint16_t* lpFileName);
            uint32_t GetLastError(void);
            ]])
        end)
        if not okDef then ffi = nil end
    end
    if ffi then
        -- 预热：强制解析 Win32 符号，避免首次打开目录时的懒加载延迟
        local _ = ffi.C.FindFirstFileW
    end
end

fs.backend = ffi and "ffi" or "popen"

local FILE_ATTRIBUTE_DIRECTORY = 0x10
local INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF
local GENERIC_READ = 0x80000000
local GENERIC_WRITE = 0x40000000
local FILE_SHARE_READ = 0x00000001
local OPEN_EXISTING = 3
local CREATE_ALWAYS = 2
local FILE_ATTRIBUTE_NORMAL = 0x80
local INVALID = ffi and ffi.cast("void*", -1) or nil

-- ---------------- UTF 转换 ----------------

-- UTF-8 字符串 → 以 0 结尾的 uint16_t 数组（UTF-16LE）
local function utf8ToUtf16(s)
    local n = #s
    local units = {}
    local i = 1
    while i <= n do
        local b = s:byte(i)
        local cp, len
        if b < 0x80 then
            cp, len = b, 1
        elseif b < 0xC0 then
            cp, len = 0xFFFD, 1
        elseif b < 0xE0 then
            cp = bor(lshift(band(b, 0x1F), 6), band(s:byte(i + 1), 0x3F))
            len = 2
        elseif b < 0xF0 then
            cp = bor(lshift(band(b, 0x0F), 12), lshift(band(s:byte(i + 1), 0x3F), 6), band(s:byte(i + 2), 0x3F))
            len = 3
        else
            cp = bor(lshift(band(b, 0x07), 18), lshift(band(s:byte(i + 1), 0x3F), 12),
                lshift(band(s:byte(i + 2), 0x3F), 6), band(s:byte(i + 3), 0x3F))
            len = 4
        end
        if cp < 0x10000 then
            units[#units + 1] = cp
        else
            cp = cp - 0x10000
            units[#units + 1] = 0xD800 + math.floor(cp / 0x400)
            units[#units + 1] = 0xDC00 + (cp % 0x400)
        end
        i = i + len
    end
    local count = #units
    local buf = ffi.new("uint16_t[?]", count + 1)
    for j = 1, count do buf[j - 1] = units[j] end
    buf[count] = 0
    return buf
end

-- uint16_t 数组（UTF-16LE，0 结尾）→ UTF-8 字符串
local function utf16ToUtf8(arr)
    local out = {}
    local i = 0
    while i < 260 do
        local u = tonumber(arr[i]) or 0
        if u == 0 then break end
        local cp = u
        if u >= 0xD800 and u <= 0xDBFF and i + 1 < 260 then
            local lo = tonumber(arr[i + 1]) or 0
            if lo >= 0xDC00 and lo <= 0xDFFF then
                cp = 0x10000 + (u - 0xD800) * 0x400 + (lo - 0xDC00)
                i = i + 1
            end
        end
        if cp < 0x80 then
            out[#out + 1] = string.char(cp)
        elseif cp < 0x800 then
            out[#out + 1] = string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
        elseif cp < 0x10000 then
            out[#out + 1] = string.char(0xE0 + math.floor(cp / 0x1000),
                0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
        else
            out[#out + 1] = string.char(0xF0 + math.floor(cp / 0x40000),
                0x80 + (math.floor(cp / 0x1000) % 0x40),
                0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
        end
        i = i + 1
    end
    return table.concat(out)
end

-- ---------------- FFI 实现 ----------------

local function listDirFFI(dir)
    local pattern = utf8ToUtf16(dir .. "*")
    local data = ffi.new("LUMI_WIN32_FIND_DATAW[1]")
    local h = ffi.C.FindFirstFileW(pattern, data)
    if h == INVALID then
        return nil
    end
    local dirs, files = {}, {}
    local more = true
    while more do
        local attrs = tonumber(data[0].dwFileAttributes) or 0
        local name = utf16ToUtf8(data[0].cFileName)
        if name ~= "." and name ~= ".." then
            if band(attrs, FILE_ATTRIBUTE_DIRECTORY) ~= 0 then
                dirs[#dirs + 1] = name
            else
                files[#files + 1] = name
            end
        end
        more = ffi.C.FindNextFileW(h, data) ~= 0
    end
    ffi.C.FindClose(h)
    table.sort(dirs)
    table.sort(files)
    return dirs, files
end

-- 读文件（Unicode 路径，返回原始字节）
local function readFileFFI(path)
    local wpath = utf8ToUtf16(path)
    local h = ffi.C.CreateFileW(wpath, GENERIC_READ, FILE_SHARE_READ, nil,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nil)
    if h == INVALID then
        return nil, "无法打开文件（错误码 " .. tonumber(ffi.C.GetLastError()) .. "）"
    end
    local chunks = {}
    local buf = ffi.new("uint8_t[?]", 65536)
    local read = ffi.new("uint32_t[1]")
    while true do
        if ffi.C.ReadFile(h, buf, 65536, read, nil) == 0 then break end
        local n = tonumber(read[0]) or 0
        if n == 0 then break end
        chunks[#chunks + 1] = ffi.string(buf, n)
    end
    ffi.C.CloseHandle(h)
    return table.concat(chunks)
end

-- 写文件（Unicode 路径，覆盖写入）
local function writeFileFFI(path, data)
    local wpath = utf8ToUtf16(path)
    local h = ffi.C.CreateFileW(wpath, GENERIC_WRITE, 0, nil,
        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nil)
    if h == INVALID then
        return nil, "无法写入文件（错误码 " .. tonumber(ffi.C.GetLastError()) .. "）"
    end
    local len = #data
    local buf = ffi.new("uint8_t[?]", math.max(1, len))
    if len > 0 then ffi.copy(buf, data, len) end
    local written = ffi.new("uint32_t[1]")
    local ok = ffi.C.WriteFile(h, buf, len, written, nil) ~= 0
    ffi.C.CloseHandle(h)
    if not ok then return nil, "写入失败" end
    return true
end

-- 取文件属性位（不存在/失败返回 nil）
local function getAttributesFFI(path)
    local wpath = utf8ToUtf16(path)
    local attrs = ffi.C.GetFileAttributesW(wpath)
    if tonumber(attrs) == INVALID_FILE_ATTRIBUTES then return nil end
    return tonumber(attrs)
end

-- ---------------- popen 回退 ----------------

local DIRS_SEP = "@@LUMI_DIRS_END@@"

local function isValidUtf8(s)
    local i, n = 1, #s
    while i <= n do
        local b = s:byte(i)
        local len
        if b < 0x80 then len = 1
        elseif b >= 0xC2 and b < 0xE0 then len = 2
        elseif b >= 0xE0 and b < 0xF0 then len = 3
        elseif b >= 0xF0 and b < 0xF5 then len = 4
        else return false end
        if i + len - 1 > n then return false end
        for j = i + 1, i + len - 1 do
            local c = s:byte(j)
            if c == nil or c < 0x80 or c >= 0xC0 then return false end
        end
        i = i + len
    end
    return true
end

local function listDirPopen(dir)
    local dirs, files = {}, {}
    local cmd = 'chcp 65001 >nul & dir /b /ad "' .. dir .. '" 2>nul'
        .. ' & echo ' .. DIRS_SEP
        .. ' & dir /b /a-d "' .. dir .. '" 2>nul'
    local ok, p = pcall(io.popen, cmd)
    if ok and p then
        local out = p:read("*a")
        p:close()
        local target = dirs
        for line in (out or ""):gmatch("[^\r\n]+") do
            if line:gsub("%s+$", "") == DIRS_SEP then
                target = files
            elseif isValidUtf8(line) then
                target[#target + 1] = line
            end
        end
    end
    table.sort(dirs)
    table.sort(files)
    return dirs, files
end

-- ---------------- 对外 ----------------

function fs.listDir(dir)
    local d = (dir or ""):gsub("/", "\\")
    if d:sub(-1) ~= "\\" then d = d .. "\\" end
    if ffi then
        local dirs, files = listDirFFI(d)
        if dirs then return dirs, files end
    end
    return listDirPopen(d)
end

function fs.readFile(path)
    if ffi then return readFileFFI(path) end
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local data = f:read("*a")
    f:close()
    return data
end

function fs.writeFile(path, data)
    if ffi then return writeFileFFI(path, data or "") end
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    f:write(data or "")
    f:close()
    return true
end

-- 返回属性位（不存在/失败返回 nil）；配合 fs.isDir 判断目录
function fs.getAttributes(path)
    if ffi then return getAttributesFFI(path) end
    local f = io.open(path, "rb")
    if not f then return nil end
    f:close()
    return 0 -- 无 FFI 时只能判断「是文件」，返回非目录属性
end

function fs.isDir(attrs)
    return attrs ~= nil and band(attrs, FILE_ATTRIBUTE_DIRECTORY) ~= 0
end

return fs
