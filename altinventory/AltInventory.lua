-- Alt Inventory
-- Tracks per-alt item counts (Bags, Character Bank, Mail, Warband Bank),
-- appends them to item tooltips, and searches them by name.
--   Core.lua               saved data and scanning
--   Tooltip.lua            the tooltip lines
--   Search.lua             finding items by name
--   UI/SearchWindow.lua    the search window and the bag button
-- This file: events and the slash command.

local _, ns = ...

local bankOpen = false

-- ---------------------------------------------------------------------
-- Slash command
--
--   /altinv              rescan now and list tracked characters
--   /altinv search       open the search window
--   /altinv find Text    open the search window searching for Text
--   /altinv remove Name  forget a character (Name or Name-Realm)
-- ---------------------------------------------------------------------

local PREFIX = "|cffffd100Alt Inventory:|r "

local function Print(msg)
    print(PREFIX .. msg)
end

local function ListCharacters()
    local keys = ns.Search.Characters()
    Print(#keys .. (#keys == 1 and " character" or " characters") .. " tracked.")
    for _, key in ipairs(keys) do
        local data = AltInventoryDB.chars[key]
        local name = key
        local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.class]
        if classColor then name = classColor:WrapTextInColorCode(key) end
        local bank = data.bankScannedAt and (ns.AgeText(data.bankScannedAt) or "today") or "never opened"
        local mail = data.mailScannedAt and (ns.AgeText(data.mailScannedAt) or "today") or "never opened"
        print("  " .. name .. "  |cff999999bank: " .. bank .. ", mail: " .. mail .. "|r")
    end
    local warband = AltInventoryDB.warbandScannedAt and (ns.AgeText(AltInventoryDB.warbandScannedAt) or "today") or "never opened"
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
    if key == ns.GetCharKey() then
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
    elseif cmd == "search" or cmd == "find" then
        ns.SearchWindow:Open(rest ~= "" and rest or nil)
    elseif cmd == "" or cmd == "scan" or cmd == "list" then
        ns.ScanBags()
        if bankOpen then
            ns.ScanBank()
            ns.ScanWarband()
        end
        ListCharacters()
    else
        Print("/altinv - rescan and list characters")
        Print("/altinv search - search all your characters")
        Print("/altinv find Name - search for an item")
        Print("/altinv remove Name - forget a character")
    end
end

-- ---------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------

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
SafeRegisterEvent("MAIL_SHOW")
SafeRegisterEvent("MAIL_INBOX_UPDATE")
SafeRegisterEvent("MAIL_CLOSED")

local mailOpen = false

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ns.InitDB()
        ns.ScanBags()
        ns.TidyNames()
        ns.SearchWindow:AddBagButton()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.ScanBags()
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Moving an item between bags and either bank only shows up here, so
        -- both banks are rescanned whenever they're open, not just on open.
        ns.ScanBags()
        if bankOpen then
            ns.ScanBank()
            ns.ScanWarband()
        end
        ns.SearchWindow:QueueRefresh()
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        ns.ScanBank()
        ns.ScanWarband()
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        if bankOpen then ns.ScanBank() end
    elseif event == "ACCOUNT_BANKING_ENABLED" or event == "BANK_TABS_CHANGED" then
        -- Bank tabs read as empty while the bank is closed, so scanning then
        -- would wipe the saved warband counts.
        if bankOpen then ns.ScanWarband() end
    elseif event == "MAIL_SHOW" then
        mailOpen = true
    elseif event == "MAIL_INBOX_UPDATE" then
        -- Taking an item out of a mail fires this too, so the mail count
        -- drops as the bags count rises. Only read while the mailbox is open:
        -- the inbox list is empty otherwise.
        if mailOpen then
            ns.ScanMail()
            ns.SearchWindow:QueueRefresh()
        end
    elseif event == "MAIL_CLOSED" then
        mailOpen = false
    end
end)
