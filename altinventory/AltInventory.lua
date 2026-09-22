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

local BANK_BAGS = BuildBagList({
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

local function ScanBank()
    local data = GetCharData()
    wipe(data.bank)
    for _, bagID in ipairs(BANK_BAGS) do
        ScanContainer(bagID, data.bank)
    end
end

local function ScanWarband()
    wipe(AltInventoryDB.warband)
    for _, bagID in ipairs(WARBAND_BAGS) do
        ScanContainer(bagID, AltInventoryDB.warband)
    end
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
            if bank > 0 then table.insert(parts, "Bank: " .. bank) end

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
        tooltip:AddDoubleLine("Warband Bank", tostring(warbandCount), 0.6, 0.8, 1, 0.8, 0.8, 0.8)
    end
    tooltip:Show()
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)

-- ---------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------

local bankOpen = false

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
        ScanBags()
        if bankOpen then ScanBank() end
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        ScanBank()
        ScanWarband()
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        if bankOpen then ScanBank() end
    elseif event == "ACCOUNT_BANKING_ENABLED" or event == "BANK_TABS_CHANGED" then
        ScanWarband()
    end
end)
