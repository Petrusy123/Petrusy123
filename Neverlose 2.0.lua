script_name (Neverlose)
script_author("s1lent227")
script_version("2.0")

require ("lib.moonloader")
local imgui             = require ('mimgui')
local blur              = require ('mimgui_blur')
local ev                = require ('lib.samp.events')
local memory            = require ('memory')
local bit               = require('bit')
local sampAddChatMessage = sampAddChatMessage
local sampGetCurrentServerAddress = sampGetCurrentServerAddress
local sampGetServerName = sampGetServerName
local sampGetServerPassword = sampGetServerPassword
local sampGetPlayerIdByCharHandle = sampGetPlayerIdByCharHandle
local sampGetPlayerNickname = sampGetPlayerNickname
local sampGetPlayerPing = sampGetPlayerPing


local inicfg            = require 'inicfg'
local ffi               = require 'ffi'
local faicons           = require 'fAwesome6'
local fa_script         = 'https://kit.fontawesome.com/AddFontFromMemoryCompressedBase85TTF.js'
local currentPage       = 'Rage'
local new               = imgui.new
local inputField        = new.char[256]()
local notifications     = {}

local notifIconFont
local NOTIF_ICON_FONT_SIZE = 20 -- default size for notification icons

local playerNick = "Player"
do
    local ok, id = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
    if ok and id then
        local ok2, name = pcall(sampGetPlayerNickname, id)
        if ok2 and name then playerNick = name end
    end
end

local serverIP = "offline"
if type(sampGetCurrentServerAddress) == 'function' then
    local ok, addr = pcall(sampGetCurrentServerAddress)
    if ok and addr then serverIP = addr end
end

local FPS_UPDATE_PERIOD = 0.5
local PING_UPDATE_PERIOD = 1.0

-- Хранилище состояния анимаций и служебных переменных
local state = {
    wmMetrics = {
        fpsLast = os.clock(),
        fpsAccumTime = 0.0,
        fpsAccumCount = 0,
        fpsDisplay = 0.0,
        pingValue = 0,
        pingLast = os.clock()
    },

    lastKeyState = false,

toggleAnim = {},
borderColorAnim = {},
toggleHoverAnim = {},
toggleDrag = {}
}

-- central configuration storage
local cfg = {
    path = 'neverlose.ini',
    data = {
        toggles = {
            no_spread = false,
            rage_enabled = false,
            silent_aim = false,
            auto_fire = false,
            penetrate_walls = false,
            rapid_fire = false,
            auto_save = false,
            ['##wm'] = true,
            ['##12h'] = false,
            ['##trans'] = false
        }
    }
}

function cfg.load()
    local res = inicfg.load(cfg.data, cfg.path)
    if res then
        cfg.data = res
    else
        inicfg.save(cfg.data, cfg.path)
    end
end

function cfg.save()
    inicfg.save(cfg.data, cfg.path)
end

function cfg.get(section, key)
    local sec = cfg.data[section]
    return sec and sec[key]
end

function cfg.set(section, key, value)
    if not cfg.data[section] then cfg.data[section] = {} end
    cfg.data[section][key] = value
end

function cfg.getToggle(key)
    return cfg.get('toggles', key)
end

function cfg.setToggle(key, value)
    cfg.set('toggles', key, value)
end

function cfg.toggle(key)
    local v = not cfg.getToggle(key)
    cfg.setToggle(key, v)
    return v
end

function cfg.reset()
    cfg.data.toggles = {
        no_spread = false,
        rage_enabled = false,
        silent_aim = false,
        auto_fire = false,
        penetrate_walls = false,
        rapid_fire = false,
        auto_save = false,
        watermark = true,
        use_12h = false,
        wm_transparent = false
    }
    cfg.save()
end

cfg.load()

local AboutNeverlose    = imgui.new.bool(false)
local MessageMenuState  = imgui.new.bool(false)
local WaterMark         = imgui.new.bool(cfg.getToggle('##wm'))
local LogoWaterMark     = imgui.new.bool(true)
-- default toggle states; re-use existing globals if script is reloaded
local HotkeysState   = HotkeysState   or imgui.new.bool(false)
local RapidFireState = RapidFireState or imgui.new.bool(false)
local SyncState      = SyncState      or imgui.new.bool(false)
local wmCorner          = 2 -- 1=UL,2=UR,3=BL,4=BR
local wmTransparent     = imgui.new.bool(cfg.getToggle('##trans') or false)
local use12h            = imgui.new.bool(cfg.getToggle('##12h') or false)
local currentConfigName = "default"
local wmOptions         = {
    nickname  = true,
    config    = true,
    latency   = true,
    framerate = true,
    serverip  = true,
    time      = true,
}

local defaultWmOrder = {"nickname", "config", "latency", "framerate", "serverip", "time"}
local wmOrder = wmOrder or defaultWmOrder
local wmLabels = {
    nickname  = "Nickname",
    config    = "Config",
    latency   = "Latency",
    framerate = "Framerate",
    serverip  = "Server IP",
    time      = "Current Time",
}

local VK_INSERT         = 0x2D

local blurRadius        = new.float(0.8)
local WinState          = imgui.new.bool(true)

local ui_meta = {
    __index = function(self, v)
        if v == "switch" then
            -- Логика переключения состояния окна
            local switch = function()
                if self.process and self.process:status() ~= "dead" then
                    return false  -- Предыдущая анимация еще не завершена!
                end
                self.timer = os.clock()
                self.state = not self.state

                self.process = lua_thread.create(function()
                    local bringFloatTo = function(from, to, start_time, duration)
                        local timer = os.clock() - start_time
                        if timer >= 0.00 and timer <= duration then
                            local count = timer / (duration / 100)
                            return count * ((to - from) / 100)
                        end
                        return (timer > duration) and to or from
                    end

                    -- Анимация изменения прозрачности окна
                    while true do wait(0)
                        local a = bringFloatTo(0.00, 1.00, self.timer, self.duration)
                        self.alpha = self.state and a or 1.00 - a
                        if a == 1.00 then break end
                    end
                end)
                return true  -- Состояние окна изменено
            end
            return switch
        end

        if v == "alpha" then
            return self.state and 1.00 or 0.00  -- Прозрачность окна
        end
    end
}

local menu = { state = false, duration = 0.1 } setmetatable(menu, ui_meta)

-- UI animation handlers for menu toggles
local wmAnim   = { state = WaterMark[0],   duration = 0.1 }
setmetatable(wmAnim, ui_meta)
local logoAnim = { state = LogoWaterMark[0], duration = 0.1 }
setmetatable(logoAnim, ui_meta)
local hotkeysAnim   = { state = HotkeysState[0],   duration = 0.1 }
setmetatable(hotkeysAnim, ui_meta)
local rapidAnim     = { state = RapidFireState[0], duration = 0.1 }
setmetatable(rapidAnim, ui_meta)
local syncAnim      = { state = SyncState[0],      duration = 0.1 }
setmetatable(syncAnim, ui_meta)
local settingsAnim  = { state = AboutNeverlose[0], duration = 0.1 }
setmetatable(settingsAnim, ui_meta)
local chatAnim      = { state = MessageMenuState[0], duration = 0.1 }
setmetatable(chatAnim, ui_meta)
local prevWaterMark, prevLogoWaterMark = WaterMark[0], LogoWaterMark[0]

local function DrawCustomVerticalStripeOnEdge(thickness, stripeHeight, x_offset, y_offset, stripeColor, globalAlpha)
    thickness   = thickness   or 4              -- Толщина полоски в пикселях (по умолчанию 4)
    x_offset    = x_offset    or 0              -- Горизонтальное смещение от левого края окна
    y_offset    = y_offset    or 0              -- Вертикальное смещение от верхнего края окна
    stripeColor = stripeColor or 0xFF3854B0     -- Цвет полоски (формат 0xAARRGGBB)
    globalAlpha = globalAlpha or 1.0            -- Глобальная прозрачность

    -- Получаем абсолютное положение и размер текущего окна
    local winPos  = imgui.GetWindowPos()          -- Верхний левый угол окна
    local winSize = imgui.GetWindowSize()         -- Размер окна (ширина, высота)

    -- Если stripeHeight не указан, используем всю высоту окна, учитывая вертикальное смещение
    stripeHeight = stripeHeight or (winSize.y - y_offset)

    -- Рассчитываем координаты полоски:
    -- p1 – верхняя левая точка полоски, p2 – нижняя правая точка полоски
    local p1 = { x = winPos.x + x_offset,         y = winPos.y + y_offset }
    local p2 = { x = p1.x + thickness,             y = p1.y + stripeHeight }

    local draw_list = imgui.GetForegroundDrawList()
    if globalAlpha < 1.0 then
        local a = bit.band(bit.rshift(stripeColor, 24), 0xFF) / 255
        local r = bit.band(bit.rshift(stripeColor, 16), 0xFF) / 255
        local g = bit.band(bit.rshift(stripeColor,  8), 0xFF) / 255
        local b = bit.band(stripeColor, 0xFF) / 255
        stripeColor = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(r, g, b, a * globalAlpha))
    end
    draw_list:AddRectFilled(p1, p2, stripeColor)
end

local function unpackColor(c)
    local a = bit.band(bit.rshift(c, 24), 0xFF) / 255
    local r = bit.band(bit.rshift(c, 16), 0xFF) / 255
    local g = bit.band(bit.rshift(c,  8), 0xFF) / 255
    local b = bit.band(            c, 0xFF) / 255
    return r, g, b, a
end
local function CustomHorizontalSeparator(x_offset, y_offset, width, thickness, color, globalAlpha)
    x_offset    = x_offset    or 0
    y_offset    = y_offset    or 0
    width       = width       or (imgui.GetWindowSize().x - x_offset)
    thickness   = thickness   or 1
    color       = color       or 0xFFFFFFFF
    globalAlpha = globalAlpha or 1.0

    -- распакуем цвет
    local r, g, b, a0 = unpackColor(color)
    local a = a0 * globalAlpha
    local col32 = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(r, g, b, a))

    local draw_list  = imgui.GetWindowDrawList()
    local cursor_pos = imgui.GetCursorScreenPos()

    local p1 = imgui.ImVec2(cursor_pos.x + x_offset,            cursor_pos.y + y_offset)
    local p2 = imgui.ImVec2(cursor_pos.x + x_offset + width,    cursor_pos.y + y_offset)

    -- рисуем линию
    draw_list:AddLine(p1, p2, col32, thickness)

    -- «резерв» места
    imgui.Dummy(imgui.ImVec2(width, thickness * 2))
end

--------LOAD TEXTURES-------
imgui.OnInitialize(function()
    imgui.Theme() -- Применяем стиль
    imgui.GetIO().MouseDrawCursor = false  -- Отключаем курсор ImGui

    if doesFileExist(getWorkingDirectory()..'\\resource\\Neverlose\\neverlose.png') then 
        neverlose           = imgui.CreateTextureFromFile(getWorkingDirectory() .. '\\resource\\Neverlose\\neverlose.png')
    end
    if doesFileExist(getWorkingDirectory()..'\\resource\\Neverlose\\neverlose_settings.png') then
        neverlose_settings  = imgui.CreateTextureFromFile(getWorkingDirectory() .. '\\resource\\Neverlose\\neverlose_settings.png') 
    end
    if doesFileExist(getWorkingDirectory()..'\\resource\\Neverlose\\neverlose_avatar.png') then
        neverlose_avatar    = imgui.CreateTextureFromFile(getWorkingDirectory() .. '\\resource\\Neverlose\\neverlose_avatar.png') 
    end
    if doesFileExist(getWorkingDirectory()..'\\resource\\Neverlose\\neverlose_watermark.png') then
        neverlose_watermark    = imgui.CreateTextureFromFile(getWorkingDirectory() .. '\\resource\\Neverlose\\neverlose_watermark.png') 
    end
    imgui.GetIO().IniFilename = nil
    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    iconRanges = imgui.new.ImWchar[3](faicons.min_range, faicons.max_range, 0)
    imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(faicons.get_font_data_base85('regular'), 16, config, iconRanges) -- solid - тип иконок, так же есть thin, regular, light и duotone
    iconRanges = imgui.new.ImWchar[3](faicons.min_range, faicons.max_range, 0)
    imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(faicons.get_font_data_base85('regular'), 16, config, iconRanges) -- solid - тип иконок, так же есть thin, regular, light и duotone

    local notifConfig = imgui.ImFontConfig()
    notifConfig.PixelSnapH = true
    notifIconFont = imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(
        faicons.get_font_data_base85('regular'),
        NOTIF_ICON_FONT_SIZE,
        notifConfig,
        iconRanges
    )
end)

--------FAWESOME 6--------
downloadUrlToFile(fa_script, "moonloader/lib/fAwesome6", function()
    -- Подключение файла
    require "fAwesome6"
end)

--------КАСТОМ ПОДСКАЗКА--------
function imgui.TextQuestion(text)
    imgui.TextDisabled('(?)')
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushTextWrapPos(450)
        imgui.TextUnformatted(text)
        imgui.PopTextWrapPos()
        imgui.EndTooltip() 
    end
end




-- state for animated buttons: hover progress and ripple animations
local BtnSys = { hover = {}, ripples = {} }

local function ImVec4ToU32(c)
    local a = math.floor(c.w * 255)
    local r = math.floor(c.x * 255)
    local g = math.floor(c.y * 255)
    local b = math.floor(c.z * 255)
    return a * 16777216 + b * 65536 + g * 256 + r
end

-- helpers for color and value interpolation
local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerpVec4(a, b, t)
    return imgui.ImVec4(
        lerp(a.x, b.x, t),
        lerp(a.y, b.y, t),
        lerp(a.z, b.z, t),
        lerp(a.w, b.w, t)
    )
end

local function lerpColor(c1, c2, t)
    local r1, g1, b1, a1 = unpackColor(c1)
    local r2, g2, b2, a2 = unpackColor(c2)
    return imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
        lerp(r1, r2, t),
        lerp(g1, g2, t),
        lerp(b1, b2, t),
        lerp(a1, a2, t)
    ))
end

local function colToU32_vec(v)
    return imgui.ColorConvertFloat4ToU32(v)
end

local function colToU32_rgba(r, g, b, a)
    return imgui.ColorConvertFloat4ToU32(imgui.ImVec4(r, g, b, a))
end

-- state for animated buttons: hover progress and ripple animations
local BtnSys = { hover = {}, ripples = {} }

-- Добавляем параметр isActive — true, если попап открыт
local function ImVec4ToU32(c)
    local a = math.floor(c.w * 255)
    local r = math.floor(c.x * 255)
    local g = math.floor(c.y * 255)
    local b = math.floor(c.z * 255)
    return a * 16777216 + b * 65536 + g * 256 + r
end

local buttonAlpha = {}  -- хранит альфа-канал для каждого кнопки
-- Добавляем параметр isActive — true, если попап открыт
function DrawAnimatedIconButton(id, icon, pos, size, isActive)
    if buttonAlpha[id] == nil then
        buttonAlpha[id] = 0
    end

    imgui.SetCursorPos(pos)
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0,0,0,0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0,0,0,0))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0,0,0,0))

    local clicked = imgui.Button(id, size)
    imgui.PopStyleColor(3)

    local dt = imgui.GetIO().DeltaTime
    if dt <= 0 then dt = 0.016 end
    local transitionTime = 0.15
    local targetAlpha = imgui.IsItemHovered() and 1 or 0

    if targetAlpha > buttonAlpha[id] then
        buttonAlpha[id] = math.min(buttonAlpha[id] + dt / transitionTime, 1)
    else
        buttonAlpha[id] = math.max(buttonAlpha[id] - dt / transitionTime, 0)
    end

    local baseColor = imgui.ImVec4(1, 1, 1, 1) -- белый
    local hoverColor = imgui.ImVec4(75/255, 102/255, 178/255, 1.0) -- синий
    local activeColor = imgui.ImVec4(0, 150/255, 1, 1) -- голубой

    local color
    if isActive then
        color = activeColor
    else
        local r = baseColor.x + (hoverColor.x - baseColor.x) * buttonAlpha[id]
        local g = baseColor.y + (hoverColor.y - baseColor.y) * buttonAlpha[id]
        local b = baseColor.z + (hoverColor.z - baseColor.z) * buttonAlpha[id]
        local a = baseColor.w + (hoverColor.w - baseColor.w) * buttonAlpha[id]
        color = imgui.ImVec4(r, g, b, a)
    end

    local drawList = imgui.GetWindowDrawList()
    local p_min = imgui.GetItemRectMin()
    local p_max = imgui.GetItemRectMax()
    local textSize = imgui.CalcTextSize(icon)
    local textPos = imgui.ImVec2(
        p_min.x + (size.x - textSize.x) / 2,
        p_min.y + (size.y - textSize.y) / 2
    )

    drawList:AddText(textPos, ImVec4ToU32(color), icon)

    return clicked
end

local function DrawPopupToggle(icon, label, state, anim, callback)
    local startPos = imgui.GetCursorPosX()
    local offset = 16 * anim.alpha
    imgui.SetCursorPosX(startPos + offset)
    imgui.PushStyleColor(imgui.Col.Header,        imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.HeaderHovered, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.HeaderActive,  imgui.ImVec4(0, 0, 0, 0))
    if imgui.Selectable(icon .. "    " .. label, false, imgui.SelectableFlags.DontClosePopups) then
        state[0] = not state[0]
        anim.switch()
        if callback then callback(state[0]) end
    end
    imgui.PopStyleColor(3)
    if anim.alpha > 0 then
        local dl = imgui.GetWindowDrawList()
        local pos = imgui.GetItemRectMin()
        local checkSize = imgui.CalcTextSize(faicons("check"))
        dl:AddText(
            imgui.ImVec2(pos.x - offset, pos.y + (imgui.GetTextLineHeight() - checkSize.y) * 0.5 + 2),
            imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, anim.alpha)),
            faicons("check")
        )
    end
end

local function DrawPopupButton(icon, label, state, anim, callback)
    if imgui.Button(icon .. "    " .. label) then
        state[0] = not state[0]
        anim.switch()
        if callback then callback(state[0]) end
    end
end

function DrawAnimatedButton(btnId, label, position, size, options)
    options = options or {}
    local globalAlpha = options.globalAlpha or 1.0
    imgui.SetCursorPos(position)
    imgui.InvisibleButton(btnId, size)
    local clicked = imgui.IsItemClicked()

    local p_min = imgui.GetItemRectMin()
    local p_max = imgui.GetItemRectMax()
    local hovered = imgui.IsItemHovered()

    local dt = imgui.GetIO().DeltaTime
    if dt <= 0 then dt = 0.016 end

    local target = hovered and 1 or 0
    BtnSys.hover[btnId] = BtnSys.hover[btnId] or 0.0
    local speed = options.hoverSpeed or (options.transitionTime and (1 / options.transitionTime)) or 12
    BtnSys.hover[btnId] = BtnSys.hover[btnId] + (target - BtnSys.hover[btnId]) * math.min(dt * speed, 1.0)
    local t = BtnSys.hover[btnId]

    local idleFill  = options.idleFillColor  or imgui.ImVec4(0.05,0.06,0.07,1.0)
    local hoverFill = options.hoverFillColor or imgui.ImVec4(0.53,0.29,0.44,1.0)
    local fillCol   = lerpVec4(idleFill, hoverFill, t)
    fillCol.w = fillCol.w * globalAlpha

    local idleBorder  = options.borderColor       or imgui.ImVec4(0.06,0.06,0.08,1.0)
    local hoverBorder = options.borderHoverColor  or idleBorder
    local borderCol   = lerpVec4(idleBorder, hoverBorder, t)
    borderCol.w = borderCol.w * globalAlpha

    local idleText  = options.textColor       or imgui.ImVec4(1,1,1,1)
    local hoverText = options.textHoverColor or idleText
    local textCol   = lerpVec4(idleText, hoverText, t)
    textCol.w = textCol.w * globalAlpha

    local rounding        = options.rounding or 6
    local borderThickness = options.borderThickness or 1

    local drawList = imgui.GetWindowDrawList()
    drawList:AddRectFilled(p_min, p_max, colToU32_vec(fillCol), rounding)
    drawList:AddRect      (p_min, p_max, colToU32_vec(borderCol), rounding, 0, borderThickness)

    if clicked then
        BtnSys.ripples[btnId] = BtnSys.ripples[btnId] or {}
        local mp = imgui.GetIO().MousePos
        table.insert(BtnSys.ripples[btnId], { pos = imgui.ImVec2(mp.x, mp.y), time = 0 })
        if options.onClick then options.onClick() end
    end

    local ripples = BtnSys.ripples[btnId]
    if ripples then
        drawList:PushClipRect(p_min, p_max, true)
        local rc = options.rippleColor or imgui.ImVec4(1,1,1,0.25)
        local rd = options.rippleDuration or 0.4
        for i = #ripples, 1, -1 do
            local rp = ripples[i]
            rp.time = rp.time + dt
            local prog = rp.time / rd
            if prog >= 1 then
                table.remove(ripples, i)
            else
                local radius = (size.x + size.y) * 0.6 * prog
                local alpha = (1 - prog) * rc.w * globalAlpha
                drawList:AddCircleFilled(rp.pos, radius, colToU32_rgba(rc.x, rc.y, rc.z, alpha), 32)
            end
        end
        drawList:PopClipRect()
    end

    local slide = (options.hoverOffset or 0) * t
    local textSize = imgui.CalcTextSize(label)
    local textPos  = imgui.ImVec2(
        p_min.x + (size.x - textSize.x)/2 + slide,
        p_min.y + (size.y - textSize.y)/2
    )
    drawList:AddText(textPos, colToU32_vec(textCol), label)
end




local TabCfg = {
  btnW = 157,
  btnH = 30,
  padX = 10,
  rounding = 6,
  leftIndicatorWidth = 6,
  sweepColor = imgui.ImVec4(177/255, 1/255, 78/255, 1.0),
  indicatorColor = imgui.ImVec4(177/255, 1/255, 78/255, 1.0),
  bgColor = imgui.ImVec4(0, 0, 0, 0),
  bgHoverColor = imgui.ImVec4(98/255, 0/255, 68/255, 0.9),
  bgActiveColor = imgui.ImVec4(19/255, 23/255, 34/255, 1.0),
  iconColor = imgui.ImVec4(75/255, 102/255, 178/255, 1.0),
  iconColorActive = imgui.ImVec4(177/255, 1/255, 78/255, 1.0),
  textColor = imgui.ImVec4(1.0, 1.0, 1.0, 0.6),
  textColorActive = imgui.ImVec4(1.0, 1.0, 1.0, 1.0),
  hoverSpeed = 12,
  indicatorSpeed = 12,
  sweepDuration = 0.42,
  sweepPad = 4,  -- отступ у sweep-капсулы
  rippleDuration = 0.4,
}

local TabSys = {
  alpha = {},         -- hover alpha per page
  rects = {},         -- last rect per page
  ripples = {},       -- ripple animations per page
  indicator = { y = 0, target = 0, h = 0, init = false },
  sweep = { active = false, prog = 0, start = nil, stop = nil, duration = TabCfg.sweepDuration, color = TabCfg.sweepColor },
  lastActive = nil,   -- предыдущая активная страница (для sweep)
}

local function lerp(a,b,t) return a + (b-a) * t end
local function lerpVec4(a, b, t)
  return imgui.ImVec4(
    lerp(a.x, b.x, t),
    lerp(a.y, b.y, t),
    lerp(a.z, b.z, t),
    lerp(a.w, b.w, t)
  )
end
local function easeOutCubic(t) return 1 - (1 - t) * (1 - t) * (1 - t) end
local function colToU32_vec(v) return imgui.ColorConvertFloat4ToU32(v) end
local function colToU32_rgba(r,g,b,a) return imgui.ColorConvertFloat4ToU32(imgui.ImVec4(r,g,b,a)) end

-- internal: start sweep from prevPage -> newPage
local function startSweep(prevPage, newPage)
  if not newPage then return end
  local r_to = TabSys.rects[newPage]
  local r_from = TabSys.rects[prevPage]

  if not r_to then return end

  -- если нет rect у previous, создаём старт-rect слева от целевой (чтобы эффект всегда виден)
  if not r_from then
    local w = (r_to.rmax.x - r_to.rmin.x)
    r_from = {
      rmin = imgui.ImVec2(r_to.rmin.x - w * 0.6, r_to.rmin.y),
      rmax = imgui.ImVec2(r_to.rmin.x, r_to.rmax.y),
    }
  end

  TabSys.sweep.active = true
  TabSys.sweep.prog = 0
  TabSys.sweep.start = { x = r_from.rmin.x, y = r_from.rmin.y, w = (r_from.rmax.x - r_from.rmin.x), h = (r_from.rmax.y - r_from.rmin.y) }
  TabSys.sweep.stop =  { x = r_to.rmin.x,   y = r_to.rmin.y,   w = (r_to.rmax.x - r_to.rmin.x),   h = (r_to.rmax.y - r_to.rmin.y) }
  TabSys.sweep.duration = TabCfg.sweepDuration
  TabSys.sweep.color = TabCfg.sweepColor
end

-- TabButton: рисует кнопку, хранит rect, обновляет hover alpha; при клике запускает sweep
function TabButton(icon, label, page)
    local btnW, btnH = TabCfg.btnW, TabCfg.btnH
    local padX, rounding = TabCfg.padX, TabCfg.rounding

    if TabSys.alpha[page] == nil then TabSys.alpha[page] = 0.0 end

    local id = "tab_" .. tostring(page)
    imgui.InvisibleButton(id, imgui.ImVec2(btnW, btnH))
    local clicked = imgui.IsItemClicked()
    local rmin = imgui.GetItemRectMin()
    local rmax = imgui.GetItemRectMax()
    local hovered = imgui.IsItemHovered()
    local isActive = (currentPage == page)

    -- сохраняем rect
    TabSys.rects[page] = { rmin = rmin, rmax = rmax }

    local dt = imgui.GetIO().DeltaTime
    if dt <= 0 then dt = 0.016 end
    local target = (isActive or hovered) and 1.0 or 0.0
    TabSys.alpha[page] = lerp(TabSys.alpha[page], target, math.min(dt * TabCfg.hoverSpeed, 1.0))
    local t = TabSys.alpha[page]

    local drawList = imgui.GetWindowDrawList()

    -- индикатор target если активна
    if isActive then
        TabSys.indicator.target = rmin.y
        if not TabSys.indicator.init then
            TabSys.indicator.y = rmin.y
            TabSys.indicator.init = true
        end
        TabSys.indicator.h = btnH
    end

    -- цвета с плавной интерполяцией
    local bgTarget = isActive and TabCfg.bgActiveColor or TabCfg.bgHoverColor
    local bgColor = lerpVec4(TabCfg.bgColor, bgTarget, t)
    if bgColor.w > 0.01 then
        drawList:AddRectFilled(rmin, rmax, colToU32_vec(bgColor), rounding)
    end

    -- ripple эффект
    local ripples = TabSys.ripples[page]
    if ripples then
        drawList:PushClipRect(rmin, rmax, true)
        for i = #ripples, 1, -1 do
            local rp = ripples[i]
            rp.time = rp.time + dt
            local prog = rp.time / TabCfg.rippleDuration
            if prog >= 1 then
                table.remove(ripples, i)
            else
                local radius = btnH * 1.5 * prog
                local alpha = (1 - prog) * 0.3
                drawList:AddCircleFilled(rp.pos, radius, colToU32_rgba(TabCfg.iconColor.x, TabCfg.iconColor.y, TabCfg.iconColor.z, alpha), 32)
            end
        end
        drawList:PopClipRect()
    end

    -- цвета текста и иконки
    local iconColor = lerpVec4(TabCfg.iconColor, TabCfg.iconColorActive, t)
    local textColor = lerpVec4(TabCfg.textColor, TabCfg.textColorActive, t)

    -- ИКОНКА
    local font = imgui.GetFont()
    local sizeFont = font.FontSize
    local offset = 2 * t
    local yIcon = rmin.y + (btnH - sizeFont) * 0.5
    local iconPos = imgui.ImVec2(rmin.x + padX + offset, yIcon)
    drawList:AddText(iconPos, colToU32_vec(iconColor), tostring(icon))

    -- ТЕКСТ
    local xText = rmin.x + padX + sizeFont + 6 + offset
    local yText = rmin.y + (btnH - imgui.GetFont().FontSize) * 0.5
    local textPos = imgui.ImVec2(xText, yText)
    drawList:AddText(textPos, colToU32_vec(textColor), tostring(label))

    -- клик: стартуем sweep и ripple, переключаем страницу
    if clicked then
        local prev = TabSys.lastActive or currentPage
        if prev ~= page then
            startSweep(prev, page)
        end
        TabSys.lastActive = prev
        currentPage = page

        local mp = imgui.GetIO().MousePos
        TabSys.ripples[page] = TabSys.ripples[page] or {}
        table.insert(TabSys.ripples[page], { pos = imgui.ImVec2(mp.x, mp.y), time = 0 })
    end

    return { rmin = rmin, rmax = rmax, alpha = t }
end

-- Finish: должен вызываться после всех TabButton вызовов в том же OnFrame.
-- рисует левый индикатор и sweep эффект.
function DrawTabsFinish(x)
  local dt = imgui.GetIO().DeltaTime
  if dt <= 0 then dt = 0.016 end

  -- плавный индикатор (Y)
  TabSys.indicator.y = lerp(TabSys.indicator.y or 0, TabSys.indicator.target or 0, math.min(dt * TabCfg.indicatorSpeed, 1.0))

  local drawList = imgui.GetWindowDrawList()

  -- левый индикатор
  if TabSys.indicator.init and TabSys.indicator.h and x then
    local w = TabCfg.leftIndicatorWidth
    local x0 = x - TabCfg.gap - w
    local p1 = imgui.ImVec2(x0, TabSys.indicator.y + 4)
    local p2 = imgui.ImVec2(x0 + w, TabSys.indicator.y + TabSys.indicator.h - 4)
    drawList:AddRectFilled(p1, p2, colToU32(TabCfg.indicatorColor), TabCfg.rounding / 2)
  end

  -- sweep animation
  if TabSys.sweep.active then
    local s = TabSys.sweep
    s.prog = math.min(1.0, s.prog + dt / math.max(0.0001, s.duration))
    local t = easeOutCubic(s.prog)

    local ix = lerp(s.start.x, s.stop.x, t)
    local iy = lerp(s.start.y, s.stop.y, t)
    local iw = lerp(s.start.w, s.stop.w, t)
    local ih = lerp(s.start.h, s.stop.h, t)

    local pad = TabCfg.sweepPad
    local alpha = 1.0 * (1.0 - t * 0.9)
    local c = s.color

    drawList:AddRectFilled(
      imgui.ImVec2(ix - pad, iy - pad/2),
      imgui.ImVec2(ix + iw + pad, iy + ih + pad/2),
      colToU32(imgui.ImVec4(c.x, c.y, c.z, c.w * alpha)),
      math.max(4, ih * 0.25)
    )

    -- subtle glow layers
    for i=1,2 do
      local grow = i * 6
      local fall = (1.0 - t) * (0.45 / i)
      drawList:AddRectFilled(
        imgui.ImVec2(ix - pad - grow, iy - pad - grow/2),
        imgui.ImVec2(ix + iw + pad + grow, iy + ih + pad/2 + grow/2),
        colToU32(imgui.ImVec4(c.x, c.y, c.z, c.w * fall)),
        math.max(4, ih * 0.25)
      )
    end

    if s.prog >= 1.0 then s.active = false end
  end
end





function SeparatorLine(length)
    length = length or imgui.GetContentRegionAvail().x
    local drawList = imgui.GetWindowDrawList()
    local pos = imgui.GetCursorScreenPos()

    -- Зарезервировать место под линию
    imgui.Dummy(imgui.ImVec2(length, 1))

    -- Нарисовать линию по координатам зарезервированного места
    drawList:AddLine(
        pos,
        { x = pos.x + length, y = pos.y },
        imgui.GetColorU32(imgui.Col.Border),
        1
    )
end

rageEnabled = cfg.getToggle('rage_enabled') or false
noSpread = cfg.getToggle('no_spread') or false
silentAim = cfg.getToggle('silent_aim') or false
autoFire = cfg.getToggle('auto_fire') or false
penetrateWalls = cfg.getToggle('penetrate_walls') or false
rapidFire = cfg.getToggle('rapid_fire') or false
autoSave = cfg.getToggle('auto_save') or false

------------------------
--------WINDOW 1--------
------------------------

local main_frame = imgui.OnFrame(function() return menu.alpha > 0.00 end, function(self)
	self.HideCursor = not menu.state  -- Убираем курсор при исчезающем окне
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, menu.alpha)  -- Применяем прозрачность
    imgui.SetNextWindowPos(imgui.ImVec2(800, 585), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(800, 585), imgui.Cond.FirstUseEver + imgui.WindowFlags.NoTitleBar)
    imgui.Begin('NeverLose', _, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoScrollbar)

--------USER-------
    CustomHorizontalSeparator(-15, 529, 195, 1, 0xFF151316, menu.alpha)
    imgui.SetCursorPos(imgui.ImVec2(0, 530))
    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(12 / 255, 16 / 255, 19 / 255, 0.99))
    imgui.BeginChild("User", imgui.ImVec2(180, 55), false)
    blur.apply(imgui.GetWindowDrawList(), blurRadius[0])


    imgui.SetCursorPos(imgui.ImVec2(55, 10))
    imgui.Text("s1lent227")
    if imgui.IsItemHovered() and imgui.IsMouseClicked(0) then
        os.execute('start "" "https://t.me/dsdrdsa"')
    end
    imgui.SetCursorPos(imgui.ImVec2(55, 30))
    imgui.TextColored(imgui.ImVec4(177 / 255, 1 / 255, 78 / 255, 1.0), "Limited Beta Access")
    imgui.SetCursorPos(imgui.ImVec2(10, 10))
    imgui.Image(neverlose_avatar, imgui.ImVec2(35, 35))
imgui.EndChild()
imgui.PopStyleColor()

imgui.SetCursorPos(imgui.ImVec2(180, 0))
imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(13 / 255, 14 / 255, 18 / 255, 0.99))
imgui.BeginChild("UpTabButton", imgui.ImVec2(620, 65), false)
blur.apply(imgui.GetWindowDrawList(), blurRadius[0])

-- Установка позиции и размера кнопки
imgui.SetCursorPos(imgui.ImVec2(20, 20))
local btnSize = imgui.ImVec2(100, 30)
DrawAnimatedButton("SaveButton", faicons("floppy_disk") .. "   Save", imgui.ImVec2(20, 20), imgui.ImVec2(100, 30),
  {
    idleFillColor   = imgui.ImVec4(13/255,14/255,18/255,1.0),
    hoverFillColor  = imgui.ImVec4(12/255,30/255,58/255,1.0),
    borderColor     = imgui.ImVec4(22/255,20/255,21/255,0.7),
    textColor       = imgui.ImVec4(1,1,1,1),
    rounding        = 8,
    borderThickness = 1,
    transitionTime  = 0.2,
    globalAlpha     = menu.alpha,
    onClick         = function()
        addNotification({title = "Configs", message = "Config successfully saved."}, 3.0, faicons("gear"))
    end
  }
)

--------BUTTON SETTINGS--------
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0, 0, 0, 0))
    local isPopupOpen = imgui.IsPopupOpen("bars")

-- Рисуем кнопку, передаём isPopupOpen как isActive
if DrawAnimatedIconButton("", faicons("bars"), imgui.ImVec2(545, 25), imgui.ImVec2(25, 25), isPopupOpen) then
    imgui.OpenPopup("bars")
end

-- Сам попап
        imgui.SetNextWindowSize(imgui.ImVec2(190, 220))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(15, 15))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, imgui.ImVec2(13, 13))
    if imgui.BeginPopup("bars", imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoDecoration) then
        local items = {
            {icon = faicons("rectangle_ad"),       label = "Watermark",      state = WaterMark,       anim = wmAnim,      cb = function(v) LogoWaterMark[0] = v; cfg.setToggle('watermark', v); cfg.save() end},
            {icon = faicons("keyboard_brightness"), label = "Hotkeys",        state = HotkeysState,    anim = hotkeysAnim},
            {icon = faicons("gun"),                 label = "Rapid Fire",     state = RapidFireState,  anim = rapidAnim},
            {separator = true},
            {icon = faicons("screencast"),          label = "Synchronization", state = SyncState,       anim = syncAnim},
            {separator = true},
            {icon = faicons('gear'),                 label = "Settings",       state = AboutNeverlose,  anim = settingsAnim, button = true},
            {icon = faicons('comments'),             label = "Chat",           state = MessageMenuState,anim = chatAnim,     button = true}
        }
        for _, entry in ipairs(items) do
            if entry.separator then
                imgui.Separator()
            elseif entry.button then
                DrawPopupButton(entry.icon, entry.label, entry.state, entry.anim, entry.cb)
            else
                DrawPopupToggle(entry.icon, entry.label, entry.state, entry.anim, entry.cb)
            end
        end
        imgui.EndPopup()
    end
    imgui.PopStyleVar(2)
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0, 0, 0, 0))
    if DrawAnimatedIconButton(" ", faicons("magnifying_glass"), imgui.ImVec2(580, 25), imgui.ImVec2(25, 25)) then
        sampAddChatMessage('Вы нажали кнопку', -1)
    end
imgui.EndChild()
imgui.PopStyleColor()

    local availWidth = imgui.GetContentRegionAvail().x
    CustomHorizontalSeparator(180, -8, 690, 1, 0xFF161415, menu.alpha)
    imgui.SetCursorPos(imgui.ImVec2(0, 0))
    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(12 / 255, 16 / 255, 19 / 255, 0.98))
    imgui.BeginChild("TabButtons", imgui.ImVec2(180, 529), false)
    blur.apply(imgui.GetWindowDrawList(), blurRadius[0])

    imgui.SetCursorPos(imgui.ImVec2(15, 25))
    imgui.Image(neverlose, imgui.ImVec2(150, 20))

        imgui.SetCursorPos(imgui.ImVec2(20, 65))
        imgui.TextColored(imgui.ImVec4(0.3176, 0.3725, 0.4235, 1), "Aimbot")

        imgui.SetCursorPos(imgui.ImVec2(12, 85))
        local style = imgui.GetStyle()
        local oldX = style.ButtonTextAlign.x
        local oldY = style.ButtonTextAlign.y
        style.ButtonTextAlign = imgui.ImVec2(0, 0.5)
        TabButton(faicons("crosshairs"), "    Rage", "Rage")
        style.ButtonTextAlign = imgui.ImVec2(oldX, oldY)

        imgui.SetCursorPos(imgui.ImVec2(12, 125))
        local style = imgui.GetStyle()
        local oldX = style.ButtonTextAlign.x
        local oldY = style.ButtonTextAlign.y
        style.ButtonTextAlign = imgui.ImVec2(0, 0.5)
        TabButton(faicons("computer_mouse"), "    Legit", "Legit")
        style.ButtonTextAlign = imgui.ImVec2(oldX, oldY)

        imgui.SetCursorPos(imgui.ImVec2(20, 170))
        imgui.TextColored(imgui.ImVec4(0.3176, 0.3725, 0.4235, 1), "Common")

        imgui.SetCursorPos(imgui.ImVec2(12, 190))
        local style = imgui.GetStyle()
        local oldX = style.ButtonTextAlign.x
        local oldY = style.ButtonTextAlign.y
        style.ButtonTextAlign = imgui.ImVec2(0, 0.5)
        TabButton(faicons('moon_over_sun'), "    Visuals", "Visuals")
        style.ButtonTextAlign = imgui.ImVec2(oldX, oldY)
 
        imgui.SetCursorPos(imgui.ImVec2(12, 230))
        local style = imgui.GetStyle()
        local oldX = style.ButtonTextAlign.x
        local oldY = style.ButtonTextAlign.y
        style.ButtonTextAlign = imgui.ImVec2(0, 0.5)
        TabButton(faicons("list_tree"), "    Miscellaneous", "Miscellaneous")
        style.ButtonTextAlign = imgui.ImVec2(oldX, oldY)
        
        imgui.SetCursorPos(imgui.ImVec2(20, 275))
        imgui.TextColored(imgui.ImVec4(0.3176, 0.3725, 0.4235, 1), "Presets")

        imgui.SetCursorPos(imgui.ImVec2(12, 295))
        local style = imgui.GetStyle()
        local oldX = style.ButtonTextAlign.x
        local oldY = style.ButtonTextAlign.y
        style.ButtonTextAlign = imgui.ImVec2(0, 0.5)
        TabButton(faicons('gear'), "    Configs", "Configs")
        style.ButtonTextAlign = imgui.ImVec2(oldX, oldY)
        imgui.PopStyleColor()

    imgui.EndChild()
    imgui.GetForegroundDrawList()
    imgui.PopStyleColor()

    imgui.SameLine()


imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(11 / 255, 10 / 255, 15 / 255, 0.99)) -- Темно-серый фон
imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 0.0) -- Для float-параметров
imgui.SetCursorPos(imgui.ImVec2(180, 66))
if imgui.BeginChild("body", imgui.ImVec2(650, 519), false) then
    blur.apply(imgui.GetWindowDrawList(), blurRadius[0])

    if currentPage == "Rage" then
        imgui.SetCursorPos(imgui.ImVec2(35, 15))
        imgui.TextColored(imgui.ImVec4(0.3176, 0.3725, 0.4235, 1), "MAIN")

        imgui.SetCursorPos(imgui.ImVec2(20, 35))
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(15, 15))
        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, imgui.ImVec2(10, 10))
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(10 / 255, 10 / 255, 18 / 255, 0.85))
        imgui.PushStyleColor(imgui.Col.Border,  imgui.ImVec4(14 / 255, 15 / 255, 18 / 255, 1.00)) -- Цвет границы
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 10.0)
        if imgui.BeginChild("Child1", imgui.ImVec2(285, 198), true) then
            imgui.Text("Enabled")
            imgui.SameLine(205)
            if imgui.Button(faicons('gear') .. "", imgui.ImVec2(22, 19)) then
                imgui.OpenPopup("Enabled")
            end
            imgui.SetNextWindowSize(imgui.ImVec2(285, 45))
            if imgui.BeginPopup("Enabled", imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoDecoration) then
                imgui.Text("No spread")
                imgui.SameLine(240)
                noSpread = ToggleSwitch("no_spread", noSpread or false)
                imgui.EndPopup()
            end
            imgui.SameLine(240)
            rageEnabled = ToggleSwitch("rage_enabled", rageEnabled or false)
            SeparatorLine(255)
            imgui.Text("Silent Aim")
            imgui.SameLine(240)
            silentAim = ToggleSwitch("silent_aim", silentAim or false)
            SeparatorLine(255)
            imgui.Text("Automatic Fire")
            imgui.SameLine(240)
            autoFire = ToggleSwitch("auto_fire", autoFire or false)
            SeparatorLine(255)
            imgui.Text("Penetrate Walls")
            imgui.SameLine(240)
            penetrateWalls = ToggleSwitch("penetrate_walls", penetrateWalls or false)
            SeparatorLine(255)
            imgui.Text("Field of View")
            
            imgui.EndChild()
        end
        imgui.PopStyleVar(2)
        imgui.PopStyleColor()

        imgui.SetCursorPos(imgui.ImVec2(330, 15))
        imgui.TextColored(imgui.ImVec4(0.3176, 0.3725, 0.4235, 1), "OTHER")

        imgui.SetCursorPos(imgui.ImVec2(315, 35))
        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, imgui.ImVec2(15, 13))
        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, imgui.ImVec2(10, 10))
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(10 / 255, 10 / 255, 18 / 255, 0.85))
        imgui.PushStyleColor(imgui.Col.Border,  imgui.ImVec4(14 / 255, 15 / 255, 18 / 255, 1.00)) -- Цвет границы
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 10.0)
        if imgui.BeginChild("Child2", imgui.ImVec2(285, 175), true) then
            imgui.Text("Rapid Fire")
            imgui.SameLine(240)
            rapidFire = ToggleSwitch("rapid_fire", rapidFire or false)
            SeparatorLine(255)
            imgui.Text(tostring(sampGetPlayerPing(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED)))))
            imgui.EndChild()
        end
        imgui.PopStyleVar(3)

        imgui.SetCursorPos(imgui.ImVec2(35, 240))
        imgui.TextColored(imgui.ImVec4(0.3176, 0.3725, 0.4235, 1), "SELECTION")

        imgui.SetCursorPos(imgui.ImVec2(20, 260))
        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, imgui.ImVec2(15, 15))
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(10 / 255, 10 / 255, 18 / 255, 0.85))
        imgui.PushStyleColor(imgui.Col.Border,  imgui.ImVec4(14 / 255, 15 / 255, 18 / 255, 1.00))   -- Цвет границы
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 10.0)
        if imgui.BeginChild("Child3", imgui.ImVec2(285, 45), true) then
            imgui.Text("Hit Chance")
            imgui.EndChild()
        end
        imgui.PopStyleVar(2)

        imgui.PopStyleColor()
    end
    imgui.EndChild()
end

imgui.PopStyleVar(1)
imgui.PopStyleColor()

    if currentPage == "Legit" then
        imgui.Text("Legitbot")
        imgui.Separator()
    end

    if currentPage == "Configs" then
        imgui.Text("Configs")
        imgui.Separator()
        imgui.SetCursorPos(imgui.ImVec2(500, 20))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(3 / 255, 122 / 255, 179 / 255, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(7 / 255, 149 / 255, 215 / 255, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(56/255, 84/255, 176/255, 1))
        if imgui.Button(faicons("plus") .. " " .. "Create", imgui.ImVec2(125, 30)) then
            sampAddChatMessage('Вы нажали кнопку',-1)
        end
        imgui.PopStyleColor(3)
    end
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, 1.0)
    imgui.End()
end)

--------WINDOW ABOUT NEVERLOSE-------
imgui.OnFrame(function() return AboutNeverlose[0] end, function()
    imgui.SetNextWindowPos(imgui.ImVec2(1000, 600), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(300, 515), imgui.Cond.FirstUseEver)
    imgui.Begin(faicons('gear') .. " " .. "About Neverlose", AboutNeverlose, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.AlwaysUseWindowPadding)

    imgui.Separator()

    imgui.SetCursorPos(imgui.ImVec2(25, 50))
    imgui.Image(neverlose_settings, imgui.ImVec2(245, 25))

    imgui.SetCursorPos(imgui.ImVec2(140, 100))
    imgui.Separator() -- Разделитель

    imgui.SetCursorPos(imgui.ImVec2(15, 115))
    imgui.SetWindowFontScale(1.1)
    imgui.Text("Username:")
    imgui.SetCursorPos(imgui.ImVec2(88, 115))
    if imgui.IsItemHovered() and imgui.IsMouseClicked(0) then
        os.execute('start "" "https://t.me/dsdrdsa"')
    end

    imgui.SetCursorPos(imgui.ImVec2(15, 140))
    imgui.Text("Branch:")
    imgui.SetCursorPos(imgui.ImVec2(70, 140))
    imgui.TextColored(imgui.ImVec4(177 / 255, 1 / 255, 78 / 255, 1.0), "Release")

    imgui.SetCursorPos(imgui.ImVec2(15, 165))
    imgui.Text("Updated:")
    imgui.SetCursorPos(imgui.ImVec2(80, 165))
    imgui.TextColored(imgui.ImVec4(177 / 255, 1 / 255, 78 / 255, 1.0), "Apr 6 2025")

    imgui.SetCursorPos(imgui.ImVec2(15, 190))
    imgui.Text("Valid Until:")
    imgui.SetCursorPos(imgui.ImVec2(90, 190))
    imgui.TextColored(imgui.ImVec4(177 / 255, 1 / 255, 78 / 255, 1.0), "Never")

    imgui.SetCursorPos(imgui.ImVec2(75, 225))
    imgui.Text("neverlose.cc")
    imgui.SetCursorPos(imgui.ImVec2(159, 229))
    imgui.SetWindowFontScale(0.7)
    imgui.Text(faicons("copyright"))
    imgui.SetWindowFontScale(1.0)
    imgui.SetCursorPos(imgui.ImVec2(175, 225))
    imgui.Text("2024-2025")

    imgui.SetCursorPos(imgui.ImVec2(15, 265))
    imgui.Separator()

    imgui.SetCursorPos(imgui.ImVec2(15, 275))
    imgui.Text("Auto Save")
    imgui.SetCursorPos(imgui.ImVec2(250, 275))
    autoSave = ToggleSwitch("auto_save", autoSave or false)

    imgui.SetCursorPos(imgui.ImVec2(15, 300))
    imgui.Separator()

    imgui.SetCursorPos(imgui.ImVec2(15, 310))
    imgui.TextColored(imgui.ImVec4(152 / 255, 174 / 255, 187 / 255, 1.0), "Language")
    imgui.SameLine()

    imgui.SetCursorPos(imgui.ImVec2(15, 336))
    imgui.Separator()

    imgui.SetCursorPos(imgui.ImVec2(15, 346))
    imgui.TextColored(imgui.ImVec4(152 / 255, 174 / 255, 187 / 255, 1.0), "Menu Scale")
    imgui.SetWindowFontScale(1.0)
    imgui.SameLine() 
    
    imgui.SetCursorPos(imgui.ImVec2(15, 372))
    imgui.Separator()

    imgui.Text(faicons('apple'))
    imgui.TextColored(imgui.ImVec4(79 / 255, 125 / 255, 255 / 255, 1.0),faicons("xbox") .. ' ' ..  "s1lent227")
    if imgui.IsItemHovered() and imgui.IsMouseClicked(0) then
        os.execute('start "" "https://t.me/dsdrdsa"')
    end

    imgui.End()
end)

--------WINDOW CHAT-------
imgui.OnFrame(function() return MessageMenuState[0] end, function()
    imgui.SetNextWindowPos(imgui.ImVec2(1000, 600), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(300, 500), imgui.Cond.FirstUseEver)
    imgui.Begin(faicons('comments') .. " " .. "Chat", MessageMenuState, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.AlwaysUseWindowPadding + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
    imgui.Separator()

    imgui.SetCursorPos(imgui.ImVec2(15, 455))
    imgui.Separator() -- Разделитель
    imgui.SetCursorPos(imgui.ImVec2(10, 465))
    imgui.PushItemWidth(179)
    imgui.InputTextWithHint('', 'Message', inputField, 256)
    imgui.PopItemWidth()
    imgui.SameLine()
    imgui.SetCursorPos(imgui.ImVec2(192, 465))
    DrawAnimatedButton("Send", faicons("share"), 
        imgui.ImVec2(192, 465), imgui.ImVec2(30, 23), {
            idleFillColor = imgui.ImVec4(9 / 255, 96 / 255, 139 / 255, 1.0),
            hoverFillColor = imgui.ImVec4(56/255, 84/255, 176/255, 1),
            borderColor = imgui.ImVec4(14 / 255, 15 / 255, 18 / 255, 1.00),
            textColor = imgui.ImVec4(1.0, 1.0, 1.0, 1.0),
            rounding = 6,
            borderThickness = 1,
            transitionTime = 0.2,
            onClick = function()
                addNotification({title = "Chat", message = "Message sent"}, 3.0, faicons("paper_plane"))
            end
    }
)
    
    imgui.SameLine()
    imgui.SetCursorPos(imgui.ImVec2(225, 465))
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(3 / 255, 122 / 255, 179 / 255, 1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(7 / 255, 149 / 255, 215 / 255, 1.0))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(56/255, 84/255, 176/255, 1))
    if imgui.Button(faicons("paper_plane") .. " " .. "Send", imgui.ImVec2(65, 23)) then
        sampAddChatMessage('Вы нажали кнопку',-1)
    end

    imgui.End()
end)

--------WINDOW WATERMARK--------
local WM_HEIGHT = 22
local LOGO_WIDTH, LOGO_HEIGHT = 31, 22
local WM_MARGIN_X, WM_MARGIN_Y, WM_SPACING = 5, 5, 4

local PADDING_X = 5
local ICON_Y, TEXT_Y = 6, 3
local ICON_TEXT_SPACING = 4
local ELEMENT_SPACING = 8
local SEP_PADDING = 5
local SEP_WIDTH = 1
local SEP_HEIGHT = 15
local SEP_Y_OFFSET = 4
local ACCENT = imgui.ImVec4(177 / 255, 1 / 255, 78 / 255, 1.0)

local function getScreenSize()
    local w, h = 1920, 1080
    if type(getScreenResolution) == 'function' then
        local ww, hh = getScreenResolution()
        if ww then w = ww end
        if hh then h = hh end
    end
    return w, h
end

local function updateWatermarkMetrics(now)
    local dt = now - state.wmMetrics.fpsLast
    state.wmMetrics.fpsLast = now
    state.wmMetrics.fpsAccumTime = state.wmMetrics.fpsAccumTime + dt
    state.wmMetrics.fpsAccumCount = state.wmMetrics.fpsAccumCount + 1
    if state.wmMetrics.fpsAccumTime >= FPS_UPDATE_PERIOD then
        state.wmMetrics.fpsDisplay = state.wmMetrics.fpsAccumCount / state.wmMetrics.fpsAccumTime
        state.wmMetrics.fpsAccumTime = state.wmMetrics.fpsAccumTime - FPS_UPDATE_PERIOD
        state.wmMetrics.fpsAccumCount = 0
    end
    if now - state.wmMetrics.pingLast >= PING_UPDATE_PERIOD then
        local ping = 0
        if sampGetPlayerPing and sampGetPlayerIdByCharHandle then
            local ok, id = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
            if ok and id then
                local okPing, value = pcall(sampGetPlayerPing, id)
                if okPing and value then ping = value end
            end
        end
        state.wmMetrics.pingValue = ping
        state.wmMetrics.pingLast = now
    end
end

local function buildWatermarkElements()
    updateWatermarkMetrics(os.clock())
    local order = wmOrder or defaultWmOrder
    local items = {}
    for _, key in ipairs(order) do
        if wmOptions[key] then
            if key == 'nickname' then
                table.insert(items, {icon = 'user', text = playerNick})
            elseif key == 'config' then
                table.insert(items, {icon = 'gear', text = currentConfigName})
            elseif key == 'latency' then
                table.insert(items, {icon = 'wifi', text = string.format('%d ms', state.wmMetrics.pingValue)})
            elseif key == 'framerate' then
                table.insert(items, {icon = 'chart_line_up', text = string.format('%.0f fps', state.wmMetrics.fpsDisplay)})
            elseif key == 'serverip' then
                table.insert(items, {icon = 'globe', text = serverIP})
            elseif key == 'time' then
                local fmt = use12h[0] and '%I:%M %p' or '%H:%M'
                table.insert(items, {icon = 'clock', text = os.date(fmt)})
            end
        end
    end

    local elements = {}
    for i, item in ipairs(items) do
        table.insert(elements, item)
        if i < #items then
            table.insert(elements, {sep = true})
        end
    end
    return elements
end

local function calcWatermarkWidth(elements)
    local width = PADDING_X
    for i, e in ipairs(elements) do
        if e.sep then
            width = width + SEP_PADDING + SEP_WIDTH + SEP_PADDING
        else
            local iconW = imgui.CalcTextSize(faicons(e.icon)).x
            local textW = imgui.CalcTextSize(e.text).x
            width = width + iconW + ICON_TEXT_SPACING + textW
            if i < #elements then
                width = width + ELEMENT_SPACING
            end
        end
    end
    width = width + PADDING_X
    return width
end

local wmFrameCache = {frame = -1}
local function getWatermarkFrameData()
    local frame = imgui.GetFrameCount()
    if wmFrameCache.frame ~= frame then
        local elements = buildWatermarkElements()
        local width = calcWatermarkWidth(elements)
        local screenW, screenH = getScreenSize()
        local wmX, wmY, logoX, logoY

        if WaterMark[0] or wmAnim.alpha > 0 then
            if wmCorner == 1 or wmCorner == 3 then -- left side
                wmX = WM_MARGIN_X + ((LogoWaterMark[0] or logoAnim.alpha > 0) and (LOGO_WIDTH + WM_SPACING) or 0)
            else -- right side
                wmX = screenW - width - WM_MARGIN_X
            end
            wmY = (wmCorner <= 2) and WM_MARGIN_Y or (screenH - WM_HEIGHT - WM_MARGIN_Y)
        end

        if LogoWaterMark[0] or logoAnim.alpha > 0 then
            if wmCorner == 1 or wmCorner == 3 then -- left side␊
                logoX = WM_MARGIN_X
            else
                logoX = (wmX and (wmX - LOGO_WIDTH - WM_SPACING)) or (screenW - LOGO_WIDTH - WM_MARGIN_X)
            end
            logoY = (wmCorner <= 2) and WM_MARGIN_Y or (screenH - LOGO_HEIGHT - WM_MARGIN_Y)
        end
        wmFrameCache.frame = frame
        wmFrameCache.width = width
        wmFrameCache.wmX = wmX or wmFrameCache.wmX
        wmFrameCache.wmY = wmY or wmFrameCache.wmY
        wmFrameCache.logoX = logoX or wmFrameCache.logoX
        wmFrameCache.logoY = logoY or wmFrameCache.logoY
        wmFrameCache.elements = elements
    end
    return wmFrameCache
end

local function drawWatermarkElements(elements, alpha)
    local cursorX = PADDING_X
    for i, e in ipairs(elements) do
        if e.sep then
            cursorX = cursorX + SEP_PADDING
            DrawCustomVerticalStripeOnEdge(SEP_WIDTH, SEP_HEIGHT, cursorX, SEP_Y_OFFSET, 0xFF3A3D4B, alpha)
            cursorX = cursorX + SEP_WIDTH + SEP_PADDING
        else
            imgui.SetCursorPos(imgui.ImVec2(cursorX, ICON_Y))
            imgui.SetWindowFontScale(0.8)
            imgui.TextColored(ACCENT, faicons(e.icon))
            imgui.SetWindowFontScale(1.0)
            cursorX = cursorX + imgui.CalcTextSize(faicons(e.icon)).x + ICON_TEXT_SPACING
            imgui.SetCursorPos(imgui.ImVec2(cursorX, TEXT_Y))
            imgui.Text(e.text)
            cursorX = cursorX + imgui.CalcTextSize(e.text).x
            if i < #elements then
                cursorX = cursorX + ELEMENT_SPACING
            end
        end
    end
end

local contextPos = {x = 0, y = 0}
local cornerNames = {"Upper-Left", "Upper-Right", "Bottom-Left", "Bottom-Right"}

local function drawWatermarkContext()
    -- Привязка контекста к углам экрана
    local screenW, screenH = getScreenSize()
    local contextX, contextY

    -- Определение позиции в зависимости от угла
    if wmCorner == 1 then
        contextX, contextY = WM_MARGIN_X, WM_MARGIN_Y
    elseif wmCorner == 2 then
        contextX, contextY = screenW - WM_MARGIN_X - 90, WM_MARGIN_Y
    elseif wmCorner == 3 then
        contextX, contextY = WM_MARGIN_X, screenH - WM_MARGIN_Y - 320
    else
        contextX, contextY = screenW - WM_MARGIN_X - 90, screenH - WM_MARGIN_Y - 320
    end

    -- Настройка позиции окна для контекста
    imgui.SetNextWindowPos(imgui.ImVec2(contextX, contextY), imgui.Cond.Always)
    if imgui.BeginPopup("WatermarkContext") then
        local contentW = imgui.GetWindowContentRegionWidth()
        local toggleW = (imgui.GetTextLineHeight() + imgui.GetStyle().FramePadding.y * 2) * 1.8

        imgui.Text("Build")
        imgui.SameLine(contentW - toggleW)
        WaterMark[0] = ToggleSwitch("##wm", WaterMark[0] or false, 'watermark')

        imgui.Text("Use 12h Format")
        imgui.SameLine(contentW - toggleW)
        use12h[0] = ToggleSwitch("##12h", use12h[0] or false, 'use_12h')

        imgui.Text("Lock To")
        imgui.SameLine(contentW - 120)
        imgui.SetNextItemWidth(120)
        if imgui.BeginCombo("##wmCorner", cornerNames[wmCorner]) then
            for i, name in ipairs(cornerNames) do
                if imgui.Selectable(name, wmCorner == i) then
                    wmCorner = i
                end
            end
            imgui.EndCombo()
        end

        imgui.Text("Transparent")
        imgui.SameLine(contentW - toggleW)
        wmTransparent[0] = ToggleSwitch("##trans", wmTransparent[0] or false, 'wm_transparent')

        imgui.Separator()

        local handleW = 10
        local itemW = contentW - handleW
        for i, key in ipairs(wmOrder) do
            imgui.PushIDStr(key)
            local label = wmLabels[key]

            local disableColor
            if not wmOptions[key] then
                disableColor = true
                imgui.PushStyleColor(imgui.Col.Text, imgui.GetStyle().Colors[imgui.Col.TextDisabled])
            end

            if imgui.Selectable(label, false, imgui.SelectableFlags.DontClosePopups, imgui.ImVec2(itemW, 0)) then
                wmOptions[key] = not wmOptions[key]
            end
            if disableColor then imgui.PopStyleColor() end

            -- drag handle
            local handleH = imgui.GetTextLineHeight() + imgui.GetStyle().FramePadding.y * 2
            imgui.SameLine(contentW - handleW)
            imgui.PushStyleColor(imgui.Col.Button, imgui.GetStyle().Colors[imgui.Col.WindowBg])
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.GetStyle().Colors[imgui.Col.WindowBg])
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.GetStyle().Colors[imgui.Col.WindowBg])
            imgui.Button(":::", imgui.ImVec2(handleW, handleH))
            imgui.PopStyleColor(3)

            if imgui.BeginDragDropSource() then
                local payloadData = ffi.new("int[1]", i)
                imgui.SetDragDropPayload("WM_ITEM", payloadData, 4)
                imgui.Text(label)
                imgui.EndDragDropSource()
            end

            if imgui.BeginDragDropTarget() then
                local payload = imgui.AcceptDragDropPayload("WM_ITEM")
                if payload ~= nil then
                    local src = ffi.cast("int*", payload.Data)[0]
                    local moved = table.remove(wmOrder, src)
                    table.insert(wmOrder, i, moved)
                end
                imgui.EndDragDropTarget()
            end

            imgui.PopID()
        end

        imgui.EndPopup()
    end
end

local function renderWatermarks()
    if WaterMark[0] ~= prevWaterMark then
        wmAnim.switch()
        prevWaterMark = WaterMark[0]
    end
    if LogoWaterMark[0] ~= prevLogoWaterMark then
        logoAnim.switch()
        prevLogoWaterMark = LogoWaterMark[0]
    end

    local data = getWatermarkFrameData()
    local showWM = wmAnim.alpha > 0
    local showLogo = logoAnim.alpha > 0
    if not (data and (showWM or showLogo)) then return end
    local style = imgui.GetStyle()
    local savedWindowRounding = style.WindowRounding
    style.WindowRounding = 5.0
    local bgAlpha = wmTransparent[0] and 0.0 or 0.99
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(30 / 255, 17 / 255, 60 / 255, bgAlpha))

    local hintPos

    if showWM and data.wmX then
        imgui.SetNextWindowPos(imgui.ImVec2(data.wmX, data.wmY), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(data.width, WM_HEIGHT), imgui.Cond.Always)
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, wmAnim.alpha)
        local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoResize
        if not menu.state then flags = flags + imgui.WindowFlags.NoInputs end
        imgui.Begin("##Watermark", nil, flags)
        local hovered = imgui.IsWindowHovered()
        if menu.state and hovered and imgui.IsMouseClicked(1) then
            local mp = imgui.GetMousePos()
            contextPos.x, contextPos.y = mp.x, mp.y
            imgui.OpenPopup("WatermarkContext")
        end
        drawWatermarkElements(data.elements, wmAnim.alpha)
        if menu.state then
            if hovered then hintPos = {x = data.wmX, y = data.wmY + WM_HEIGHT + 2} end
            drawWatermarkContext()
        end
        imgui.End()
        imgui.PopStyleVar(1)
    end
    if showLogo and data.logoX then
        imgui.SetNextWindowPos(imgui.ImVec2(data.logoX, data.logoY), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(LOGO_WIDTH, LOGO_HEIGHT), imgui.Cond.Always)
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, logoAnim.alpha)
        local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoResize
        if not menu.state then flags = flags + imgui.WindowFlags.NoInputs end
        imgui.Begin("##LogoWaterMark", nil, flags)
        local hovered = imgui.IsWindowHovered()
        if menu.state and hovered and imgui.IsMouseClicked(1) then
            local mp = imgui.GetMousePos()
            contextPos.x, contextPos.y = mp.x, mp.y
            imgui.OpenPopup("WatermarkContext")
        end
        imgui.SetCursorPos(imgui.ImVec2(7, 6))
        imgui.Image(neverlose_watermark, imgui.ImVec2(17, 10))
        if menu.state then
            if hovered then hintPos = {x = data.logoX, y = data.logoY + LOGO_HEIGHT + 2} end
            drawWatermarkContext()
        end
        imgui.End()
        imgui.PopStyleVar(1)
    end

    if hintPos then
        imgui.GetForegroundDrawList():AddText(
            imgui.ImVec2(hintPos.x, hintPos.y),
            imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 1)),
            "press m2 for open menu"
        )
    end

    imgui.PopStyleColor()
    style.WindowRounding = savedWindowRounding
end

imgui.OnFrame(
    function() return (WaterMark[0] or LogoWaterMark[0] or wmAnim.alpha > 0 or logoAnim.alpha > 0) and not isPauseMenuActive() end,
    function()
        renderWatermarks()
    end
).HideCursor = true

--------WINDOW NOTIFICATIONS--------
local NOTIF_W, NOTIF_H = 320, 60
local MARGIN_X, MARGIN_Y = 10, 10
local SPACING = 10
local NOTIF_ICON_FONT_SIZE = 20
local RADIUS = 8
local SLIDE_TIME = 0.26
local FADE_TIME = 0.18
local PROGRESS_H = 4
local PROGRESS_CUT = 6
local SHADOW_LAYERS = 2
local TEXT_LEFT = 15
local ICON_BG_X = 15
local ICON_BG_SIZE = NOTIF_ICON_FONT_SIZE + 20
local TEXT_X = ICON_BG_X + ICON_BG_SIZE + 20
local function clamp(v,a,b) if v<a then return a end if v>b then return b end return v end
local function easeOutCubic(t) return 1 - (1 - t) * (1 - t) * (1 - t) end
local notifLastClock = os.clock()

-- Добавление уведомления: text (string или {title="", message=""}), duration (sec), icon (строка faicons)
function addNotification(text, duration, icon)
    duration = duration or 3.0
    local title, message
    if type(text) == 'table' then
        title = text.title and tostring(text.title) or nil
        message = text.message and tostring(text.message) or ""
    else
        message = tostring(text or "")
    end
    table.insert(notifications, {
        title   = title,
        text    = message,
        duration= duration,
        start   = nil,
        icon    = icon or nil,
        closed  = false,
    })
end

-- Принудно закрыть нотификацию по индексу (опция)
function closeNotification(idx)
    if notifications[idx] then notifications[idx].closed = true end
end

-- Рисование — вызывай каждый кадр в GUI
function drawNotifications()
    local now = os.clock()
    local dt = now - notifLastClock
    if dt <= 0 then dt = 0.016 end
    notifLastClock = now

    local screenW = getScreenSize()

    -- Проход с конца (верхнее — верхняя позиция)
    for i = #notifications, 1, -1 do
        local n = notifications[i]
        if not n.start then n.start = now end

        local elapsed = now - n.start
        local duration = n.duration

        -- Если пометили на закрытие — переводим в disappear сразу
        local totalLife = duration + SLIDE_TIME + FADE_TIME
        if n.closed then
            if elapsed < duration then
                n.start = now - duration
                elapsed = duration
            end
        end

        if elapsed >= totalLife then
            table.remove(notifications, i)
        else
            -- Вычисляем параметры анимации
            local alpha = 1.0
            local offset = 0.0
            -- appearing
            if elapsed < SLIDE_TIME then
                local t = clamp(elapsed / SLIDE_TIME, 0, 1)
                local te = easeOutCubic(t)
                alpha = clamp(elapsed / FADE_TIME, 0, 1)
                offset = (1 - te) * (NOTIF_W + MARGIN_X)
            -- visible
            elseif elapsed < duration then
                alpha = 1.0
                offset = 0.0
            -- disappearing
            else
                local t2 = clamp((elapsed - duration) / SLIDE_TIME, 0, 1)
                local te2 = easeOutCubic(t2)
                alpha = clamp(1 - ((elapsed - duration) / FADE_TIME), 0, 1)
                offset = te2 * (NOTIF_W + MARGIN_X)
            end

            -- Позиция
            local x = screenW - NOTIF_W - MARGIN_X + offset
            local y = MARGIN_Y + (i - 1) * (NOTIF_H + SPACING)

            -- Опции окна ImGui
            imgui.SetNextWindowPos(imgui.ImVec2(x, y), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(NOTIF_W, NOTIF_H), imgui.Cond.Always)
            local flags = imgui.WindowFlags.NoTitleBar
                        + imgui.WindowFlags.NoResize
                        + imgui.WindowFlags.NoMove
                        + imgui.WindowFlags.NoScrollbar
                        + imgui.WindowFlags.NoSavedSettings
                        + imgui.WindowFlags.NoInputs 
                        + imgui.WindowFlags.NoBackground

            if imgui.Begin("##notif"..i, nil, flags) then
                local dl = imgui.GetWindowDrawList()
                local wp = imgui.GetWindowPos()
                local ws = imgui.GetWindowSize()

                -- Рисуем слои тени
                for s = 1, SHADOW_LAYERS do
                    local a = 0.06 * (1 - (s - 1) / SHADOW_LAYERS) * alpha
                    local pad = s * 2
                    local shadowCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0, 0, 0, a))
                    dl:AddRectFilled(
                        imgui.ImVec2(wp.x - pad, wp.y - pad),
                        imgui.ImVec2(wp.x + ws.x + pad, wp.y + ws.y + pad),
                        shadowCol,
                        RADIUS + pad
                    )
                end

                -- Фон + граница
                local bgU32 = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(12 / 255, 13 / 255, 17 / 255, 0.95 * alpha))
                dl:AddRectFilled(wp, imgui.ImVec2(wp.x + ws.x, wp.y + ws.y), bgU32, RADIUS)

                local borderU32 = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1 / 255, 1 / 255, 1 / 255, 0.06 * alpha))
                dl:AddRect(wp, imgui.ImVec2(wp.x + ws.x, wp.y + ws.y), borderU32, RADIUS, 0, 1.0)

                -- Иконка (если есть)
                if n.icon then
                    local iconBgPos = imgui.ImVec2(wp.x + ICON_BG_X, wp.y + (NOTIF_H - ICON_BG_SIZE) / 2)
                    local bgCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0, 0, 0, 0.6 * alpha))
                    dl:AddRectFilled(iconBgPos, imgui.ImVec2(iconBgPos.x + ICON_BG_SIZE, iconBgPos.y + ICON_BG_SIZE), bgCol, 3)

                    imgui.PushFont(notifIconFont or imgui.GetFont())
                    local iconSize = imgui.CalcTextSize(n.icon)
                    local iconPos = imgui.ImVec2(iconBgPos.x + (ICON_BG_SIZE - iconSize.x) / 2, iconBgPos.y + (ICON_BG_SIZE - iconSize.y) / 2)
                    local iconColor = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.43, 0.88, 0.05, alpha))
                    dl:AddText(iconPos, iconColor, n.icon)
                    imgui.PopFont()
                end

                -- Текст
                local textX = wp.x + (n.icon and TEXT_X or TEXT_LEFT)
                if n.title then
                    local titleSize = imgui.CalcTextSize(n.title)
                    local message = n.text or ""
                    local msgSize = imgui.CalcTextSize(message)
                    local baseY = wp.y + (NOTIF_H - (titleSize.y + msgSize.y + 2)) / 2
                    dl:AddText(imgui.ImVec2(textX, baseY), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, alpha)), n.title)
                    dl:AddText(imgui.ImVec2(textX, baseY + titleSize.y + 2), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.7, 0.7, 0.7, alpha)), message)
                else
                    local txt = n.text or ""
                    local txtSize = imgui.CalcTextSize(txt)
                    dl:AddText(imgui.ImVec2(textX, wp.y + (NOTIF_H - txtSize.y) / 2 - 1), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, alpha)), txt)
                end

                -- Прогресс-бар снизу
                local lifeRatio = clamp((math.min(elapsed, duration) / duration), 0, 1)
                local barW = (1 - lifeRatio) * ws.x
                local barColor = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.43, 0.88, 0.05, alpha))
                local cut = math.min(PROGRESS_CUT, barW)
                dl:PathClear()
                dl:PathLineTo(imgui.ImVec2(wp.x, wp.y + ws.y - PROGRESS_H))
                dl:PathLineTo(imgui.ImVec2(wp.x + barW, wp.y + ws.y - PROGRESS_H))
                dl:PathLineTo(imgui.ImVec2(wp.x + barW - cut, wp.y + ws.y))
                dl:PathLineTo(imgui.ImVec2(wp.x, wp.y + ws.y))
                dl:PathFillConvex(barColor)

                -- Invisible clickable area
                imgui.SetCursorScreenPos(imgui.ImVec2(wp.x, wp.y))
                if imgui.InvisibleButton("##notifbtn"..i, imgui.ImVec2(ws.x, ws.y)) then
                    notifications[i].closed = true
                end
            end
            imgui.End()
        end
    end
end

imgui.OnFrame(
    function() return #notifications > 0 end,
    function()
        drawNotifications()
    end
).HideCursor = true

local function addNotificationOnLoad()
    addNotification({title = "Neverlose", message = "Load successfully."}, 3.0, faicons("gear"))
end

function main()
    while not isSampAvailable() do
        wait(0)  -- Ждем, пока SAMP не станет доступен
    end

    -- Регистрируем команду чата
    sampRegisterChatCommand('nl', function()
        WinState[0] = not WinState[0]  -- Переключаем состояние окна
    end)

    -- Добавляем уведомление сразу при загрузке
    addNotificationOnLoad()

    -- Главный цикл
    while true do
        -- Обрабатываем нажатие клавиши INSERT
        local currentKeyState = isKeyDown(VK_INSERT)
        if currentKeyState and not state.lastKeyState then
            -- Переключаем состояние меню
            menu.switch()
        end

        -- Сохраняем состояние клавиши
        state.lastKeyState = currentKeyState

        -- Нужен wait(0) для корректного выполнения
        wait(0)
        imgui.GetIO().MouseDrawCursor = false
    end
end


function ToggleSwitch(id, isOn, key)
    local cfgKey = key or id
    -- read persisted state if available
    local stored = cfg.getToggle(cfgKey)
    if stored ~= nil then
        isOn = stored
    else
        cfg.setToggle(cfgKey, isOn)
        cfg.save()
    end

    local size   = imgui.ImVec2(30, 17)
    local radius = size.y * 0.5

    -- define interactive area first so ImGui registers clicks correctly
    imgui.InvisibleButton(id, size)
    local pos = imgui.GetItemRectMin()
    local drawList = imgui.GetWindowDrawList()

    -- handle click
    if imgui.IsItemClicked(0) then
        isOn = not isOn
        cfg.setToggle(cfgKey, isOn)
        cfg.save()
    end

    -- animation state
    local io = imgui.GetIO()
    local dt = io.DeltaTime
    local speed = 5

    if state.toggleAnim[id] == nil then
        state.toggleAnim[id] = isOn and 1 or 0
    end
    if isOn then
        state.toggleAnim[id] = math.min(state.toggleAnim[id] + dt * speed, 1)
    else
        state.toggleAnim[id] = math.max(state.toggleAnim[id] - dt * speed, 0)
    end

    local bgColor   = isOn and 0xFF2E1703 or 0xFF0D0000
    local knobColor = isOn and 0xFFF5A803 or 0xFF948A7D

    drawList:AddRectFilled(
        pos,
        { x = pos.x + size.x, y = pos.y + size.y },
        bgColor,
        radius
    )

    local knobRadius = radius - 2
    local knobCenter = {
        x = pos.x + radius + state.toggleAnim[id] * (size.x - 2 * radius),
        y = pos.y + radius
    }
    drawList:AddCircleFilled(knobCenter, knobRadius, knobColor, 32)

    return isOn
end

function imgui.Theme()
    imgui.SwitchContext()
    local style, colors = imgui.GetStyle(), imgui.GetStyle().Colors
    local clr, ImVec4, ImVec2 = imgui.Col, imgui.ImVec4, imgui.ImVec2

    -- Параметры отступов и размеров
    style.WindowMinSize = imgui.ImVec2(10, 10)
    style.WindowPadding = ImVec2(0, 0) -- Отступы внутри окна
    style.WindowRounding = 10.0 -- Радиус скругления углов окна
    style.FramePadding = ImVec2(5, 5) -- Отступы внутри фреймов
    style.ItemSpacing = ImVec2(12, 8) -- Промежуток между элементами
    style.ItemInnerSpacing = ImVec2(8, 6) -- Внутренние отступы между элементами
    style.IndentSpacing = 25.0 -- Отступ для вложенных объектов
    style.ScrollbarSize = 15.0 -- Ширина полосы прокрутки
    style.ScrollbarRounding = 15.0 -- Радиус скругления полосы прокрутки
    style.ChildRounding = 10.0 -- Скругление для дочерних окон
    style.WindowTitleAlign = ImVec2(0.0, 0.5) -- Центрирование заголовка окна
    style.TabRounding = 6.0
    style.WindowBorderSize = 0.0
    style.ChildBorderSize = 1.0
    style.PopupBorderSize = 1.0
    style.FrameBorderSize = 0.0

    style.FrameRounding    = 6.0   -- Скругление углов фона слайдера
    style.GrabRounding     = 10.0   -- Скругление самого ползунка
    style.GrabMinSize      = 10.0  -- Минимальный размер ползунка
    style.FrameBorderSize  = 0.0   -- Граница слайдера (если нужна)

    -- Установка цветов интерфейса
    colors[clr.Text]             = ImVec4(0.95, 0.96, 0.98, 1.00) -- Цвет текста
    colors[clr.TextDisabled]     = ImVec4(0.36, 0.42, 0.47, 1.00) -- Цвет выключенного текста
    colors[clr.WindowBg]         = ImVec4(0.00, 0.00, 0.00, 0.01) -- Фон окна  
    colors[clr.PopupBg]          = ImVec4(0.08, 0.08, 0.08, 0.94) -- Фон всплывающего окна

    colors[clr.Border]           = ImVec4(0.00, 0.00, 0.00, 0.00) -- Цвет границы
    colors[clr.BorderShadow]     = ImVec4(30 / 255, 17 / 255, 60 / 255, 0.99) -- Тень границы
    colors[clr.FrameBg]          = ImVec4(0.20, 0.25, 0.29, 1.00) -- Фон фрейма
    colors[clr.FrameBgHovered]   = ImVec4(0.12, 0.20, 0.28, 1.00) -- Фон фрейма при наведении
    colors[clr.FrameBgActive]    = ImVec4(0.09, 0.12, 0.14, 1.00) -- Фон активного фрейма
    colors[clr.TitleBg]          = ImVec4(30 / 255, 17 / 255, 60 / 255, 0.99) -- Фон заголовка окна
    colors[clr.TitleBgCollapsed] = ImVec4(0.00, 0.00, 0.00, 1.00) -- Фон свернутого заголовка окна
    colors[clr.TitleBgActive]    = ImVec4(42 / 255, 35 / 255, 69 / 255, 1.00) -- Фон активного заголовка окна
    colors[clr.MenuBarBg]        = ImVec4(0.00, 0.00, 0.00, 1.00) -- Фон панели меню
    colors[clr.ScrollbarBg]      = ImVec4(0.02, 0.02, 0.02, 0.39) -- Фон полосы прокрутки
    colors[clr.ScrollbarGrab]    = ImVec4(0.20, 0.25, 0.29, 1.00) -- Цвет "захвата" полосы прокрутки
    colors[clr.ScrollbarGrabHovered] = ImVec4(0.18, 0.22, 0.25, 1.00) -- Цвет "захвата" при наведении
    colors[clr.ScrollbarGrabActive] = ImVec4(0.09, 0.21, 0.31, 1.00) -- Цвет активного "захвата"
    colors[clr.CheckMark]        = ImVec4(0.28, 0.56, 1.00, 1.00) -- Цвет галочки
    colors[clr.SliderGrab]       = ImVec4(0.28, 0.56, 1.00, 1.00) -- Цвет "захвата" слайдера
    colors[clr.SliderGrabActive] = ImVec4(0.37, 0.61, 1.00, 1.00) -- Цвет активного "захвата" слайдера
    colors[clr.Button]           = ImVec4(0.20, 0.25, 0.29, 1.00) -- Цвет кнопки
    colors[clr.ButtonHovered]    = ImVec4(0.28, 0.56, 1.00, 1.00) -- Цвет кнопки при наведении
    colors[clr.ButtonActive]     = ImVec4(0.06, 0.53, 0.98, 1.00) -- Цвет активной кнопки
    colors[clr.Header]           = ImVec4(0.20, 0.25, 0.29, 0.55) -- Фон заголовка
    colors[clr.HeaderHovered]    = ImVec4(0.26, 0.59, 0.98, 0.80) -- Фон заголовка при наведении
    colors[clr.HeaderActive]     = ImVec4(0.26, 0.59, 0.98, 1.00) -- Фон активного заголовка
    colors[clr.ResizeGrip]       = ImVec4(0.26, 0.59, 0.98, 0.25) -- Цвет захвата изменения размера
    colors[clr.ResizeGripHovered] = ImVec4(0.26, 0.59, 0.98, 0.67) -- Цвет при наведении на захват
    colors[clr.ResizeGripActive] = ImVec4(0.06, 0.05, 0.07, 1.00) -- Цвет активного захвата
    colors[clr.PlotLines]        = ImVec4(0.61, 0.61, 0.61, 1.00) -- Цвет линий графика
    colors[clr.PlotLinesHovered] = ImVec4(1.00, 0.43, 0.35, 1.00) -- Цвет линий графика при наведении
    colors[clr.PlotHistogram]    = ImVec4(0.90, 0.70, 0.00, 1.00) -- Цвет гистограммы
    colors[clr.PlotHistogramHovered] = ImVec4(1.00, 0.60, 0.00, 1.00) -- Цвет гистограммы при наведении
    colors[clr.TextSelectedBg]   = ImVec4(0.25, 1.00, 0.00, 0.43) -- Цвет фона выделенного текста
    colors[clr.ModalWindowDimBg] = ImVec4(1.00, 0.98, 0.95, 0.73) -- Затенение для модальных окон
    colors[imgui.Col.ChildBg]    = imgui.ImVec4(0.10, 0.10, 0.12, 0.90)  -- Добавлен цвет фона для 
    colors[clr.Separator]        = ImVec4(14 / 255, 15 / 255, 18 / 255, 1.00)
end

return state