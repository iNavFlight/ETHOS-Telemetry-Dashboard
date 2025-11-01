--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local inavdash = require("inavdash")
local render = {}
local radio = assert(loadfile("radios.lua"))()

local MODE_TEXT = {[0] = "DISARMED", [1] = "READY TO ARM", [2] = "ARMING PREVENTED", [10] = "ACRO", [11] = "ANGLE", [12] = "HORIZON", [13] = "MANUAL", [20] = "ALTITUDE HOLD", [21] = "POSITION HOLD", [22] = "WAYPOINT", [23] = "RTH", [26] = "COURSE HOLD", [27] = "CRUISE", [99] = "FAILSAFE", [100] = "WAIT", [101] = "ERROR!", [102] = "ACRO (AIR)", [103] = "HOME RESET", [104] = "LANDING", [105] = "ANGLE HOLD", [255] = "NO DATA"}

local function ascii_skeleton(s) return (s or ""):gsub("[\128-\255]", "x") end

local function chooseFontForPair(valueStr, unitStr, gap, maxW, maxH, fonts, useAscii)
    local function measureWith(font)
        lcd.font(font)
        local vMeasure = useAscii and valueStr:gsub("[\128-\255]", "x") or valueStr
        local uMeasure = useAscii and unitStr:gsub("[\128-\255]", "x") or unitStr
        local vw, vh = lcd.getTextSize(vMeasure)
        local uw, uh = 0, 0
        if unitStr ~= "" then uw, uh = lcd.getTextSize(uMeasure) end
        local cw = vw + (unitStr ~= "" and (gap + uw) or 0)
        local ch = math.max(vh, uh)
        return cw, ch, vw, vh, uw, uh
    end

    local best = {font = fonts[1], cw = 0, ch = 0, vw = 0, vh = 0, uw = 0, uh = 0}
    for _, f in ipairs(fonts) do
        local cw, ch, vw, vh, uw, uh = measureWith(f)
        if cw <= maxW and ch <= maxH then
            best = {font = f, cw = cw, ch = ch, vw = vw, vh = vh, uw = uw, uh = uh}
        else
            break
        end
    end
    lcd.font(best.font)
    return best
end

function render.paint(x, y, w, h, label, value, unit, opts)

    if value == nil then value = "-" end
    opts = opts or {}
    if not opts.colorbg then opts.colorbg = lcd.RGB(0, 0, 0) end
    if not opts.colorvalue then opts.colorvalue = lcd.RGB(255, 255, 255) end
    if not opts.colorlabel then opts.colorlabel = (lcd.darkMode() and lcd.RGB(154, 154, 154)) or lcd.RGB(77, 73, 77) end
    if opts.widthAsciiFallback == nil then opts.widthAsciiFallback = false end

    lcd.color(opts.colorbg)
    lcd.drawFilledRectangle(x, y, w, h)

    local TEXT_COLOR = (lcd.darkMode() and lcd.RGB(255, 255, 255)) or lcd.RGB(77, 73, 77)

    local offsetY = 0

    if label and label ~= "" then
        local fontsTitle = radio.fontTitle or {FONT_XXS, FONT_XS}
        local maxWTitle, maxHTitle = w * 0.9, h
        local chosenTitle = chooseFontForPair(label, "", 0, maxWTitle, maxHTitle, fontsTitle, false)
        local lw, lh = chosenTitle.vw, chosenTitle.vh

        local lx = x + (w - lw) / 2
        local ly = y + (lh / 4)

        lcd.color(opts.colorlabel)
        lcd.drawText(lx, ly, label)

        offsetY = lh - 3
    end

    local valueStr = MODE_TEXT[value] or tostring(value)
    local unitStr = unit and tostring(unit) or ""
    local gap = radio.unitGap or 4
    local fontsValue = radio.fontValue or {FONT_XXS, FONT_XS, FONT_S, FONT_M, FONT_L}

    local maxVW, maxVH = w * 0.9, h - offsetY
    local chosen = chooseFontForPair(valueStr, unitStr, gap, maxVW, maxVH, fontsValue, opts.widthAsciiFallback)

    local startX = x + (w - chosen.cw) / 2
    local topY = y + offsetY + ((h - offsetY) - chosen.ch) / 2

    lcd.color(TEXT_COLOR)

    lcd.drawText(startX, topY, valueStr)

    if unitStr ~= "" then
        local unitX = startX + chosen.vw + gap
        lcd.drawText(unitX, topY, unitStr)
    end
end

return render
