-- Alt Inventory - saved data and scanning.
--
-- Counts per character (bags, bank, mail) and for the warband bank, plus a
-- name for every item held, so the search window can find items by name:
--
--   AltInventoryDB = {
--     chars = { ["Name-Realm"] = { class, bags = { [itemID] = count },
--                                  bank = {...}, bankScannedAt,
--                                  mail = {...}, mailScannedAt,
--                                  money (copper),
--                                  currencies = { [currencyID] = amount } } },
--     warband = { [itemID] = count }, warbandScannedAt,
--     warbandMoney, warbandMoneyAt,
--     names = { [itemID] = { n = name, q = quality, i = icon } },
--     currencyNames = { [currencyID] = { n = name, i = icon } },
--     window = { point, x, y },
--   }
--
-- Only the logged-in character can be read, so a character's counts are
-- as of the last time it was on (and its bank and mail as of the last time
-- those were opened).

local _, ns = ...

-- ---------------------------------------------------------------------
-- Bag ID lists
--
-- Built from Enum.BagIndex by name rather than hardcoded numbers, since
-- Blizzard has renamed/shuffled these across recent patches. Missing
-- names are silently skipped so the addon degrades gracefully instead of
-- erroring if an ID isn't present on a given client build.
-- ---------------------------------------------------------------------

local function BuildBagList(names)
    local list = {}
    for _, name in ipairs(names) do
        local id = Enum.BagIndex[name]
        if id ~= nil then
            table.insert(list, id)
        end
    end
    return list
end

local BAGS = BuildBagList({
    "Backpack", "Bag_1", "Bag_2", "Bag_3", "Bag_4", "ReagentBag",
})

-- Patch 11.2 replaced the bag-slot character bank with purchasable tabs
-- (CharacterBankTab_N) and dropped Bank/BankBag_N from the enum. Both sets
-- are listed so whichever the client actually has gets scanned.
local BANK_BAGS = BuildBagList({
    "CharacterBankTab_1", "CharacterBankTab_2", "CharacterBankTab_3",
    "CharacterBankTab_4", "CharacterBankTab_5", "CharacterBankTab_6",
    "Bank", "BankBag_1", "BankBag_2", "BankBag_3", "BankBag_4", "BankBag_5", "BankBag_6", "BankBag_7",
})

local WARBAND_BAGS = BuildBagList({
    "AccountBankTab_1", "AccountBankTab_2", "AccountBankTab_3", "AccountBankTab_4", "AccountBankTab_5",
})

-- Places a character's items can be, in the order they're shown.
ns.PLACES = { "bags", "bank", "mail" }

-- ---------------------------------------------------------------------
-- Item names
-- ---------------------------------------------------------------------

-- Remembers an item's name, quality and icon. The name comes from the
-- item's link, which always carries it, even when the game hasn't cached
-- the item yet.
local function NoteName(itemID, link, quality, icon)
    local names = AltInventoryDB.names
    local name = link and link:match("|h%[(.-)%]|h")
    if not name or name == "" then return end
    local entry = names[itemID]
    if not entry then
        names[itemID] = { n = name, q = quality, i = icon }
    else
        entry.n, entry.q, entry.i = name, quality or entry.q, icon or entry.i
    end
end
ns.NoteName = NoteName

-- ---------------------------------------------------------------------
-- Scanning
-- ---------------------------------------------------------------------

local function ScanContainer(bagID, target)
    local numSlots = C_Container.GetContainerNumSlots(bagID)
    if not numSlots or numSlots == 0 then return end
    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info and info.itemID then
            target[info.itemID] = (target[info.itemID] or 0) + (info.stackCount or 1)
            NoteName(info.itemID, info.hyperlink, info.quality, info.iconFileID)
        end
    end
end

function ns.GetCharKey()
    return UnitName("player") .. "-" .. GetNormalizedRealmName()
end

local function GetCharData()
    local key = ns.GetCharKey()
    local data = AltInventoryDB.chars[key]
    if not data then
        data = { class = select(2, UnitClass("player")), bags = {}, bank = {}, mail = {} }
        AltInventoryDB.chars[key] = data
    else
        data.class = select(2, UnitClass("player"))
        data.bags = data.bags or {}
        data.bank = data.bank or {}
        data.mail = data.mail or {}
    end
    return data
end

function ns.InitDB()
    AltInventoryDB = AltInventoryDB or {}
    AltInventoryDB.chars = AltInventoryDB.chars or {}
    AltInventoryDB.warband = AltInventoryDB.warband or {}
    AltInventoryDB.names = AltInventoryDB.names or {}
    AltInventoryDB.currencyNames = AltInventoryDB.currencyNames or {}
end

function ns.ScanBags()
    local data = GetCharData()
    wipe(data.bags)
    for _, bagID in ipairs(BAGS) do
        ScanContainer(bagID, data.bags)
    end
end

-- Banks only update while open, so each scan stamps when it happened and
-- the tooltip can say how old a bank count is.
function ns.ScanBank()
    local data = GetCharData()
    wipe(data.bank)
    for _, bagID in ipairs(BANK_BAGS) do
        ScanContainer(bagID, data.bank)
    end
    data.bankScannedAt = time()
end

function ns.ScanWarband()
    wipe(AltInventoryDB.warband)
    for _, bagID in ipairs(WARBAND_BAGS) do
        ScanContainer(bagID, AltInventoryDB.warband)
    end
    AltInventoryDB.warbandScannedAt = time()
end

-- The mailbox can only be read while it's open. Items still attached to
-- mail count; gold and letters don't.
function ns.ScanMail()
    if not GetInboxNumItems or not GetInboxItem then return end
    local data = GetCharData()
    wipe(data.mail)
    local attachments = ATTACHMENTS_MAX_RECEIVE or 16
    for i = 1, GetInboxNumItems() do
        for a = 1, attachments do
            local _, itemID, icon, count, quality = GetInboxItem(i, a)
            if itemID then
                data.mail[itemID] = (data.mail[itemID] or 0) + (count or 1)
                local link = GetInboxItemLink and GetInboxItemLink(i, a)
                NoteName(itemID, link, quality, icon)
            end
        end
    end
    data.mailScannedAt = time()
end

-- ---------------------------------------------------------------------
-- Gold and currencies
-- ---------------------------------------------------------------------

function ns.ScanMoney()
    GetCharData().money = GetMoney()
end

-- The Warband Bank's gold can be read without the bank open.
function ns.ScanWarbandMoney()
    if not (C_Bank and C_Bank.FetchDepositedMoney and Enum.BankType and Enum.BankType.Account) then return end
    local ok, money = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
    if ok and type(money) == "number" then
        AltInventoryDB.warbandMoney = money
        AltInventoryDB.warbandMoneyAt = time()
    end
end

local function CurrencyID(index, info)
    if info.currencyID then return info.currencyID end
    local link = C_CurrencyInfo.GetCurrencyListLink and C_CurrencyInfo.GetCurrencyListLink(index)
    return link and tonumber(link:match("currency:(%d+)"))
end

-- Only currencies each character keeps for itself that can be moved to
-- another character (the game's Transfer option): account-wide ones are
-- the same everywhere, and the rest can't be moved, so neither is worth a
-- per-character list.
function ns.IsTransferable(info)
    return info and not info.isHeader and info.isAccountTransferable and not info.isAccountWide
end

-- Collapsed headers hide their currencies from the list, so they're opened
-- for the scan and closed again after; left alone while the currency tab
-- is up, so it doesn't jump about under the mouse.
function ns.ScanCurrencies()
    local C = C_CurrencyInfo
    if not (C and C.GetCurrencyListSize and C.GetCurrencyListInfo) then return end
    local opened = {}
    if C.ExpandCurrencyList and not (TokenFrame and TokenFrame:IsVisible()) then
        local i = 1
        while i <= C.GetCurrencyListSize() do
            local info = C.GetCurrencyListInfo(i)
            if info and info.isHeader and not info.isHeaderExpanded then
                C.ExpandCurrencyList(i, true)
                opened[info.name] = true
            end
            i = i + 1
        end
    end
    local found = {}
    for index = 1, C.GetCurrencyListSize() do
        local info = C.GetCurrencyListInfo(index)
        if ns.IsTransferable(info) then
            local id = CurrencyID(index, info)
            if id then
                AltInventoryDB.currencyNames[id] = { n = info.name, i = info.iconFileID }
                if (info.quantity or 0) > 0 then found[id] = info.quantity end
            end
        end
    end
    for index = C.GetCurrencyListSize(), 1, -1 do
        local info = C.GetCurrencyListInfo(index)
        if info and info.isHeader and info.isHeaderExpanded and opened[info.name] then
            C.ExpandCurrencyList(index, false)
        end
    end
    GetCharData().currencies = found
end

-- 1234567 copper as "123g" with a gold icon, thousands separated.
function ns.GoldText(copper)
    local gold = math.floor((copper or 0) / 10000)
    local text = BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)
    return text .. "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
end

-- Characters with gold, most first, the total, and the Warband Bank's.
function ns.GoldList()
    local list, total = {}, 0
    for key, data in pairs(AltInventoryDB and AltInventoryDB.chars or {}) do
        if data.money then
            list[#list + 1] = { key = key, name = ns.ClassName(key, data.class), money = data.money }
            total = total + data.money
        end
    end
    table.sort(list, function(a, b) return a.money > b.money or (a.money == b.money and a.key < b.key) end)
    local warband = AltInventoryDB and AltInventoryDB.warbandMoney
    return list, total + (warband or 0), warband
end

-- ---------------------------------------------------------------------
-- Name upkeep
-- ---------------------------------------------------------------------

-- Every item ID held anywhere: { [itemID] = true }.
local function HeldItems()
    local held = {}
    for _, charData in pairs(AltInventoryDB.chars) do
        for _, place in ipairs(ns.PLACES) do
            for itemID in pairs(charData[place] or {}) do held[itemID] = true end
        end
    end
    for itemID in pairs(AltInventoryDB.warband) do held[itemID] = true end
    return held
end

-- Drops names of items nobody holds any more, and looks up names for items
-- saved before names were kept (a few at a time, so login doesn't stutter).
local LOOKUPS_PER_TICK = 20
function ns.TidyNames()
    local held = HeldItems()
    local names = AltInventoryDB.names
    for itemID in pairs(names) do
        if not held[itemID] then names[itemID] = nil end
    end
    if not (Item and Item.CreateFromItemID and C_Timer) then return end
    local missing = {}
    for itemID in pairs(held) do
        if not names[itemID] then missing[#missing + 1] = itemID end
    end
    if #missing == 0 then return end
    local index = 0
    local ticker
    ticker = C_Timer.NewTicker(0.2, function()
        for _ = 1, LOOKUPS_PER_TICK do
            index = index + 1
            local itemID = missing[index]
            if not itemID then ticker:Cancel(); return end
            local item = Item:CreateFromItemID(itemID)
            if not item:IsItemEmpty() then
                item:ContinueOnItemLoad(function()
                    NoteName(itemID, item:GetItemLink(), item:GetItemQuality(), item:GetItemIcon())
                end)
            end
        end
    end)
end

-- ---------------------------------------------------------------------
-- Ages
-- ---------------------------------------------------------------------

-- Counts under a day old are treated as current and get no age note.
local STALE_AFTER = 24 * 60 * 60

function ns.AgeText(scannedAt)
    if not scannedAt then return nil end
    local age = time() - scannedAt
    if age < STALE_AFTER then return nil end
    return math.floor(age / STALE_AFTER) .. "d ago"
end

function ns.WithAge(text, scannedAt)
    local age = ns.AgeText(scannedAt)
    if not age then return text end
    return text .. " |cff999999(" .. age .. ")|r"
end

function ns.ClassName(charKey, class)
    local name = charKey:match("^[^%-]+") or charKey
    local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if classColor then name = classColor:WrapTextInColorCode(name) end
    return name
end

-- One character's holding of an item as "Bags: 12, Bank: 20, Mail: 3",
-- with ages on bank and mail, and the total. places limits which count.
function ns.HoldingText(charData, itemID, places)
    local parts, total = {}, 0
    for _, place in ipairs(ns.PLACES) do
        if not places or places[place] then
            local count = charData[place] and charData[place][itemID] or 0
            if count > 0 then
                total = total + count
                local label = place == "bags" and "Bags" or place == "bank" and "Bank" or "Mail"
                local text = label .. ": " .. count
                if place ~= "bags" then text = ns.WithAge(text, charData[place .. "ScannedAt"]) end
                parts[#parts + 1] = text
            end
        end
    end
    return table.concat(parts, ", "), total
end
