-- Alt Inventory - this week's progress per character (2.1): the Great
-- Vault's three rows, the Mythic+ keys done this week, and raid lockouts,
-- read when you log in and whenever the game says they changed.
--
--   chars["Name-Realm"].weekly = {
--     at       when it was read
--     resetAt  when the weekly reset happens after that (vault and keys
--              then count as last week)
--     vault    { raid = { slot, ... }, dungeons = {...}, world = {...} },
--              slot = { progress, threshold, level, ilvl }   (Retail)
--     ready    true when the Great Vault had rewards to collect at login
--     keys     { level, ... } this week's finished keys, highest first   (Retail)
--     lockouts { { name, difficulty, killed, total, resetAt }, ... } raids
--   }
-- The Vault and Mythic+ only exist on Retail; lockouts are read everywhere,
-- so WoW Forever and the Classic versions get the raid column.

local _, ns = ...

local Weekly = {}
ns.Weekly = Weekly

local function Now() return time() end

-- Retail only: WoW Forever's client can carry these functions without the
-- Great Vault or Mythic+ (its project ID isn't Retail's).
local function IsRetail()
    return WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
end

-- The vault rows the game has, by the enum names it uses for them.
local VAULT_ROWS = {
    { key = "raid", enum = "Raid" },
    { key = "dungeons", enum = "Activities" },
    { key = "world", enum = "World" },
}

local function ResetAt()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok, seconds = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok and type(seconds) == "number" and seconds > 0 then return Now() + seconds end
    end
    return nil
end

local function RewardItemLevel(id)
    if not (id and C_WeeklyRewards.GetExampleRewardItemHyperlinks) then return nil end
    local ok, link = pcall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, id)
    if not ok or type(link) ~= "string" then return nil end
    local getLevel = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
    local okLevel, level = pcall(getLevel, link)
    if okLevel and type(level) == "number" and level > 0 then return level end
    return nil
end

local function ReadVault()
    if not IsRetail() then return nil end
    if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities and Enum.WeeklyRewardChestThresholdType) then return nil end
    local vault = {}
    for _, row in ipairs(VAULT_ROWS) do
        local kind = Enum.WeeklyRewardChestThresholdType[row.enum]
        if kind then
            local ok, list = pcall(C_WeeklyRewards.GetActivities, kind)
            if ok and type(list) == "table" then
                local slots = {}
                table.sort(list, function(a, b) return (a.index or 0) < (b.index or 0) end)
                for _, a in ipairs(list) do
                    local slot = { progress = a.progress or 0, threshold = a.threshold or 0, level = a.level or 0 }
                    if slot.threshold > 0 and slot.progress >= slot.threshold then slot.ilvl = RewardItemLevel(a.id) end
                    slots[#slots + 1] = slot
                end
                vault[row.key] = slots
            end
        end
    end
    return next(vault) and vault or nil
end

local function ReadKeys()
    if not IsRetail() then return nil end
    if not (C_MythicPlus and C_MythicPlus.GetRunHistory) then return nil end
    -- This week's runs only, finished or not; only finished ones count.
    local ok, runs = pcall(C_MythicPlus.GetRunHistory, false, true)
    if not ok or type(runs) ~= "table" then return nil end
    local keys = {}
    for _, run in ipairs(runs) do
        if run.completed and run.level then keys[#keys + 1] = run.level end
    end
    table.sort(keys, function(a, b) return a > b end)
    return keys
end

local function ReadLockouts()
    if not (GetNumSavedInstances and GetSavedInstanceInfo) then return nil end
    local list = {}
    for i = 1, GetNumSavedInstances() do
        local name, _, reset, _, locked, extended, _, isRaid, _, difficultyName, numEncounters, encounterProgress =
            GetSavedInstanceInfo(i)
        if name and isRaid and (locked or extended) and (reset or 0) > 0 then
            list[#list + 1] = {
                name = name, difficulty = difficultyName, killed = encounterProgress or 0,
                total = numEncounters or 0, resetAt = Now() + reset,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return (a.difficulty or "") < (b.difficulty or "")
    end)
    return list
end

-- Reads everything for the logged-in character.
function Weekly:Scan()
    if not AltInventoryDB or not AltInventoryDB.chars then return end
    local key = ns.GetCharKey()
    local data = key and AltInventoryDB.chars[key]
    if not data then return end
    local old = data.weekly or {}
    local w = { at = Now(), resetAt = ResetAt() or old.resetAt }
    w.vault = ReadVault()
    w.keys = ReadKeys()
    w.lockouts = ReadLockouts() or old.lockouts
    if C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards then
        local ok, ready = pcall(C_WeeklyRewards.HasAvailableRewards)
        w.ready = ok and ready or nil
    end
    data.weekly = w
    if ns.SearchWindow then ns.SearchWindow:QueueRefresh() end
end

-- Whether a character's vault and keys are from before the last reset.
function Weekly.IsOld(w, now)
    return not w or not w.resetAt or (now or Now()) >= w.resetAt
end

-- How many of a vault row's slots are unlocked.
function Weekly.Unlocked(slots)
    local n = 0
    for _, slot in ipairs(slots or {}) do
        if slot.threshold > 0 and slot.progress >= slot.threshold then n = n + 1 end
    end
    return n
end

-- True when the character has vault rewards to collect: the game said so
-- at login, or the vault had something unlocked before a reset since.
function Weekly.RewardsWaiting(w, now)
    if not w then return false end
    if w.ready then return true end
    if not Weekly.IsOld(w, now) or not w.vault then return false end
    for _, slots in pairs(w.vault) do
        if Weekly.Unlocked(slots) > 0 then return true end
    end
    return false
end

-- Lockouts that haven't reset yet.
function Weekly.Lockouts(w, now)
    local list = {}
    now = now or Now()
    for _, l in ipairs(w and w.lockouts or {}) do
        if (l.resetAt or 0) > now then list[#list + 1] = l end
    end
    return list
end

function Weekly.HasVault()
    return IsRetail() and C_WeeklyRewards ~= nil and C_WeeklyRewards.GetActivities ~= nil
end

function Weekly.HasKeys()
    return IsRetail() and C_MythicPlus ~= nil and C_MythicPlus.GetRunHistory ~= nil
end

-- Asks the game for fresh data; the events below read it when it arrives.
function Weekly:Request()
    if RequestRaidInfo then pcall(RequestRaidInfo) end
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
end

local pending
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = nil
        if not InCombatLockdown() then Weekly:Scan() end
    end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "UPDATE_INSTANCE_INFO", "WEEKLY_REWARDS_UPDATE", "CHALLENGE_MODE_COMPLETED",
                         "CHALLENGE_MODE_MAPS_UPDATE", "BOSS_KILL", "PLAYER_REGEN_ENABLED" }) do
    pcall(events.RegisterEvent, events, event)
end
local dirty = false
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Saved data is set up at PLAYER_LOGIN too; read once the rest has loaded.
        C_Timer.After(4, function()
            Weekly:Request()
            Soon()
        end)
    elseif event == "BOSS_KILL" or event == "CHALLENGE_MODE_COMPLETED" then
        Weekly:Request()
        dirty = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        if dirty then
            dirty = false
            Soon()
        end
    else
        Soon()
    end
end)
