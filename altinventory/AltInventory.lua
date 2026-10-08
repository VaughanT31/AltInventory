-- Alt Inventory
-- Tracks per-alt item counts (Bags, Character Bank, Warband Bank) and
-- appends them to item tooltips. See project-guideline.md for scope.

local ADDON_NAME = ...

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
        end
    end
end

local function GetCharKey()
    return UnitName("player") .. "-" .. GetNormalizedRealmName()
end

local function GetCharData()
    local key = GetCharKey()
    local data = AltInventoryDB.chars[key]
    if not data then
        data = { class = select(2, UnitClass("player")), bags = {}, bank = {} }
        AltInventoryDB.chars[key] = data
    else
        data.class = select(2, UnitClass("player"))
        data.bags = data.bags or {}
        data.bank = data.bank or {}
    end
    return data
end

local function InitDB()
    AltInventoryDB = AltInventoryDB or {}
    AltInventoryDB.chars = AltInventoryDB.chars or {}
    AltInventoryDB.warband = AltInventoryDB.warband or {}
end

local function ScanBags()
    local data = GetCharData()
    wipe(data.bags)
    for _, bagID in ipairs(BAGS) do
        ScanContainer(bagID, data.bags)
    end
end

-- Banks only update while open, so each scan stamps when it happened and
-- the tooltip can say how old a bank count is.
local function ScanBank()
    local data = GetCharData()
    wipe(data.bank)
    for _, bagID in ipairs(BANK_BAGS) do
        ScanContainer(bagID, data.bank)
    end
    data.bankScannedAt = time()
end

local function ScanWarband()
    wipe(AltInventoryDB.warband)
    for _, bagID in ipairs(WARBAND_BAGS) do
        ScanContainer(bagID, AltInventoryDB.warband)
    end
    AltInventoryDB.warbandScannedAt = time()
end

-- Counts under a day old are treated as current and get no age note.
local STALE_AFTER = 24 * 60 * 60

local function AgeText(scannedAt)
    if not scannedAt then return nil end
    local age = time() - scannedAt
    if age < STALE_AFTER then return nil end
    return math.floor(age / STALE_AFTER) .. "d ago"
end

local function WithAge(text, scannedAt)
    local age = AgeText(scannedAt)
    if not age then return text end
    return text .. " |cff999999(" .. age .. ")|r"
end

-- ---------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------

local function OnTooltipSetItem(tooltip, tooltipData)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if not AltInventoryDB then return end

    local itemID = tooltipData and tooltipData.id
    if not itemID then
        local _, link = tooltip:GetItem()
        if link then
            itemID = tonumber(link:match("item:(%d+)"))
        end
    end
    if not itemID then return end

    local lines = {}
    local total = 0

    for charKey, charData in pairs(AltInventoryDB.chars) do
        local bags = (charData.bags and charData.bags[itemID]) or 0
        local bank = (charData.bank and charData.bank[itemID]) or 0
        local sum = bags + bank
        if sum > 0 then
            total = total + sum

            local parts = {}
            if bags > 0 then table.insert(parts, "Bags: " .. bags) end
            if bank > 0 then table.insert(parts, WithAge("Bank: " .. bank, charData.bankScannedAt)) end

            local name = charKey:match("^[^%-]+") or charKey
            local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[charData.class]
            if classColor then
                name = classColor:WrapTextInColorCode(name)
            end

            table.insert(lines, { name = name, text = table.concat(parts, ", ") })
        end
    end

    local warbandCount = (AltInventoryDB.warband and AltInventoryDB.warband[itemID]) or 0
    total = total + warbandCount

    if total == 0 then return end

    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("Alt Inventory", "Total: " .. total, 1, 0.82, 0, 1, 0.82, 0)
    for _, line in ipairs(lines) do
        tooltip:AddDoubleLine(line.name, line.text, 1, 1, 1, 0.8, 0.8, 0.8)
    end
    if warbandCount > 0 then
        tooltip:AddDoubleLine("Warband Bank", WithAge(tostring(warbandCount), AltInventoryDB.warbandScannedAt), 0.6, 0.8, 1, 0.8, 0.8, 0.8)
    end
    tooltip:Show()
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)

-- ---------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------

local bankOpen = false

-- ---------------------------------------------------------------------
-- Slash command
--
--   /altinv              rescan now and list tracked characters
--   /altinv remove Name  forget a character (Name or Name-Realm)
-- ---------------------------------------------------------------------

local PREFIX = "|cffffd100Alt Inventory:|r "

local function Print(msg)
    print(PREFIX .. msg)
end

local function ListCharacters()
    local keys = {}
    for key in pairs(AltInventoryDB.chars) do table.insert(keys, key) end
    table.sort(keys)

    Print(#keys .. (#keys == 1 and " character" or " characters") .. " tracked.")
    for _, key in ipairs(keys) do
        local data = AltInventoryDB.chars[key]
        local name = key
        local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.class]
        if classColor then name = classColor:WrapTextInColorCode(key) end
        local bank = data.bankScannedAt and (AgeText(data.bankScannedAt) or "today") or "never opened"
        print("  " .. name .. "  |cff999999bank: " .. bank .. "|r")
    end
    local warband = AltInventoryDB.warbandScannedAt and (AgeText(AltInventoryDB.warbandScannedAt) or "today") or "never opened"
    print("  |cff99ccffWarband Bank|r  |cff999999" .. warband .. "|r")
end

-- Matches "Name-Realm" exactly, or a bare "Name" when only one realm has it.
local function FindCharacter(input)
    local wanted = input:lower()
    local matches = {}
    for key in pairs(AltInventoryDB.chars) do
        local lower = key:lower()
        if lower == wanted then return key end
        if (lower:match("^[^%-]+") or lower) == wanted then table.insert(matches, key) end
    end
    if #matches == 1 then return matches[1] end
    return nil, #matches
end

local function RemoveCharacter(input)
    if input == "" then
        Print("Usage: /altinv remove Name or Name-Realm")
        return
    end
    local key, matchCount = FindCharacter(input)
    if not key then
        if matchCount and matchCount > 1 then
            Print("More than one " .. input .. ", use Name-Realm.")
        else
            Print("No tracked character called " .. input .. ".")
        end
        return
    end
    if key == GetCharKey() then
        Print("That's the character you're on, it would be added straight back.")
        return
    end
    AltInventoryDB.chars[key] = nil
    Print("Removed " .. key .. ".")
end

SLASH_ALTINVENTORY1 = "/altinv"
SlashCmdList.ALTINVENTORY = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "remove" then
        RemoveCharacter(rest)
    elseif cmd == "" or cmd == "scan" or cmd == "list" then
        ScanBags()
        if bankOpen then
            ScanBank()
            ScanWarband()
        end
        ListCharacters()
    else
        Print("/altinv - rescan and list characters")
        Print("/altinv remove Name - forget a character")
    end
end

local frame = CreateFrame("Frame")

local function SafeRegisterEvent(event)
    pcall(frame.RegisterEvent, frame, event)
end

SafeRegisterEvent("PLAYER_LOGIN")
SafeRegisterEvent("PLAYER_ENTERING_WORLD")
SafeRegisterEvent("BAG_UPDATE_DELAYED")
SafeRegisterEvent("BANKFRAME_OPENED")
SafeRegisterEvent("BANKFRAME_CLOSED")
SafeRegisterEvent("PLAYERBANKSLOTS_CHANGED")
SafeRegisterEvent("ACCOUNT_BANKING_ENABLED")
SafeRegisterEvent("BANK_TABS_CHANGED")

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        InitDB()
        ScanBags()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ScanBags()
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Moving an item between bags and either bank only shows up here, so
        -- both banks are rescanned whenever they're open, not just on open.
        ScanBags()
        if bankOpen then
            ScanBank()
            ScanWarband()
        end
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        ScanBank()
        ScanWarband()
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        if bankOpen then ScanBank() end
    elseif event == "ACCOUNT_BANKING_ENABLED" or event == "BANK_TABS_CHANGED" then
        -- Bank tabs read as empty while the bank is closed, so scanning then
        -- would wipe the saved warband counts.
        if bankOpen then ScanWarband() end
    end
end)
