--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local inavdash = require("inavdash")

local widget = {}

widget.sensors = {}
widget.layout = {}
widget.render = {}

local sensors = {}
local units = {}
local internalModule = nil
local externalModule = nil
local currentPage = nil
local lastColourMode = nil

local gps_lock_prev = false

local colorTable = {
    ['darkmode'] = {backdrop = lcd.RGB(0, 0, 0), background = lcd.RGB(40, 40, 40), foreground = lcd.RGB(255, 255, 255), label = lcd.RGB(200, 200, 200), hd = "gfx/hd_white.png"},
    ['lightmode'] = {backdrop = lcd.RGB(255, 255, 255), background = lcd.RGB(208, 208, 208), foreground = lcd.RGB(40, 40, 40), label = lcd.RGB(50, 50, 50), hd = "gfx/hd_black.png"}
}
local colors

local LAYOUTS = {
    [1] = {
        grid = {cols = 32, rows = 16, pad = 2, header = 0},
        table = {
            ah = {col = 1, row = 1, colspan = 16, rowspan = 12},
            flightmode = {col = 17, row = 13, colspan = 8, rowspan = 4},
            map = nil,
            altitude = {col = 25, row = 1, colspan = 4, rowspan = 4},
            groundspeed = {col = 25, row = 5, colspan = 4, rowspan = 4},
            heading = {col = 29, row = 5, colspan = 4, rowspan = 4},
            satellites = {col = 25, row = 9, colspan = 4, rowspan = 4},
            gps = {col = 25, row = 13, colspan = 4, rowspan = 4},
            gps_lock = {col = 29, row = 13, colspan = 4, rowspan = 4},
            voltage = {col = 1, row = 13, colspan = 4, rowspan = 4},
            current = {col = 5, row = 13, colspan = 4, rowspan = 4},
            fuel = {col = 9, row = 13, colspan = 8, rowspan = 4},
            rssi = {col = 29, row = 9, colspan = 4, rowspan = 4},
            home_dir = {col = 17, row = 0, colspan = 8, rowspan = 12},
            vspeed = {col = 29, row = 1, colspan = 4, rowspan = 4}
        }
    },
    [2] = {
        grid = {cols = 32, rows = 16, pad = 2, header = 0},
        table = {
            ah = {col = 9, row = 1, colspan = 16, rowspan = 9},
            flightmode = {col = 1, row = 10, colspan = 12, rowspan = 3},
            map = {col = 21, row = 10, colspan = 12, rowspan = 7},
            altitude = {col = 25, row = 4, colspan = 4, rowspan = 3},
            groundspeed = {col = 5, row = 4, colspan = 4, rowspan = 3},
            distance = {col = 1, row = 7, colspan = 8, rowspan = 3},
            satellites = {col = 5, row = 1, colspan = 4, rowspan = 3},
            gps = {col = 1, row = 13, colspan = 12, rowspan = 4},
            gps_lock = {col = 1, row = 4, colspan = 4, rowspan = 3},
            voltage = {col = 25, row = 1, colspan = 4, rowspan = 3},
            current = {col = 29, row = 1, colspan = 4, rowspan = 3},
            fuel = {col = 25, row = 7, colspan = 8, rowspan = 3},
            rssi = {col = 1, row = 1, colspan = 4, rowspan = 3},
            home_dir_light = {col = 13, row = 10, colspan = 8, rowspan = 7},
            vspeed = {col = 29, row = 4, colspan = 4, rowspan = 3}
        }
    },
    [3] = {
        grid = {cols = 32, rows = 16, pad = 2, header = 0},
        table = {
            ah = {col = 1, row = 1, colspan = 16, rowspan = 12},
            flightmode = nil,
            map = {col = 17, row = 1, colspan = 16, rowspan = 12},
            altitude = {col = 13, row = 13, colspan = 4, rowspan = 4},
            groundspeed = {col = 17, row = 13, colspan = 4, rowspan = 4},
            vspeed = {col = 21, row = 13, colspan = 4, rowspan = 4},
            satellites = nil,
            gps = {col = 25, row = 13, colspan = 8, rowspan = 4},
            gps_lock = nil,
            voltage = {col = 1, row = 13, colspan = 4, rowspan = 4},
            current = {col = 5, row = 13, colspan = 4, rowspan = 4},
            fuel = {col = 9, row = 13, colspan = 4, rowspan = 4},
            rssi = nil,
            home_dir = nil
        }
    }

}

local function computeGridRects(sw, sh, grid, widgets)
    local cols = math.max(1, grid.cols or 1)
    local rows = math.max(1, grid.rows or 1)
    local pad = grid.pad or 0
    local header = grid.header or 0

    local W_raw, H_raw = sw, sh
    local W, H = W_raw, H_raw - header

    local function adjustDimension(dim, cells, padCount) return dim - ((dim - padCount * pad) % cells) end

    W = adjustDimension(W, cols, cols - 1)
    H = adjustDimension(H, rows, rows + 1)

    local xOffset = math.floor((W_raw - W) / 2)

    local contentW = W - ((cols - 1) * pad)
    local contentH = H - ((rows + 1) * pad)
    local cellW = contentW / cols
    local cellH = contentH / rows

    local rects = {}
    for name, box in pairs(widgets or {}) do
        local c = math.max(1, math.min(cols, box.col or 1))
        local r = math.max(1, math.min(rows, box.row or 1))
        local cs = math.max(1, math.min(cols - c + 1, box.colspan or 1))
        local rs = math.max(1, math.min(rows - r + 1, box.rowspan or 1))

        local w = math.floor(cs * cellW + (cs - 1) * pad)
        local h = math.floor(rs * cellH + (rs - 1) * pad)

        local x = math.floor((c - 1) * (cellW + pad)) + xOffset
        local y = math.floor(pad + (r - 1) * (cellH + pad)) + header

        rects[name] = {x = x, y = y, w = w, h = h}
    end
    return rects
end

local function getCurrentPage() return LAYOUTS[currentPage] or LAYOUTS[1] end

local function recomputeLayout()
    local sw, sh = lcd.getWindowSize()
    local page = getCurrentPage()
    widget.layout = computeGridRects(sw, sh, page.grid or {}, page.table or {})
end

function widget.create()

    if not widget.sensors.telemetry then widget.sensors.telemetry = assert(loadfile("sensors/telemetry.lua"))() end

    if not widget.render.telemetry then widget.render.telemetry = assert(loadfile("render/telemetry.lua"))() end
    if not widget.render.ah then widget.render.ah = assert(loadfile("render/ah.lua"))() end
    if not widget.render.gps then widget.render.gps = assert(loadfile("render/gps.lua"))() end
    if not widget.render.gps_lock then widget.render.gps_lock = assert(loadfile("render/gps_lock.lua"))() end
    if not widget.render.map then widget.render.map = assert(loadfile("render/map.lua"))() end
    if not widget.render.flightmode then widget.render.flightmode = assert(loadfile("render/flightmode.lua"))() end
    if not widget.render.hd then widget.render.hd = assert(loadfile("render/homedirection.lua"))() end
    if not widget.render.hd_light then widget.render.hd_light = assert(loadfile("render/homedirection_light.lua"))() end

end

function widget.configure() end

function widget.paint()

    local LCD_WIDTH, LCD_HEIGHT = lcd.getWindowSize()

    lcd.color(colors.backdrop)
    lcd.drawFilledRectangle(0, 0, LCD_WIDTH, LCD_HEIGHT)

    if widget.layout.ah then widget.render.ah.paint() end

    if widget.layout.map then widget.render.map.paint() end

    if widget.render.telemetry then

        if widget.layout.flightmode then
            local opts = {colorbg = colors.background, colorvalue = colors.foreground, colorlabel = colors.label, fontvalue = FONT_L, fontlabel = FONT_XS}

            widget.render.flightmode.paint(widget.layout.flightmode.x, widget.layout.flightmode.y, widget.layout.flightmode.w, widget.layout.flightmode.h, "Flight Mode", sensors['flightmode'] or 0, "", opts)
        end

        if widget.layout.altitude then
            local opts = {colorbg = colors.background, colorvalue = colors.foreground, colorlabel = colors.label, fontvalue = FONT_L, fontlabel = FONT_XS}

            widget.render.telemetry.paint(widget.layout.altitude.x, widget.layout.altitude.y, widget.layout.altitude.w, widget.layout.altitude.h, "Altitude", sensors['altitude'] or 0, units['altitude'], opts)
        end

        if widget.layout.vspeed then
            local opts = {colorbg = colors.background, colorvalue = colors.foreground, colorlabel = colors.label, fontvalue = FONT_L, fontlabel = FONT_XS}

            widget.render.telemetry.paint(widget.layout.vspeed.x, widget.layout.vspeed.y, widget.layout.vspeed.w, widget.layout.vspeed.h, "Vspeed", sensors['vertical_speed'] or 0, units['vertical_speed'], opts)
        end

        if widget.layout.groundspeed then
            local opts = {colorbg = colors.background, colorvalue = colors.foreground, colorlabel = colors.label, fontvalue = FONT_L, fontlabel = FONT_XS}

            widget.render.telemetry.paint(widget.layout.groundspeed.x, widget.layout.groundspeed.y, widget.layout.groundspeed.w, widget.layout.groundspeed.h, "Speed", sensors['groundspeed'] or 0, units['groundspeed'], opts)
        end

        if widget.layout.heading then
            local opts = {colorbg = colors.background, colorvalue = colors.foreground, colorlabel = colors.label, fontvalue = FONT_L, fontlabel = FONT_XS, widthAsciiFallback = true}

            widget.render.telemetry.paint(widget.layout.heading.x, widget.layout.heading.y, widget.layout.heading.w, widget.layout.heading.h, "Heading", math.floor(sensors['heading'] or 0), units['heading'], opts)
        end

        if widget.layout.distance then
            local opts = {colorbg = colors.background, colorvalue = colors.foreground, colorlabel = colors.label, fontvalue = FONT_L, fontlabel = FONT_XS, widthAsciiFallback = true}

            widget.render.telemetry.paint(widget.layout.distance.x, widget.layout.distance.y, widget.layout.distance.w, widget.layout.distance.h, "Distance", math.floor(sensors['gps_distancehome'] or 0), units['gps_distancehome'], opts)
        end

        if widget.layout.voltage then
            local opts = {colorbg = colors.background, colorvalue = colors.foreground, colorlabel = colors.label, fontvalue = FONT_L, fontlabel = FONT_XS}

            widget.render.telemetry.paint(widget.layout.voltage.x, widget.layout.voltage.y, widget.layout.voltage.w, widget.layout.voltage.h, "Voltage", sensors['voltage'] or 0, units['voltage'], opts)
        end

        if widget.layout.fuel then
            local opts = {colorbg = colors.background, colorvalue = colors.foreground, colorlabel = colors.label, fontvalue = FONT_L, fontlabel = FONT_XS}

            widget.render.telemetry.paint(widget.layout.fuel.x, widget.layout.fuel.y, widget.layout.fuel.w, widget.layout.fuel.h, "Fuel", sensors['fuel'] or 0, units['fuel'] or "mAh", opts)
        end

        if widget.layout.current then
            local opts = {colorbg = colors.background, colorvalue = colors.foreground, colorlabel = colors.label, fontvalue = FONT_L, fontlabel = FONT_XS}

            widget.render.telemetry.paint(widget.layout.current.x, widget.layout.current.y, widget.layout.current.w, widget.layout.current.h, "Current", sensors['current'] or 0, units['current'], opts)
        end

        if widget.layout.rssi then
            local opts = {colorbg = colors.background, colorvalue = colors.foreground, colorlabel = colors.label, fontvalue = FONT_L, fontlabel = FONT_XS}

            widget.render.telemetry.paint(widget.layout.rssi.x, widget.layout.rssi.y, widget.layout.rssi.w, widget.layout.rssi.h, "RSSI", sensors['rssi'] or 0, units['rssi'], opts)
        end

        if widget.layout.satellites then
            local opts = {colorbg = colors.background, colorvalue = colors.foreground, colorlabel = colors.label, fontvalue = FONT_L, fontlabel = FONT_XS}
            widget.render.telemetry.paint(widget.layout.satellites.x, widget.layout.satellites.y, widget.layout.satellites.w, widget.layout.satellites.h, "Satellites", sensors['satellites'] or 0, "", opts)
        end

        if widget.layout.home_dir then widget.render.hd.paint() end

        if widget.layout.home_dir_light then widget.render.hd_light.paint() end

    end

    if widget.layout.gps then
        local opts = {colorbg = colors.background, colorvalue = colors.foreground, colorlabel = colors.label, fontvalue = FONT_S, fontlabel = FONT_XS, minWidthForDMS = 300, decimalPlaces = 4, widthAsciiFallback = true}
        widget.render.gps.paint(widget.layout.gps.x, widget.layout.gps.y, widget.layout.gps.w, widget.layout.gps.h, "GPS", sensors['gps_latitude'], sensors['gps_longitude'], opts)
    end

    if widget.layout.gps_lock then
        local opts = {images = {red = "gfx/red.png", orange = "gfx/orange.png", green = "gfx/green.png"}, colorbg = colors.background}
        widget.render.gps_lock.paint(widget.layout.gps_lock.x, widget.layout.gps_lock.y, widget.layout.gps_lock.w, widget.layout.gps_lock.h, sensors['gps_lock'], sensors['satellites'], opts)
    end

end

function widget.wakeup()
    local colorMode

    if lcd.darkMode() then
        colors = colorTable['darkmode']
        colorMode = 'darkmode'
    else
        colors = colorTable['lightmode']
        colorMode = 'lightmode'
    end

    if colorMode ~= lastColourMode then
        if widget.render and widget.render.hd and widget.render.hd.resetArrowCache then

            widget.render.hd.resetArrowCache(colors.hd)
            widget.render.hd_light.resetArrowCache(colors.hd_light)
        end
        lastColourMode = colorMode
    end

    recomputeLayout()

    if widget.sensors and widget.sensors.telemetry then
        widget.sensors.telemetry.wakeup()

        sensors['voltage'], units['voltage'] = widget.sensors.telemetry.getSensor('voltage')
        sensors['current'], units['current'] = widget.sensors.telemetry.getSensor('current')
        sensors['altitude'], units['altitude'] = widget.sensors.telemetry.getSensor('altitude')
        sensors['fuel'], units['fuel'] = widget.sensors.telemetry.getSensor('fuel')
        sensors['rssi'], units['rssi'] = widget.sensors.telemetry.getSensor('rssi')
        sensors['roll'], units['roll'] = widget.sensors.telemetry.getSensor('roll')
        sensors['pitch'], units['pitch'] = widget.sensors.telemetry.getSensor('pitch')
        sensors['heading'], units['heading'] = widget.sensors.telemetry.getSensor('heading')
        sensors['groundspeed'], units['groundspeed'] = widget.sensors.telemetry.getSensor('groundspeed')
        sensors['satellites'], units['satellites'] = widget.sensors.telemetry.getSensor('satellites')
        sensors['gps_latitude'], units['gps_latitude'] = widget.sensors.telemetry.getSensor('gps_latitude')
        sensors['gps_longitude'], units['gps_longitude'] = widget.sensors.telemetry.getSensor('gps_longitude')
        sensors['flightmode'], units['flightmode'] = widget.sensors.telemetry.getSensor('flightmode')
        sensors['vertical_speed'], units['vertical_speed'] = widget.sensors.telemetry.getSensor('vertical_speed')

        if sensors['gps_lock'] == false then
            sensors['groundspeed'] = 0
            sensors['heading'] = 0
            sensors['altitude'] = 0
        end

        do

            local prev = gps_lock_prev
            local fm = sensors['flightmode']

            local new_lock
            if fm == nil then
                new_lock = false
            elseif fm == 2 or fm == 100 or fm == 101 then
                new_lock = false
            else
                new_lock = true
            end

            if prev == false and new_lock == true then end
            gps_lock_prev = new_lock

            sensors['gps_lock'] = new_lock

            local lat = sensors['gps_latitude']
            local lon = sensors['gps_longitude']
            if new_lock then
                if (not sensors['home_latitude'] or sensors['home_latitude'] == 0 or fm == 103) and lat and lon then
                    sensors['home_latitude'] = lat
                    sensors['home_longitude'] = lon
                end
            else
                sensors['home_latitude'] = 0
                sensors['home_longitude'] = 0
            end

        end

        do
            local lat, lon = sensors['gps_latitude'], sensors['gps_longitude']
            local hlat, hlon = sensors['home_latitude'], sensors['home_longitude']
            if sensors['gps_lock'] and lat and lon and hlat and hlon and hlat ~= 0 and hlon ~= 0 then
                local dx, dy = widget.render.map.enu_dxdy(lat, lon, hlat, hlon)
                sensors['gps_distancehome'] = widget.render.map.hypot(dx, dy)
                units['gps_distancehome'] = "m"
            else
                sensors['gps_distancehome'] = 0
                units['gps_distancehome'] = "m"
            end
        end

    end

    if widget.render.ah then
        local ahconfig = {ppd = 2.0, show_altitude = true, show_groundspeed = true}
        if widget.render.ah then widget.render.ah.wakeup(sensors, units, widget.layout.ah.x, widget.layout.ah.y, widget.layout.ah.w, widget.layout.ah.h, ahconfig) end
    end

    if widget.render.map then
        local opts = {
            north_up = true,
            show_grid = true,
            show_distance = true,
            home_icon = "gfx/home.png",
            own_icon = "gfx/arrow.png",
            show_speed_vec = false,
            show_zoom = true,
            angle_step = 5,
            colors = {bg = lcd.RGB(0, 60, 0), grid = lcd.RGB(0, 90, 0), trail = lcd.RGB(170, 220, 170), own = lcd.RGB(255, 255, 255), home = lcd.RGB(255, 255, 255), text = lcd.RGB(255, 255, 255)},

            home = sensors['gps_lock'] and {lat = sensors['home_latitude'], lon = sensors['home_longitude']} or nil,

            light_on_gps_ms = 2000
        }

        local s = {latitude = sensors['gps_latitude'], longitude = sensors['gps_longitude'], heading = sensors['heading'], groundspeed = sensors['groundspeed'], home_lat = sensors['home_latitude'], home_lon = sensors['home_longitude']}

        local box = widget.layout.map
        if box then widget.render.map.wakeup(box.x, box.y, box.w, box.h, s, units, opts) end
    end

    if widget.layout.home_dir then
        local box = widget.layout.home_dir
        local s = {latitude = sensors['gps_latitude'], longitude = sensors['gps_longitude'], heading = sensors['heading'], home_lat = sensors['home_latitude'], home_lon = sensors['home_longitude']}
        local opts = {colors = {bg = colors.background, frame = colors.foreground, text = colors.foreground}, show_ring = true, show_text = true, image = colors.hd, angle_step = 5, flip_180 = false}
        if box then widget.render.hd.wakeup(box.x, box.y, box.w, box.h, s, units, opts) end
    end

    if widget.layout.home_dir_light then
        local box = widget.layout.home_dir_light
        local s = {latitude = sensors['gps_latitude'], longitude = sensors['gps_longitude'], heading = sensors['heading'], home_lat = sensors['home_latitude'], home_lon = sensors['home_longitude']}
        local opts = {colors = {bg = colors.background, frame = colors.foreground, text = colors.foreground}, show_ring = true, show_text = false, image = colors.hd, angle_step = 5, flip_180 = false}
        if box then widget.render.hd_light.wakeup(box.x, box.y, box.w, box.h, s, units, opts) end
    end

    do
        local fm = sensors['flightmode']
        local prev = widget._prev_flightmode

        if (fm == 0 or fm == 1) and (prev ~= 0 or prev ~= 1) then
            sensors['home_latitude'] = 0
            sensors['home_longitude'] = 0
            sensors['gps_distancehome'] = 0
        end

        if fm and (prev == nil or fm ~= prev) then
            local file = string.format("audio/en/default/fm-%d.wav", fm)
            system.playFile(file)
            widget._prev_flightmode = fm
        end
    end

    if lcd.isVisible() then lcd.invalidate() end

end

function widget.read()
    local storedPage = storage.read("currentPage")
    if storedPage then
        currentPage = tonumber(storedPage)
    else
        currentPage = 1
    end
end

function widget.write() storage.write("currentPage", tostring(currentPage or 1)) end

function widget.event(widget, category, value, x, y)
    if not lcd.hasFocus() then return false end

    local num_pages = #LAYOUTS
    if num_pages == 0 then return false end

    currentPage = currentPage or 1
    local prevPage = currentPage

    if value == 32 then
        currentPage = currentPage + 1
        if currentPage > num_pages then currentPage = 1 end
    end

    if currentPage ~= prevPage then
        recomputeLayout()
        return true
    end

    return false
end

function widget.menu() return {} end

return widget
