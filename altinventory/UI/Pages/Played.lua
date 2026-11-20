-- Alt Inventory - Play time page (2.0): time played by character, class,
-- role or faction (Played.lua), as class-coloured bars.

local _, ns = ...
local Skin = ns.Skin
local C = Skin.C
local Window = ns.SearchWindow

local Page = { key = "played", label = "Play time", order = 3 }
local ROW = 30
local LABEL, RIGHT = 150, 130

local function InitBar(row, data)
    if not row.bar then
        row.hover = row:CreateTexture(nil, "HIGHLIGHT")
        row.hover:SetAllPoints()
        row.hover:SetColorTexture(1, 1, 1, 0.04)
        row.label = Skin.Text(row, 13, C.text)
        row.label:SetPoint("LEFT", 10, 0)
        row.label:SetWidth(LABEL - 16)
        row.bar = Skin.Bar(row, 12)
        row.bar.track:SetPoint("LEFT", LABEL, 0)
        row.bar.track:SetPoint("RIGHT", -RIGHT, 0)
        row.share = Skin.Text(row, 12, C.gold)
        row.share:SetPoint("RIGHT", -70, 0)
        row.share:SetJustifyH("RIGHT")
        row.time = Skin.Text(row, 12, C.muted)
        row.time:SetPoint("RIGHT", -10, 0)
        row.time:SetJustifyH("RIGHT")
    end
    local e = data.entry
    local color = { e.color[1], e.color[2], e.color[3] }
    row.label:SetText(e.label)
    Skin.SetColor(row.label, color)
    local width = math.max(40, row:GetWidth() - LABEL - RIGHT)
    row.bar:Set(e.seconds / math.max(1, data.top), width, color)
    row.share:SetText(("%.1f%%"):format(100 * e.seconds / math.max(1, data.total)))
    row.time:SetText(ns.Played.Format(e.seconds))
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.label, color[1], color[2], color[3])
        GameTooltip:AddLine(ns.Played.Format(e.seconds), 1, 1, 1)
        if data.group ~= "character" then
            GameTooltip:AddLine(e.count .. (e.count == 1 and " character" or " characters"), 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function Page:Build(frame)
    self.group = AltInventoryDB.playedGroup or "character"
    self.groupButtons = {}
    local previous
    for _, key in ipairs(ns.Played.GROUP_ORDER) do
        local b = Skin.Button(frame, ns.Played.GROUP_LABELS[key], nil, 26, true)
        if previous then b:SetPoint("LEFT", previous, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 16, -16) end
        b:SetScript("OnClick", function()
            Page.group = key
            AltInventoryDB.playedGroup = key
            Page:Refresh()
        end)
        b.group = key
        self.groupButtons[#self.groupButtons + 1] = b
        previous = b
    end

    local total = Skin.Frame(frame, C.bar, C.lineSoft)
    total:SetSize(200, 50)
    total:SetPoint("TOPRIGHT", -16, -12)
    total.caption = Skin.Caption(total, "Total played")
    total.caption:SetPoint("TOPLEFT", 12, -9)
    total.value = Skin.Text(total, 17, C.gold)
    total.value:SetPoint("TOPLEFT", total.caption, "BOTTOMLEFT", 0, -5)
    self.total = total

    local listFrame = Skin.Frame(frame, C.window, C.lineSoft)
    listFrame:SetPoint("TOPLEFT", 16, -74)
    listFrame:SetPoint("BOTTOMRIGHT", -16, 12)
    self.list = Skin.List(listFrame, ROW, InitBar)
    self.list:SetPoint("TOPLEFT", 4, -6)
    self.list:SetPoint("BOTTOMRIGHT", -18, 6)
    self.empty = Skin.Text(listFrame, 13, C.dim)
    self.empty:SetPoint("TOP", 0, -40)
end

function Page:Show()
    -- This character's time, if login couldn't ask for it quietly.
    local data = AltInventoryDB.chars[ns.GetCharKey()]
    if data and not data.played then ns.Played:Request(false) end
end

function Page:Refresh()
    if not self.frame then return end
    for _, b in ipairs(self.groupButtons) do b:SetActive(b.group == self.group) end
    local list, total, missing = ns.Played.List(self.group)
    local top = list[1] and list[1].seconds or 1
    local rows = {}
    for _, entry in ipairs(list) do rows[#rows + 1] = { entry = entry, top = top, total = total, group = self.group } end
    self.list:SetRows(rows)
    self.empty:SetText(#list == 0 and "No time played recorded yet. It's read when each character logs in." or "")
    self.total.value:SetText(ns.Played.Format(total))
    Window:SetStatus(#list > 0 and ("Hover a bar for details.") or "",
        missing > 0 and (("%d character%s not recorded yet: log in on %s once"):format(missing, missing == 1 and "" or "s", missing == 1 and "it" or "each")) or "")
end

Window:AddPage(Page)
