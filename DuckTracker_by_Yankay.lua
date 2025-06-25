--[[
    DuckTracker — автоматизированный помощник для охоты на уток на сервере Radmir RP.
    Скрипт подсвечивает уток и автоматически собирает трупы.
    Автор: Yankay
--]]

script_name("DuckTracker")
script_author("Yankay")
script_description("DuckTracker — это автоматизированный помощник для охоты на уток на сервере Radmir RP. Скрипт подсвечивает уток и автоматически собирает трупы.")

-- === Импорт библиотек ===
require "lib.moonloader"
local imgui    = require("mimgui")
local sampev   = require 'samp.events'
local vkeys    = require("vkeys")
local ffi      = require("ffi")
local encoding = require 'encoding'
local inicfg   = require 'inicfg'
local requests = require 'requests'

-- === Настройка кодировки ===
encoding.default = 'CP1251'
local u8 = encoding.UTF8

-- === Переменные ImGui ===
local new        = imgui.new
local MainWindow = new.bool()

-- === Глобальные переменные и константы ===
local x2, y2         = getScreenResolution() -- разрешение экрана
local targetModel    = 10809                 -- модель утки
local aimEnabled     = false                 -- включён ли аим
local objectCooldowns= {}                    -- кулдауны на объекты (для автосбора)
local duckTracking   = {}                    -- отслеживание уток
local deadDuckList   = {}                    -- список мёртвых уток

-- === Настройки хоткея аима ===
local aimHotkey      = imgui.new.char(vkeys.VK_E) -- текущий хоткей аима
local aimHotkeyNames = { [vkeys.VK_E] = "E", [vkeys.VK_R] = "R", [vkeys.VK_F] = "F", [vkeys.VK_X] = "X" }
local aimHotkeyList  = { vkeys.VK_E, vkeys.VK_R, vkeys.VK_F, vkeys.VK_X }

-- === Переключатели функций ===
local enableWH      = imgui.new.bool(true)   -- включить WH (подсветка уток)
local enableAutoPick= imgui.new.bool(true)   -- включить авто-сбор уток
local enableStats   = imgui.new.bool(true)   -- включить статистику
local enableDebug   = imgui.new.bool(false)  -- включить отладку

-- === Служебные переменные ===
local waitingForKey = imgui.new.bool(false)  -- ожидание нажатия клавиши для смены хоткея

local function getKeyName(key)
    local vkNames = {
        [0x01] = "LMB", [0x02] = "RMB", [0x03] = "Cancel", [0x04] = "MMB", [0x05] = "X1MB", [0x06] = "X2MB",
        [0x08] = "Backspace", [0x09] = "Tab", [0x0C] = "Clear", [0x0D] = "Enter",
        [0x10] = "Shift", [0x11] = "Ctrl", [0x12] = "Alt", [0x13] = "Pause", [0x14] = "CapsLock",
        [0x1B] = "Esc", [0x20] = "Space", [0x21] = "PageUp", [0x22] = "PageDown", [0x23] = "End", [0x24] = "Home",
        [0x25] = "Left", [0x26] = "Up", [0x27] = "Right", [0x28] = "Down",
        [0x2C] = "PrintScreen", [0x2D] = "Insert", [0x2E] = "Delete",
        [0x30] = "0", [0x31] = "1", [0x32] = "2", [0x33] = "3", [0x34] = "4", [0x35] = "5", [0x36] = "6", [0x37] = "7", [0x38] = "8", [0x39] = "9",
        [0x41] = "A", [0x42] = "B", [0x43] = "C", [0x44] = "D", [0x45] = "E", [0x46] = "F", [0x47] = "G", [0x48] = "H", [0x49] = "I",
        [0x4A] = "J", [0x4B] = "K", [0x4C] = "L", [0x4D] = "M", [0x4E] = "N", [0x4F] = "O", [0x50] = "P", [0x51] = "Q", [0x52] = "R", [0x53] = "S",
        [0x54] = "T", [0x55] = "U", [0x56] = "V", [0x57] = "W", [0x58] = "X", [0x59] = "Y", [0x5A] = "Z",
        [0x5B] = "LWin", [0x5C] = "RWin", [0x5D] = "Apps",
        [0x60] = "Num0", [0x61] = "Num1", [0x62] = "Num2", [0x63] = "Num3", [0x64] = "Num4", [0x65] = "Num5", [0x66] = "Num6", [0x67] = "Num7", [0x68] = "Num8", [0x69] = "Num9",
        [0x6A] = "Num*", [0x6B] = "Num+", [0x6C] = "NumEnter", [0x6D] = "Num-", [0x6E] = "Num.", [0x6F] = "Num/",
        [0x70] = "F1", [0x71] = "F2", [0x72] = "F3", [0x73] = "F4", [0x74] = "F5", [0x75] = "F6", [0x76] = "F7", [0x77] = "F8", [0x78] = "F9", [0x79] = "F10", [0x7A] = "F11", [0x7B] = "F12",
        [0x90] = "NumLock", [0x91] = "ScrollLock",
        [0xA0] = "LShift", [0xA1] = "RShift", [0xA2] = "LCtrl", [0xA3] = "RCtrl", [0xA4] = "LAlt", [0xA5] = "RAlt",
        [0xBA] = ";", [0xBB] = "=", [0xBC] = ",", [0xBD] = "-", [0xBE] = ".", [0xBF] = "/", [0xC0] = "`",
        [0xDB] = "[", [0xDC] = "\\", [0xDD] = "]", [0xDE] = "'"
    }
    return vkNames[key] or ("VK_"..string.format("%02X", key))
end

local config_path = 'DuckTracker/settings'
local config = inicfg.load({
    main = {
        aimHotkey = vkeys.VK_E,
        enableWH = true,
        enableAutoPick = true,
        enableStats = true,
        enableDebug = false
    }
}, config_path)

local function saveConfig()
    config.main.aimHotkey = aimHotkey[0]
    config.main.enableWH = enableWH[0]
    config.main.enableAutoPick = enableAutoPick[0]
    config.main.enableStats = enableStats[0]
    config.main.enableDebug = enableDebug[0]
    inicfg.save(config, config_path)
end

function imgui.CenterText(text)
    local width = imgui.GetWindowWidth()
    local calc = imgui.CalcTextSize(text)
    imgui.SetCursorPosX(width / 2 - calc.x / 2)
    imgui.Text(text)
end

function imgui.CenterButton(label, size)
    local windowWidth = imgui.GetWindowWidth()
    local buttonWidth = size.x
    imgui.SetCursorPosX((windowWidth - buttonWidth) / 2)
    return imgui.Button(label, size)
end

function imgui.CenterTextColored(color, text)
    local width = imgui.GetWindowWidth()
    local calc = imgui.CalcTextSize(text)
    imgui.SetCursorPosX(width / 2 - calc.x / 2)
    imgui.TextColored(color, text)
end

function getObjectKey(x, y, z)
    return string.format("%.1f_%.1f_%.1f", x, y, z)
end

local imgui = require 'mimgui'
local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8

local new = imgui.new
local renderWindow = new.bool(false)


local function clamp(val, min, max)
    if val < min then
        return min
    elseif val > max then
        return max
    else
        return val
    end
end

local bg_alpha = 0
local memory = require("memory")
local dots = {}
local queue = {}

local function random(min, max, s)
    kf = math.random(min, max)
    math.randomseed(os.time() * kf / s)
    rand = math.random(min, max)
    if rand == 0 then 
        if math.random(1, 2) == 1 then 
            rand = -1
        else
            rand = 1 
        end
    end
    return tonumber(rand)
end

local function min_number(a, b, c)
    if a < b and a < c then
        return a
    elseif b < a and b < c then
        return b
    else
        return c
    end
end

local function rainbow(speed, alpha, offset) -- by rraggerr
    local clock = os.clock() + offset
    local r = math.floor(math.sin(clock * speed) * 127 + 128)
    local g = math.floor(math.sin(clock * speed + 2) * 127 + 128)
    local b = math.floor(math.sin(clock * speed + 4) * 127 + 128)
    return r,g,b,alpha
end

local function calccolor(distan)
    local r, g, b = rainbow(0.5, 255, 0)
    return math.floor(min_number(255 * (1 - (distan / 180)), bg_alpha, 100))*0x1000000 + r*0x10000 + g*0x100 + b
end

local screenX, screenY = getScreenResolution()
local r_c = 1
dots = {}
for i = 1, 100 do 
    table.insert(dots, {posx =  random(0, screenX, i), posy = random(0, screenY, i), speedx = random(-1, 1, i), speedy = random(-1, 1, i), rotate = random(0,360,i), random = math.random(-5,5,i)})
end

function onD3DPresent()
    local sx, sy = getScreenResolution()
    if renderWindow[0] then
        local fps = 60/memory.getfloat(12045136, 4, false)
        bg_alpha = math.floor(clamp(bg_alpha + ((--[[about.font[0] and--]] renderWindow[0]) and 10 or -10)*fps, 0, 200))
        renderDrawBox(0, 0, sx, sy, bg_alpha*0x1000000+0x000000)
        for key, val in pairs(dots) do 
            if val.posx >= screenX then val.speedx = -val.speedx val.random = random(-5,5,os.time()*1000) end 
            if val.posy >= screenY then val.speedy = -val.speedy val.random = random(-5,5,os.time()*1000) end 
            if val.posx <= 0 then val.speedx = -val.speedx val.random = random(-5,5,os.time()*1000) end 
            if val.posy <= 0 then val.speedy = -val.speedy val.random = random(-5,5,os.time()*1000) end
            val.posx = val.posx + val.speedx * fps
            val.posy = val.posy + val.speedy * fps
            val.rotate = val.rotate + val.random
        end
        if isKeyDown(1) then
            local x,y = getCursorPos()
            table.remove(dots, 1)
            r_c = r_c + 1 > #dots and 1 or r_c + 1
            x, y = x + random(-100,100,os.time()*math.random(1,9999)), y + random(-100,100,os.time()*math.random(1,9999))
            table.insert(dots, {posx = x, posy = y, speedx = random(-1, 1, r_c), speedy = random(-1, 1, r_c), rotate = random(0,360,r_c), random = math.random(-5,5,r_c)})
        end
        queue = {}
        for key, val in pairs(dots) do 
            for key2, val2 in pairs(dots) do 
                distance = math.sqrt(math.pow(val.posx - val2.posx, 2) + math.pow(val.posy - val2.posy, 2));
                if distance < 180 and distance > 0 then
                    table.insert(queue, {from = key, to = key2, distance = distance})
                end
            end
        end
        for key, val in pairs(queue) do 
            for key2, val2 in pairs(queue) do 
                if val.from == val2.to and val.to == val2.from then 
                    table.remove(queue, key)
                end
            end
        end
        for key, val in pairs(queue) do 
            if val.distance < 180 and val.distance > 0 then 
                renderDrawLine(dots[val.from].posx, dots[val.from].posy, dots[val.to].posx, dots[val.to].posy, 1, calccolor(val.distance))
            end
        end
        mX, mY = getCursorPos()
        for key, val in pairs(dots) do
            renderDrawPolygon(val.posx, val.posy, 5, 5, 6, 0, bg_alpha*0x1000000+0xffffff)
            --if texture == nil then texture = renderLoadTextureFromFileInMemory(memory.strptr(amogus), #amogus) else renderDrawTexture(texture, val.posx-16, val.posy-16, 32, 32, val.rotate, -1) end
            distance = math.sqrt(math.pow(val.posx - mX, 2) + math.pow(val.posy - mY, 2));
            if distance < 180 and distance > 0 then
                renderDrawLine(val.posx, val.posy, mX, mY, 1, calccolor(distance))
            end
        end
    end
end

function setDuckTrackerTheme()
    local style = imgui.GetStyle()
    local colors = style.Colors

    local accent      = imgui.ImVec4(0.48, 0.41, 0.93, 1.00)
    local accentHover = imgui.ImVec4(0.60, 0.52, 1.00, 1.00)
    local accentActive= imgui.ImVec4(0.38, 0.31, 0.83, 1.00)
    local bg          = imgui.ImVec4(0.13, 0.14, 0.18, 0.98)
    local bg2         = imgui.ImVec4(0.18, 0.19, 0.23, 1.00)
    local bgPopup     = imgui.ImVec4(0.16, 0.17, 0.22, 0.98)
    local border      = imgui.ImVec4(0.32, 0.32, 0.45, 0.60)
    local white       = imgui.ImVec4(1.00, 1.00, 1.00, 1.00)
    local textMuted   = imgui.ImVec4(0.70, 0.72, 0.85, 1.00)
    local separator   = imgui.ImVec4(0.32, 0.32, 0.45, 0.60)

    colors[imgui.Col.WindowBg]             = bg
    colors[imgui.Col.ChildBg]              = bg2
    colors[imgui.Col.PopupBg]              = bgPopup
    colors[imgui.Col.Border]               = border
    colors[imgui.Col.BorderShadow]         = imgui.ImVec4(0,0,0,0)
    colors[imgui.Col.FrameBg]              = bg2
    colors[imgui.Col.FrameBgHovered]       = accentHover
    colors[imgui.Col.FrameBgActive]        = accentActive
    colors[imgui.Col.TitleBg]              = accent
    colors[imgui.Col.TitleBgActive]        = accentActive
    colors[imgui.Col.TitleBgCollapsed]     = accentActive
    colors[imgui.Col.MenuBarBg]            = bg2
    colors[imgui.Col.ScrollbarBg]          = bg2
    colors[imgui.Col.ScrollbarGrab]        = accent
    colors[imgui.Col.ScrollbarGrabHovered] = accentHover
    colors[imgui.Col.ScrollbarGrabActive]  = accentActive
    colors[imgui.Col.CheckMark]            = accent
    colors[imgui.Col.SliderGrab]           = accent
    colors[imgui.Col.SliderGrabActive]     = accentHover
    colors[imgui.Col.Button]               = accent
    colors[imgui.Col.ButtonHovered]        = accentHover
    colors[imgui.Col.ButtonActive]         = accentActive
    colors[imgui.Col.Header]               = accent
    colors[imgui.Col.HeaderHovered]        = accentHover
    colors[imgui.Col.HeaderActive]         = accentActive
    colors[imgui.Col.Separator]            = separator
    colors[imgui.Col.SeparatorHovered]     = accentHover
    colors[imgui.Col.SeparatorActive]      = accentActive
    colors[imgui.Col.Text]                 = white
    colors[imgui.Col.TextDisabled]         = textMuted
    colors[imgui.Col.TextSelectedBg]       = accent
    colors[imgui.Col.DragDropTarget]       = accent
    colors[imgui.Col.NavHighlight]         = accent
    colors[imgui.Col.Tab]                  = accent
    colors[imgui.Col.TabHovered]           = accentHover
    colors[imgui.Col.TabActive]            = accentActive
    colors[imgui.Col.TabUnfocused]         = bg2
    colors[imgui.Col.TabUnfocusedActive]   = bg2

    style.WindowRounding    = 9
    style.ChildRounding     = 7
    style.FrameRounding     = 7
    style.PopupRounding     = 7
    style.ScrollbarRounding = 7
    style.GrabRounding      = 7
    style.TabRounding       = 7

    style.WindowBorderSize  = 1.5
    style.FrameBorderSize   = 1.0
    style.PopupBorderSize   = 1.0

    style.WindowPadding     = imgui.ImVec2(15, 11)
    style.FramePadding      = imgui.ImVec2(9, 5)
    style.ItemSpacing       = imgui.ImVec2(9, 7)
    style.ItemInnerSpacing  = imgui.ImVec2(7, 5)
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    setDuckTrackerTheme()
end)

local showSettings = imgui.new.bool(false)

local showStatsWindow = imgui.new.bool(false)

local stats3_path = 'DuckTracker/stats'
local stats3_ini = inicfg.load({
    stats = {
        today = os.date("%Y-%m-%d"),
        today_shot = 0,
        today_picked = 0,
        yesterday = "",
        yesterday_shot = 0,
        yesterday_picked = 0,
        before_yesterday = "",
        before_yesterday_shot = 0,
        before_yesterday_picked = 0
    }
}, stats3_path)

local stats3 = {
    today = stats3_ini.stats.today or os.date("%Y-%m-%d"),
    today_shot = tonumber(stats3_ini.stats.today_shot) or 0,
    today_picked = tonumber(stats3_ini.stats.today_picked) or 0,
    yesterday = stats3_ini.stats.yesterday or "",
    yesterday_shot = tonumber(stats3_ini.stats.yesterday_shot) or 0,
    yesterday_picked = tonumber(stats3_ini.stats.yesterday_picked) or 0,
    before_yesterday = stats3_ini.stats.before_yesterday or "",
    before_yesterday_shot = tonumber(stats3_ini.stats.before_yesterday_shot) or 0,
    before_yesterday_picked = tonumber(stats3_ini.stats.before_yesterday_picked) or 0
}

local function saveStats3()
    stats3_ini.stats.today = stats3.today
    stats3_ini.stats.today_shot = stats3.today_shot
    stats3_ini.stats.today_picked = stats3.today_picked
    stats3_ini.stats.yesterday = stats3.yesterday
    stats3_ini.stats.yesterday_shot = stats3.yesterday_shot
    stats3_ini.stats.yesterday_picked = stats3.yesterday_picked
    stats3_ini.stats.before_yesterday = stats3.before_yesterday
    stats3_ini.stats.before_yesterday_shot = stats3.before_yesterday_shot
    stats3_ini.stats.before_yesterday_picked = stats3.before_yesterday_picked
    inicfg.save(stats3_ini, stats3_path)
end

local function loadStats3()
    stats3.today = stats3_ini.stats.today or os.date("%Y-%m-%d")
    stats3.today_shot = tonumber(stats3_ini.stats.today_shot) or 0
    stats3.today_picked = tonumber(stats3_ini.stats.today_picked) or 0
    stats3.yesterday = stats3_ini.stats.yesterday or ""
    stats3.yesterday_shot = tonumber(stats3_ini.stats.yesterday_shot) or 0
    stats3.yesterday_picked = tonumber(stats3_ini.stats.yesterday_picked) or 0
    stats3.before_yesterday = stats3_ini.stats.before_yesterday or ""
    stats3.before_yesterday_shot = tonumber(stats3_ini.stats.before_yesterday_shot) or 0
    stats3.before_yesterday_picked = tonumber(stats3_ini.stats.before_yesterday_picked) or 0
end

local function rotateStats3IfNeeded()
    local today = os.date("%Y-%m-%d")
    if stats3.today ~= today then
        stats3.before_yesterday = stats3.yesterday
        stats3.before_yesterday_shot = stats3.yesterday_shot
        stats3.before_yesterday_picked = stats3.yesterday_picked

        stats3.yesterday = stats3.today
        stats3.yesterday_shot = stats3.today_shot
        stats3.yesterday_picked = stats3.today_picked

        stats3.today = today
        stats3.today_shot = 0
        stats3.today_picked = 0

        saveStats3()
    end
end

loadStats3()
rotateStats3IfNeeded()

lua_thread.create(function()
    while true do
        rotateStats3IfNeeded()
        wait(60000)
    end
end)

imgui.OnFrame(function() return showStatsWindow[0] end, function(self)
    local resX, resY = getScreenResolution()
    local winW, winH = 320, 250
    imgui.SetNextWindowPos(imgui.ImVec2(resX / 2 - winW / 2, resY / 2 - winH / 2), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(winW, winH), imgui.Cond.Always)
    imgui.Begin(u8'Статистика за 3 дня', showStatsWindow, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
    imgui.CenterTextColored(imgui.ImVec4(0.48, 0.41, 0.93, 1), u8"DuckTracker | By Yankay")
    imgui.Separator()
    imgui.CenterText(u8"Сегодня (" .. stats3.today .. "):")
    imgui.CenterText(u8"  Подстрелено: " .. tostring(stats3.today_shot) .. "  |  Подобрано: " .. tostring(stats3.today_picked))
    imgui.Separator()
    imgui.CenterText(u8"Вчера (" .. (stats3.yesterday ~= "" and stats3.yesterday or "-") .. "):")
    imgui.CenterText(u8"  Подстрелено: " .. tostring(stats3.yesterday_shot) .. "  |  Подобрано: " .. tostring(stats3.yesterday_picked))
    imgui.Separator()
    imgui.CenterText(u8"Позавчера (" .. (stats3.before_yesterday ~= "" and stats3.before_yesterday or "-") .. "):")
    imgui.CenterText(u8"  Подстрелено: " .. tostring(stats3.before_yesterday_shot) .. "  |  Подобрано: " .. tostring(stats3.before_yesterday_picked))
    imgui.Separator()
    if imgui.CenterButton(u8"Сбросить статистику за сегодня", imgui.ImVec2(200, 0)) then
        stats3.today_shot = 0
        stats3.today_picked = 0
        saveStats3()
    end
    imgui.End()
end)

local showStats = imgui.new.bool(false)
local sessionStats = {
    ducks_shot = 0,
    ducks_picked = 0
}

imgui.OnFrame(function() return showStats[0] end, function(self)
    self.HideCursor = true
    local resX, resY = getScreenResolution()
    local winW, winH = 220, 120
    imgui.SetNextWindowPos(imgui.ImVec2(resX - winW - 20, resY / 2 - winH / 2), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(winW, winH), imgui.Cond.Always)
    imgui.Begin(u8'Статистика (сессия)', showStats,
        imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoMove +
        imgui.WindowFlags.NoCollapse +
        imgui.WindowFlags.NoDecoration
    )
    imgui.CenterTextColored(imgui.ImVec4(0.48, 0.41, 0.93, 1), u8"DuckTracker | By Yankay")
    imgui.Separator()
    imgui.CenterText(u8"За сессию:")
    imgui.CenterText(u8"Уток подстрелено: " .. tostring(sessionStats.ducks_shot))
    imgui.CenterText(u8"Уток подобрано: " .. tostring(sessionStats.ducks_picked))
    imgui.End()
end)

imgui.OnFrame(function() return MainWindow[0] end, function(player)
    local resX, resY = getScreenResolution()
    local winW, winH = 600, 360
    imgui.SetNextWindowPos(imgui.ImVec2(resX / 2 - winW / 2, resY / 2 - winH / 2), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(winW, winH), imgui.Cond.Always)
    imgui.Begin(u8'DuckTracker | By Yankay | For Radmir RP | v.1.0', MainWindow, imgui.WindowFlags.NoResize)

    local windowWidth = imgui.GetWindowWidth()
    local btnWidth = 120
    local spacing = 20
    local totalWidth = btnWidth * 2 + spacing

    if not showSettings[0] then
        local title = u8"DuckTracker | By Yankay | For Radmir RP | Main Page | v.1.0"
        local titleWidth = imgui.CalcTextSize(title).x
        imgui.SetCursorPosX((windowWidth - titleWidth) / 2)
        imgui.TextColored(imgui.ImVec4(0.48, 0.41, 0.93, 1), title)

        imgui.Separator()

        local infoLines = {
            u8"Этот скрипт для охоты на уток.",
            u8"Автоматически подсвечивает уток на карте и собирает их, если вы рядом.",
            u8"Аим можно включать и выключать по хоткею.",
            u8"Статистика ведётся за три дня и за сессию.",
            u8"",
            u8"Автор: Yankay. Запрещено распространение и продажа без согласия автора.",
            u8"",
            u8"Для получения подробной информации и поддержки — заходите в телеграм.",
            u8"Настройки, статистика и прочее доступны в меню.",
            u8"",
            u8"Аим по умолчанию на клавишу E (можно изменить в настройках).",
        }
        for _, line in ipairs(infoLines) do
            local lineWidth = imgui.CalcTextSize(line).x
            imgui.SetCursorPosX((windowWidth - lineWidth) / 2)
            imgui.Text(line)
        end
        imgui.Dummy(imgui.ImVec2(0, 15))

        imgui.SetCursorPosX((windowWidth - (btnWidth * 2 + 140 + spacing * 2)) / 2)
        if imgui.Button(u8"Открыть Telegram", imgui.ImVec2(btnWidth, 0)) then
            os.execute('start "" "https://t.me/whyyankay"')
        end
        imgui.SameLine()
        if imgui.Button(u8"Настройки", imgui.ImVec2(btnWidth, 0)) then
            showSettings[0] = true
        end
        imgui.SameLine()
        if imgui.Button(u8"Статистика", imgui.ImVec2(140, 0)) then
            showStatsWindow[0] = true
        end
    else
        local title = u8"DuckTracker | By Yankay | For Radmir RP | Setting Page | v.1.0"
        local titleWidth = imgui.CalcTextSize(title).x
        imgui.SetCursorPosX((windowWidth - titleWidth) / 2)
        imgui.TextColored(imgui.ImVec4(0.48, 0.41, 0.93, 1), title)
        imgui.Separator()

        imgui.Text(u8"Выберите клавишу аима:")
        imgui.SameLine()
        if waitingForKey[0] then
            imgui.TextColored(imgui.ImVec4(1,0.7,0.2,1), u8"[Нажмите клавишу]")
            for i = 1, 254 do
                if wasKeyPressed(i) then
                    aimHotkey[0] = i
                    waitingForKey[0] = false
                    saveConfig()
                    break
                end
            end
        else
            local keyName = getKeyName(aimHotkey[0])
            if imgui.Button(u8"["..keyName..u8"]##aimkey", imgui.ImVec2(80, 0)) then
                waitingForKey[0] = true
            end
        end

        imgui.Separator()
        if imgui.Checkbox(u8"Включить WH (подсветка уток)", enableWH) then saveConfig() end
        if imgui.Checkbox(u8"Включить авто-сбор уток", enableAutoPick) then saveConfig() end
        imgui.Separator()
        if imgui.Checkbox(u8"Включить статистику", enableStats) then saveConfig() end
        imgui.Separator()
        if imgui.Checkbox(u8"Включить отладку", enableDebug) then saveConfig() end

        imgui.Dummy(imgui.ImVec2(0, 15))
        -- Кнопки для выхода и статистики снизу окна настроек
        local totalBtnWidth = btnWidth + 140 + spacing
        imgui.SetCursorPosX((windowWidth - totalBtnWidth) / 2)
        if imgui.Button(u8"Назад", imgui.ImVec2(btnWidth, 0)) then
            showSettings[0] = false
        end
        imgui.SameLine()
        if imgui.Button(u8"Статистика", imgui.ImVec2(140, 0)) then
            showStatsWindow[0] = true
        end
    end

    imgui.End()

    if not MainWindow[0] then
        renderWindow[0] = false
        showSettings[0] = false
    end
end)

local show = imgui.new.bool(false)
local popupStart = 0.0
local popupText = u8'Попап сообщение'
local screenX, screenY = getScreenResolution()
local popupWidth, popupHeight = 300, 60

imgui.OnFrame(function() return show[0] end, function(self)
    self.HideCursor = true
    local timeNow = os.clock()
    local elapsed = timeNow - popupStart
    local alpha, posY

    local yOffset = 20
    if elapsed < 0.3 then
        alpha = elapsed / 0.3
        posY = screenY - popupHeight * alpha - yOffset
    elseif elapsed < 3.0 then
        alpha = 1.0
        posY = screenY - popupHeight - yOffset
    elseif elapsed < 3.3 then
        alpha = 1.0 - ((elapsed - 3.0) / 0.3)
        posY = screenY - popupHeight * alpha - yOffset
    else
        show[0] = false
        return
    end

    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 30.0)
    imgui.SetNextWindowPos(imgui.ImVec2((screenX - popupWidth) / 2, posY), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(popupWidth, popupHeight), imgui.Cond.Always)
    imgui.Begin('##popup', show,
        imgui.WindowFlags.NoTitleBar +
        imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoMove +
        imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoFocusOnAppearing +
        imgui.WindowFlags.NoNav +
        imgui.WindowFlags.NoInputs)
    
    imgui.CenterTextColored(imgui.ImVec4(0.48, 0.41, 0.93, alpha), u8"DuckTracker | By Yankay | For Radmir RP")
    imgui.CenterText(popupText)
    imgui.End()
    imgui.PopStyleVar()
end)

function showPopup(text)
    popupText = text or u8'Попап сообщение'
    popupStart = os.clock()
    show[0] = true
end

local GITHUB_RAW_URL = 'https://raw.githubusercontent.com/<USER>/<REPO>/main/DuckTracker_by_Yankay.lua' -- замените на свой путь
local LOCAL_SCRIPT_PATH = thisScript().path

function checkForUpdate()
    local ok, response = pcall(function()
        return requests.get(GITHUB_RAW_URL)
    end)
    if ok and response.status_code == 200 then
        local remote_code = response.text
        local local_file = io.open(LOCAL_SCRIPT_PATH, 'r')
        local local_code = local_file:read('*a')
        local_file:close()
        if remote_code ~= local_code then
            local f = io.open(LOCAL_SCRIPT_PATH, 'w+')
            f:write(remote_code)
            f:close()
            sampAddChatMessage("{7B68EE}[DuckTracker] -|- {FFFFFF}Обнаружено обновление! Скрипт перезапускается...", -1)
            thisScript():reload()
        end
    end
end

function main()
    checkForUpdate()
    while not isSampAvailable() do wait(100) end
    local font = renderCreateFont("Tahoma", 8, 5)
    local animationTimer = 0.0
    imgui.Process = true

    sampAddChatMessage("{7B68EE}[DuckTracker] -|- {FFFFFF}Скрипт успешно загружен", -1)
    sampAddChatMessage("{7B68EE}[DuckTracker] -|- {FFFFFF}Script By {7B68EE}Yankay", -1)
    sampAddChatMessage("{7B68EE}[DuckTracker] -|- {FFFFFF}Для открытия меню используйте: {7B68EE}/dt", -1)

    sampRegisterChatCommand('dt', function()
        MainWindow[0] = not MainWindow[0]
        if MainWindow[0] then
            renderWindow[0] = true
        else
            renderWindow[0] = false
        end
    end)

    aimHotkey[0] = config.main.aimHotkey or vkeys.VK_E
    enableWH[0] = config.main.enableWH
    enableAutoPick[0] = config.main.enableAutoPick
    enableStats[0] = config.main.enableStats
    enableDebug[0] = config.main.enableDebug

    while true do
        wait(0)

        if wasKeyPressed(aimHotkey[0]) then
            aimEnabled = not aimEnabled
            -- sampAddChatMessage("Object Aim: " .. tostring(aimEnabled), -1)
            showPopup(u8"Аим " .. (aimEnabled and u8"включён" or u8"выключен"))
        end

        local px, py, pz = getCharCoordinates(PLAYER_PED)
        local psx, psy = convert3DCoordsToScreen(px, py, pz)

        for _, handle in ipairs(getAllObjects()) do
            if getObjectModel(handle) == targetModel then
                -- print("Handle утки:", handle)
                local success, ox, oy, oz = getObjectCoordinates(handle)
                if success then
                    local currentTime = getGameTimer()
                    local last = duckTracking[handle]
                    local moved = true

                    if last then
                        local d = getDistanceBetweenCoords3d(last.x, last.y, last.z, ox, oy, oz)
                        moved = d > 0.01
                        if moved then
                            duckTracking[handle] = {x = ox, y = oy, z = oz, time = currentTime, dead = false}
                        elseif not last.dead and (currentTime - last.time >= 5000) then
                            -- sampAddChatMessage(string.format("Труп утки был обнаружен: X: %.2f, Y: %.2f, Z: %.2f", ox, oy, oz), 0xFF2222FF)
                            table.insert(deadDuckList, {x = ox, y = oy, z = oz})
                            duckTracking[handle].dead = true
                        end
                    else
                        duckTracking[handle] = {x = ox, y = oy, z = oz, time = currentTime, dead = false}
                    end

                    local dist = getDistanceBetweenCoords3d(ox, oy, oz, px, py, pz)
                    -- sampAddChatMessage(string.format("Утка на координатах: X: %.2f, Y: %.2f, Z: %.2f", ox, oy, oz), -1)

                    if dist <= 2 and enableAutoPick[0] then
                        local key = getObjectKey(ox, oy, oz)
                        if not objectCooldowns[key] or (currentTime - objectCooldowns[key] > 500) then
                            sampSendChat("/take_duck")
                            objectCooldowns[key] = currentTime
                        end
                    end
                end
            end
        end

        if aimEnabled and isKeyDown(2) then
            local screenCenterX, screenCenterY = x2 / 2, y2 / 2
            local closestHandle = nil
            local closestDist = nil

            for _, handle in ipairs(getAllObjects()) do
                if getObjectModel(handle) == targetModel and isObjectOnScreen(handle) then
                    local success, ox, oy, oz = getObjectCoordinates(handle)
                    if success then
                        local sx, sy = convert3DCoordsToScreen(ox, oy, oz)
                        if sx and sy then
                            local screenDist = math.sqrt((sx - screenCenterX)^2 + (sy - screenCenterY)^2)
                            if not closestDist or screenDist < closestDist then
                                closestDist = screenDist
                                closestHandle = handle
                            end
                        end
                    end
                end
            end

            if closestHandle then
                local _, tx, ty, tz = getObjectCoordinates(closestHandle)
                targetAtCoords(tx, ty, tz)
            end
        end

        animationTimer = animationTimer + 0.05
        if animationTimer > math.pi * 2 then animationTimer = 0 end

        for _, handle in ipairs(getAllObjects()) do
            if getObjectModel(handle) == targetModel and isObjectOnScreen(handle) then
                local success, ox, oy, oz = getObjectCoordinates(handle)
                if success then
                    local sx, sy = convert3DCoordsToScreen(ox, oy, oz)
                    local dist = getDistanceBetweenCoords3d(ox, oy, oz, px, py, pz)
                    local distLabel = string.format("%.1f m", dist)

                    if sx and sy and psx and psy and enableWH[0] then
                        renderDrawLine(psx, psy, sx, sy, 1.0, -1)
                        renderFontDrawText(font, distLabel, sx, sy, -1)

                        local radius = 1.25 + math.sin(animationTimer) * 0.25
                        drawCircle3D(ox, oy, oz, radius, 32, 0xFFFF3333)
                    end
                end
            end
        end

        if wasKeyPressed and wasKeyPressed(vkeys.VK_ESCAPE) then
            MainWindow[0] = false
            renderWindow[0] = false
            showSettings[0] = false
        end
    end
end

function drawCircle3D(x, y, z, radius, segments, color)
    local prevX, prevY = nil, nil
    for i = 0, segments do
        local angle = (math.pi * 2) * (i / segments)
        local cx = x + radius * math.cos(angle)
        local cy = y + radius * math.sin(angle)
        local cz = z
        local sx, sy = convert3DCoordsToScreen(cx, cy, cz)
        if sx and sy then
            if prevX and prevY then
                renderDrawLine(prevX, prevY, sx, sy, 1.0, color)
            end
            prevX, prevY = sx, sy
        end
    end
end

function targetAtCoords(x, y, z)
    z = z + 0.2
    local cx, cy, cz = getActiveCameraCoordinates()
    local vect = { fX = cx - x, fY = cy - y, fZ = cz - z }

    local screenAspectRatio = representIntAsFloat(readMemory(0xC3EFA4, 4, false))
    local crosshairOffset = {
        representIntAsFloat(readMemory(0xB6EC10, 4, false)),
        representIntAsFloat(readMemory(0xB6EC14, 4, false))
    }

    local mult = math.tan(getCameraFov() * 0.5 * 0.017453292)
    local fz = math.pi - math.atan2(1.0, mult * ((0.5 - crosshairOffset[1]) * (2 / screenAspectRatio)))
    local fx = math.pi - math.atan2(1.0, mult * 2 * (crosshairOffset[2] - 0.5))

    local camMode = readMemory(0xB6F1A8, 1, false)
    if not (camMode == 53 or camMode == 55) then
        fx = math.pi / 2
        fz = math.pi / 2
    end

    local ax = math.atan2(vect.fY, -vect.fX) - math.pi / 2
    local az = math.atan2(math.sqrt(vect.fX^2 + vect.fY^2), vect.fZ)

    setCameraPositionUnfixed(az - fz, fx - ax)
end

lua_thread.create(function()
    while true do
        if enableStats[0] then
            showStats[0] = true
        else
            showStats[0] = false
        end
        wait(1000)
    end
end)

function sampev.onServerMessage(color, text)
    local cleanText = text:gsub("{.-}", "")
    if cleanText:find("Вы успешно подстрелили утку") then
        rotateStats3IfNeeded()
        stats3.today_shot = stats3.today_shot + 1
        saveStats3()
        sessionStats.ducks_shot = sessionStats.ducks_shot + 1
    end
    if cleanText:find("Вы подобрали Мёртвая утка. Вы можете продать её на Рынке") then
        rotateStats3IfNeeded()
        stats3.today_picked = stats3.today_picked + 1
        saveStats3()
        sessionStats.ducks_picked = sessionStats.ducks_picked + 1
    end
end

lua_thread.create(function()
    while true do
        if enableStats[0] then
            showStats[0] = true
        else
            showStats[0] = false
        end
        wait(1000)
    end
end)