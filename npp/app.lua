--[[
    app.lua —— Notepad++ 复刻版核心逻辑
    多文档管理、文件打开/保存、查找替换、转到行、缩放、快捷键、
    文件浏览器、确认弹窗。配合 npp/tabbar、npp/statusbar、npp/toolbar 使用。
]]

local syntax = require("npp.syntax")
local fs = require("npp.fs")

local App = {}
App.__index = App

local function isCtrl()
    return love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
end

local function isShift()
    return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
end

local function joinPath(dir, name)
    dir = dir or ""
    if dir:sub(-1) ~= "\\" and dir:sub(-1) ~= "/" then
        dir = dir .. "\\"
    end
    return dir .. name
end

local function parentOf(dir)
    dir = (dir or ""):gsub("[\\/]+$", "")
    if dir == "" then return nil end
    local i = dir:match("^.*[\\/]()")
    if not i then return nil end
    local parent = dir:sub(1, i - 1)
    if parent == "" then return nil end
    return parent
end

-- ---------------- 构造 ----------------

function App.new(ui)
    local self = setmetatable({}, App)
    self.ui = ui
    self.docs = {}
    self.active = 0
    self.editor = nil
    self.zoom = 100
    self.unnamedCount = 0
    self._lastFind = nil
    self._quitting = false
    self._dirCache = {}
    self._dirCacheOrder = {}
    self.cwd = self:_defaultDir()
    self:newFile()
    return self
end

function App:_defaultDir()
    local p = os.getenv("USERPROFILE")
    if p and p ~= "" then return p:gsub("/", "\\") end
    local src = love.filesystem.getSourceBaseDirectory()
    if src then return src:gsub("/", "\\") end
    return "C:\\"
end

-- ---------------- 文档管理 ----------------

function App:_makeDoc(name, path, text)
    return {
        name = name or "未命名",
        path = path,
        text = text or "",
        cursor = 0, anchor = nil, prefCol = nil,
        scrollX = 0, scrollY = 0,
        undoStack = {}, redoStack = {},
        dirty = false,
        lang = path and syntax.detect(path) or "text",
    }
end

function App:_saveEditorState()
    local e = self.editor
    if not e then return end
    local d = self.docs[self.active]
    if not d then return end
    d.text = e:getText()
    d.cursor = e.cursor
    d.anchor = e._selAnchor
    d.prefCol = e._prefCol
    d.scrollX = e.scrollX
    d.scrollY = e.scrollY
    d.undoStack = e._undoStack
    d.redoStack = e._redoStack
end

function App:_loadEditorState()
    local e = self.editor
    if not e then return end
    local d = self.docs[self.active]
    if not d then return end
    e._text = d.text
    e.cursor = d.cursor
    e._selAnchor = d.anchor
    e._prefCol = d.prefCol
    e.scrollX = d.scrollX
    e.scrollY = d.scrollY
    e._undoStack = d.undoStack
    e._redoStack = d.redoStack
    e._findText = nil
    e._matches = nil
    e._linesDirty = true
    e:invalidate()
end

function App:_afterSwitch()
    self:updateTitle()
end

-- 由 main.lua 在构建完成后调用，绑定编辑器引用
function App:attach(editor)
    self.editor = editor
    self:_loadEditorState()
    self:updateTitle()
end

function App:_pushDoc(name, path, text)
    self:_saveEditorState()
    self.docs[#self.docs + 1] = self:_makeDoc(name, path, text)
    self.active = #self.docs
    self:_loadEditorState()
    self:_afterSwitch()
end

function App:newFile()
    self.unnamedCount = self.unnamedCount + 1
    self:_pushDoc("未命名 " .. self.unnamedCount, nil, "")
    if self.editor then self.ui:setFocus(self.editor) end
end

function App:switchTo(i)
    if i == self.active or i < 1 or i > #self.docs then return end
    self:_saveEditorState()
    self.active = i
    self:_loadEditorState()
    self:_afterSwitch()
    if self.editor then self.ui:setFocus(self.editor) end
end

function App:closeTab(i)
    local d = self.docs[i]
    if not d then return end
    if d.dirty then
        self:_confirmClose(i)
    else
        self:_removeTab(i)
    end
end

function App:_removeTab(i)
    local wasActive = (i == self.active)
    table.remove(self.docs, i)

    if #self.docs == 0 then
        self.unnamedCount = self.unnamedCount + 1
        self.docs[1] = self:_makeDoc("未命名 " .. self.unnamedCount, nil, "")
        self.active = 1
        self:_loadEditorState()
        self:_afterSwitch()
        return
    end

    if wasActive then
        if self.active > #self.docs then self.active = #self.docs end
        self:_loadEditorState()
        self:_afterSwitch()
    else
        if i < self.active then self.active = self.active - 1 end
        self:_afterSwitch()
    end
end

function App:onEditorChange()
    local d = self.docs[self.active]
    if d then
        d.dirty = true
        self:updateTitle()
    end
end

function App:updateTitle()
    local d = self.docs[self.active]
    local name = d and (d.name or "未命名") or "Notepad++ 复刻"
    if d and d.dirty then name = name .. " *" end
    love.window.setTitle(name .. " - Notepad++ 复刻")
end

function App:hasDirty()
    self:_saveEditorState()
    for _, d in ipairs(self.docs) do
        if d.dirty then return true end
    end
    return false
end

-- ---------------- 文件读写 ----------------

function App:openPath(path)
    self.ui:closeAllOverlays()
    local data, err = fs.readFile(path)
    if not data then
        self.ui:toast("无法打开文件: " .. tostring(err))
        return false
    end
    if data:sub(1, 3) == "\239\187\191" then data = data:sub(4) end
    data = data:gsub("\r\n", "\n"):gsub("\r", "\n")
    local name = path:match("[^\\/]+$") or path
    self:_pushDoc(name, path, data)
    local dir = path:match("^(.*[\\/])")
    if dir then self.cwd = dir end
    self.ui:toast("已打开: " .. name)
    return true
end

function App:_writeFile(d)
    if self.docs[self.active] == d then self:_saveEditorState() end
    local ok, err = fs.writeFile(d.path, d.text)
    if not ok then
        self.ui:toast("保存失败: " .. tostring(err))
        return false
    end
    d.dirty = false
    self:updateTitle()
    self.ui:toast("已保存: " .. d.name)
    return true
end

function App:save()
    local d = self.docs[self.active]
    if not d then return end
    if d.path then
        self:_writeFile(d)
    else
        self:saveAs()
    end
end

function App:saveAll()
    local count = 0
    for i, d in ipairs(self.docs) do
        if d.dirty and d.path then
            if self:_writeFile(d) then count = count + 1 end
        end
    end
    self.ui:toast("已保存 " .. count .. " 个文件")
end

function App:saveAs()
    local d = self.docs[self.active]
    if not d then return end
    local ui = self.ui
    local default = d.path or joinPath(self.cwd, (d.name or "未命名") .. ".txt")
    local pathValue = default
    ui:closeAllOverlays()
    self:_modal({ title = "另存为", w = 520, dismissible = true }, function(p)
        p:input({
            label = "保存路径",
            text = default,
            onChange = function(v) pathValue = v end,
            onSubmit = function() self:_doSaveAs(pathValue) end,
        })
        p:box({ direction = "row", justify = "end", gap = 8 }, function(r)
            r:button("取消", { variant = "text", onClick = function() ui:closeAllOverlays() end })
            r:button("保存", { variant = "filled", onClick = function() self:_doSaveAs(pathValue) end })
        end)
    end)
end

function App:_doSaveAs(path)
    path = (path or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if path == "" then self.ui:toast("路径为空"); return end
    local d = self.docs[self.active]
    if not d then return end
    d.path = path
    d.name = path:match("[^\\/]+$") or path
    d.lang = syntax.detect(path)
    self.ui:closeAllOverlays()
    self:_writeFile(d)
end

-- ---------------- 文件浏览器 ----------------

-- 短时缓存目录列表（2 秒内重复访问同一目录直接命中，避免重复列举）
function App:_listDirCached(dir)
    local norm = (dir or ""):gsub("/", "\\")
    if norm:sub(-1) ~= "\\" then norm = norm .. "\\" end
    local key = norm:lower()
    local now = love.timer.getTime()
    local hit = self._dirCache[key]
    if hit and now - hit.t < 2 then
        return hit.norm, hit.dirs, hit.files
    end
    local dirs, files = fs.listDir(norm)
    self._dirCache[key] = { t = now, norm = norm, dirs = dirs, files = files }
    self._dirCacheOrder[#self._dirCacheOrder + 1] = key
    if #self._dirCacheOrder > 64 then
        local old = table.remove(self._dirCacheOrder, 1)
        self._dirCache[old] = nil
    end
    return norm, dirs, files
end

function App:openDialog()
    self:_buildFileBrowser(self.cwd)
end

local FILE_BROWSER_MAX_ITEMS = 800

function App:_buildFileBrowser(dir)
    self.cwd = dir
    local norm, dirs, files = self:_listDirCached(dir)
    self.ui:closeAllOverlays()
    self:_modal({ title = "打开文件", w = 680, dismissible = true }, function(p)
        p:input({
            label = "路径",
            text = norm,
            onSubmit = function(v) self:_navigateOrOpen(v) end,
        })
        p:scroll({ direction = "column", h = 360, gap = 0, bg = "surface2", radius = "medium" }, function(s)
            local parent = parentOf(norm)
            if parent then
                s:button("↑ 上级目录", { variant = "text", align = "left", padX = 12, h = 30,
                    onClick = function() self:_buildFileBrowser(parent) end })
            end

            local total = #dirs + #files
            if total > FILE_BROWSER_MAX_ITEMS then
                s:label("  （条目过多，仅显示前 " .. FILE_BROWSER_MAX_ITEMS .. " 项）",
                    { variant = "caption", color = "muted" })
            end

            local budget = FILE_BROWSER_MAX_ITEMS
            local nd = math.min(#dirs, budget)
            for i = 1, nd do
                local full = joinPath(norm, dirs[i])
                s:button(dirs[i] .. "\\", { variant = "text", align = "left", padX = 12, h = 30,
                    onClick = function() self:_buildFileBrowser(full) end })
            end
            budget = budget - nd

            local nf = math.min(#files, budget)
            for i = 1, nf do
                local full = joinPath(norm, files[i])
                s:button(files[i], { variant = "text", align = "left", padX = 12, h = 30,
                    onClick = function() self:openPath(full) end })
            end
        end)
        p:box({ direction = "row", justify = "end", gap = 8 }, function(r)
            r:button("取消", { variant = "text", onClick = function() self.ui:closeAllOverlays() end })
        end)
    end)
end

function App:_navigateOrOpen(path)
    path = (path or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if path == "" then return end
    local attrs = fs.getAttributes(path)
    if attrs and not fs.isDir(attrs) then
        self:openPath(path)
    else
        self:_buildFileBrowser(path)
    end
end

-- ---------------- 查找 / 替换 / 转到行 ----------------

function App:_applyFind(v)
    self._lastFind = v
    if self.editor then self.editor:setFindText(v) end
end

function App:findNext()
    if not self.editor or not self._lastFind or #self._lastFind == 0 then return end
    self.editor:setFindText(self._lastFind)
    self.editor:findNext()
end

function App:findPrev()
    if not self.editor or not self._lastFind or #self._lastFind == 0 then return end
    self.editor:setFindText(self._lastFind)
    self.editor:findPrev()
end

function App:findDialog()
    local ui = self.ui
    local findText = self._lastFind or ""
    ui:closeAllOverlays()
    self:_modal({ title = "查找", w = 460, dismissible = false }, function(p)
        p:input({
            label = "查找内容",
            text = findText,
            onChange = function(v) findText = v; self:_applyFind(v) end,
            onSubmit = function() self:findNext() end,
        })
        p:box({ direction = "row", gap = 8 }, function(r)
            r:button("查找上一个", { variant = "tonal", onClick = function() self:findPrev() end })
            r:button("查找下一个", { variant = "filled", onClick = function() self:findNext() end })
            r:button("关闭", { variant = "text", onClick = function() ui:closeAllOverlays() end })
        end)
    end)
    self:_applyFind(findText)
end

function App:replaceDialog()
    local ui = self.ui
    local findText = self._lastFind or ""
    local replaceText = ""
    ui:closeAllOverlays()
    self:_modal({ title = "替换", w = 460, dismissible = false }, function(p)
        p:input({
            label = "查找内容",
            text = findText,
            onChange = function(v) findText = v; self:_applyFind(v) end,
        })
        p:input({
            label = "替换为",
            text = "",
            onChange = function(v) replaceText = v end,
        })
        p:box({ direction = "row", gap = 8 }, function(r)
            r:button("查找下一个", { variant = "tonal", onClick = function() self:findNext() end })
            r:button("替换", { variant = "filled", onClick = function() self:replaceOne(replaceText) end })
            r:button("全部替换", { variant = "filled", onClick = function() self:replaceAll(replaceText) end })
            r:button("关闭", { variant = "text", onClick = function() ui:closeAllOverlays() end })
        end)
    end)
    self:_applyFind(findText)
end

function App:replaceOne(repl)
    if not self.editor then return end
    self.editor:setFindText(self._lastFind or "")
    self.editor:replace(repl or "")
end

function App:replaceAll(repl)
    if not self.editor then return end
    local n = self.editor:replaceAll(self._lastFind or "", repl or "")
    self.ui:toast("替换 " .. n .. " 处")
end

function App:gotoDialog()
    local ui = self.ui
    local lineValue = ""
    local total = self.editor and self.editor:lineCount() or 1
    ui:closeAllOverlays()
    self:_modal({ title = "转到行", w = 360, dismissible = true }, function(p)
        p:input({
            label = "行号 (1 - " .. total .. ")",
            text = "",
            onChange = function(v) lineValue = v end,
            onSubmit = function() self:_gotoLine(lineValue) end,
        })
        p:box({ direction = "row", justify = "end", gap = 8 }, function(r)
            r:button("取消", { variant = "text", onClick = function() ui:closeAllOverlays() end })
            r:button("转到", { variant = "filled", onClick = function() self:_gotoLine(lineValue) end })
        end)
    end)
end

function App:_gotoLine(v)
    local n = tonumber(v)
    if not n or not self.editor then return end
    n = math.max(1, math.min(self.editor:lineCount(), math.floor(n)))
    self.editor:setCursorRowCol(n, 1)
    self.editor:scrollToCursor()
    self.ui:closeAllOverlays()
end

-- ---------------- 缩放 / 视图 ----------------

function App:setZoom(pct)
    pct = math.max(60, math.min(220, math.floor(pct)))
    self.zoom = pct
    if self.editor then
        self.editor.props.fontSize = math.floor(14 * pct / 100)
        self.ui:invalidateLayout()
    end
end

function App:zoomIn() self:setZoom(self.zoom + 10) end
function App:zoomOut() self:setZoom(self.zoom - 10) end
function App:zoomReset() self:setZoom(100) end

function App:toggleLineNumbers()
    if not self.editor then return end
    self.editor.props.lineNumbers = not self.editor.props.lineNumbers
    self.ui:invalidateLayout()
end

function App:setTheme(mode)
    self.ui:setTheme(mode)
end

-- ---------------- 弹窗 ----------------

-- 打开模态弹窗并在关闭时把焦点还给编辑器
function App:_modal(props, fn)
    local dlg = self.ui:dialog(props, fn)
    if dlg._overlayOpts then
        dlg._overlayOpts.onClose = function() self:afterDialogClose() end
    end
    return dlg
end

function App:afterDialogClose()
    if self.editor and not self._quitting then
        self.ui:setFocus(self.editor)
    end
end

function App:aboutDialog()
    self.ui:closeAllOverlays()
    self:_modal({ title = "关于", w = 400, dismissible = true }, function(p)
        p:label("Notepad++ 复刻版", { variant = "subtitle" })
        p:label("基于 LumiUI（LÖVE）实现的多标签文本编辑器。", { wrap = true, color = "muted" })
        p:label("快捷键：Ctrl+N/O/S/W/F/H/G，Ctrl+Tab 切换标签，Ctrl+滚轮缩放。", { wrap = true, color = "muted" })
        p:box({ direction = "row", justify = "end" }, function(r)
            r:button("确定", { variant = "filled", onClick = function() self.ui:closeAllOverlays() end })
        end)
    end)
end

function App:_confirmClose(i)
    local ui = self.ui
    ui:closeAllOverlays()
    local d = self.docs[i]
    self:_modal({ title = "未保存的更改", w = 420, dismissible = false }, function(p)
        p:label("文件「" .. (d and d.name or "") .. "」有未保存的更改，是否保存？", { wrap = true })
        p:box({ direction = "row", justify = "end", gap = 8 }, function(r)
            r:button("取消", { variant = "text", onClick = function() ui:closeAllOverlays() end })
            r:button("不保存", { variant = "tonal", onClick = function()
                ui:closeAllOverlays()
                self:_removeTab(i)
            end })
            r:button("保存", { variant = "filled", onClick = function()
                ui:closeAllOverlays()
                self:_saveAndRemove(i)
            end })
        end)
    end)
end

function App:_saveAndRemove(i)
    local d = self.docs[i]
    if not d then return end
    if not d.path then
        self.ui:toast("文件未命名，请先另存为")
        return
    end
    self:_writeFile(d)
    self:_removeTab(i)
end

function App:_confirmQuit()
    local ui = self.ui
    ui:closeAllOverlays()
    self:_modal({ title = "退出确认", w = 400, dismissible = false }, function(p)
        p:label("存在未保存的更改，确定要退出吗？", { wrap = true })
        p:box({ direction = "row", justify = "end", gap = 8 }, function(r)
            r:button("取消", { variant = "text", onClick = function() ui:closeAllOverlays() end })
            r:button("退出", { variant = "filled", onClick = function()
                self._quitting = true
                love.event.quit()
            end })
        end)
    end)
end

function App:quit()
    if self:hasDirty() and not self._quitting then
        self:_confirmQuit()
        return
    end
    self._quitting = true
    love.event.quit()
end

-- LÖVE 语义：love.quit() 返回 true 表示「中止退出」，返回 false/nil 表示「允许退出」
function App:onQuit()
    if self._quitting then return false end
    if self:hasDirty() then
        self:_confirmQuit()
        return true
    end
    return false
end

-- ---------------- 快捷键 ----------------

function App:onKey(key)
    if isCtrl() then
        if key == "n" then self:newFile(); return true
        elseif key == "o" then self:openDialog(); return true
        elseif key == "s" then
            if isShift() then self:saveAs() else self:save() end
            return true
        elseif key == "w" then self:closeTab(self.active); return true
        elseif key == "f" then self:findDialog(); return true
        elseif key == "h" then self:replaceDialog(); return true
        elseif key == "g" then self:gotoDialog(); return true
        elseif key == "tab" then
            local n = #self.docs
            if n > 1 then
                if isShift() then
                    self:switchTo(((self.active - 2) % n) + 1)
                else
                    self:switchTo((self.active % n) + 1)
                end
            end
            return true
        elseif key == "=" or key == "kp+" then self:zoomIn(); return true
        elseif key == "-" or key == "kp-" then self:zoomOut(); return true
        elseif key == "0" or key == "kp0" then self:zoomReset(); return true
        end
    elseif key == "f3" then
        self:findNext()
        return true
    end
    return false
end

-- ---------------- 菜单 / 工具栏 ----------------

function App:menuItems()
    local A = self
    return {
        { label = "文件", items = {
            { label = "新建", onClick = function() A:newFile() end },
            { label = "打开…", onClick = function() A:openDialog() end },
            { divider = true },
            { label = "保存", onClick = function() A:save() end },
            { label = "另存为…", onClick = function() A:saveAs() end },
            { label = "全部保存", onClick = function() A:saveAll() end },
            { divider = true },
            { label = "关闭标签页", onClick = function() A:closeTab(A.active) end },
            { label = "退出", onClick = function() A:quit() end },
        } },
        { label = "编辑", items = {
            { label = "撤销", onClick = function() if A.editor then A.editor:undo() end end },
            { label = "重做", onClick = function() if A.editor then A.editor:redo() end end },
            { divider = true },
            { label = "剪切", onClick = function() if A.editor then A.editor:cut() end end },
            { label = "复制", onClick = function() if A.editor then A.editor:copy() end end },
            { label = "粘贴", onClick = function() if A.editor then A.editor:paste() end end },
            { divider = true },
            { label = "全选", onClick = function()
                if A.editor then A.editor._selAnchor = 0; A.editor.cursor = #A.editor:getText() end
            end },
        } },
        { label = "搜索", items = {
            { label = "查找…", onClick = function() A:findDialog() end },
            { label = "替换…", onClick = function() A:replaceDialog() end },
            { label = "转到行…", onClick = function() A:gotoDialog() end },
        } },
        { label = "视图", items = {
            { label = "切换行号", onClick = function() A:toggleLineNumbers() end },
            { divider = true },
            { label = "放大", onClick = function() A:zoomIn() end },
            { label = "缩小", onClick = function() A:zoomOut() end },
            { label = "重置缩放", onClick = function() A:zoomReset() end },
            { divider = true },
            { label = "深色主题", onClick = function() A:setTheme("dark") end },
            { label = "浅色主题", onClick = function() A:setTheme("light") end },
        } },
        { label = "帮助", items = {
            { label = "关于", onClick = function() A:aboutDialog() end },
        } },
    }
end

function App:toolbarItems()
    local A = self
    return {
        { label = "新建", onClick = function() A:newFile() end },
        { label = "打开", onClick = function() A:openDialog() end },
        { label = "保存", onClick = function() A:save() end },
        { label = "另存为", onClick = function() A:saveAs() end },
        { label = "撤销", onClick = function() if A.editor then A.editor:undo() end end },
        { label = "重做", onClick = function() if A.editor then A.editor:redo() end end },
        { label = "查找", onClick = function() A:findDialog() end },
        { label = "替换", onClick = function() A:replaceDialog() end },
        { label = "转行", onClick = function() A:gotoDialog() end },
    }
end

return App
