-- Alt Inventory - the search window: "where is my X?" across every
-- character, their banks and mail, and the warband bank. A second tab,
-- Play time, shows time played by character, class, role or faction
-- (Played.lua).
--
-- Opened with /altinv search (or /altinv find <text>) and from the
-- magnifier button on the bags' search box, which carries over whatever
-- was typed there.

local _, ns = ...

local Window = {}
ns.SearchWindow = Window

local WIDTH, HEIGHT = 470, 500
local ITEM_ROW, HOLDER_ROW = 26, 17
local BAR_ROW = 22
local BAR_LABEL, BAR_RIGHT = 120, 112
local REFRESH_DELAY = 0.15

local PLACE_LABELS = {
    { key = nil, label = "All places" },
    { key = "bags", label = "Bags" },
    { key = "bank", label = "Bank" },
    { key = "mail", label = "Mail" },
    { key = "warband", label = "Warband bank" },
    { key = "currency", label = "Currencies" },
}

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

local filters = { char = nil, place = nil, sort = "name" }

local function QualityColor(quality)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function ItemLink(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = getInfo(itemID)
    return link
end

-- Rows ----------------------------------------------------------------

local function EnsureRegions(row)
    if row.text then return end
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.06)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -6, 0)
    row.right:SetJustifyH("RIGHT")
    row.right:SetWordWrap(false)
end

local function InitRow(row, data)
    EnsureRegions(row)
    row.itemID, row.currencyID = data.itemID, data.currencyID
    row.text:ClearAllPoints()
    if data.kind == "item" then
        local result = data.result
        row.icon:Show()
        row.icon:SetTexture(result.icon or 134400) -- question mark when unknown
        row.text:SetFontObject("GameFontHighlight")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
        row.text:SetText(result.name)
        row.text:SetTextColor(QualityColor(result.quality))
        row.right:SetText("|cffffd100Total " .. result.total .. "|r")
    else
        row.icon:Hide()
        row.text:SetFontObject("GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 30, 0)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
        row.text:SetTextColor(1, 1, 1)
        if data.kind == "warband" then
            row.text:SetText("|cff99ccffWarband Bank|r")
            row.right:SetText(ns.WithAge(tostring(data.count), AltInventoryDB.warbandScannedAt))
        else
            row.text:SetText(data.holder.name)
            row.right:SetText("|cffcccccc" .. data.holder.text .. "|r")
        end
    end
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.currencyID then
            GameTooltip:SetCurrencyByID(self.currencyID)
        else
            GameTooltip:SetItemByID(self.itemID)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if IsModifiedClick and IsModifiedClick("CHATLINK") then
            local link
            if self.currencyID then
                link = C_CurrencyInfo.GetCurrencyLink and C_CurrencyInfo.GetCurrencyLink(self.currencyID, 0)
            else
                link = ItemLink(self.itemID)
            end
            if link then ChatEdit_InsertLink(link) end
        end
    end)
end

-- Play time rows: name, a bar as long as its share of the most played,
-- and "20.5%  47d 4h".
local function InitBar(row, data)
    if not row.bar then
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.06)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", 6, 0)
        row.label:SetWidth(BAR_LABEL - 10)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.back = row:CreateTexture(nil, "BACKGROUND")
        row.back:SetPoint("LEFT", BAR_LABEL, 0)
        row.back:SetPoint("RIGHT", -BAR_RIGHT, 0)
        row.back:SetHeight(14)
        row.back:SetColorTexture(1, 1, 1, 0.05)
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetPoint("LEFT", BAR_LABEL, 0)
        row.bar:SetHeight(14)
        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetPoint("RIGHT", -6, 0)
        row.right:SetJustifyH("RIGHT")
    end
    local e = data.entry
    local r, g, b = e.color[1], e.color[2], e.color[3]
    row.label:SetText(e.label)
    row.label:SetTextColor(r, g, b)
    row.bar:SetColorTexture(r, g, b, 0.85)
    row.bar:SetWidth(math.max(1, data.width * e.seconds / math.max(1, data.top)))
    row.right:SetText(("|cffffd100%.1f%%|r  %s"):format(100 * e.seconds / math.max(1, data.total), ns.Played.Format(e.seconds)))
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.label, r, g, b)
        GameTooltip:AddLine(ns.Played.Format(e.seconds), 1, 1, 1)
        if data.group ~= "character" then
            GameTooltip:AddLine(e.count .. (e.count == 1 and " character" or " characters"), 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Tabs at the top: gold and underlined when chosen.
local function Tab(parent, text)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetHeight(20)
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.text:SetPoint("CENTER", 0, 1)
    tab.text:SetText(text)
    tab:SetWidth(tab.text:GetStringWidth() + 18)
    tab.line = tab:CreateTexture(nil, "ARTWORK")
    tab.line:SetColorTexture(1, 0.82, 0, 0.8)
    tab.line:SetHeight(2)
    tab.line:SetPoint("BOTTOMLEFT", 6, 0)
    tab.line:SetPoint("BOTTOMRIGHT", -6, 0)
    function tab:SetActive(on)
        self.text:SetTextColor(on and 1 or 0.6, on and 0.82 or 0.6, on and 0 or 0.6)
        self.line:SetShown(on)
    end
    return tab
end

-- Building -------------------------------------------------------------

local function Dropdown(parent, width)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width)
    return dropdown
end

function Window:Build()
    local f = CreateFrame("Frame", "AltInventorySearchFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0.06, 0.06, 0.07, 0.96)
    f:SetBackdropBorderColor(0.3, 0.28, 0.24, 0.9)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        AltInventoryDB.window = { point = point, x = x, y = y }
    end)
    local saved = AltInventoryDB.window
    if saved and saved.point then
        f:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
    else
        f:SetPoint("CENTER")
    end
    f:Hide()
    table.insert(UISpecialFrames, "AltInventorySearchFrame")
    self.frame = f

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Alt Inventory")
    self.tabs = {}
    local previous
    for _, t in ipairs({ { "search", "Search" }, { "played", "Play time" } }) do
        local tab = Tab(f, t[2])
        if previous then tab:SetPoint("LEFT", previous, "RIGHT", 2, 0) else tab:SetPoint("LEFT", title, "RIGHT", 10, -1) end
        tab:SetScript("OnClick", function() Window:SetView(t[1]) end)
        self.tabs[t[1]] = tab
        previous = tab
    end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local box = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
    box:SetSize(WIDTH - 24, 22)
    box:SetPoint("TOPLEFT", 16, -36)
    box:SetAutoFocus(false)
    box:HookScript("OnTextChanged", function() Window:QueueRefresh() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    self.box = box

    -- Drop an item on the box (or shift-click one) to search for it.
    box:HookScript("OnReceiveDrag", function(self)
        local kind, itemID = GetCursorInfo()
        if kind == "item" and itemID then
            self:SetText(tostring(itemID))
            ClearCursor()
        end
    end)

    local charDrop = Dropdown(f, 160)
    charDrop:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -8)
    charDrop:SetupMenu(function(_, root)
        root:CreateRadio("All characters", function() return filters.char == nil end, function()
            filters.char = nil
            Window:Refresh()
        end)
        for _, key in ipairs(ns.Search.Characters()) do
            local data = AltInventoryDB.chars[key]
            root:CreateRadio(ns.ClassName(key, data.class) .. " |cff999999" .. (key:match("%-(.+)$") or "") .. "|r",
                function() return filters.char == key end,
                function() filters.char = key; Window:Refresh() end)
        end
    end)
    self.charDrop = charDrop

    local placeDrop = Dropdown(f, 130)
    placeDrop:SetPoint("LEFT", charDrop, "RIGHT", 6, 0)
    placeDrop:SetupMenu(function(_, root)
        for _, place in ipairs(PLACE_LABELS) do
            root:CreateRadio(place.label, function() return filters.place == place.key end,
                function() filters.place = place.key; Window:Refresh() end)
        end
    end)

    local sortDrop = Dropdown(f, 120)
    sortDrop:SetPoint("LEFT", placeDrop, "RIGHT", 6, 0)
    sortDrop:SetupMenu(function(_, root)
        root:CreateRadio("Sort: name", function() return filters.sort == "name" end,
            function() filters.sort = "name"; Window:Refresh() end)
        root:CreateRadio("Sort: total", function() return filters.sort == "total" end,
            function() filters.sort = "total"; Window:Refresh() end)
    end)

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.2)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 10, -100)
    line:SetPoint("TOPRIGHT", -10, -100)

    local scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 10, -106)
    scrollBox:SetPoint("BOTTOMRIGHT", -26, 30)
    local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function(_, data) return data.kind == "item" and ITEM_ROW or HOLDER_ROW end)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    self.scrollBox = scrollBox

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("BOTTOMLEFT", 12, 10)
    status:SetPoint("BOTTOMRIGHT", -12, 10)
    status:SetJustifyH("LEFT")
    self.status = status

    local empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", scrollBox, "TOPLEFT", 10, -20)
    empty:SetPoint("TOPRIGHT", scrollBox, "TOPRIGHT", -10, -20)
    empty:SetJustifyH("CENTER")
    self.empty = empty
    self.searchParts = { box, charDrop, placeDrop, sortDrop, line, scrollBox, scrollBar, empty }

    -- Play time
    self.group = AltInventoryDB.playedGroup or "character"
    local groupDrop = Dropdown(f, 160)
    groupDrop:SetPoint("TOPLEFT", 10, -38)
    groupDrop:SetupMenu(function(_, root)
        for _, key in ipairs(ns.Played.GROUP_ORDER) do
            root:CreateRadio(ns.Played.GROUP_LABELS[key], function() return Window.group == key end, function()
                Window.group = key
                AltInventoryDB.playedGroup = key
                Window:Refresh()
            end)
        end
    end)
    local playLine = f:CreateTexture(nil, "ARTWORK")
    playLine:SetColorTexture(1, 0.82, 0, 0.2)
    playLine:SetHeight(1)
    playLine:SetPoint("TOPLEFT", 10, -70)
    playLine:SetPoint("TOPRIGHT", -10, -70)
    local playBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
    playBox:SetPoint("TOPLEFT", 10, -76)
    playBox:SetPoint("BOTTOMRIGHT", -26, 30)
    local playBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
    playBar:SetPoint("TOPLEFT", playBox, "TOPRIGHT", 6, 0)
    playBar:SetPoint("BOTTOMLEFT", playBox, "BOTTOMRIGHT", 6, 0)
    local playView = CreateScrollBoxListLinearView()
    playView:SetElementExtent(BAR_ROW)
    playView:SetElementInitializer("Button", InitBar)
    ScrollUtil.InitScrollBoxListWithScrollBar(playBox, playBar, playView)
    self.playBox = playBox
    local playEmpty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    playEmpty:SetPoint("TOPLEFT", playBox, "TOPLEFT", 10, -20)
    playEmpty:SetPoint("TOPRIGHT", playBox, "TOPRIGHT", -10, -20)
    playEmpty:SetJustifyH("CENTER")
    self.playEmpty = playEmpty
    self.playedParts = { groupDrop, playLine, playBox, playBar, playEmpty }

    self.view = AltInventoryDB.windowView == "played" and "played" or "search"
    self:ShowView()
end

function Window:ShowView()
    for _, part in ipairs(self.searchParts) do part:SetShown(self.view == "search") end
    for _, part in ipairs(self.playedParts) do part:SetShown(self.view == "played") end
    for key, tab in pairs(self.tabs) do tab:SetActive(key == self.view) end
end

function Window:SetView(view)
    if not self.frame then self:Build() end
    self.view = view
    AltInventoryDB.windowView = view
    self:ShowView()
    if view == "played" then
        -- This character's time, if login couldn't ask for it quietly.
        local data = AltInventoryDB.chars[ns.GetCharKey()]
        if data and not data.played then ns.Played:Request(false) end
    else
        self.box:SetFocus()
    end
    self:Refresh()
end

function Window:RefreshPlayed()
    local list, total, missing = ns.Played.List(self.group)
    local top = list[1] and list[1].seconds or 1
    local width = math.max(40, self.playBox:GetWidth() - BAR_LABEL - BAR_RIGHT)
    local elements = {}
    for _, entry in ipairs(list) do
        elements[#elements + 1] = { entry = entry, top = top, total = total, width = width, group = self.group }
    end
    self.playBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)
    self.playEmpty:SetText(#list == 0 and "No time played recorded yet. It's read when each character logs in." or "")
    local text = "|cffffd100Total: " .. ns.Played.Format(total) .. "|r"
    if missing > 0 then
        text = text .. ("  |cff999999%d character%s not recorded yet: log in on %s once.|r"):format(missing,
            missing == 1 and "" or "s", missing == 1 and "it" or "each")
    end
    self.status:SetText(text)
end

-- Refreshing ------------------------------------------------------------

function Window:QueueRefresh()
    if self.pending then return end
    self.pending = true
    C_Timer.After(REFRESH_DELAY, function()
        self.pending = false
        self:Refresh()
    end)
end

function Window:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    if self.view == "played" then return self:RefreshPlayed() end
    local text = self.box:GetText()
    local results, found = ns.Search.Find(text, filters)
    local elements = {}
    for _, result in ipairs(results) do
        elements[#elements + 1] = { kind = "item", itemID = result.itemID, currencyID = result.currencyID, result = result }
        for _, holder in ipairs(result.holders) do
            elements[#elements + 1] = { kind = "holder", itemID = result.itemID, currencyID = result.currencyID, holder = holder }
        end
        if result.warband > 0 then
            elements[#elements + 1] = { kind = "warband", itemID = result.itemID, count = result.warband }
        end
    end
    self.scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)

    local hasQuery = ns.Search.ParseQuery(text) ~= nil
    if not hasQuery then
        self.empty:SetText("Type part of an item's name, or drop an item here.")
    elseif found == 0 then
        self.empty:SetText("No matches.\n\nCharacters you haven't logged into since installing Alt Inventory aren't included, and banks and mail only count once they've been opened.")
    else
        self.empty:SetText("")
    end
    local chars = #ns.Search.Characters()
    if found > #results then
        self.status:SetText(("Showing %d of %d items. Type more to narrow it down."):format(#results, found))
    elseif hasQuery then
        self.status:SetText(("%d item%s across %d character%s."):format(found, found == 1 and "" or "s", chars, chars == 1 and "" or "s"))
    else
        self.status:SetText(("%d character%s tracked."):format(chars, chars == 1 and "" or "s"))
    end
end

function Window:Open(text)
    if not self.frame then self:Build() end
    self.frame:Show()
    -- Opening with something to find goes to Search.
    if text then
        self.box:SetText(text)
        return self:SetView("search")
    end
    self:SetView(self.view)
end

function Window:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

-- Bag button -------------------------------------------------------------

-- A magnifier inside the bags' own search box, at its right end (left of
-- Blizzard's clear button). It carries the box's text over to the window.
function Window:AddBagButton()
    local bagBox = _G.BagItemSearchBox
    if not bagBox or self.bagButton then return end
    local button = CreateFrame("Button", nil, bagBox)
    button:SetSize(16, 16)
    button:SetPoint("RIGHT", bagBox, "RIGHT", -18, 0)
    button:SetFrameLevel(bagBox:GetFrameLevel() + 5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetAtlas("common-search-magnifyingglass")
    icon:SetVertexColor(1, 0.82, 0)
    button:SetHighlightAtlas("common-search-magnifyingglass", "ADD")
    button:SetScript("OnClick", function()
        local text = bagBox:GetText()
        Window:Open(text ~= "" and text or nil)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Alt Inventory")
        GameTooltip:AddLine("Search all your characters, banks and mail.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.bagButton = button
end
