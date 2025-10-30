--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local inavdash = require("inavdash")

local M = {}

M.MODE = {DISARMED = 0, READY_TO_ARM = 1, ARMING_PREVENTED = 2, ACRO = 10, ANGLE = 11, HORIZON = 12, PASSTHRU = 13, ALT_HOLD_ANGLE = 20, POS_HOLD_ANGLE = 21, WAYPOINT = 22, RTH = 23, COURSE_HOLD = 26, CRUISE = 27, FAILSAFE = 99, WAIT = 100, ERROR = 101, ACRO_AIR = 102, HOME_RESET = 103, LANDING = 104, ANGLE_HOLD = 105, NO_DATA = 255}

local last_mode_id = M.MODE.DISARMED

local function bit_is_set(value, mask)
    value = value or 0
    return (value % (mask * 2)) >= mask
end

local function digits_ABCDE(n)
    n = tonumber(n) or 0
    local E = n % 10;
    n = (n - E) / 10
    local D = n % 10;
    n = (n - D) / 10
    local C = n % 10;
    n = (n - C) / 10
    local B = n % 10;
    n = (n - B) / 10
    local A = n % 10

    return math.floor(A), math.floor(B), math.floor(C), math.floor(D), math.floor(E)
end

local function crsfToModeID(value)
    if not value then return nil end
    
    if value == "OK" then
        return M.MODE.READY_TO_ARM
    elseif value == "!ERR" then
        return M.MODE.ERROR
    elseif value == "WAIT" then
        return M.MODE.WAIT
    elseif value == "AIR" then
        return M.MODE.ACRO_AIR
    elseif value == "ACRO" then
        return M.MODE.ACRO
    elseif value == "!FS!" then
        return M.MODE.FAILSAFE
    elseif value == "HRST" then
        return M.MODE.HOME_RESET
    elseif value == "MANU" then
        return M.MODE.PASSTHRU
    elseif value == "RTH" then
        return M.MODE.RTH
    elseif value == "HOLD" then
        return M.MODE.POS_HOLD_ANGLE
    elseif value == "CRUZ" then
        return M.MODE.CRUISE
    elseif value == "CRSH" then
        return M.MODE.COURSE_HOLD
    elseif value == "WP" then
        return M.MODE.WAYPOINT
    elseif value == "AH" then
        return M.MODE.ALT_HOLD_ANGLE
    elseif value == "ANGL" then
        return M.MODE.ANGLE
    elseif value == "HOR" then
        return M.MODE.HORIZON
    elseif value == "ANGH" then
        return M.MODE.ANGLE_HOLD
    elseif value == "LAND" then
        return M.MODE.LANDING
    end
end

local function sportToModeID(abcde)
    local A, B, C, D, E = digits_ABCDE(abcde)

    if bit_is_set(A, 4) then return M.MODE.FAILSAFE end

    local armed = bit_is_set(E, 4)
    local prevented = bit_is_set(E, 2)
    local ok = bit_is_set(E, 1)

    if not armed then
        if prevented then return M.MODE.ARMING_PREVENTED end
        if ok then return M.MODE.READY_TO_ARM end
        return M.MODE.DISARMED
    end

    if bit_is_set(B, 1) then return M.MODE.RTH end
    if bit_is_set(B, 2) then return M.MODE.WAYPOINT end

    local angle = bit_is_set(D, 1)
    local horizon = bit_is_set(D, 2)
    local passthru = bit_is_set(D, 4)
    local heading = bit_is_set(C, 1)
    local alt = bit_is_set(C, 2)
    local pos = bit_is_set(C, 4)
    local course_hold = bit_is_set(B, 8)

    if course_hold and alt then return M.MODE.CRUISE end
    if course_hold then return M.MODE.COURSE_HOLD end
    if pos and angle then return M.MODE.POS_HOLD_ANGLE end
    if alt and angle then return M.MODE.ALT_HOLD_ANGLE end
    if passthru then return M.MODE.PASSTHRU end
    if horizon then return M.MODE.HORIZON end
    if angle then return M.MODE.ANGLE end

    return M.MODE.ACRO
end

local function valueToModeId(telemType, value)
    if telemType == "sport" then
        return sportToModeID(value or 0)
    elseif telemType == "crsf" then
        return crsfToModeID(tostring(value or ""))
    else
        return nil
    end
end

function M.eval(telemType, value)
    local mode_id = valueToModeId(telemType, value)
    
    if mode_id == nil then return last_mode_id end
    
    last_mode_id = mode_id

    return mode_id
end

function M.last_mode() return last_mode end
function M.reset()
    last_mode_id = M.MODE.DISARMED
end

return M
