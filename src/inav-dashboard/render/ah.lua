--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local inavdash = require("inavdash")

local RenderAH = {_frame = nil}

local function sval(sensors, key, default)
    local v = sensors and sensors[key]
    if type(v) == "table" then v = v.value or v.val or v.v or v[1] end
    v = tonumber(v);
    if v == nil then return default end
    return v
end

local function rotate(px, py, cx, cy, s, c)
    px, py = px - cx, py - cy
    local xnew = px * c - py * s
    local ynew = px * s + py * c
    return xnew + cx, ynew + cy
end

local function q(x, step) return step > 0 and (math.floor(x / step + 0.5) * step) or x end
local function clamp(v, a, b)
    if v < a then
        return a
    elseif v > b then
        return b
    else
        return v
    end
end
local function col(opts, k, fallback)
    local colors = opts.colors or {};
    return colors[k] or fallback
end

local function build_frame(sensors, units, x, y, w, h, opts)
    opts = opts or {}
    local ppd = tonumber(opts.ppd) or 2.0

    local show_arc = (opts.show_arc ~= false)
    local show_ladder = (opts.show_ladder ~= false)
    local show_compass = (opts.show_compass ~= false)
    local show_altitude = (opts.show_altitude == true)
    local show_groundspeed = (opts.show_groundspeed == true)

    local pitch = q(sval(sensors, "pitch", 0), 0.5)
    local roll = q(sval(sensors, "roll", 0), 0.5)
    local heading = q(sval(sensors, "heading", 0), 1.0) % 360
    local altitude = math.floor(sval(sensors, "altitude", 0) + 0.5)
    local groundspeed = math.floor(sval(sensors, "groundspeed", 0) + 0.5)

    local cx, cy = x + w / 2, y + h / 2

    local colors = {
        sky = col(opts, "sky", lcd.RGB(70, 130, 180)),
        ground = col(opts, "ground", lcd.RGB(160, 82, 45)),
        arc = col(opts, "arc", lcd.RGB(255, 255, 255)),
        ladder = col(opts, "ladder", lcd.RGB(255, 255, 255)),
        compass = col(opts, "compass", lcd.RGB(255, 255, 255)),
        crosshair = col(opts, "crosshair", lcd.RGB(255, 255, 255)),
        altitude = col(opts, "altitude", lcd.RGB(255, 255, 255)),
        groundspeed = col(opts, "groundspeed", lcd.RGB(255, 255, 255))
    }

    local r = math.rad(roll)
    local s, c = math.sin(r), math.cos(r)

    local horizonY = cy + pitch * ppd
    local xL, yL = cx - 3 * w, horizonY
    local xR, yR = cx + 3 * w, horizonY
    local rxL, ryL = rotate(xL, yL, cx, horizonY, s, c)
    local rxR, ryR = rotate(xR, yR, cx, horizonY, s, c)

    local nx, ny = -s, c
    local overlayColor = (pitch >= 0) and colors.ground or colors.sky
    local baseFillColor = (pitch >= 0) and colors.sky or colors.ground
    local BIG = 4 * math.max(w, h)
    local sx = (pitch >= 0) and (nx * BIG) or (-nx * BIG)
    local sy = (pitch >= 0) and (ny * BIG) or (-ny * BIG)

    local ground_sky = {base = {x = x, y = y, w = w, h = h}, baseFillColor = baseFillColor, overlayColor = overlayColor, t1 = {rxL + sx, ryL + sy, rxR + sx, ryR + sy, rxR, ryR}, t2 = {rxL + sx, ryL + sy, rxR, ryR, rxL, ryL}}

    local crosshair = {lines = {{cx - 5, cy, cx + 5, cy}, {cx, cy - 5, cx, cy + 5}}, circle = {cx, cy, 3}}

    local arc = nil
    if show_arc then
        local arcR = w * 0.4
        local ticks = {}
        for _, ang in ipairs({-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60}) do
            local rad = math.rad(ang)
            local x1 = cx + arcR * math.sin(rad)
            local y1 = y + 10 + arcR * (1 - math.cos(rad))
            local x2 = cx + (arcR - 6) * math.sin(rad)
            local y2 = y + 10 + (arcR - 6) * (1 - math.cos(rad))
            ticks[#ticks + 1] = {x1, y1, x2, y2}
        end
        arc = {ticks = ticks, tri = {cx, y + 5, cx - 6, y + 15, cx + 6, y + 15}}
    end

    local ladder = nil
    if show_ladder then
        local segs, labels = {}, {}
        for ang = -90, 90, 10 do
            local off = (pitch - ang) * ppd
            local py = cy + off
            if py > y - 40 and py < y + h + 40 then
                local major = (ang % 20 == 0)
                local len = major and 25 or 15
                local x1, y1 = rotate(cx - len, py, cx, cy, s, c)
                local x2, y2 = rotate(cx + len, py, cx, cy, s, c)
                segs[#segs + 1] = {x1, y1, x2, y2}
                if major then
                    local lx, ly = rotate(cx - len - 10, py - 4, cx, cy, s, c)
                    local rx, ry = rotate(cx + len + 2, py - 4, cx, cy, s, c)
                    labels[#labels + 1] = {t = tostring(ang), x = lx, y = ly, fl = RIGHT}
                    labels[#labels + 1] = {t = tostring(ang), x = rx, y = ry, fl = LEFT}
                end
            end
        end
        ladder = {segs = segs, labels = labels}
    end

    local compass = nil
    if show_compass then
        local ribbonY = y + h - 24
        local labels = {[0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW"}
        local ticks, texts = {}, {}
        local hdg = heading
        for d = -90, 90, 10 do
            local tickHdg = (hdg + d + 360) % 360
            local px = cx + d * ppd
            if px > x and px < x + w then
                local th = (tickHdg % 30 == 0) and 8 or 4
                ticks[#ticks + 1] = {px, ribbonY, px, ribbonY - th}
                if tickHdg % 30 == 0 then texts[#texts + 1] = {t = (labels[tickHdg] or string.format("%d", tickHdg)), x = px, y = ribbonY - th - 8, fl = CENTERED + FONT_XS} end
            end
        end
        compass = {ribbonY = ribbonY, ticks = ticks, texts = texts, box = {bw = 60, bh = 14, bx = cx - 30, by = ribbonY + 6, txt = string.format("%03d°", hdg)}, tri = {cx, ribbonY + 1, cx - 5, ribbonY - 7, cx + 5, ribbonY - 7}}
    end

    local bars = {alt = nil, gs = nil}

    local alt_unit = (units and units["altitude"]) or "m"
    local gs_unit = (units and units["groundspeed"]) or "kt"

    if show_altitude then
        local barX, barY = x + w - 10, y + 5
        local barH = h - 10
        local fillH = math.floor((clamp(altitude, 0, 200)) / 200 * barH)
        bars.alt = {rect = {barX, barY, 6, barH}, fill = {barX, barY + barH - fillH, 6, fillH}, text = {x = barX - 4, y = barY + barH / 2 - 4, str = string.format("%d %s", altitude, alt_unit), fl = RIGHT + FONT_XS}}
    end

    if show_groundspeed then
        local barX, barY = x + 4, y + 5
        local barH = h - 10
        local fillH = math.floor((clamp(groundspeed, 0, 100)) / 100 * barH)
        bars.gs = {rect = {barX, barY, 6, barH}, fill = {barX, barY + barH - fillH, 6, fillH}, text = {x = barX + 10, y = barY + barH / 2 - 4, str = string.format("%d %s", groundspeed, gs_unit), fl = LEFT + FONT_XS}}
    end

    return {
        x = x,
        y = y,
        w = w,
        h = h,
        ppd = ppd,
        colors = colors,
        crosshair = crosshair,
        ground_sky = ground_sky,
        arc = arc,
        ladder = ladder,
        compass = compass,
        bars = bars,
        show = {arc = show_arc, ladder = show_ladder, compass = show_compass, altitude = show_altitude, groundspeed = show_groundspeed}
    }
end

function RenderAH.wakeup(sensors, units, x, y, w, h, opts) RenderAH._frame = build_frame(sensors, units, x, y, w, h, opts) end

function RenderAH.paint()
    local F = RenderAH._frame
    if not F then return end

    local cx, cy = F.x + F.w / 2, F.y + F.h / 2

    lcd.setClipping(F.x, F.y, F.w, F.h)

    lcd.color(F.ground_sky.baseFillColor)
    lcd.drawFilledRectangle(F.x, F.y, F.w, F.h)
    lcd.color(F.ground_sky.overlayColor)
    local t1 = F.ground_sky.t1;
    lcd.drawFilledTriangle(t1[1], t1[2], t1[3], t1[4], t1[5], t1[6])
    local t2 = F.ground_sky.t2;
    lcd.drawFilledTriangle(t2[1], t2[2], t2[3], t2[4], t2[5], t2[6])

    lcd.color(F.colors.crosshair)
    local L1 = F.crosshair.lines[1];
    lcd.drawLine(L1[1], L1[2], L1[3], L1[4])
    local L2 = F.crosshair.lines[2];
    lcd.drawLine(L2[1], L2[2], L2[3], L2[4])
    local C = F.crosshair.circle;
    lcd.drawCircle(C[1], C[2], C[3])

    if F.show.arc and F.arc then
        lcd.color(F.colors.arc)
        local ticks = F.arc.ticks
        for i = 1, #ticks do
            local t = ticks[i];
            lcd.drawLine(t[1], t[2], t[3], t[4])
        end
        local a = F.arc.tri;
        lcd.drawFilledTriangle(a[1], a[2], a[3], a[4], a[5], a[6])
    end

    if F.show.ladder and F.ladder then
        lcd.color(F.colors.ladder)
        local segs = F.ladder.segs
        for i = 1, #segs do
            local s = segs[i];
            lcd.drawLine(s[1], s[2], s[3], s[4])
        end
        local labels = F.ladder.labels
        for i = 1, #labels do
            local lbl = labels[i];
            lcd.drawText(lbl.x, lbl.y, lbl.t, lbl.fl)
        end
    end

    if F.show.compass and F.compass then
        lcd.color(F.colors.compass)
        local ticks = F.compass.ticks
        for i = 1, #ticks do
            local t = ticks[i];
            lcd.drawLine(t[1], t[2], t[3], t[4])
        end
        local tri = F.compass.tri;
        lcd.drawFilledTriangle(tri[1], tri[2], tri[3], tri[4], tri[5], tri[6])

        local bx, by = F.compass.box.bx, F.compass.box.by
        local bw, bh = F.compass.box.bw, F.compass.box.bh
        lcd.color(lcd.RGB(0, 0, 0));
        lcd.drawFilledRectangle(bx, by, bw, bh)
        lcd.color(F.colors.compass);
        lcd.drawRectangle(bx, by, bw, bh)
        lcd.drawText(cx, by + 1, F.compass.box.txt, CENTERED + FONT_XS)

        local texts = F.compass.texts
        for i = 1, #texts do
            local t = texts[i];
            lcd.drawText(t.x, t.y, t.t, t.fl)
        end
    end

    if F.show.altitude and F.bars.alt then
        lcd.color(F.colors.altitude)
        local B = F.bars.alt
        local r = B.rect;
        lcd.drawRectangle(r[1], r[2], r[3], r[4])
        local f = B.fill;
        lcd.drawFilledRectangle(f[1], f[2], f[3], f[4])
        lcd.drawText(B.text.x, B.text.y, B.text.str, B.text.fl)
    end
    if F.show.groundspeed and F.bars.gs then
        lcd.color(F.colors.groundspeed)
        local B = F.bars.gs
        local r = B.rect;
        lcd.drawRectangle(r[1], r[2], r[3], r[4])
        local f = B.fill;
        lcd.drawFilledRectangle(f[1], f[2], f[3], f[4])
        lcd.drawText(B.text.x, B.text.y, B.text.str, B.text.fl)
    end

    local W, H = lcd.getWindowSize()
    lcd.setClipping(0, 0, W, H)
end

return RenderAH
