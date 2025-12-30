--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local inavdash = require("inavdash")
local render = {}

local _bmpCache = {}

local function getBitmap(path)
    if not path then return nil end
    if not _bmpCache[path] then _bmpCache[path] = lcd.loadBitmap(path, true) end
    return _bmpCache[path]
end

local function normalizeColor(c)
    if type(c) == "number" then return c end
    if type(c) == "table" then
        local r = c.r or c.R or c[1] or 0
        local g = c.g or c.G or c[2] or 0
        local b = c.b or c.B or c[3] or 0
        if lcd.RGB then return lcd.RGB(r, g, b) end
        return (r << 16) | (g << 8) | b
    end
    return nil
end

local function fillBg(x, y, w, h, color)
    if not color then return end
    if lcd.color then pcall(lcd.color, color) end
    if lcd.drawFilledRectangle then
        if not pcall(lcd.drawFilledRectangle, x, y, w, h, color) then pcall(lcd.drawFilledRectangle, x, y, w, h) end
        return
    end
    if lcd.fillRect then if not pcall(lcd.fillRect, x, y, w, h, color) then pcall(lcd.fillRect, x, y, w, h) end end
end

function render.paint(x, y, w, h, value, satellites, opts)
    if not lcd.isVisible() then return end
    opts = opts or {}

    local bg = normalizeColor(opts.colorbg)
    if bg then fillBg(x, y, w, h, bg) end

    local images = opts.images or {red = "red.png", green = "green.png", orange = "orange.png"}

    local key
    if not value then
        key = "red"
    elseif type(value) == "boolean" then
        if satellites and satellites <= 5 then
            key = "orange"
        else
            key = value and "green" or "red"
        end
    elseif tonumber(value) then
        key = (tonumber(value) ~= 0) and "green" or "red"
    end

    local bmp = getBitmap(images[key])
    if not bmp then return end

    if not pcall(lcd.drawBitmap, x, y, bmp, w, h) then lcd.drawBitmap(x, y, bmp) end
end

return render
