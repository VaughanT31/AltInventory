-- Alt Inventory - time played on each character, for the Play time tab.
--
-- The game only says a character's /played while you're on it, so each
-- character is recorded at login (and kept up to date at logout):
--   chars["Name-Realm"].played    seconds played, as of playedAt
--   chars["Name-Realm"].playedAt  when that was
--   chars["Name-Realm"].faction   "Horde" | "Alliance" | "Neutral"
--   chars["Name-Realm"].role      "TANK" | "HEALER" | "DAMAGER" (current spec)
--
-- Asking for /played prints it in chat. At login that's noise, so the
-- game's printer is skipped for that one answer; typing /played yourself
-- still prints as normal. If this client's printer can't be found, nothing
-- is asked at login and the time is read when the tab is opened instead.

local _, ns = ...

local Played = {}
ns.Played = Played

local quiet = 0

-- Wraps the game's /played printer (its name has moved between versions)
-- so answers we asked for aren't printed. Returns true when it could.
local function WrapPrinter()
    local spots = { { _G, "ChatFrame_DisplayTimePlayed" }, { _G.ChatFrameUtil, "DisplayTimePlayed" } }
    local wrapped = false
    for _, spot in ipairs(spots) do
        local owner, name = spot[1], spot[2]
        if type(owner) == "table" and type(owner[name]) == "function" then
            local original = owner[name]
            owner[name] = function(...)
                if quiet > 0 then
                    quiet = quiet - 1
                    return
                end
                return original(...)
            end
            wrapped = true
        end
    end
    return wrapped
end

local canQuiet

-- Asks the game for /played. silent: don't print the answer.
function Played:Request(silent)
    if not RequestTimePlayed then return end
    if silent then
        if canQuiet == nil then canQuiet = WrapPrinter() end
        if not canQuiet then return end
        quiet = quiet + 1
        -- If no answer comes, don't swallow the next /played the player types.
        C_Timer.After(10, function() quiet = 0 end)
    end
    RequestTimePlayed()
end

local function CharData()
    return AltInventoryDB and AltInventoryDB.chars[ns.GetCharKey()]
end

local function SpecRole()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getRole = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationRole) or GetSpecializationRole
    local spec = getSpec and getSpec()
    return spec and getRole and getRole(spec) or nil
end

function Played:Note()
    local data = CharData()
    if not data then return end
    data.faction = UnitFactionGroup("player") or data.faction
    data.role = SpecRole() or data.role
end

function Played:OnTimePlayed(total)
    local data = CharData()
    if not data or type(total) ~= "number" then return end
    data.played, data.playedAt = total, time()
end

-- At logout, the time since the last answer is added on.
function Played:Save()
    local data = CharData()
    if data and data.played and data.playedAt then
        data.played = data.played + math.max(0, time() - data.playedAt)
        data.playedAt = time()
    end
end

-- A character's seconds played now: the character you're on keeps counting.
function Played.Seconds(key, data)
    if not data.played then return nil end
    if key == ns.GetCharKey() and data.playedAt then
        return data.played + math.max(0, time() - data.playedAt)
    end
    return data.played
end

local ROLE_LABELS = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
local ROLE_COLORS = { TANK = { 0.35, 0.6, 1 }, HEALER = { 0.3, 0.85, 0.4 }, DAMAGER = { 0.9, 0.3, 0.3 } }
local FACTION_COLORS = { Horde = { 0.85, 0.2, 0.2 }, Alliance = { 0.25, 0.5, 1 } }
local GREY = { 0.6, 0.6, 0.6 }

local function ClassColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and { c.r, c.g, c.b } or GREY
end

-- What a character counts under for a grouping: key, label, colour.
local GROUPS = {
    character = function(key, data)
        return key, key:match("^[^%-]+") or key, ClassColor(data.class)
    end,
    class = function(_, data)
        local class = data.class or "?"
        local label = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
        return class, label, ClassColor(class)
    end,
    role = function(_, data)
        local role = data.role or "?"
        return role, ROLE_LABELS[role] or "Unknown", ROLE_COLORS[role] or GREY
    end,
    faction = function(_, data)
        local faction = data.faction or "?"
        return faction, (faction == "?" and "Unknown" or faction), FACTION_COLORS[faction] or GREY
    end,
}
Played.GROUP_ORDER = { "character", "class", "role", "faction" }
Played.GROUP_LABELS = { character = "By character", class = "By class", role = "By role", faction = "By faction" }

-- Time played grouped: { { key, label, color, seconds, count }, ... } most
-- first, the total, and how many characters have no time recorded yet.
function Played.List(group)
    local Group = GROUPS[group] or GROUPS.character
    local byKey, list, total, missing = {}, {}, 0, 0
    for key, data in pairs(AltInventoryDB and AltInventoryDB.chars or {}) do
        local seconds = Played.Seconds(key, data)
        if seconds then
            local groupKey, label, color = Group(key, data)
            local entry = byKey[groupKey]
            if not entry then
                entry = { key = groupKey, label = label, color = color, seconds = 0, count = 0 }
                byKey[groupKey] = entry
                list[#list + 1] = entry
            end
            entry.seconds = entry.seconds + seconds
            entry.count = entry.count + 1
            total = total + seconds
        else
            missing = missing + 1
        end
    end
    table.sort(list, function(a, b) return a.seconds > b.seconds or (a.seconds == b.seconds and a.label < b.label) end)
    return list, total, missing
end

-- 4075200 seconds as "47d 4h", under a day "5h 20m", under an hour "12m".
function Played.Format(seconds)
    seconds = math.floor(seconds or 0)
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds % 86400 / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    if days > 0 then return days .. "d " .. hours .. "h" end
    if hours > 0 then return hours .. "h " .. minutes .. "m" end
    return minutes .. "m"
end
