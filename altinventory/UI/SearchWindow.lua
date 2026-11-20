-- Alt Inventory - the main window (2.0): a title bar with the tabs, a page
-- area, and a status bar. Each tab is a page in UI/Pages/ that registers
-- itself with Window:AddPage and builds its own content.
--
-- Opened with /altinv search (or /altinv find <text>), the minimap button
-- and the magnifier on the bags' search box, which carries over whatever
-- was typed there. The functions here (Open, Toggle, SetView, Refresh,
-- QueueRefresh, AddBagButton) are what the rest of the addon calls.

local _, ns = ...
local Skin = ns.Skin
local C = Skin.C

local Window = { pages = {}, order = {} }
ns.SearchWindow = Window

local WIDTH, HEIGHT = 820, 520
local TITLE_HEIGHT, STATUS_HEIGHT = 48, 28
local REFRESH_DELAY = 0.15

-- Older saved tab names.
local VIEW_ALIASES = { lumber = "watch", played = "played", characters = "characters", search = "search" }

-- page = { key, label, order, available = function() -> bool,
--          Build(page, content), Refresh(page), Show(page, arg) }
function Window:AddPage(page)
    self.pages[page.key] = page
    self.order[#self.order + 1] = page
    table.sort(self.order, function(a, b) return (a.order or 99) < (b.order or 99) end)
end

local function Available(page)
    return not page.available or page.available()
end

function Window:SetStatus(left, right)
    if not self.frame then return end
    self.statusLeft:SetText(left or "")
    self.statusRight:SetText(right or "")
end

function Window:Build()
    local f = CreateFrame("Frame", "AltInventorySearchFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    Skin.Panel(f, C.window, C.line)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    local saved = AltInventoryDB.window
    if saved and saved.point then
        f:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
    else
        f:SetPoint("CENTER")
    end
    if AltInventoryDB.windowScale then f:SetScale(AltInventoryDB.windowScale) end
    f:Hide()
    table.insert(UISpecialFrames, "AltInventorySearchFrame")
    self.frame = f

    -- Title bar: drags the window.
    local bar = Skin.Frame(f, C.bar)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(TITLE_HEIGHT - 1)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        AltInventoryDB.window = { point = point, x = x, y = y }
    end)
    local barLine = Skin.Fill(bar, C.line, "BORDER")
    barLine:SetHeight(1)
    barLine:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, -1)
    barLine:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -1)

    local badge = Skin.Frame(bar, C.goldDeep, C.goldLine)
    badge:SetSize(26, 26)
    badge:SetPoint("LEFT", 14, 0)
    local badgeIcon = badge:CreateTexture(nil, "ARTWORK")
    badgeIcon:SetPoint("TOPLEFT", 3, -3)
    badgeIcon:SetPoint("BOTTOMRIGHT", -3, 3)
    badgeIcon:SetTexture("Interface\\AddOns\\AltInventory\\icon")
    local title = Skin.Text(bar, 16, C.gold, true)
    title:SetPoint("LEFT", badge, "RIGHT", 10, 0)
    title:SetText("Alt Inventory")

    self.tabs = {}
    local previous
    for _, page in ipairs(self.order) do
        if Available(page) then
            local tab = Skin.Button(bar, page.label, nil, 28)
            Skin.Panel(tab, C.bar)
            -- Tabs: plain text until chosen, then the gold pill.
            local SetActive = tab.SetActive
            function tab:SetActive(on)
                SetActive(self, on)
                if not on then Skin.Panel(self, C.bar) end
            end
            tab:SetActive(false)
            if previous then tab:SetPoint("LEFT", previous, "RIGHT", 4, 0) else tab:SetPoint("LEFT", title, "RIGHT", 22, 0) end
            tab:SetScript("OnClick", function() Window:SetView(page.key) end)
            self.tabs[page.key] = tab
            previous = tab
        end
    end

    local close = Skin.CloseButton(bar)
    close:SetPoint("RIGHT", -10, 0)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Status bar.
    local status = Skin.Frame(f, C.side)
    status:SetPoint("BOTTOMLEFT", 1, 1)
    status:SetPoint("BOTTOMRIGHT", -1, 1)
    status:SetHeight(STATUS_HEIGHT - 1)
    local statusLine = Skin.Fill(status, C.line, "BORDER")
    statusLine:SetHeight(1)
    statusLine:SetPoint("TOPLEFT", status, "TOPLEFT", 0, 1)
    statusLine:SetPoint("TOPRIGHT", status, "TOPRIGHT", 0, 1)
    self.statusLeft = Skin.Text(status, 11, C.dim)
    self.statusLeft:SetPoint("LEFT", 14, 0)
    self.statusRight = Skin.Text(status, 11, C.dim)
    self.statusRight:SetPoint("RIGHT", -14, 0)
    self.statusRight:SetJustifyH("RIGHT")
    self.statusLeft:SetPoint("RIGHT", self.statusRight, "LEFT", -12, 0)

    -- Page area: each page gets its own frame here, built the first time it shows.
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 1, -TITLE_HEIGHT)
    content:SetPoint("BOTTOMRIGHT", -1, STATUS_HEIGHT)
    self.content = content

    local view = VIEW_ALIASES[AltInventoryDB.windowView or "search"] or "search"
    if not self.pages[view] or not Available(self.pages[view]) then view = "search" end
    self.view = view
end

function Window:PageFrame(page)
    if not page.frame then
        page.frame = CreateFrame("Frame", nil, self.content)
        page.frame:SetAllPoints()
        page.frame:Hide()
        page:Build(page.frame)
    end
    return page.frame
end

-- Shows a tab. arg goes to the page (a character key, a watch list, text).
function Window:SetView(view, arg)
    if not self.frame then self:Build() end
    view = VIEW_ALIASES[view] or view
    local page = self.pages[view]
    if not page or not Available(page) then page, view = self.pages.search, "search" end
    self.view = view
    AltInventoryDB.windowView = view
    for key, other in pairs(self.pages) do
        if other.frame then other.frame:SetShown(key == view) end
    end
    self:PageFrame(page):Show()
    for key, tab in pairs(self.tabs) do tab:SetActive(key == view) end
    if page.Show then page:Show(arg) end
    self:Refresh()
end

-- Opens a character's bag viewer.
function Window:OpenCharacter(key)
    self:SetView("search", { character = key })
end

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
    local page = self.pages[self.view]
    if page and page.frame and page.Refresh then page:Refresh() end
end

function Window:Open(text)
    if not self.frame then self:Build() end
    self.frame:Show()
    -- Opening with something to find goes to Search.
    if text then return self:SetView("search", { text = text }) end
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
    -- The Classic clients may not have this atlas: then the old magnifying glass texture.
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("common-search-magnifyingglass")
    if hasAtlas then
        icon:SetAtlas("common-search-magnifyingglass")
    else
        icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    end
    icon:SetVertexColor(1, 0.82, 0)
    if hasAtlas then
        button:SetHighlightAtlas("common-search-magnifyingglass", "ADD")
    else
        button:SetHighlightTexture("Interface\\Common\\UI-Searchbox-Icon", "ADD")
    end
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
