-- Alt Inventory - saved data and scanning.
--
-- Counts per character (bags, bank, mail) and for the warband bank, plus a
-- name for every item held, so the search window can find items by name:
--
--   AltInventoryDB = {
--     chars = { ["Name-Realm"] = { class, bags = { [itemID] = count },
--                                  bank = {...}, bankScannedAt,
--                                  mail = {...}, mailScannedAt } },
--     warband = { [itemID] = count }, warbandScannedAt,
--     names = { [itemID] = { n = name, q = quality, i = icon } },
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
