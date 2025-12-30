--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local inavdash = {}

package.loaded.inavdash = inavdash

local _ENV = setmetatable({inavdash = inavdash}, {__index = _G, __newindex = function(_, k) print("attempt to create global '" .. tostring(k) .. "'", 2) end})

local config = {}
config.name = "INAV Dashboard"
config.version = {major = 0, minor = 0, revision = 0, suffix = "DEV"}
config.ethosVersion = {1, 6, 2}
config.baseDir = "inav-dashboard"
config.key = "inavdsh"

inavdash.config = config

inavdash.widget = assert(loadfile("widget.lua"))()

local function init()

    system.registerWidget({
        key = inavdash.config.key,
        name = inavdash.config.name,
        create = inavdash.widget.create,
        configure = inavdash.widget.configure,
        paint = inavdash.widget.paint,
        wakeup = inavdash.widget.wakeup,
        read = inavdash.widget.read,
        write = inavdash.widget.write,
        event = inavdash.widget.event,
        menu = inavdash.widget.menu,
        persistent = false
    })

end

return {init = init}
