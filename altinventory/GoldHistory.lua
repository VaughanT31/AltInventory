-- Alt Inventory - gold over time (2.1): one entry per day with what each
-- character and the Warband Bank had, written whenever their gold is read.
--
--   AltInventoryDB.goldDays["2026-11-26"] = { c = { ["Name-Realm"] = copper }, w = copper }
--
-- A day only holds what was seen that day; the last known amount carries
-- forward, so a character you didn't log in on still counts.

local _, ns = ...

local Gold = {}
ns.GoldHistory = Gold

local KEEP_DAYS = 400
local DAY = 86400

local function Today(at) return date("%Y-%m-%d", at or time()) end

local function Days()
    AltInventoryDB.goldDays = AltInventoryDB.goldDays or {}
    return AltInventoryDB.goldDays
end

local function Entry(day)
    local days = Days()
    local e = days[day]
    if not e then
        e = { c = {} }
        days[day] = e
    end
    return e
end

function Gold.NoteCharacter(key, copper)
    if not key or type(copper) ~= "number" then return end
    Entry(Today()).c[key] = copper
end

function Gold.NoteWarband(copper)
    if type(copper) ~= "number" then return end
    Entry(Today()).w = copper
end

function Gold.Prune()
    local cutoff = Today(time() - KEEP_DAYS * DAY)
    for day in pairs(Days()) do
        if day < cutoff then Days()[day] = nil end
    end
end

-- Values for the last `count` steps of `step` days, oldest first:
-- { { day, value }, ... } with value nil before anything was saved.
-- which: "all" (every character still listed plus the warband), "warband",
-- or a character key.
function Gold.Series(which, count, step)
    step = step or 1
    local days = Days()
    local sorted = {}
    for day in pairs(days) do sorted[#sorted + 1] = day end
    table.sort(sorted)

    local now = time()
    local wanted = {}
    for i = count - 1, 0, -1 do wanted[#wanted + 1] = Today(now - i * step * DAY) end

    local chars, warband = {}, nil
    local listed = AltInventoryDB.chars or {}
    local out, at = {}, 1
    for _, day in ipairs(wanted) do
        while sorted[at] and sorted[at] <= day do
            local e = days[sorted[at]]
            for key, copper in pairs(e.c or {}) do chars[key] = copper end
            if e.w then warband = e.w end
            at = at + 1
        end
        local value
        if which == "warband" then
            value = warband
        elseif which == "all" then
            local sum, any = warband or 0, warband ~= nil
            for key, copper in pairs(chars) do
                if listed[key] then sum, any = sum + copper, true end
            end
            value = any and sum or nil
        else
            value = chars[which]
        end
        out[#out + 1] = { day = day, value = value }
    end
    return out
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    C_Timer.After(5, function() if AltInventoryDB then Gold.Prune() end end)
end)

-- Wraps the gold scans so every read is noted (ns.ScanMoney and
-- ns.ScanWarbandMoney are in Core.lua, loaded before this file).
local scanMoney, scanWarband = ns.ScanMoney, ns.ScanWarbandMoney
function ns.ScanMoney(...)
    scanMoney(...)
    local key = ns.GetCharKey()
    local data = key and AltInventoryDB.chars[key]
    if data then Gold.NoteCharacter(key, data.money) end
end
function ns.ScanWarbandMoney(...)
    scanWarband(...)
    if AltInventoryDB.warbandMoney and AltInventoryDB.warbandMoneyAt and time() - AltInventoryDB.warbandMoneyAt < 5 then
        Gold.NoteWarband(AltInventoryDB.warbandMoney)
    end
end
