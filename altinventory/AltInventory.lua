-- Alt Inventory
-- Tracks per-alt item counts (Bags, Character Bank, Mail, Warband Bank),
-- gold and transferable currencies, appends them to tooltips, and searches
-- them by name.
--   Core.lua               saved data and scanning
--   Tooltip.lua            the tooltip lines
--   Search.lua             finding items by name
--   Played.lua             time played per character
--   Characters.lua         bag space, item level, concentration, Moxie, cooldowns, this patch's currencies
--   UI/Skin.lua            the 2.0 look: colours, panels, buttons, lists
--   UI/SearchWindow.lua    the main window (title bar, tabs, status bar) and the bag button
--   UI/Pages/*.lua         its pages: Search (with the bag viewer), Characters, Play time, Watch lists
--   UI/ReagentFinder.lua   who else holds a recipe's materials, beside the profession window
--   UI/MinimapButton.lua   the minimap button and addon compartment entry
-- This file: events and the slash command.

local _, ns = ...

local bankOpen = false

-- Errors from the login steps, kept for /altinv debug. Each step runs on its
-- own so one failing can't stop the rest; the error still goes to the game's
-- error handler (and BugSack) as usual.
local loginErrors = {}
local function Try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        loginErrors[#loginErrors + 1] = label .. ": " .. tostring(err)
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(err) end
    end
end

-- ---------------------------------------------------------------------
-- Slash command
--
--   /altinv              rescan now and list tracked characters
--   /altinv search       open the search window
--   /altinv find Text    open the search window searching for Text
--   /altinv remove Name  forget a character (Name or Name-Realm), e.g. an old name after a rename
--   /altinv minimap      show or hide the minimap button
--   /altinv lumber       open the Lumber tab (Retail)
--   /altinv mail         list mail expiring in the next 3 days
--   /altinv debug        what the addon sees, to paste into a bug report
--   /altinv mailwarn     turn the login warning about expiring mail off or on
-- ---------------------------------------------------------------------

local PREFIX = "|cffffd100Alt Inventory:|r "

local function Print(msg)
    print(PREFIX .. msg)
end

-- Mail with items or gold expiring within 3 days, on any character, as of
-- the last time each one opened its mailbox.
local function ExpiringMailLines()
    local lines = {}
    for _, e in ipairs(ns.ExpiringMail()) do
        local what = e.items > 0 and (e.items .. (e.items == 1 and " item" or " items")) or nil
        if e.money > 0 and GetCoinTextureString then
            what = (what and (what .. " and ") or "") .. GetCoinTextureString(e.money)
        end
        lines[#lines + 1] = ("  %s: %d mail%s%s, first in %s"):format(
            ns.ClassName(e.key, AltInventoryDB.chars[e.key].class), e.count, e.count == 1 and "" or "s",
            what and (" (" .. what .. ")") or "", ns.TimeLeftText(e.soonest))
    end
    return lines
end

local function WarnExpiringMail(always)
    local lines = ExpiringMailLines()
    if #lines == 0 then
        if always then Print("No mail with items or gold expires in the next 3 days.") end
        return
    end
    Print("Mail expiring soon. Log in and open the mailbox to keep it:")
    for _, line in ipairs(lines) do print(line) end
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
        local gold = data.money and (ns.GoldText(data.money) .. "  ") or ""
        print("  " .. name .. "  " .. gold .. "|cff999999bank: " .. bank .. ", mail: " .. mail .. "|r")
    end
    if ns.HAS_WARBAND then
        local warband = AltInventoryDB.warbandScannedAt and (ns.AgeText(AltInventoryDB.warbandScannedAt) or "today") or "never opened"
        local warbandGold = AltInventoryDB.warbandMoney and (ns.GoldText(AltInventoryDB.warbandMoney) .. "  ") or ""
        print("  |cff99ccffWarband Bank|r  " .. warbandGold .. "|cff999999" .. warband .. "|r")
    end
    local _, total = ns.GoldList()
    Print("Gold on all characters: " .. ns.GoldText(total))
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
            Print("More than one " .. input .. ", use their full name or Name-Realm.")
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
    AltInventoryDB.collapsed[key] = nil
    Print("Removed " .. key .. ".")
end

-- Everything useful for a bug report, in one chat block.
local function Debug()
    local function Show(v)
        if issecretvalue and issecretvalue(v) then return "(secret)" end
        if v == nil then return "nil" end
        return '"' .. tostring(v) .. '"'
    end
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("AltInventory", "Version")
        or (GetAddOnMetadata and GetAddOnMetadata("AltInventory", "Version")) or "?"
    local gameVersion, build, _, interface = GetBuildInfo()
    Print(("debug: version %s, game %s (%s), interface %s, project %s"):format(
        tostring(version), tostring(gameVersion), tostring(build), tostring(interface), tostring(WOW_PROJECT_ID)))
    local name, second = UnitName("player")
    Print(("debug: name %s %s, realm %s, normalized %s"):format(Show(name), Show(second),
        Show(GetRealmName()), Show(GetNormalizedRealmName and GetNormalizedRealmName())))
    local key = ns.GetCharKey()
    local db = AltInventoryDB
    local chars = type(db) == "table" and type(db.chars) == "table" and db.chars or nil
    local count = 0
    if chars then for _ in pairs(chars) do count = count + 1 end end
    local mine = chars and key and chars[key]
    local items = 0
    if mine and mine.bags then for _ in pairs(mine.bags) do items = items + 1 end end
    Print(("debug: key %s, saved data %s, characters %d, this one saved %s, different items in its bags %d"):format(
        Show(key), type(db), count, mine and "yes" or "no", items))
    if #loginErrors == 0 then
        Print("debug: no errors at login")
    else
        for _, err in ipairs(loginErrors) do Print("debug: error " .. err) end
    end
end

SLASH_ALTINVENTORY1 = "/altinv"
SlashCmdList.ALTINVENTORY = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "remove" then
        RemoveCharacter(rest)
    elseif cmd == "search" or cmd == "find" then
        ns.SearchWindow:Open(rest ~= "" and rest or nil)
    elseif cmd == "characters" or cmd == "chars" then
        ns.SearchWindow:Open()
        ns.SearchWindow:SetView("characters")
    elseif cmd == "watch" then
        ns.SearchWindow:Open()
        ns.SearchWindow:SetView("watch")
    elseif cmd == "lumber" and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
        ns.SearchWindow:Open()
        ns.SearchWindow:SetView("watch", "lumber")
    elseif cmd == "debug" then
        Debug()
    elseif cmd == "mail" then
        WarnExpiringMail(true)
    elseif cmd == "mailwarn" then
        AltInventoryDB.mailWarnOff = not AltInventoryDB.mailWarnOff or nil
        Print(AltInventoryDB.mailWarnOff and "Expiring mail warning on login off. /altinv mail still lists it."
            or "Expiring mail warning on login on.")
    elseif cmd == "reagents" then
        Print(ns.ReagentFinder:Toggle() and "Reagent finder on, beside the profession window." or "Reagent finder off.")
    elseif cmd == "minimap" then
        if ns.MinimapButton:Toggle() then
            Print("Minimap button shown.")
        else
            Print("Minimap button hidden. The addon list button on the minimap still opens the search, or type /altinv minimap to bring it back.")
        end
    elseif cmd == "" or cmd == "scan" or cmd == "list" then
        ns.ScanBags()
        ns.ScanMoney()
        ns.ScanWarbandMoney()
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
        Print("/altinv characters - gold, item level, bag space and last played for every character")
        Print("/altinv watch - your watch lists, plus consumables and trade goods")
        if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
            Print("/altinv lumber - lumber and Essence of Lumber on every character")
        end
        Print("/altinv mail - mail with items or gold expiring in the next 3 days")
        Print("/altinv mailwarn - turn the expiring mail warning on login off or on")
        Print("/altinv reagents - turn the reagent finder off or on")
        Print("/altinv minimap - show or hide the minimap button")
        Print("/altinv debug - what the addon sees, to paste into a bug report")
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
SafeRegisterEvent("PLAYER_MONEY")
SafeRegisterEvent("ACCOUNT_MONEY")
SafeRegisterEvent("CURRENCY_DISPLAY_UPDATE")
SafeRegisterEvent("PLAYER_REGEN_ENABLED")
SafeRegisterEvent("TIME_PLAYED_MSG")
SafeRegisterEvent("PLAYER_LOGOUT")
SafeRegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
SafeRegisterEvent("PLAYER_EQUIPMENT_CHANGED")
SafeRegisterEvent("TRADE_SKILL_SHOW")
SafeRegisterEvent("TRADE_SKILL_LIST_UPDATE")

local mailOpen = false
local professionScannedAt = 0

-- Currency updates come in bursts (looting, quest turn-ins), so the list
-- is read once things settle, and never in combat.
-- Opening and closing headers for the scan fires updates of its own, so
-- those are ignored for a moment after each scan.
local currencyPending, scannedAt = false, 0
local function QueueCurrencyScan()
    if currencyPending or GetTime() - scannedAt < 3 then return end
    currencyPending = true
    C_Timer.After(2, function()
        if InCombatLockdown() then return end -- PLAYER_REGEN_ENABLED picks it up
        currencyPending = false
        ns.ScanCurrencies()
        ns.Characters.ScanMoxie()
        ns.Characters.ScanConcentration()
        scannedAt = GetTime()
        ns.SearchWindow:QueueRefresh()
    end)
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        Try("saved data", ns.InitDB)
        Try("bags", ns.ScanBags)
        Try("item names", ns.TidyNames)
        Try("last played", ns.NoteSeen)
        Try("bag button", ns.SearchWindow.AddBagButton, ns.SearchWindow)
        Try("minimap button", ns.MinimapButton.Create, ns.MinimapButton)
        Try("gold", ns.ScanMoney)
        Try("warband gold", ns.ScanWarbandMoney)
        Try("reagent finder", ns.ReagentFinder.Init, ns.ReagentFinder)
        -- The currency list fills in a moment after login.
        QueueCurrencyScan()
        C_Timer.After(3, function() Try("characters", ns.Characters.ScanAll) end)
        Try("play time", ns.Played.Note, ns.Played)
        -- After other addons' login requests, so the answer is ours.
        C_Timer.After(6, function() ns.Played:Request(true) end)
        -- Once login chat has settled.
        if not AltInventoryDB.mailWarnOff then C_Timer.After(8, function() WarnExpiringMail(false) end) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.ScanBags()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        ns.Characters.ScanItemLevel()
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
        -- The list update fires in bursts, and this reads every recipe.
        if not InCombatLockdown() and GetTime() - professionScannedAt > 5 then
            professionScannedAt = GetTime()
            ns.Characters.ScanOpenProfession()
            ns.SearchWindow:QueueRefresh()
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Moving an item between bags and either bank only shows up here, so
        -- both banks are rescanned whenever they're open, not just on open.
        ns.ScanBags()
        ns.Characters.ScanBagSpace()
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
    elseif event == "TIME_PLAYED_MSG" then
        ns.Played:OnTimePlayed(...)
        ns.SearchWindow:QueueRefresh()
    elseif event == "PLAYER_LOGOUT" then
        ns.NoteSeen()
        ns.Played:Save()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit == nil or unit == "player" then ns.Played:Note() end
    elseif event == "PLAYER_MONEY" then
        ns.ScanMoney()
    elseif event == "ACCOUNT_MONEY" then
        ns.ScanWarbandMoney()
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        QueueCurrencyScan()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if currencyPending then
            currencyPending = false
            QueueCurrencyScan()
        end
    end
end)
