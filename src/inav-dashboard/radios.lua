--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local inavdash = require("inavdash")

local environment = system.getVersion()
local LCD_W = environment['lcdWidth']
local LCD_H = environment['lcdHeight']

local resolution = LCD_W .. "x" .. LCD_H

local supportedRadios = {

    ["800x480"] = {fontTitle = {FONT_XXS, FONT_XS}, fontValue = {FONT_XXS, FONT_XS, FONT_S, FONT_M, FONT_L}, gpsFontValue = {FONT_XXS, FONT_XS, FONT_S}, gpsLineGap = 4, unitGap = 0},

    ["480x320"] = {fontTitle = {FONT_XXS}, fontValue = {FONT_XXS, FONT_XS, FONT_S, FONT_M}, gpsFontValue = {FONT_XXS, FONT_XS, FONT_S}, gpsLineGap = -2, unitGap = 0},

    ["640x360"] = {fontTitle = {FONT_XXS, FONT_XS}, fontValue = {FONT_XXS, FONT_XS, FONT_S, FONT_M}, gpsFontValue = {FONT_XXS, FONT_XS, FONT_S}, gpsLineGap = 3, unitGap = 0}
}

local chosenKey = resolution
if not supportedRadios[chosenKey] then
    print(string.format("[ui] %s not supported; falling back to X18 (480x320)", resolution))
    chosenKey = "480x320"
end
local radio = supportedRadios[chosenKey]

for resKey in pairs(supportedRadios) do if resKey ~= chosenKey then supportedRadios[resKey] = nil end end

return radio
