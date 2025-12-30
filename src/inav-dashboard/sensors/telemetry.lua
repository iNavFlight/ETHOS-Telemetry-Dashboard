--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local inavdash = require("inavdash")

local arg = {...}
local flightmodes = assert(loadfile("sensors/flightmodes.lua"))()

local telemetry = {}
local protocol, telemetrySOURCE, crsfSOURCE

local currentTelemetrySensor = nil
local currentTelemetryType = nil
local internalModule = nil
local externalModule = nil
local telemetryType

local _sourceCache = setmetatable({}, {__mode = "v"})
local _createTried = {}
local _dropDone = false

local _startTime = os.clock()
local _lastCreateTime = -1

local function round(num, numDecimalPlaces)
    local mult = 10 ^ (numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

local function _creationAllowed()
    local now = os.clock()

    if now < 5.0 then return false end

    if _lastCreateTime > 0 and (now - _lastCreateTime) < 5.0 then return false end
    return true
end

local sensorTable = {

    rssi = {name = "RSSI", unit_string = "%", sensors = {sport = {{appId = 0xF010, subId = 0}}, crsf = {"Rx Quality"}}},

    link = {name = "Link Quality", unit_string = "dB", sensors = {sport = {{appId = 0xF101, subId = 0}}, crsf = {"Rx RSSI1"}}},

    voltage = {name = "Voltage", unit_string = "V", sensors = {sport = {{appId = 0x0B50, subId = 0}, {appId = 0x0210, subId = 0}, {appId = 0xF103, subId = 0}, {appId = 0xF103, subId = 1}}, crsf = {"Rx Batt"}}},

    fuel = {name = "Fuel", unit_string = "%", autoCreate = true, sensors = {sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0600}}, crsf = {"Rx Cons"}}},

    current = {
        name = "Current",
        unit_string = "A",
        sensors = {sport = {{appId = 0x0B50, subId = 1}, {appId = 0x0200, subId = 0}}, crsf = {"Rx Current"}},
        transform = function(value)
            if value then return round(value, 2) end
            return value
        end
    },

    temp_esc = {name = "ESC Temperature", sensors = {sport = {{appId = 0x0B70, subId = 0}}}},

    altitude = {
        name = "Altitude",
        sensors = {sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0100}, {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0820}}, crsf = {"GPS alt"}},
        transform = function(value)
            if value then return round(value, 2) end
            return value
        end
    },

    vertical_speed = {
        name = "Vspeed",
        sensors = {sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0110}}, crsf = {"VSpeed"}},
        transform = function(value)
            if value then return round(value, 2) end
            return value
        end
    },

    heading = {name = "Yaw", sensors = {sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0840}}, crsf = {"GPS Heading"}}},

    roll = {name = "Roll", sensors = {sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0440, subId = 0, physId = 0x1B}, {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0730, subId = 0}}, crsf = {"Roll"}}, autoCreate = true, transform = function(value) if value then return -value end end},

    pitch = {
        name = "Pitch",
        sensors = {sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0430, subId = 0, physId = 0x1B}, {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0730, subId = 1}}, crsf = {"Pitch"}},
        autoCreate = true,
        transform = function(value) if value then return -value end end
    },

    groundspeed = {
        name = "Ground Speed",
        sensors = {sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0830, subId = 0}}, crsf = {"GPS speed"}},
        transform = function(value)
            if value then return round(value, 2) end
            return value
        end
    },

    satellites = {
        name = "Satellites",
        sensors = {sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0480, subId = 0}, {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0410, subId = 0}}, crsf = {"GPS Satellites"}},
        autoCreate = true,
        transform = function(value)
            if currentTelemetryType == "sport" then
                if value then
                    if string.len(value) > 1 then
                        if string.len(value) < 2 then
                            value = tonumber(widget.value)
                        else
                            value = tonumber(string.sub(value, 3))
                        end
                    end
                end
                return value
            else
                return value
            end
        end
    },

    gps_latitude = {name = "GPS Latitude", sensors = {sport = {{name = "GPS", options = OPTION_LATITUDE}}, crsf = {{name = "GPS", options = OPTION_LATITUDE}}}},

    gps_longitude = {name = "GPS Longitude", sensors = {sport = {{name = "GPS", options = OPTION_LONGITUDE}}, crsf = {{name = "GPS", options = OPTION_LONGITUDE}}}},

    flightmode = {
        name = "Flight Mode",
        sensors = {sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0470, subId = 0}}, crsf = {"Flight mode"}},
        autoCreate = true,
        transform = function(value)
            if currentTelemetryType == "sport" then
                if value and flightmodes then return flightmodes.eval("sport", value) end
                return value
            else
                if value and flightmodes then return flightmodes.eval("crsf", value) end
            end
        end
    }

}

local unitMap = {
    [UNIT_MILLIVOLT] = "mV",
    [UNIT_VOLT] = "V",
    [UNIT_MILLIAMPERE] = "mA",
    [UNIT_AMPERE] = "A",
    [UNIT_MILLIAMPERE_HOUR] = "mAh",
    [UNIT_AMPERE_HOUR] = "Ah",
    [UNIT_MILLIWATT] = "mW",
    [UNIT_WATT] = "W",

    [UNIT_CENTIMETER] = "cm",
    [UNIT_METER] = "m",
    [UNIT_KILOMETER] = "km",
    [UNIT_FOOT] = "ft",

    [UNIT_CENTIMETER_PER_SECOND] = "cm/s",
    [UNIT_METER_PER_SECOND] = "m/s",
    [UNIT_METER_PER_MINUTE] = "m/min",
    [UNIT_FOOT_PER_SECOND] = "ft/s",
    [UNIT_FOOT_PER_MINUTE] = "ft/min",
    [UNIT_KILOMETER_PER_HOUR] = "km/h",
    [UNIT_MILE_PER_HOUR] = "mph",
    [UNIT_KNOT] = "kt",

    [UNIT_CELSIUS] = "°C",
    [UNIT_FAHRENHEIT] = "°F",
    [UNIT_PERCENT] = "%",

    [UNIT_MICROSECOND] = "µs",
    [UNIT_MILLISECOND] = "ms",
    [UNIT_SECOND] = "s",
    [UNIT_MINUTE] = "min",
    [UNIT_HOUR] = "h",

    [UNIT_DB] = "dB",
    [UNIT_DBM] = "dBm",

    [UNIT_HERTZ] = "Hz",
    [UNIT_MEGAHERTZ] = "MHz",

    [UNIT_G] = "G",
    [UNIT_DEGREE] = "°",
    [UNIT_RADIAN] = "rad",

    [UNIT_MILLILITER] = "mL",
    [UNIT_MILLILITER_PER_MINUTE] = "mL/min",
    [UNIT_MILLILITER_PER_PULSE] = "mL/pulse",

    [UNIT_RPM] = "rpm",
    [UNIT_DEGREE_PER_SECOND] = "°/s"
}

local autoCreate = {
    roll = {name = "Roll", unit = UNIT_DEGREE, decimals = 1, appId = 0x0440, subId = 0},
    pitch = {name = "Pitch", unit = UNIT_DEGREE, decimals = 1, appId = 0x0430, subId = 1},
    flightmode = {name = "Flight Mode", unit = UNIT_RAW, decimals = 0, appId = 0x0470, subId = 0},
    gps_speed = {name = "GPS Speed", unit = UNIT_KNOT, decimals = 0, appId = 0x0830, subId = 0},
    satellites = {name = "Satellites", unit = UNIT_RAW, decimals = 0, appId = 0x0480, subId = 0},
    fuel = {name = "Fuel", unit = UNIT_MILLIAMPERE_HOUR, decimals = 0, appId = 0x0600, subId = 0}
}

local autoDrop = {fuel = {name = "Fuel", unit = UNIT_PERCENT, appId = 0x0600, subId = 0}}

local function getTelemetryType()

    if not internalModule or not externalModule then
        internalModule = model.getModule(0)
        externalModule = model.getModule(1)
    end

    if internalModule and internalModule:enable() then
        currentTelemetrySensor = system.getSource({appId = 0xF101})
        currentTelemetryType = "sport"
    elseif externalModule and externalModule:enable() then
        currentTelemetrySensor = system.getSource({crsfId = 0x14, subIdStart = 0, subIdEnd = 1})
        currentTelemetryType = "crsf"
        if not currentTelemetrySensor then
            currentTelemetrySensor = system.getSource({appId = 0xF101})
            currentTelemetryType = "sport"
        end
    end
end

local function _defKey(def) return (currentTelemetryType or "unknown") .. "|" .. string.format("%04X", def.appId or 0) .. "|" .. tostring(def.subId or 0) end

local function _createSportSensor(sensorDef, sensorKey)
    if currentTelemetryType ~= "sport" or not currentTelemetrySensor then return false end
    if not _creationAllowed() then return false end

    local cfg = autoCreate[sensorKey]
    if not cfg then return false end

    local voltageSensor = system.getSource({appId = 0x0210})
    local physId = voltageSensor and voltageSensor:physId()
    if not physId then return false end

    local band = voltageSensor and voltageSensor:band()
    if not band then return false end

    local defKey = _defKey(sensorDef)
    if _createTried[defKey] then return false end
    _createTried[defKey] = true

    local already = system.getSource(sensorDef)
    if already then return false end

    local s = model.createSensor({type = SENSOR_TYPE_DIY})
    s:name(cfg.name)
    s:unit(cfg.unit)
    s:decimals(cfg.decimals)
    s:protocolDecimals(cfg.decimals)
    s:physId(physId)
    s:band(band)
    s:minimum(-1000000000);
    s:maximum(2147483647)

    s:appId(sensorDef.appId)
    s:subId(sensorDef.subId or 0)

    _lastCreateTime = os.clock()
    return true
end

local function _ck(name) return (telemetryType or "unknown") .. "|" .. tostring(name) end

function telemetry.clearCache() _sourceCache = setmetatable({}, {__mode = "v"}) end

function telemetry.setTelemetryType(t)
    if telemetryType ~= t then
        telemetryType = t
        telemetry.clearCache()

        _createTried = {}
    end
end

function telemetry.getSensorProtocol() return protocol end

local function _runDropCycle()

    if _dropDone then return end
    if currentTelemetryType ~= "sport" or not currentTelemetrySensor then return end

    for key, cfg in pairs(autoDrop or {}) do

        if cfg.appId then
            local src = system.getSource({appId = cfg.appId, subId = cfg.subId or 0})
            if src then
                local u = src:unit()
                print("Found auto-drop sensor: " .. (cfg.name or "?") .. " unit=" .. tostring(u) .. " appId=" .. string.format("%04X", cfg.appId) .. " subId=" .. tostring(cfg.subId or 0))

                if u == cfg.unit then if type(src.drop) == "function" then src:drop() end end

                _sourceCache[src] = nil

            end
        end
    end

    _dropDone = true
end

function telemetry.getSensorSource(name)
    if not sensorTable[name] then return nil end

    local key = _ck(name)
    local cached = _sourceCache[key]
    if cached ~= nil then return cached end

    if currentTelemetryType == "crsf" then
        protocol = "crsf"
        for _, sensor in ipairs(sensorTable[name].sensors.crsf or {}) do
            local source = system.getSource(sensor)
            if source then
                _sourceCache[key] = source
                return source
            end
        end
    elseif currentTelemetryType == "sport" then
        protocol = "sport"

        _runDropCycle()

        local entry = sensorTable[name]
        for _, sensor in ipairs(entry.sensors.sport or {}) do
            local source = system.getSource(sensor)
            if source then
                _sourceCache[key] = source
                return source
            end

            if entry.autoCreate and currentTelemetrySensor then
                if _createSportSensor(sensor, name) then
                    local s2 = system.getSource(sensor)
                    if s2 then
                        _sourceCache[key] = s2
                        return s2
                    end
                end

            end
        end
    end

    return nil
end

function telemetry.getSensor(sensorKey)
    local entry = sensorTable[sensorKey]

    if entry and type(entry.source) == "function" then
        local src = entry.source()
        if src and type(src.value) == "function" then
            local value, major, minor = src.value()
            major = major or entry.unit

            if type(entry.transform) == "function" then value = entry.transform(value) end

            return value, major, minor
        end
    end

    local source = telemetry.getSensorSource(sensorKey)
    if not source then return nil end

    local value = source:value()
    local unit = source:unit()
    local major = nil
    local minor = nil

    if unit and unitMap[unit] then
        major = unitMap[unit]
    else
        major = unit
    end

    if entry and type(entry.transform) == "function" then value = entry.transform(value) end

    return value, major, minor
end

function telemetry.wakeup() getTelemetryType() end

return telemetry
