-- Alt Inventory - Search page (2.0): characters down the left, results as
-- cards on the right. Clicking a character swaps the results for that
-- character's bag viewer: their bags, bank, mail and the warband bank as
-- icon grids, from what was saved the last time each was read.

local _, ns = ...
local Skin = ns.Skin
local C = Skin.C
local Window = ns.SearchWindow

local SIDE_WIDTH = 210
local CARD_GAP = 8
local HOLDERS_PER_LINE = 3
local GRID_COLUMNS, CELL, CELL_GAP = 12, 40, 6
local MAX_SEGMENTS = 8

local Page = { key = "search", label = "Search", order = 1 }
local filters = { char = nil, place = nil, sort = "name" }
local selected        -- character key shown in the bag viewer, or nil for results
local bagPlace = "bags"

local PLACES = {
    { key = nil, label = "All places" },
    { key = "bags", label = "Bags" },
    { key = "bank", label = "Bank" },
    { key = "mail", label = "Mail" },
    { key = "warband", label = "Warband", warband = true },
    { key = "currency", label = "Currencies" },
}

local function Realm(key) return key:match("%-(.+)$") or "" end
local function Short(key) return key:match("^[^%-]+") or key end
local function Number(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

-- ---------------------------------------------------------------------
-- Character column
-- ---------------------------------------------------------------------

local SIDE_ROWS = { all = 34, realm = 26, char = 28 }

local function CharacterRows()
    local me = ns.GetCharKey()
    local myRealm = me and Realm(me)
    local byRealm, realms = {}, {}
    local count = 0
    for key, data in pairs(AltInventoryDB.chars) do
        local realm = Realm(key)
        if not byRealm[realm] then byRealm[realm] = {}; realms[#realms + 1] = realm end
        local list = byRealm[realm]
        list[#list + 1] = { key = key, data = data }
        count = count + 1
    end
    table.sort(realms, function(a, b)
        if (a == myRealm) ~= (b == myRealm) then return a == myRealm end
        return a < b
    end)
    local rows = { { kind = "all", count = count } }
    for _, realm in ipairs(realms) do
        rows[#rows + 1] = { kind = "realm", realm = realm }
        local list = byRealm[realm]
        table.sort(list, function(a, b)
            local la, lb = a.data.ilvl or 0, b.data.ilvl or 0
            if la ~= lb then return la > lb end
            return a.key < b.key
        end)
        for _, entry in ipairs(list) do rows[#rows + 1] = { kind = "char", key = entry.key, data = entry.data } end
    end
    return rows
end

local function InitSideRow(row, data)
    if not row.label then
        row.bg = Skin.Fill(row, C.selected, "BACKGROUND")
        row.bg:SetPoint("TOPLEFT", 0, -1)
        row.bg:SetPoint("BOTTOMRIGHT", 0, 1)
        row.hover = row:CreateTexture(nil, "HIGHLIGHT")
        row.hover:SetAllPoints(row.bg)
        row.hover:SetColorTexture(1, 1, 1, 0.04)
        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetSize(7, 7)
        row.dot:SetPoint("LEFT", 10, 0)
        row.label = Skin.Text(row, 12, C.text)
        row.right = Skin.Text(row, 11, C.dim)
        row.right:SetPoint("RIGHT", -10, 0)
        row.right:SetJustifyH("RIGHT")
    end
    row.label:ClearAllPoints()
    row.dot:Hide()
    row.right:SetText("")
    row.bg:Hide()
    row:SetScript("OnClick", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    if data.kind == "all" then
        row.label:SetPoint("LEFT", 10, 0)
        row.label:SetText("All characters")
        Skin.SetColor(row.label, selected and C.muted or C.text)
        row.right:SetText(data.count)
        row.bg:SetShown(selected == nil)
        row:SetScript("OnClick", function() Page:Select(nil) end)
    elseif data.kind == "realm" then
        row.label:SetPoint("BOTTOMLEFT", 10, 4)
        row.label:SetText(Skin.Code(C.dim) .. data.realm:upper() .. "|r")
    else
        local color = Skin.ClassColor(data.data.class)
        row.dot:Show()
        row.dot:SetColorTexture(color[1], color[2], color[3], 1)
        row.label:SetPoint("LEFT", row.dot, "RIGHT", 8, 0)
        row.label:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row.label:SetText(Short(data.key))
        Skin.SetColor(row.label, color)
        row.right:SetText(Skin.ItemLevel(data.data.ilvl))
        row.bg:SetShown(selected == data.key)
        row:SetScript("OnClick", function() Page:Select(data.key) end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(data.key, color[1], color[2], color[3])
            GameTooltip:AddLine("Click to see their bags, bank and mail.", 1, 1, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
end

-- ---------------------------------------------------------------------
-- Result cards
-- ---------------------------------------------------------------------

local function HolderParts(result)
    local parts = {}
    for _, holder in ipairs(result.holders) do
        local data = AltInventoryDB.chars[holder.key]
        local color = Skin.ClassColor(data and data.class)
        parts[#parts + 1] = { name = Short(holder.key), color = color, text = holder.text, count = holder.count or 0 }
    end
    if (result.warband or 0) > 0 then
        parts[#parts + 1] = { name = "Warband", color = C.warband,
            text = ns.WithAge(tostring(result.warband), AltInventoryDB.warbandScannedAt), count = result.warband }
    end
    return parts
end

local function CardExtent(data)
    local lines = math.max(1, math.ceil(#data.parts / HOLDERS_PER_LINE))
    return 70 + 16 * lines + CARD_GAP
end

local function InitCard(row, data)
    if not row.card then
        row.card = Skin.Frame(row, C.bar, C.lineSoft, "Button")
        row.card:SetPoint("TOPLEFT")
        row.card:SetPoint("TOPRIGHT")
        Skin.ItemScripts(row.card)
        row.card.icon = Skin.ItemIcon(row.card, 34)
        row.card.icon:SetPoint("TOPLEFT", 10, -10)
        row.card.icon:EnableMouse(false)
        row.card.name = Skin.Text(row.card, 13, C.text)
        row.card.name:SetPoint("TOPLEFT", row.card.icon, "TOPRIGHT", 10, -2)
        row.card.sub = Skin.Text(row.card, 11, C.dim)
        row.card.sub:SetPoint("TOPLEFT", row.card.name, "BOTTOMLEFT", 0, -4)
        row.card.total = Skin.Text(row.card, 17, C.text)
        row.card.total:SetPoint("TOPRIGHT", -12, -10)
        row.card.totalLabel = Skin.Text(row.card, 10, C.dim)
        row.card.totalLabel:SetPoint("TOPRIGHT", row.card.total, "BOTTOMRIGHT", 0, -2)
        row.card.totalLabel:SetText("total")
        row.card.name:SetPoint("RIGHT", row.card.total, "LEFT", -10, 0)
        row.card.track = Skin.Fill(row.card, C.deep, "ARTWORK")
        row.card.track:SetHeight(5)
        row.card.track:SetPoint("TOPLEFT", 10, -54)
        row.card.track:SetPoint("TOPRIGHT", -10, -54)
        row.card.segments = {}
        for i = 1, MAX_SEGMENTS do
            local seg = row.card:CreateTexture(nil, "OVERLAY")
            seg:SetHeight(5)
            row.card.segments[i] = seg
        end
        row.card.lines = {}
    end
    local card, result = row.card, data.result
    card:SetHeight(CardExtent(data) - CARD_GAP)
    card.itemID, card.currencyID = result.itemID, result.currencyID
    card.icon:SetItem(result.icon, result.quality)
    card.name:SetText(result.name or "?")
    Skin.SetColor(card.name, result.currencyID and C.gold or Skin.QualityColor(result.quality))
    local n = #result.holders
    card.sub:SetText(result.currencyID and "Currency" or
        (n == 0 and "Warband bank" or (n .. (n == 1 and " character" or " characters") .. ((result.warband or 0) > 0 and " and the warband bank" or ""))))
    card.total:SetText(Number(result.total or 0))

    -- The bar: one segment per holder, most first.
    local sorted = {}
    for _, part in ipairs(data.parts) do sorted[#sorted + 1] = part end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    local width = math.max(1, card:GetWidth() - 20)
    local x, total = 0, math.max(1, result.total or 1)
    for i, seg in ipairs(card.segments) do
        local part = sorted[i]
        if part and part.count > 0 then
            local w = math.max(2, width * part.count / total - 2)
            seg:ClearAllPoints()
            seg:SetPoint("LEFT", card.track, "LEFT", x, 0)
            seg:SetWidth(w)
            seg:SetColorTexture(part.color[1], part.color[2], part.color[3], 1)
            seg:Show()
            x = x + w + 2
        else
            seg:Hide()
        end
    end

    -- Holders, three to a line.
    local lineCount = math.max(1, math.ceil(#data.parts / HOLDERS_PER_LINE))
    for i = 1, math.max(lineCount, #card.lines) do
        local fs = card.lines[i]
        if not fs then
            fs = Skin.Text(card, 12, C.muted)
            fs:SetPoint("TOPLEFT", 10, -66 - (i - 1) * 16)
            fs:SetPoint("RIGHT", -10, 0)
            card.lines[i] = fs
        end
        if i <= lineCount then
            local bits = {}
            for j = (i - 1) * HOLDERS_PER_LINE + 1, math.min(#data.parts, i * HOLDERS_PER_LINE) do
                local part = data.parts[j]
                bits[#bits + 1] = Skin.Code(part.color) .. part.name .. "|r " .. part.text
            end
            fs:SetText(table.concat(bits, "      "))
            fs:Show()
        else
            fs:Hide()
        end
    end
end

-- ---------------------------------------------------------------------
-- Bag viewer
-- ---------------------------------------------------------------------

local function PlaceItems(key, place)
    local counts
    if place == "warband" then
        counts = AltInventoryDB.warband or {}
    else
        local data = AltInventoryDB.chars[key]
        counts = data and data[place] or {}
    end
    local items = {}
    for itemID, count in pairs(counts) do
        local name = AltInventoryDB.names and AltInventoryDB.names[itemID]
        items[#items + 1] = { itemID = itemID, count = count, name = name and name.n or "", quality = name and name.q or 1, icon = name and name.i }
    end
    table.sort(items, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.name < b.name
    end)
    local rows = {}
    for i = 1, #items, GRID_COLUMNS do
        local row = {}
        for j = i, math.min(#items, i + GRID_COLUMNS - 1) do row[#row + 1] = items[j] end
        rows[#rows + 1] = { items = row }
    end
    return rows, #items
end

local function InitGridRow(row, data)
    row.cells = row.cells or {}
    for i = 1, GRID_COLUMNS do
        local cell = row.cells[i]
        if not cell then
            cell = Skin.ItemIcon(row, CELL)
            cell:SetPoint("TOPLEFT", (i - 1) * (CELL + CELL_GAP), 0)
            Skin.ItemScripts(cell)
            row.cells[i] = cell
        end
        local item = data.items[i]
        if item then
            cell.itemID = item.itemID
            cell:SetItem(item.icon, item.quality, item.count)
            cell:Show()
        else
            cell.itemID = nil
            cell:Hide()
        end
    end
end

-- ---------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------

function Page:Build(frame)
    -- Left column.
    local side = Skin.Frame(frame, C.side)
    side:SetPoint("TOPLEFT")
    side:SetPoint("BOTTOMLEFT")
    side:SetWidth(SIDE_WIDTH)
    local sideLine = Skin.Fill(side, C.line, "BORDER")
    sideLine:SetWidth(1)
    sideLine:SetPoint("TOPRIGHT")
    sideLine:SetPoint("BOTTOMRIGHT")
    self.sideList = Skin.List(side, function(data) return SIDE_ROWS[data.kind] end, InitSideRow)
    self.sideList:SetPoint("TOPLEFT", 8, -10)
    self.sideList:SetPoint("BOTTOMRIGHT", -20, 10)

    local main = CreateFrame("Frame", nil, frame)
    main:SetPoint("TOPLEFT", side, "TOPRIGHT", 16, -14)
    main:SetPoint("BOTTOMRIGHT", -16, 12)
    self.main = main

    -- Results view.
    local results = CreateFrame("Frame", nil, main)
    results:SetAllPoints()
    self.results = results

    local search = Skin.SearchBox(results)
    search:SetPoint("TOPLEFT")
    search:SetPoint("TOPRIGHT")
    search:SetHint("Search every character: type part of a name, or drop an item here")
    search.box:HookScript("OnTextChanged", function() Window:QueueRefresh() end)
    search.box:HookScript("OnReceiveDrag", function(box)
        local kind, itemID = GetCursorInfo()
        if kind == "item" and itemID then box:SetText(tostring(itemID)); ClearCursor() end
    end)
    search:SetScript("OnReceiveDrag", function() search.box:GetScript("OnReceiveDrag")(search.box) end)
    self.search = search

    self.placeButtons = {}
    local previous
    for _, place in ipairs(PLACES) do
        if not place.warband or ns.HAS_WARBAND then
            local b = Skin.Button(results, place.label, nil, 24, true)
            if previous then b:SetPoint("LEFT", previous, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -10) end
            b:SetScript("OnClick", function()
                filters.place = place.key
                Page:Refresh()
            end)
            b.place = place.key
            self.placeButtons[#self.placeButtons + 1] = b
            previous = b
        end
    end
    local sort = Skin.Button(results, "Sort: name", 110, 24)
    sort:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -10)
    sort:SetScript("OnClick", function()
        filters.sort = filters.sort == "name" and "total" or "name"
        Page:Refresh()
    end)
    self.sort = sort

    self.list = Skin.List(results, CardExtent, InitCard)
    self.list:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -46)
    self.list:SetPoint("BOTTOMRIGHT", -14, 0)
    self.empty = Skin.Text(results, 13, C.dim)
    self.empty:SetPoint("TOPLEFT", self.list, "TOPLEFT", 10, -30)
    self.empty:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", -10, -30)
    self.empty:SetJustifyH("CENTER")
    self.empty:SetWordWrap(true)

    -- Bag viewer.
    local viewer = CreateFrame("Frame", nil, main)
    viewer:SetAllPoints()
    viewer:Hide()
    self.viewer = viewer
    viewer.badge = Skin.Frame(viewer, C.deep, C.line)
    viewer.badge:SetSize(40, 40)
    viewer.badge:SetPoint("TOPLEFT")
    viewer.badgeIcon = viewer.badge:CreateTexture(nil, "ARTWORK")
    viewer.badgeIcon:SetPoint("TOPLEFT", 2, -2)
    viewer.badgeIcon:SetPoint("BOTTOMRIGHT", -2, 2)
    viewer.name = Skin.Text(viewer, 16, C.text)
    viewer.name:SetPoint("TOPLEFT", viewer.badge, "TOPRIGHT", 12, -3)
    viewer.sub = Skin.Text(viewer, 11, C.dim)
    viewer.sub:SetPoint("TOPLEFT", viewer.name, "BOTTOMLEFT", 0, -5)
    viewer.gold = Skin.Text(viewer, 15, C.gold)
    viewer.gold:SetPoint("TOPRIGHT", 0, -4)
    viewer.goldLabel = Skin.Text(viewer, 10, C.dim)
    viewer.goldLabel:SetPoint("TOPRIGHT", viewer.gold, "BOTTOMRIGHT", 0, -3)
    viewer.goldLabel:SetText("on this character")

    viewer.tabs = {}
    local prevTab
    for _, place in ipairs({ "bags", "bank", "mail", "warband" }) do
        if place ~= "warband" or ns.HAS_WARBAND then
            local tab = Skin.Button(viewer, place, nil, 26)
            if prevTab then tab:SetPoint("LEFT", prevTab, "RIGHT", 4, 0) else tab:SetPoint("TOPLEFT", viewer.badge, "BOTTOMLEFT", 0, -14) end
            tab:SetScript("OnClick", function() bagPlace = place; Page:Refresh() end)
            viewer.tabs[place] = tab
            prevTab = tab
        end
    end
    viewer.grid = Skin.List(viewer, CELL + CELL_GAP, InitGridRow, "Frame")
    viewer.grid:SetPoint("TOPLEFT", viewer.badge, "BOTTOMLEFT", 0, -52)
    viewer.grid:SetPoint("BOTTOMRIGHT", -14, 0)
    viewer.empty = Skin.Text(viewer, 13, C.dim)
    viewer.empty:SetPoint("TOPLEFT", viewer.grid, "TOPLEFT", 0, -20)
    viewer.empty:SetPoint("TOPRIGHT", viewer.grid, "TOPRIGHT", 0, -20)
    viewer.empty:SetJustifyH("CENTER")
    viewer.empty:SetWordWrap(true)
end

function Page:Select(key)
    selected = key
    if key then bagPlace = "bags" end
    self:Refresh()
end

-- arg: { text = "..." } to search, { character = key } for the bag viewer.
function Page:Show(arg)
    if type(arg) == "table" and arg.character then
        selected = arg.character
        bagPlace = "bags"
    elseif type(arg) == "table" and arg.text then
        selected = nil
        self.search.box:SetText(arg.text)
    end
    if not selected then self.search.box:SetFocus() end
end

local function AgeOrToday(at)
    return at and (ns.AgeText(at) or "today") or "never"
end

function Page:RefreshViewer()
    local viewer, key = self.viewer, selected
    local data = AltInventoryDB.chars[key]
    if not data then selected = nil; return self:RefreshResults() end
    local color = Skin.ClassColor(data.class)
    viewer.badge:SetBackdropBorderColor(color[1], color[2], color[3], 1)
    local coords = data.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[data.class]
    if coords then
        viewer.badgeIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        viewer.badgeIcon:SetTexCoord(unpack(coords))
    else
        viewer.badgeIcon:SetTexture(nil)
    end
    viewer.name:SetText(Short(key))
    Skin.SetColor(viewer.name, color)
    local className = data.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[data.class] or ""
    local bits = { className, Realm(key) }
    if data.ilvl then bits[#bits + 1] = "item level " .. Skin.ItemLevel(data.ilvl) end
    if data.seenAt then bits[#bits + 1] = "last on " .. AgeOrToday(data.seenAt) end
    viewer.sub:SetText(table.concat(bits, "  -  "))
    viewer.gold:SetText(data.money and ns.GoldText(data.money) or "")
    viewer.goldLabel:SetShown(data.money ~= nil)

    for place, tab in pairs(viewer.tabs) do
        local label
        if place == "bags" then
            label = "Bags" .. (data.bagTotal and ("  " .. (data.bagTotal - data.bagFree) .. "/" .. data.bagTotal) or "")
        elseif place == "bank" then
            label = "Bank"
        elseif place == "mail" then
            local n = 0
            for _ in pairs(data.mail or {}) do n = n + 1 end
            label = "Mail" .. (n > 0 and ("  " .. n) or "")
        else
            label = "Warband bank"
        end
        tab:SetLabel(label)
        tab:SetActive(place == bagPlace)
    end
    if not viewer.tabs[bagPlace] then bagPlace = "bags" end

    local rows, count = PlaceItems(key, bagPlace)
    viewer.grid:SetRows(rows)
    local never = {
        bank = "Open the bank on this character once to see it here.",
        mail = "Nothing in the mail, or the mailbox hasn't been opened on this character.",
        warband = "Open the warband bank once to see it here.",
        bags = "Nothing saved for this character's bags yet.",
    }
    viewer.empty:SetText(count == 0 and never[bagPlace] or "")

    local readAt = { bags = data.seenAt, bank = data.bankScannedAt, mail = data.mailScannedAt, warband = AltInventoryDB.warbandScannedAt }
    local placeName = { bags = "Bags", bank = "Bank", mail = "Mail", warband = "Warband bank" }
    local when = readAt[bagPlace]
    local right
    if when then
        right = placeName[bagPlace] .. " read " .. AgeOrToday(when)
    elseif bagPlace == "bags" then
        right = "Bags as of their last login"
    else
        right = placeName[bagPlace] .. " not read yet"
    end
    Window:SetStatus("A saved copy: what " .. Short(key) .. " had the last time each place was read. Hover for the item, shift-click to link it.", right)
end

function Page:RefreshResults()
    for _, b in ipairs(self.placeButtons) do b:SetActive(b.place == filters.place) end
    self.sort:SetLabel(filters.sort == "name" and "Sort: name" or "Sort: most held")
    local text = self.search.box:GetText()
    local results, found = ns.Search.Find(text, filters)
    local rows = {}
    for _, result in ipairs(results) do rows[#rows + 1] = { result = result, parts = HolderParts(result) } end
    self.list:SetRows(rows)

    local hasQuery = ns.Search.ParseQuery(text) ~= nil
    if not hasQuery then
        self.empty:SetText("Type part of an item's name to find it on every character, bank and mailbox.\n\nOr click a character on the left to see what they're carrying.")
    elseif found == 0 then
        self.empty:SetText("No matches.\n\nCharacters you haven't logged into since installing Alt Inventory aren't included, and banks and mail only count once they've been opened.")
    else
        self.empty:SetText("")
    end
    local chars = #ns.Search.Characters()
    local left
    if found > #results then
        left = ("Showing %d of %d items. Type more to narrow it down."):format(#results, found)
    elseif hasQuery then
        left = ("%d item%s match \"%s\" across %d character%s."):format(found, found == 1 and "" or "s", text, chars, chars == 1 and "" or "s")
    else
        left = ("%d character%s tracked."):format(chars, chars == 1 and "" or "s")
    end
    local total = 0
    for _, data in pairs(AltInventoryDB.chars) do total = total + (data.money or 0) end
    total = total + (AltInventoryDB.warbandMoney or 0)
    Window:SetStatus(left, total > 0 and ("Total gold " .. ns.GoldText(total)) or "")
end

function Page:Refresh()
    if not self.frame then return end
    self.sideList:SetRows(CharacterRows())
    self.results:SetShown(selected == nil)
    self.viewer:SetShown(selected ~= nil)
    if selected then self:RefreshViewer() else self:RefreshResults() end
end

Window:AddPage(Page)
