-- This file is part of upmimgui project
-- Licensed under the MIT License
-- Copyright (c) 2018, FYP <https://github.com/THE-FYP>

assert(getMoonloaderVersion() >= 025)

local imgui = require 'upmimgui.imgui'
local DX9 = require 'upmimgui.dx9'
local ffi = require 'ffi'
local winmsg = require 'windows.message'
local memory = require 'memory'
local upmimgui = {}

local renderer = nil
local subscriptionsInitialize = {}
local subscriptionsNewFrame = {}
local eventsRegistered = false
local active = false
local cursorActive = false
local playerLocked = false
local iniFilePath = nil
local defaultGlyphRanges = nil
local dpiScaling

setmetatable(upmimgui, {
    __index = imgui,
    __newindex = function(t, k, v)
        if imgui[k] then
            print('[upmimgui] Warning! Overwriting existing key "' .. k .. '"!')
        end
        rawset(t, k, v)
    end
})

-- background "Shift" triggering fix
memory.fill(0x00531155, 0x90, 5, true)

local function ScaleFontSize(size_pixels)
    return math.floor(upmimgui.GetDpiScale() * size_pixels)
end

local function HookAddFont(f, size_pixels_argn, font_cfg_argn)
    return function(...)
        local args, argc = { ... }, select('#', ...)
        args[size_pixels_argn] = args[size_pixels_argn] and ScaleFontSize(args[size_pixels_argn])
        local font_cfg = args[font_cfg_argn]
        local size_backup
        if font_cfg then
            size_backup = font_cfg.SizePixels
            font_cfg.SizePixels = ScaleFontSize(size_backup)
        end
        local ret = f(unpack(args, 1, argc))
        if font_cfg then
            font_cfg.SizePixels = size_backup
        end
        return ret
    end
end

local function ShowCursor(show)
    if show then
        showCursor(true)
    elseif cursorActive then
        showCursor(false)
    end
    cursorActive = show
end

local function LockPlayer(lock)
    if lock then
        lockPlayerControl(true)
    elseif playerLocked then
        lockPlayerControl(false)
    end
    playerLocked = lock
end

-- MoonLoader v.027
if not isCursorActive then
    isCursorActive = function() return cursorActive end
end

local function InitializeRenderer()
    -- init renderer
    local hwnd = ffi.cast('HWND', readMemory(0x00C8CF88, 4, false))
    local d3ddevice = ffi.cast('LPDIRECT3DDEVICE9', getD3DDevicePtr())
    renderer = assert(DX9.new(d3ddevice, hwnd))

    -- configure imgui
    -- imgui.GetIO().ImeWindowHandle = nil -- default causes crash. TODO: why?
    imgui.GetIO().LogFilename = nil
    local confdir = getWorkingDirectory() .. [[\config\upmimgui\]]
    if not doesDirectoryExist(confdir) then
        createDirectory(confdir)
    end
    iniFilePath = ffi.new('char[260]', confdir .. script.this.filename .. '.ini')
    imgui.GetIO().IniFilename = iniFilePath

    local dsm = upmimgui.GetDpiScalingMode()
    if dsm == 1 or dsm == 2 then
        imgui.GetIO().FontGlobalScale = upmimgui.GetDpiScale()
    elseif dsm == 4 then
        local index = imgui.ImFontAtlas.__index
        index.AddFont = HookAddFont(index.AddFont, 0, 2)
        index.AddFontDefault = HookAddFont(index.AddFontDefault, 0, 2)
        index.AddFontFromFileTTF = HookAddFont(index.AddFontFromFileTTF, 3, 4)
        index.AddFontFromMemoryTTF = HookAddFont(index.AddFontFromMemoryTTF, 4, 5)
        index.AddFontFromMemoryCompressedTTF = HookAddFont(index.AddFontFromMemoryCompressedTTF, 4, 5)
        index.AddFontFromMemoryCompressedBase85TTF = HookAddFont(index.AddFontFromMemoryCompressedBase85TTF, 3, 4)
    end

    -- change font
    local fontFile = getFolderPath(0x14) .. '\\trebucbd.ttf'
    assert(doesFileExist(fontFile), '[upmimgui] Font "' .. fontFile .. '" doesn\'t exist!')
    local fontSize = dsm == 3 and ScaleFontSize(14) or 14
    imgui.GetIO().Fonts:AddFontFromFileTTF(fontFile, fontSize, nil, imgui.GetIO().Fonts:GetGlyphRangesDefault())

    -- invoke initializers
    for _, cb in ipairs(subscriptionsInitialize) do
        cb()
    end

    if dsm == 2 or dsm == 3 or dsm == 4 then
        imgui.GetStyle():ScaleAllSizes(upmimgui.GetDpiScale())
    end
end

local function RegisterEvents()
    addEventHandler('onD3DPresent', function()
        if active then
            if not renderer then
                InitializeRenderer()
            end
            if renderer and not renderer.lost then
                renderer:SwitchContext()
                for _, sub in ipairs(subscriptionsNewFrame) do
                    if sub._render and sub._before then
                        sub:_before()
                    end
                end
                renderer:NewFrame()
                local hideCursor = true
                for _, sub in ipairs(subscriptionsNewFrame) do
                    if sub._render then
                        sub:_draw()
                        hideCursor = hideCursor and sub.HideCursor
                    end
                end
                if hideCursor and not isCursorActive() then
                    imgui.SetMouseCursor(imgui.lib.ImGuiMouseCursor_None)
                end
                renderer:EndFrame()
            end
        end
    end)

    local keyState = {}
    local WM_MOUSEHWHEEL = 0x020E
    local mouseMsgs = {
        [WM_MOUSEHWHEEL] = true,
        [winmsg.WM_LBUTTONDOWN] = true,
        [winmsg.WM_LBUTTONDBLCLK] = true,
        [winmsg.WM_RBUTTONDOWN] = true,
        [winmsg.WM_RBUTTONDBLCLK] = true,
        [winmsg.WM_MBUTTONDOWN] = true,
        [winmsg.WM_MBUTTONDBLCLK] = true,
        [winmsg.WM_LBUTTONUP] = true,
        [winmsg.WM_RBUTTONUP] = true,
        [winmsg.WM_MBUTTONUP] = true,
        [winmsg.WM_MOUSEWHEEL] = true,
        [winmsg.WM_SETCURSOR] = true
    }
    local keyboardMsgs = {
        [winmsg.WM_KEYDOWN] = true,
        [winmsg.WM_SYSKEYDOWN] = true,
        [winmsg.WM_KEYUP] = true,
        [winmsg.WM_SYSKEYUP] = true,
        [winmsg.WM_CHAR] = true
    }
    addEventHandler('onWindowMessage', function(msg, wparam, lparam)
        if not renderer then
            return
        end

        if not upmimgui.DisableInput then
            local keyboard = keyboardMsgs[msg]
            local mouse = mouseMsgs[msg]
            if active and (keyboard or mouse) then
                renderer:SwitchContext()
                local io = imgui.GetIO()
                renderer:WindowMessage(msg, wparam, lparam)
                if (keyboard and io.WantCaptureKeyboard) or (mouse and io.WantCaptureMouse) then
                    if msg == winmsg.WM_KEYDOWN or msg == winmsg.WM_SYSKEYDOWN then
                        keyState[wparam] = false
                        consumeWindowMessage(true, true, true)
                    elseif msg == winmsg.WM_KEYUP or msg == winmsg.WM_SYSKEYUP then
                        if not keyState[wparam] then
                            consumeWindowMessage(true, true, true)
                        end
                    else
                        consumeWindowMessage(true, true, true)
                    end
                end
            end
        end

        -- save key states to prevent key sticking
        if msg == winmsg.WM_KILLFOCUS then
            keyState = {}
        elseif wparam < 256 then
            if msg == winmsg.WM_KEYDOWN or msg == winmsg.WM_SYSKEYDOWN then
                keyState[wparam] = true
            elseif msg == winmsg.WM_KEYUP or msg == winmsg.WM_SYSKEYUP then
                keyState[wparam] = false
            end
        end
    end)

    addEventHandler('onD3DDeviceLost', function()
        if renderer and not renderer.lost then
            renderer:InvalidateDeviceObjects()
            renderer.lost = true
        end
    end)

    addEventHandler('onD3DDeviceReset', function()
        if renderer then
            renderer.lost = false
        end
    end)

    addEventHandler('onScriptTerminate', function(scr)
        if scr == script.this then
            ShowCursor(false)
            LockPlayer(false)
        end
    end)

    local updaterThread = lua_thread.create(function()
        while true do
            wait(0)
            local activate, hideCursor, lockPlayer = false, true, false
            if #subscriptionsNewFrame > 0 then
                for i, sub in ipairs(subscriptionsNewFrame) do
                    if type(sub.Condition) == 'function' then
                        sub._render = sub.Condition()
                    else
                        sub._render = sub.Condition and true
                    end
                    if sub._render then
                        hideCursor = hideCursor and sub.HideCursor
                        lockPlayer = lockPlayer or sub.LockPlayer
                    end
                    activate = activate or sub._render
                end
            end
            active = activate
            ShowCursor(active and not hideCursor)
            LockPlayer(active and lockPlayer)
        end
    end)
    updaterThread.work_in_pause = true
end

local function Unsubscribe(t, sub)
    for i, v in ipairs(t) do
        if v == sub then
            table.remove(t, i)
            return
        end
    end
end

local function ImGuiEnum(name)
    return setmetatable({ __name = name }, {
        __index = function(t, k)
            return imgui.lib[t.__name .. k]
        end
    })
end

--- API ---
upmimgui._VERSION = '1.92.0'
upmimgui.DisableInput = false

upmimgui.ComboFlags = ImGuiEnum('ImGuiComboFlags_')
upmimgui.Dir = ImGuiEnum('ImGuiDir_')
upmimgui.ColorEditFlags = ImGuiEnum('ImGuiColorEditFlags_')
upmimgui.Col = ImGuiEnum('ImGuiCol_')
upmimgui.WindowFlags = ImGuiEnum('ImGuiWindowFlags_')
upmimgui.NavInput = ImGuiEnum('ImGuiNavInput_')
upmimgui.FocusedFlags = ImGuiEnum('ImGuiFocusedFlags_')
upmimgui.Cond = ImGuiEnum('ImGuiCond_')
upmimgui.BackendFlags = ImGuiEnum('ImGuiBackendFlags_')
upmimgui.TreeNodeFlags = ImGuiEnum('ImGuiTreeNodeFlags_')
upmimgui.StyleVar = ImGuiEnum('ImGuiStyleVar_')
upmimgui.DrawCornerFlags = ImGuiEnum('ImDrawCornerFlags_')
upmimgui.DragDropFlags = ImGuiEnum('ImGuiDragDropFlags_')
upmimgui.SelectableFlags = ImGuiEnum('ImGuiSelectableFlags_')
upmimgui.InputTextFlags = ImGuiEnum('ImGuiInputTextFlags_')
upmimgui.MouseCursor = ImGuiEnum('ImGuiMouseCursor_')
upmimgui.FontAtlasFlags = ImGuiEnum('ImFontAtlasFlags_')
upmimgui.HoveredFlags = ImGuiEnum('ImGuiHoveredFlags_')
upmimgui.ConfigFlags = ImGuiEnum('ImGuiConfigFlags_')
upmimgui.DrawListFlags = ImGuiEnum('ImDrawListFlags_')
upmimgui.DataType = ImGuiEnum('ImGuiDataType_')
upmimgui.Key = ImGuiEnum('ImGuiKey_')
upmimgui.TabBarFlags = ImGuiEnum('ImGuiTabBarFlags_')
upmimgui.TabItemFlags = ImGuiEnum('ImGuiTabItemFlags_')
upmimgui.DockNodeFlags = ImGuiEnum('ImGuiDockNodeFlags_')
upmimgui.FreeTypeLoaderFlags = ImGuiEnum('ImGuiFreeTypeLoaderFlags_')
upmimgui.ChildFlags = ImGuiEnum('ImGuiChildFlags_')
upmimgui.ItemFlags = ImGuiEnum('ImGuiItemFlags_')
upmimgui.PopupFlags = ImGuiEnum('ImGuiPopupFlags_')
upmimgui.InputFlags = ImGuiEnum('ImGuiInputFlags_')
upmimgui.ButtonFlags = ImGuiEnum('ImGuiButtonFlags_')
upmimgui.SliderFlags = ImGuiEnum('ImGuiSliderFlags_')
upmimgui.TableFlags = ImGuiEnum('ImGuiTableFlags_')
upmimgui.TableColumnFlags = ImGuiEnum('ImGuiTableColumnFlags_')
upmimgui.TableRowFlags = ImGuiEnum('ImGuiTableRowFlags_')
upmimgui.MultiSelectFlags = ImGuiEnum('ImGuiMultiSelectFlags_')

function upmimgui.OnInitialize(cb)
    assert(type(cb) == 'function')
    table.insert(subscriptionsInitialize, cb)
    return { Unsubscribe = function() Unsubscribe(subscriptionsInitialize, cb) end }
end

function upmimgui.OnFrame(cond, cbBeforeFrame, cbDraw)
    assert(type(cond) == 'function')
    assert(type(cbBeforeFrame) == 'function')
    if cbDraw then assert(type(cbDraw) == 'function') end
    if not eventsRegistered then
        RegisterEvents()
        eventsRegistered = true
    end
    local sub = {
        Condition = cond,
        LockPlayer = false,
        HideCursor = false,
        _before = cbDraw and cbBeforeFrame or nil,
        _draw = cbDraw or cbBeforeFrame,
        _render = false,
    }
    function sub:Unsubscribe()
        Unsubscribe(subscriptionsNewFrame, self)
    end

    function sub:IsActive()
        return self._render
    end

    table.insert(subscriptionsNewFrame, sub)
    return sub
end

function upmimgui.SwitchContext()
    return renderer:SwitchContext()
end

function upmimgui.InvalidateDeviceObjects()
    return renderer:InvalidateDeviceObjects()
end

function upmimgui.CreateTextureFromFile(path)
    return renderer:CreateTextureFromFile(path)
end

function upmimgui.CreateTextureFromFileInMemory(src, size)
    return renderer:CreateTextureFromFileInMemory(src, size)
end

function upmimgui.ReleaseTexture(tex)
    return renderer:ReleaseTexture(tex)
end

function upmimgui.CreateFontsTexture()
    return renderer:CreateFontsTexture()
end

function upmimgui.InvalidateFontsTexture()
    return renderer:InvalidateFontsTexture()
end

function upmimgui.GetRenderer()
    return renderer
end

function upmimgui.IsInitialized()
    return renderer ~= nil
end

function upmimgui.StrCopy(dst, src, len)
    if len or tostring(ffi.typeof(dst)):find('*', 1, true) then
        ffi.copy(dst, src, len)
    else
        len = math.min(ffi.sizeof(dst) - 1, #src)
        ffi.copy(dst, src, len)
        dst[len] = 0
    end
end

local defaultSettings = {
    display_settings = {
        dpi_scaling_mode = 3
    }
}

--  0: None
--  1: ImGuiIO::FontGlobalScale
--  2: ImGuiIO::FontGlobalScale + ImGuiStyle::ScaleAllSizes
--  3: Default ImFontAtlas::AddFont* + ImGuiStyle::ScaleAllSizes
--  4: All ImFontAtlas::AddFont* + ImGuiStyle::ScaleAllSizes
function upmimgui.SetDpiScalingMode(v)
    dpiScaling = v
end

function upmimgui.GetDpiScalingMode()
    if not dpiScaling then
        local inicfg = require('inicfg')
        local data = inicfg.load(defaultSettings, 'upmimgui\\upmimgui.user')
        data = inicfg.load(data, 'upmimgui\\' .. script.this.filename .. '.user')
        dpiScaling = data.display_settings.dpi_scaling_mode
    end
    return dpiScaling
end

function upmimgui.GetDpiScale()
    return renderer.dpiscale
end

local new = {}
setmetatable(new, {
    __index = function(self, key)
        local basetype = ffi.typeof(key)
        local mt = {
            __index = function(self, sz)
                return setmetatable({ type = ffi.typeof('$[$]', self.type, sz) }, getmetatable(self))
            end,
            __call = function(self, ...)
                return self.type(...)
            end
        }
        return setmetatable({ type = ffi.typeof('$[1]', basetype), basetype = basetype }, {
            __index = function(self, sz)
                return setmetatable({ type = ffi.typeof('$[$]', self.basetype, sz) }, mt)
            end,
            __call = mt.__call
        })
    end,
    __call = function(self, t, ...)
        return ffi.new(t, ...)
    end
})
upmimgui.new = new

return upmimgui
