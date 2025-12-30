--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local inavdash = require("inavdash")

local DEFAULT_GRID_STEP = 32

local RenderMap = {_frame = nil, _light_until = nil}

RenderMap._icons = RenderMap._icons or {home_path = nil, home = nil, own_path = nil, own = nil}
RenderMap._rot_cache = RenderMap._rot_cache or {angle = nil, bmp = nil}

local function _resolve_bitmap(bmp_or_path)
    if not bmp_or_path then return nil end
    if type(bmp_or_path) == "string" then
        local ok, handle = pcall(lcd.loadBitmap, bmp_or_path)
        return ok and handle or nil
    end
    return bmp_or_path
end

local function _bmp_size(bmp)
    if not bmp then return 0, 0 end
    local w = (bmp.width and bmp:width()) or 0
    local h = (bmp.height and bmp:height()) or 0
    return tonumber(w) or 0, tonumber(h) or 0
end

local function _set_icon(which, src)
    local path = type(src) == "string" and src or nil
    local cache = RenderMap._icons

    if path and cache[which .. "_path"] ~= path then
        cache[which .. "_path"] = path
        cache[which] = _resolve_bitmap(path)
    elseif type(src) ~= "string" then
        cache[which .. "_path"] = nil
        cache[which] = src
    end
end

local function _dispose_rotated()
    local rc = RenderMap._rot_cache
    if rc.bmp and rc.bmp.delete then pcall(function() rc.bmp:delete() end) end
    rc.bmp = nil
    rc.angle = nil
end

local function meters_per_deg(lat_deg)
    local lat = math.rad(lat_deg or 0)
    return 111320.0, 111320.0 * math.cos(lat)
end

local function enu_from_latlon(lat, lon, lat0, lon0)
    local mlat, mlon = meters_per_deg(lat0 or 0)
    return (lon - (lon0 or 0)) * mlon, (lat - (lat0 or 0)) * mlat
end

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x ~= nil then return math.atan(y, x) end
    return math.atan(y)
end

local function rotate(px, py, s, c) return px * c - py * s, px * s + py * c end

local function clamp(v, a, b)
    if v < a then
        return a
    elseif v > b then
        return b
    else
        return v
    end
end
local function finite(v)
    v = tonumber(v) or 0
    return v == v and v ~= 1 / 0 and v ~= -1 / 0
end
local function i(v) return math.floor((tonumber(v) or 0) + 0.5) end

function RenderMap.wakeup(x, y, w, h, sensors, units, opts)
    opts = opts or {}
    local lat = (sensors.latitude or 0)
    local lon = (sensors.longitude or 0)
    local hlat = (sensors.home_lat or 0)
    local hlon = (sensors.home_lon or 0)

    local heading = (sensors.heading or 0) % 360
    local course = (sensors.course or heading) % 360
    local gs = sensors.groundspeed or 0

    local xE, yN = enu_from_latlon(lat, lon, hlat, hlon)
    local homeE, homeN = -xE, -yN

    local margin = opts.keep_home_margin or 18
    local maxR = math.max(math.abs(homeE), math.abs(homeN), 1)
    local span_m = 2.4 * maxR
    local ppm_min = opts.min_ppm or 0.2
    local ppm_max = opts.max_ppm or 3.0
    local ppm_auto = math.min((w - 2 * margin) / span_m, (h - 2 * margin) / span_m)
    local ppm = opts.ppm or clamp(ppm_auto, ppm_min, ppm_max)
    if not finite(ppm) or ppm <= 0 then ppm = 1 end

    local map_up_deg = (opts.north_up and 0 or heading)
    local r = math.rad(map_up_deg)
    local s, c = math.sin(r), math.cos(r)

    local hx, hy = rotate(homeE, homeN, s, c)
    hx, hy = w / 2 + hx * ppm, h / 2 - hy * ppm

    local own_len, own_w = 10, 6
    local p1x, p1y = 0, -own_len
    local p2x, p2y = own_w / 2, own_len * 0.6
    local p3x, p3y = -own_w / 2, own_len * 0.6

    local r2 = math.rad(course or 0)
    local s2, c2 = math.sin(r2), math.cos(r2)
    p1x, p1y = rotate(p1x, p1y, s2, c2)
    p2x, p2y = rotate(p2x, p2y, s2, c2)
    p3x, p3y = rotate(p3x, p3y, s2, c2)

    local cx, cy = x + w / 2, y + h / 2
    local own_tri = {cx + p1x, cy + p1y, cx + p2x, cy + p2y, cx + p3x, cy + p3y}

    local dist_m = math.sqrt(homeE * homeE + homeN * homeN)
    local brg = (math.deg(atan2(homeE, homeN)) + 360) % 360

    local vx, vy = nil, nil
    if gs and gs > 0 then
        local cr = math.rad(course)
        local sc, cc = math.sin(cr), math.cos(cr)
        vx, vy = sc * gs, -cc * gs
        vx, vy = cx + vx * ppm * 0.8, cy + vy * ppm * 0.8
    end

    local colors = opts.colors or {}
    local col_bg = colors.bg or lcd.RGB(0, 60, 0)
    local col_grid = colors.grid or lcd.RGB(0, 90, 0)
    local col_own = colors.own or lcd.RGB(255, 255, 255)
    local col_home = colors.home or lcd.RGB(255, 255, 255)
    local col_text = colors.text or lcd.RGB(255, 255, 255)

    if not RenderMap._light_until and (lat ~= 0 or lon ~= 0) and (lcd.getTime and opts.light_on_gps_ms) then RenderMap._light_until = lcd.getTime() + (opts.light_on_gps_ms or 2000) end

    _set_icon("home", opts.home_icon)
    _set_icon("own", opts.own_icon)

    RenderMap._frame = {
        box = {x = x, y = y, w = w, h = h},
        ppm = ppm,
        mapRot = map_up_deg,
        colors = {bg = col_bg, grid = col_grid, own = col_own, home = col_home, text = col_text},
        own_tri = own_tri,
        home_xy = {x = x + hx, y = y + hy},
        spd_vec = (vx and vy) and {cx, cy, vx, vy} or nil,
        readout = {gs = gs, dist = dist_m, brg = brg, speed_unit = (units and units.groundspeed) or "kt", dist_unit = (units and units.distance) or "m", course = course},
        show_distance = (opts.show_distance ~= false),
        show_zoom = (opts.show_zoom == true),
        show_grid = (opts.show_grid ~= false),
        grid_step = (opts.grid_step or DEFAULT_GRID_STEP),
        north_up = (opts.north_up == true),
        opts = {angle_step = opts.angle_step or 5}
    }
end

function RenderMap.paint()
    local F = RenderMap._frame
    if not F then return end
    local x, y, w, h = F.box.x, F.box.y, F.box.w, F.box.h
    lcd.setClipping(i(x), i(y), i(w), i(h))

    lcd.color(F.colors.bg);
    lcd.drawFilledRectangle(i(x), i(y), i(w), i(h))

    if F.show_grid then
        lcd.color(F.colors.grid)
        local step = F.grid_step or DEFAULT_GRID_STEP
        for gx = x, x + w, step do lcd.drawLine(i(gx), i(y), i(gx), i(y + h)) end
        for gy = y, y + h, step do lcd.drawLine(i(x), i(gy), i(x + w), i(gy)) end
    end

    local hx, hy = F.home_xy.x, F.home_xy.y
    local hbmp = RenderMap._icons.home
    if hbmp then
        lcd.drawBitmap(i(hx - 8), i(hy - 8), hbmp)
    else
        lcd.color(F.colors.home)
        local s = 6
        lcd.drawFilledTriangle(i(hx - s), i(hy - s), i(hx), i(hy - 2 * s), i(hx + s), i(hy - s))
        lcd.drawFilledRectangle(i(hx - 0.7 * s), i(hy - s), i(1.4 * s), i(1.7 * s))
    end

    local obmp = RenderMap._icons.own
    if obmp and obmp.rotate then
        local cx, cy = x + w / 2, y + h / 2
        local step = (F.opts and F.opts.angle_step) or 10
        local ang = ((F.readout and F.readout.course) or 0) % 360
        local bucket = step > 0 and (math.floor((ang + step / 2) / step) * step) or ang
        local rc = RenderMap._rot_cache
        if rc.angle ~= bucket or not rc.bmp then
            _dispose_rotated()
            rc.bmp = obmp:rotate(bucket)
            rc.angle = bucket
        end
        local rw, rh = _bmp_size(rc.bmp)
        lcd.drawBitmap(i(cx - rw / 2), i(cy - rh / 2), rc.bmp)
    else
        lcd.color(F.colors.own)
        local t = F.own_tri
        lcd.drawFilledTriangle(i(t[1]), i(t[2]), i(t[3]), i(t[4]), i(t[5]), i(t[6]))
    end

    if F.spd_vec then lcd.drawLine(i(F.spd_vec[1]), i(F.spd_vec[2]), i(F.spd_vec[3]), i(F.spd_vec[4])) end

    if F.show_distance then
        lcd.color(F.colors.text);
        lcd.font(FONT_XS)
        local gs = tonumber(F.readout.gs) or 0
        local dist_ft = (tonumber(F.readout.dist) or 0) * 3.28084
        local brg = tonumber(F.readout.brg) or 0
        local spd_unit = F.readout.speed_unit or "kt"
        local dist_unit = F.readout.dist_unit or "m"
        local dist_value = F.readout.dist or 0

        if dist_unit == "ft" then
            dist_value = dist_value * 3.28084
        elseif dist_unit == "km" then
            dist_value = dist_value / 1000
        end

        lcd.drawText(i(x + 4), i(y + 4), string.format("%.1f %s", gs, spd_unit))
        lcd.drawText(i(x + 4), i(y + h - 12), string.format("%d%s  %03d°", math.floor(dist_value + 0.5), dist_unit, (math.floor(brg + 0.5)) % 360))
    end

    if F.show_zoom and w >= 200 then
        lcd.color(F.colors.text);
        lcd.font(FONT_XS)
        local ppm = F.ppm or 1
        local step_px = F.grid_step or DEFAULT_GRID_STEP
        local meters_per_grid = step_px / ppm
        local ratio = math.floor(meters_per_grid + 0.5)
        local zoom_txt = string.format("Zoom: 1:%d", ratio)
        local text_w, text_h = lcd.getTextSize(zoom_txt)
        lcd.drawText(i(x + w - text_w - 4), i(y + h - text_h - 2), zoom_txt)
    end

    lcd.drawText(i(x + 2), i(y + h / 2 - 6), "W")
    lcd.drawText(i(x + w - 10), i(y + h / 2 - 6), "E")

    local W, H = lcd.getWindowSize();
    lcd.setClipping(0, 0, W, H)
end

RenderMap.enu_dxdy = function(lat, lon, lat0, lon0)
    local dx, dy = enu_from_latlon(lat, lon, lat0, lon0)
    return dx, dy
end

RenderMap.hypot = function(x, y) return math.sqrt((x or 0) ^ 2 + (y or 0) ^ 2) end

return RenderMap
