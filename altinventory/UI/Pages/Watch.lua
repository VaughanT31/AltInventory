-- Alt Inventory - Watch lists page (2.0): sets of items with who holds them.
-- Built in: Lumber (Retail, with the Essence of Lumber banner), Consumables
-- and Trade goods (every version, by item class). Your own lists:
--
--   AltInventoryDB.watch = { { name = "Raid consumables", ids = { [itemID] = true } }, ... }
--   AltInventoryDB.watchSelected = "lumber" | "consumable" | "trade" | "user:<n>"
--
-- Add an item by dropping it on the box at the top, or typing its name, ID or
-- link and pressing Enter. Right-click a card to take it off your list.

local _, ns = ...
local Skin = ns.Skin
local C = Skin.C
local Window = ns.SearchWindow

local Page = { key = "watch", label = "Watch lists", order = 4 }
local SIDE_WIDTH = 210
local CARD_HEIGHT, CARD_GAP = 74, 10

local IS_RETAIL = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

local function Short(key) return key:match("^[^%-]+") or key end
local function Number(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

-- Item class by ID, cached: 0 consumable, 7 trade goods.
local classCache = {}
local function ItemClass(itemID)
    local cached = classCache[itemID]
    if cached ~= nil then return cached or nil end
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local classID = getInstant and select(6, getInstant(itemID))
    classCache[itemID] = classID or false
    return classID
end

-- Every item held anywhere, as a set.
local function HeldItems()
    local held = {}
    for _, data in pairs(AltInventoryDB.chars) do
        for _, place in ipairs(ns.PLACES) do
            for itemID in pairs(data[place] or {}) do held[itemID] = true end
        end
    end
    for itemID in pairs(AltInventoryDB.warband or {}) do held[itemID] = true end
    return held
end

local function ByClass(classID)
    local ids = {}
    for itemID in pairs(HeldItems()) do
        if ItemClass(itemID) == classID then ids[itemID] = true end
    end
    return ids
end

local BUILT_IN = {
    { key = "lumber", name = "Lumber", retail = true, ids = function()
        local ids = {}
        for _, itemID in ipairs(ns.Search.LUMBER_IDS) do ids[itemID] = true end
        return ids
    end },
    { key = "consumable", name = "Consumables", ids = function() return ByClass(0) end },
    { key = "trade", name = "Trade goods", ids = function() return ByClass(7) end },
}

local function UserLists()
    AltInventoryDB.watch = AltInventoryDB.watch or {}
    return AltInventoryDB.watch
end

-- The selected list: { key, name, ids, user = index or nil }.
local function Selected()
    local key = AltInventoryDB.watchSelected or (IS_RETAIL and "lumber" or "consumable")
    local userIndex = tonumber(key:match("^user:(%d+)$") or "")
    if userIndex and UserLists()[userIndex] then
        local list = UserLists()[userIndex]
        return { key = key, name = list.name, ids = list.ids, user = userIndex }
    end
    for _, list in ipairs(BUILT_IN) do
        if list.key == key and (not list.retail or IS_RETAIL) then return { key = key, name = list.name, ids = list.ids() } end
    end
    local fallback = IS_RETAIL and BUILT_IN[1] or BUILT_IN[2]
    return { key = fallback.key, name = fallback.name, ids = fallback.ids() }
end

local function Count(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

-- ---------------------------------------------------------------------
-- Left column
-- ---------------------------------------------------------------------

local SIDE_ROWS = { caption = 26, list = 32, new = 40 }

local function SideRows()
    local current = Selected().key
    local rows = { { kind = "caption", text = "Built in" } }
    for _, list in ipairs(BUILT_IN) do
        if not list.retail or IS_RETAIL then
            rows[#rows + 1] = { kind = "list", key = list.key, name = list.name, selected = current == list.key }
        end
    end
    rows[#rows + 1] = { kind = "caption", text = "Your lists" }
    for i, list in ipairs(UserLists()) do
        local key = "user:" .. i
        rows[#rows + 1] = { kind = "list", key = key, name = list.name, count = Count(list.ids), user = i, selected = current == key }
    end
    rows[#rows + 1] = { kind = "new" }
    return rows
end

local function InitSideRow(row, data)
    if not row.label then
        row.bg = Skin.Fill(row, C.selected, "BACKGROUND")
        row.bg:SetPoint("TOPLEFT", 0, -2)
        row.bg:SetPoint("BOTTOMRIGHT", 0, 2)
        row.hover = row:CreateTexture(nil, "HIGHLIGHT")
        row.hover:SetAllPoints(row.bg)
        row.hover:SetColorTexture(1, 1, 1, 0.04)
        row.label = Skin.Text(row, 12, C.text)
        row.right = Skin.Text(row, 11, C.dim)
        row.right:SetPoint("RIGHT", -10, 0)
        row.newButton = Skin.Button(row, "+  New list", nil, 28)
        row.newButton:SetPoint("LEFT", 0, 0)
        row.newButton:SetPoint("RIGHT", 0, 0)
        row.newButton:SetScript("OnClick", function() StaticPopup_Show("ALTINVENTORY_NEW_LIST") end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    row.label:ClearAllPoints()
    row.right:SetText("")
    row.bg:Hide()
    row.newButton:SetShown(data.kind == "new")
    row.label:SetShown(data.kind ~= "new")
    row:SetScript("OnClick", nil)
    if data.kind == "caption" then
        row.label:SetPoint("BOTTOMLEFT", 10, 4)
        row.label:SetText(Skin.Code(C.dim) .. data.text:upper() .. "|r")
    elseif data.kind == "list" then
        row.label:SetPoint("LEFT", 10, 0)
        row.label:SetText(data.name)
        Skin.SetColor(row.label, data.selected and C.text or C.body)
        row.right:SetText(data.count or "")
        row.bg:SetShown(data.selected)
        row:SetScript("OnClick", function(_, button)
            if button == "RightButton" and data.user then return Page:ListMenu(row, data.user) end
            AltInventoryDB.watchSelected = data.key
            Page:Refresh()
        end)
    end
end

-- ---------------------------------------------------------------------
-- Cards, two to a row
-- ---------------------------------------------------------------------

local function Card(parent)
    local card = Skin.Frame(parent, C.bar, C.lineSoft, "Button")
    card:SetHeight(CARD_HEIGHT)
    Skin.ItemScripts(card)
    card.icon = Skin.ItemIcon(card, 30)
    card.icon:SetPoint("TOPLEFT", 10, -10)
    card.icon:EnableMouse(false)
    card.name = Skin.Text(card, 13, C.text)
    card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -1)
    card.sub = Skin.Text(card, 11, C.dim)
    card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
    card.total = Skin.Text(card, 18, C.text)
    card.total:SetPoint("TOPRIGHT", -12, -12)
    card.name:SetPoint("RIGHT", card.total, "LEFT", -8, 0)
    card.bar = Skin.Bar(card, 4)
    card.bar.track:SetPoint("TOPLEFT", 10, -48)
    card.bar.track:SetPoint("TOPRIGHT", -10, -48)
    card.who = Skin.Text(card, 12, C.muted)
    card.who:SetPoint("TOPLEFT", 10, -56)
    card.who:SetPoint("RIGHT", -10, 0)
    return card
end

local function Holders(result)
    local bits = {}
    for i, holder in ipairs(result.holders) do
        if i > 2 then bits[#bits + 1] = Skin.Code(C.dim) .. "+" .. (#result.holders - 2) .. " more|r"; break end
        local data = AltInventoryDB.chars[holder.key]
        bits[#bits + 1] = Skin.Code(Skin.ClassColor(data and data.class)) .. Short(holder.key) .. "|r " .. holder.text
    end
    if (result.warband or 0) > 0 then bits[#bits + 1] = Skin.Code(C.warband) .. "Warband|r " .. result.warband end
    return table.concat(bits, "    ")
end

local function InitCardRow(row, data)
    if not row.cards then
        row.cards = { Card(row), Card(row) }
        row.cards[1]:SetPoint("TOPLEFT")
        row.cards[1]:SetPoint("RIGHT", row, "CENTER", -CARD_GAP / 2, 0)
        row.cards[2]:SetPoint("TOPRIGHT")
        row.cards[2]:SetPoint("LEFT", row, "CENTER", CARD_GAP / 2, 0)
    end
    for i, card in ipairs(row.cards) do
        local result = data.results[i]
        card:SetShown(result ~= nil)
        if result then
            card.itemID = result.itemID
            card.icon:SetItem(result.icon, result.quality)
            card.name:SetText(result.name or "?")
            Skin.SetColor(card.name, Skin.QualityColor(result.quality))
            local n = #result.holders
            card.sub:SetText(n .. (n == 1 and " character" or " characters") .. ((result.warband or 0) > 0 and " and the warband bank" or ""))
            card.total:SetText(Number(result.total))
            card.bar:Set(result.total / math.max(1, data.max), math.max(1, card:GetWidth() - 20), C.gold)
            card.who:SetText(Holders(result))
            card.onRightClick = data.user and function()
                UserLists()[data.user].ids[result.itemID] = nil
                Page:Refresh()
            end or nil
        end
    end
end

-- ---------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------

StaticPopupDialogs["ALTINVENTORY_NEW_LIST"] = {
    text = "Name your new watch list:",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = 1,
    maxLetters = 40,
    OnAccept = function(self)
        local box = self.editBox or self.EditBox
        local name = box and strtrim(box:GetText() or "") or ""
        if name == "" then return end
        local lists = UserLists()
        lists[#lists + 1] = { name = name, ids = {} }
        AltInventoryDB.watchSelected = "user:" .. #lists
        Page:Refresh()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["ALTINVENTORY_NEW_LIST"].OnAccept(parent)
        parent:Hide()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

StaticPopupDialogs["ALTINVENTORY_DELETE_LIST"] = {
    text = "Delete the watch list \"%s\"?",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, index)
        table.remove(UserLists(), index)
        AltInventoryDB.watchSelected = nil
        Page:Refresh()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

function Page:ListMenu(owner, index)
    local list = UserLists()[index]
    if not list then return end
    local dialog = StaticPopup_Show("ALTINVENTORY_DELETE_LIST", list.name)
    if dialog then dialog.data = index end
end

-- The item an added text means: a link, an ID, or a name you hold.
local function ItemFromText(text)
    text = strtrim(text or "")
    if text == "" then return nil end
    local linked = text:match("|Hitem:(%d+)")
    if linked then return tonumber(linked) end
    if text:match("^%d+$") then return tonumber(text) end
    local wanted = text:gsub("^%[", ""):gsub("%]$", ""):lower()
    for itemID, name in pairs(AltInventoryDB.names or {}) do
        if name.n and name.n:lower() == wanted then return itemID end
    end
end

function Page:AddItem(itemID)
    local list = Selected()
    if not list.user or not itemID then return end
    UserLists()[list.user].ids[itemID] = true
    self:Refresh()
end

function Page:Build(frame)
    local side = Skin.Frame(frame, C.side)
    side:SetPoint("TOPLEFT")
    side:SetPoint("BOTTOMLEFT")
    side:SetWidth(SIDE_WIDTH)
    local sideLine = Skin.Fill(side, C.line, "BORDER")
    sideLine:SetWidth(1)
    sideLine:SetPoint("TOPRIGHT")
    sideLine:SetPoint("BOTTOMRIGHT")
    self.sideList = Skin.List(side, function(data) return SIDE_ROWS[data.kind] end, InitSideRow)
    self.sideList:SetPoint("TOPLEFT", 8, -8)
    self.sideList:SetPoint("BOTTOMRIGHT", -20, 8)

    local main = CreateFrame("Frame", nil, frame)
    main:SetPoint("TOPLEFT", side, "TOPRIGHT", 16, -14)
    main:SetPoint("BOTTOMRIGHT", -16, 12)

    -- Essence of Lumber banner (Lumber list only).
    local banner = Skin.Frame(main, Skin.Hex("#172219"), Skin.Hex("#2b4a31"), "Button")
    banner:SetHeight(56)
    banner:SetPoint("TOPLEFT")
    banner:SetPoint("TOPRIGHT")
    banner.itemID = ns.Search.ESSENCE_ID
    Skin.ItemScripts(banner)
    banner.icon = Skin.ItemIcon(banner, 34)
    banner.icon:SetPoint("LEFT", 11, 0)
    banner.icon:EnableMouse(false)
    banner.title = Skin.Text(banner, 13, C.green)
    banner.title:SetPoint("TOPLEFT", banner.icon, "TOPRIGHT", 10, -2)
    banner.sub = Skin.Text(banner, 11, Skin.Hex("#a3c9a8"))
    banner.sub:SetPoint("TOPLEFT", banner.title, "BOTTOMLEFT", 0, -4)
    banner.who = Skin.Text(banner, 12, C.muted)
    banner.who:SetPoint("RIGHT", -12, 0)
    banner.who:SetJustifyH("RIGHT")
    banner.title:SetPoint("RIGHT", banner.who, "LEFT", -12, 0)
    banner.sub:SetPoint("RIGHT", banner.who, "LEFT", -12, 0)
    self.banner = banner

    -- Add box (your own lists only).
    local add = Skin.SearchBox(main)
    add:SetPoint("TOPLEFT")
    add:SetPoint("TOPRIGHT")
    add:SetHint("Add an item: drop it here, or type its name or ID and press Enter")
    add.box:SetScript("OnEnterPressed", function(box)
        local itemID = ItemFromText(box:GetText())
        if itemID then Page:AddItem(itemID); box:SetText("") end
        box:ClearFocus()
    end)
    local function Drop()
        local kind, itemID = GetCursorInfo()
        if kind == "item" and itemID then Page:AddItem(itemID); ClearCursor() end
    end
    add.box:SetScript("OnReceiveDrag", Drop)
    add:SetScript("OnReceiveDrag", Drop)
    add.box:HookScript("OnMouseDown", Drop)
    self.add = add

    self.list = Skin.List(main, CARD_HEIGHT + CARD_GAP, InitCardRow, "Frame")
    self.list:SetPoint("BOTTOMRIGHT", -14, 0)
    self.empty = Skin.Text(main, 13, C.dim)
    self.empty:SetPoint("TOPLEFT", self.list, "TOPLEFT", 10, -30)
    self.empty:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", -10, -30)
    self.empty:SetJustifyH("CENTER")
    self.empty:SetWordWrap(true)
end

function Page:Show(arg)
    if type(arg) == "string" then AltInventoryDB.watchSelected = arg end
end

function Page:Refresh()
    if not self.frame then return end
    self.sideList:SetRows(SideRows())
    local list = Selected()
    local isLumber = list.key == "lumber"
    local essence = isLumber and (ns.Search.Find({ ids = { [ns.Search.ESSENCE_ID] = true } }, {}))[1] or nil
    self.banner:SetShown(essence ~= nil)
    self.add:SetShown(list.user ~= nil)
    self.list:ClearAllPoints()
    local top = essence and self.banner or (list.user and self.add) or nil
    if top then
        self.list:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -12)
    else
        self.list:SetPoint("TOPLEFT", self.list:GetParent(), "TOPLEFT", 0, 0)
    end
    self.list:SetPoint("BOTTOMRIGHT", -14, 0)

    if essence then
        self.banner.icon:SetItem(essence.icon, essence.quality)
        self.banner.title:SetText(("Essence of Lumber: %s"):format(Number(essence.total)))
        self.banner.sub:SetText(("Trades for %s more lumber of any type at your neighborhood lumberjack"):format(Number(essence.total * 20)))
        local bits = {}
        for _, holder in ipairs(essence.holders) do
            local data = AltInventoryDB.chars[holder.key]
            bits[#bits + 1] = Skin.Code(Skin.ClassColor(data and data.class)) .. Short(holder.key) .. "|r " .. holder.count
        end
        if (essence.warband or 0) > 0 then bits[#bits + 1] = "Warband " .. essence.warband end
        self.banner.who:SetText(table.concat(bits, "  -  "))
        self.banner.who:SetWidth(math.min(200, self.banner.who:GetStringWidth() + 2))
    end

    local results = ns.Search.Find({ ids = list.ids }, { sort = "total" })
    local maxTotal = results[1] and results[1].total or 1
    local rows = {}
    for i = 1, #results, 2 do
        rows[#rows + 1] = { results = { results[i], results[i + 1] }, max = maxTotal, user = list.user }
    end
    self.list:SetRows(rows)
    if #results == 0 then
        self.empty:SetText(list.user and "Nothing on this list yet. Drop an item on the box above to add it."
            or (isLumber and "No lumber yet. It shows here once a character holding it logs in, or the warband bank is opened."
            or "None of your characters hold any yet."))
    else
        self.empty:SetText("")
    end
    local note = list.user and "Right-click a card to take it off the list. Right-click the list's name to delete it."
        or "Hover a card for the item, shift-click to link it."
    Window:SetStatus(note, #results .. (#results == 1 and " item" or " items"))
end

Window:AddPage(Page)
