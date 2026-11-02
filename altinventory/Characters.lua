-- Alt Inventory - what each character is up to, for the Characters tab:
-- bag space, item level, concentration, Moxie, profession cooldowns and this
-- patch's currencies. Only the logged-in character can be read, so each is
-- as of the last time it was on.
--
--   chars["Name-Realm"].bagFree, bagTotal, reagentFree, reagentTotal
--   chars["Name-Realm"].ilvl
--   chars["Name-Realm"].concentration = { [currencyID] = { p = profession,
--       q = amount, m = most, at = when, per = amount a cycle, cycle = seconds } }
--   chars["Name-Realm"].moxie = { [currencyID] = amount }
--   chars["Name-Realm"].cooldowns = { [recipeID] = { n = name, ready = when,
--       c = charges, m = most charges } }
--   chars["Name-Realm"].patch = { [currencyID] = amount }
--
-- Concentration keeps filling while you're away, so it's worked out from
-- when it was last read. The game only says which currency is a profession's
-- concentration, and which recipes have cooldowns, with that profession's
-- window open, so those show after it's been opened once on each character.

local _, ns = ...

local Characters = {}
ns.Characters = Characters

-- Each profession's Moxie (Midnight).
Characters.MOXIE = { 3256, 3257, 3258, 3259, 3260, 3261, 3262, 3263, 3264, 3265, 3266 }

local function Clean(value)
    if value ~= nil and issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function Data()
    local key = ns.GetCharKey()
    return key and AltInventoryDB and AltInventoryDB.chars[key]
end

-- ---------------------------------------------------------------------
-- Scanning
-- ---------------------------------------------------------------------

local function CountBag(bagID)
    if bagID == nil then return 0, 0 end
    local total = C_Container.GetContainerNumSlots(bagID) or 0
    if total == 0 then return 0, 0 end
    local free = C_Container.GetContainerNumFreeSlots(bagID)
    return free or 0, total
end

function Characters.ScanBagSpace()
    local data = Data()
    if not data then return end
    local free, total = 0, 0
    for _, name in ipairs({ "Backpack", "Bag_1", "Bag_2", "Bag_3", "Bag_4" }) do
        local f, t = CountBag(Enum.BagIndex[name])
        free, total = free + f, total + t
    end
    data.bagFree, data.bagTotal = free, total
    data.reagentFree, data.reagentTotal = CountBag(Enum.BagIndex.ReagentBag)
end

-- Equipped item level, not the best you own.
function Characters.ScanItemLevel()
    local data = Data()
    if not (data and GetAverageItemLevel) then return end
    local overall, equipped = GetAverageItemLevel()
    local level = Clean(equipped) or Clean(overall)
    if type(level) == "number" and level > 0 then data.ilvl = level end
end

local function ReadCurrency(id)
    local C = C_CurrencyInfo
    local ok, info = pcall(C and C.GetCurrencyInfo or error, id)
    if not (ok and info) then return nil end
    if info.name and AltInventoryDB then
        AltInventoryDB.currencyNames[id] = { n = info.name, i = info.iconFileID }
    end
    return info
end

function Characters.ScanMoxie()
    local data = Data()
    if not data or not ns.HAS_WARBAND then return end
    local found = {}
    for _, id in ipairs(Characters.MOXIE) do
        local info = ReadCurrency(id)
        local amount = info and Clean(info.quantity)
        if amount and amount > 0 then found[id] = amount end
    end
    data.moxie = found
end

-- Updates concentration already known for this character.
function Characters.ScanConcentration()
    local data = Data()
    if not (data and data.concentration) then return end
    for id, entry in pairs(data.concentration) do
        local info = ReadCurrency(id)
        if info then
            entry.q = Clean(info.quantity) or entry.q
            entry.m = Clean(info.maxQuantity) or entry.m
            entry.at = time()
            local cycle = Clean(info.rechargingCycleDurationMS)
            entry.cycle = cycle and cycle > 0 and cycle / 1000 or entry.cycle
            entry.per = Clean(info.rechargingAmountPerCycle) or entry.per
        end
    end
end

-- With a profession's window open: which currency is its concentration, and
-- which of its recipes have cooldowns.
function Characters.ScanOpenProfession()
    local data = Data()
    local T = C_TradeSkillUI
    if not (data and T and T.GetChildProfessionInfo) then return end
    local ok, child = pcall(T.GetChildProfessionInfo)
    if not (ok and child) then return end
    local professionID = Clean(child.professionID)
    local name = Clean(child.parentProfessionName) or Clean(child.professionName)
    if professionID and T.GetConcentrationCurrencyID then
        local got, currencyID = pcall(T.GetConcentrationCurrencyID, professionID)
        currencyID = got and Clean(currencyID)
        if currencyID and currencyID > 0 then
            data.concentration = data.concentration or {}
            data.concentration[currencyID] = data.concentration[currencyID] or {}
            data.concentration[currencyID].p = name
            Characters.ScanConcentration()
        end
    end
    if T.GetAllRecipeIDs and T.GetRecipeCooldown then
        data.cooldowns = data.cooldowns or {}
        local now = time()
        for _, recipeID in ipairs(T.GetAllRecipeIDs() or {}) do
            local good, cooldown, _, charges, most = pcall(T.GetRecipeCooldown, recipeID)
            cooldown, charges, most = good and Clean(cooldown), good and Clean(charges), good and Clean(most)
            if good and ((cooldown and cooldown > 0) or (most and most > 0)) then
                local info = T.GetRecipeInfo and T.GetRecipeInfo(recipeID)
                if info and info.learned then
                    data.cooldowns[recipeID] = {
                        n = info.name, ready = now + (cooldown or 0),
                        c = charges or nil, m = most and most > 0 and most or nil,
                    }
                end
            end
        end
    end
end

-- Called while the currency list is read (ns.ScanCurrencies): is this header
-- the current expansion's, or a season's? "Season" isn't in every language's
-- name for it, so the expansion's own name counts too.
function Characters.IsPatchHeader(name)
    if type(name) ~= "string" then return false end
    local level = GetExpansionLevel and GetExpansionLevel()
    local expansion = level and _G["EXPANSION_NAME" .. level]
    if expansion and name:find(expansion, 1, true) then return true end
    return name:lower():find("season", 1, true) ~= nil
end

function Characters.ScanAll()
    Characters.ScanBagSpace()
    Characters.ScanItemLevel()
    Characters.ScanMoxie()
    Characters.ScanConcentration()
end

-- ---------------------------------------------------------------------
-- Reading it back
-- ---------------------------------------------------------------------

-- Concentration now: amount, most, and whether it's worked out rather than
-- just read.
function Characters.ConcentrationNow(entry, now)
    local amount = entry.q or 0
    local most = entry.m
    if entry.cycle and entry.per and entry.at and most then
        local cycles = math.floor(((now or time()) - entry.at) / entry.cycle)
        if cycles > 0 then
            return math.min(most, amount + cycles * entry.per), most, true
        end
    end
    return amount, most, false
end

local function TimeText(seconds)
    if seconds >= 86400 then return math.floor(seconds / 86400) .. "d" end
    if seconds >= 3600 then return math.floor(seconds / 3600) .. "h" end
    return math.max(1, math.floor(seconds / 60)) .. "m"
end

local function CurrencyLine(id, amount)
    local entry = AltInventoryDB.currencyNames[id]
    local amountText = BreakUpLargeNumbers and BreakUpLargeNumbers(amount) or tostring(amount)
    return { label = entry and entry.n or ("Currency " .. id), value = amountText, icon = entry and entry.i }
end

local function SortedLines(lines)
    table.sort(lines, function(a, b) return a.label < b.label end)
    return lines
end

-- One character's block for the tab:
-- { name, summary, sections = { { title, lines = { { label, value, icon } } } } }
function Characters.Block(key, data, now)
    now = now or time()
    local parts = {}
    if data.ilvl then parts[#parts + 1] = ("item level %d"):format(data.ilvl) end
    if data.bagTotal then
        local low = data.bagFree <= 5
        parts[#parts + 1] = (low and "|cffff5252%d|r/%d bag slots free" or "%d/%d bag slots free"):format(data.bagFree, data.bagTotal)
    end
    if data.reagentTotal and data.reagentTotal > 0 then
        parts[#parts + 1] = ("%d/%d reagent"):format(data.reagentFree, data.reagentTotal)
    end
    local block = { key = key, name = ns.ClassName(key, data.class), summary = table.concat(parts, ", "), sections = {} }

    local function Section(title, lines)
        if #lines > 0 then block.sections[#block.sections + 1] = { title = title, lines = SortedLines(lines) } end
    end

    local lines = {}
    for _, entry in pairs(data.concentration or {}) do
        local amount, most, worked = Characters.ConcentrationNow(entry, now)
        if most then
            local full = amount >= most
            lines[#lines + 1] = {
                label = entry.p or "?",
                value = (full and "|cff59d973%d/%d|r" or "%d/%d"):format(amount, most) .. (worked and " |cff999999est.|r" or ""),
            }
        end
    end
    Section("Concentration", lines)

    lines = {}
    for id, amount in pairs(data.moxie or {}) do lines[#lines + 1] = CurrencyLine(id, amount) end
    Section("Moxie", lines)

    lines = {}
    for _, cooldown in pairs(data.cooldowns or {}) do
        local left = (cooldown.ready or 0) - now
        lines[#lines + 1] = { label = cooldown.n or "?", value = left > 0 and TimeText(left) or "|cff59d973ready|r" }
    end
    Section("Cooldowns", lines)

    lines = {}
    for id, amount in pairs(data.patch or {}) do lines[#lines + 1] = CurrencyLine(id, amount) end
    Section("This patch", lines)

    return block
end

-- Every character, your current one first, then by name.
function Characters.Blocks(now)
    local me = ns.GetCharKey()
    local keys = {}
    for key in pairs(AltInventoryDB.chars) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if (a == me) ~= (b == me) then return a == me end
        return a < b
    end)
    local blocks = {}
    for _, key in ipairs(keys) do
        blocks[#blocks + 1] = Characters.Block(key, AltInventoryDB.chars[key], now)
    end
    return blocks
end

-- Who else holds an item, for the reagent finder: { { name, count, text }, ... }
-- most first, leaving out the character you're on, then the warband bank's count.
function Characters.Holders(itemID)
    local me = ns.GetCharKey()
    local list = {}
    for key, data in pairs(AltInventoryDB.chars) do
        if key ~= me then
            local text, total = ns.HoldingText(data, itemID)
            if total > 0 then
                list[#list + 1] = { key = key, name = ns.ClassName(key, data.class), count = total, text = text }
            end
        end
    end
    table.sort(list, function(a, b) return a.count > b.count or (a.count == b.count and a.key < b.key) end)
    return list, AltInventoryDB.warband[itemID] or 0
end
