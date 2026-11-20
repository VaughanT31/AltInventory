-- Alt Inventory - Characters page (2.0): summary cards, then a sortable
-- table of every character. Hover a row for concentration, Moxie, cooldowns
-- and this patch's currencies (Characters.lua); click it for their bags.

local _, ns = ...
local Skin = ns.Skin
local C = Skin.C
local Window = ns.SearchWindow

local Page = { key = "characters", label = "Characters", order = 2 }
local ROW = 38
local sortKey, sortDesc = "ilvl", true

local function Short(key) return key:match("^[^%-]+") or key end
local function Realm(key) return key:match("%-(.+)$") or "" end

local function HasReagent()
    for _, data in pairs(AltInventoryDB.chars) do
        if (data.reagentTotal or 0) > 0 then return true end
    end
    return false
end

-- Columns: key, label, width, align. Reagent only where a reagent bag exists.
local function Columns()
    local cols = {
        { key = "name", label = "CHARACTER", width = 220 },
        { key = "ilvl", label = "ITEM LVL", width = 70 },
        { key = "money", label = "GOLD", width = 125 },
        { key = "bags", label = "BAG SPACE", width = 150 },
    }
    if HasReagent() then cols[#cols + 1] = { key = "reagent", label = "REAGENT BAG", width = 95 } end
    cols[#cols + 1] = { key = "seen", label = "LAST PLAYED", width = 100 }
    return cols
end

local function AgeText(at)
    if not at then return "-" end
    local days = math.floor((time() - at) / 86400)
    if days <= 0 then return "Today" end
    if days == 1 then return "Yesterday" end
    if days < 14 then return days .. " days ago" end
    if days < 60 then return math.floor(days / 7) .. " weeks ago" end
    return math.floor(days / 30) .. " months ago"
end

local function SortValue(row, key)
    local data = row.data
    if key == "name" then return row.key:lower() end
    if key == "ilvl" then return data.ilvl or -1 end
    if key == "money" then return data.money or -1 end
    if key == "bags" then return data.bagTotal and data.bagFree or -1 end
    if key == "reagent" then return data.reagentTotal and data.reagentFree or -1 end
    if key == "seen" then return data.seenAt or -1 end
    return 0
end

local function Rows()
    local rows = {}
    for key, data in pairs(AltInventoryDB.chars) do
        rows[#rows + 1] = { key = key, data = data, waiting = not ns.Characters.HasInfo(data) and key ~= ns.GetCharKey() }
    end
    table.sort(rows, function(a, b)
        if a.waiting ~= b.waiting then return b.waiting end
        local va, vb = SortValue(a, sortKey), SortValue(b, sortKey)
        if va ~= vb then
            if sortDesc then return va > vb end
            return va < vb
        end
        return a.key < b.key
    end)
    for i, row in ipairs(rows) do row.alt = i % 2 == 0 end
    return rows
end

local function BagColor(free, total)
    local used = (total - free) / math.max(1, total)
    if used > 0.9 then return C.bad end
    if used > 0.7 then return C.warn end
    return C.good
end

local function InitRow(row, data)
    local cols = Page.columns
    if not row.cells or row.colCount ~= #cols then
        if row.cells then for _, cell in pairs(row.cells) do cell:Hide() end end
        row.colCount = #cols
        row.bg = row.bg or Skin.Fill(row, C.rowAlt, "BACKGROUND")
        row.bg:SetAllPoints()
        if not row.hover then
            row.hover = row:CreateTexture(nil, "HIGHLIGHT")
            row.hover:SetAllPoints()
            row.hover:SetColorTexture(1, 1, 1, 0.04)
            row.line = Skin.Fill(row, C.selected, "BORDER")
            row.line:SetHeight(1)
            row.line:SetPoint("TOPLEFT")
            row.line:SetPoint("TOPRIGHT")
        end
        row.cells = {}
        local x = 12
        for _, col in ipairs(cols) do
            local cell = CreateFrame("Frame", nil, row)
            cell:SetPoint("TOPLEFT", x, 0)
            cell:SetSize(col.width - 10, ROW)
            cell.text = Skin.Text(cell, 12, C.text)
            if col.key == "name" then
                cell.text:SetPoint("TOPLEFT", 0, -6)
                cell.sub = Skin.Text(cell, 10, C.dim)
                cell.sub:SetPoint("TOPLEFT", cell.text, "BOTTOMLEFT", 0, -3)
            elseif col.key == "bags" or col.key == "reagent" then
                cell.bar = Skin.Bar(cell, 5)
                cell.bar.track:SetPoint("TOPLEFT", 0, -11)
                cell.bar.track:SetPoint("TOPRIGHT", -10, -11)
                cell.text:SetPoint("TOPLEFT", 0, -20)
                Skin.SetColor(cell.text, C.dim)
            else
                cell.text:SetPoint("LEFT", 0, 0)
            end
            row.cells[col.key] = cell
            x = x + col.width
        end
    end
    row.bg:SetShown(data.alt)
    local d = data.data
    local color = Skin.ClassColor(d.class)
    local name = row.cells.name
    name.text:SetText(Short(data.key))
    Skin.SetColor(name.text, data.waiting and C.dim or color)
    local className = d.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[d.class] or ""
    name.sub:SetText((className ~= "" and (className .. "  -  ") or "") .. Realm(data.key))

    local function Set(key, text, textColor)
        local cell = row.cells[key]
        if not cell then return end
        cell.text:SetText(text or "")
        Skin.SetColor(cell.text, textColor or C.text)
    end
    if data.waiting then
        Set("ilvl", "-", C.dim)
        Set("money", d.money and ns.GoldText(d.money) or "-", C.dim)
        for _, key in ipairs({ "bags", "reagent" }) do
            local cell = row.cells[key]
            if cell then cell.bar.track:Hide(); cell.bar.fill:Hide(); cell.text:SetText(key == "bags" and "log in once to see" or "") end
        end
        Set("seen", AgeText(d.seenAt), C.dim)
    else
        Set("ilvl", d.ilvl and Skin.ItemLevel(d.ilvl) or "-")
        Set("money", d.money and ns.GoldText(d.money) or "-", C.gold)
        for _, key in ipairs({ "bags", "reagent" }) do
            local cell = row.cells[key]
            if cell then
                local free, total = d[key == "bags" and "bagFree" or "reagentFree"], d[key == "bags" and "bagTotal" or "reagentTotal"]
                local has = total and total > 0
                cell.bar.track:SetShown(has)
                cell.bar.fill:SetShown(has)
                if has then
                    cell.bar:Set((total - free) / total, cell:GetWidth() - 10, BagColor(free, total))
                    cell.text:SetText(free .. " free of " .. total)
                else
                    cell.text:SetText("-")
                end
                Skin.SetColor(cell.text, C.dim)
            end
        end
        Set("seen", AgeText(d.seenAt), C.muted)
    end

    row:SetScript("OnClick", function() Window:OpenCharacter(data.key) end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(data.key, color[1], color[2], color[3])
        if data.waiting then
            GameTooltip:AddLine("Log in on this character once to fill in its details.", 1, 1, 1, true)
        else
            local block = ns.Characters.Block(data.key, d)
            for _, section in ipairs(block.sections) do
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(section.title, 1, 0.82, 0)
                for _, line in ipairs(section.lines) do
                    GameTooltip:AddDoubleLine(line.label, line.value or "", 1, 1, 1, 1, 1, 1)
                end
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to see their bags, bank and mail.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A summary card: caption on top, big value, small note beside it.
local function Card(parent)
    local card = Skin.Frame(parent, C.bar, C.lineSoft)
    card:SetHeight(56)
    card.caption = Skin.Caption(card)
    card.caption:SetPoint("TOPLEFT", 12, -10)
    card.value = Skin.Text(card, 17, C.text)
    card.value:SetPoint("TOPLEFT", card.caption, "BOTTOMLEFT", 0, -6)
    card.note = Skin.Text(card, 11, C.dim)
    card.note:SetPoint("TOPRIGHT", -12, -9)
    card.note:SetJustifyH("RIGHT")
    card.caption:SetPoint("RIGHT", card.note, "LEFT", -6, 0)
    return card
end

function Page:Build(frame)
    self.cards = {}
    local gap = 10
    local full = frame:GetParent():GetWidth()
    if not full or full < 100 then full = 818 end
    local width = (full - 32 - gap * 3) / 4
    for i = 1, 4 do
        local card = Card(frame)
        card:SetWidth(width)
        card:SetPoint("TOPLEFT", 16 + (i - 1) * (width + gap), -14)
        self.cards[i] = card
    end

    local tableFrame = Skin.Frame(frame, C.window, C.lineSoft)
    tableFrame:SetPoint("TOPLEFT", 16, -82)
    tableFrame:SetPoint("BOTTOMRIGHT", -16, 12)
    self.tableFrame = tableFrame
    local header = Skin.Frame(tableFrame, C.bar)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(28)
    self.header = header
    self.headers = {}

    self.list = Skin.List(tableFrame, ROW, InitRow)
    self.list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    self.list:SetPoint("BOTTOMRIGHT", -16, 1)
end

function Page:BuildHeader()
    for _, h in ipairs(self.headers) do h:Hide() end
    self.headers = {}
    local x = 12
    for _, col in ipairs(self.columns) do
        local h = CreateFrame("Button", nil, self.header)
        h:SetPoint("LEFT", x, 0)
        h:SetSize(col.width - 10, 28)
        h.text = Skin.Caption(h, col.label)
        h.text:SetPoint("LEFT", 0, 0)
        h:SetScript("OnClick", function()
            if sortKey == col.key then sortDesc = not sortDesc else sortKey, sortDesc = col.key, col.key ~= "name" end
            Page:Refresh()
        end)
        h.key = col.key
        self.headers[#self.headers + 1] = h
        x = x + col.width
    end
end

function Page:Refresh()
    if not self.frame then return end
    local cols = Columns()
    if not self.columns or #self.columns ~= #cols then
        self.columns = cols
        self:BuildHeader()
    end
    for _, h in ipairs(self.headers) do
        local label = h.text:GetText():gsub(" [%^v]$", "")
        h.text:SetText(label .. (h.key == sortKey and (sortDesc and " v" or " ^") or ""))
        Skin.SetColor(h.text, h.key == sortKey and C.gold or C.dim)
    end

    local rows = Rows()
    self.list:SetRows(rows)

    -- Summary cards.
    local gold, seen, waiting, best, bestKey, ready = AltInventoryDB.warbandMoney or 0, 0, 0, nil, nil, 0
    local now = time()
    for _, row in ipairs(rows) do
        local d = row.data
        gold = gold + (d.money or 0)
        if row.waiting then waiting = waiting + 1 else seen = seen + 1 end
        if d.ilvl and (not best or d.ilvl > best) then best, bestKey = d.ilvl, row.key end
        for _, cd in pairs(d.cooldowns or {}) do
            if (cd.ready or 0) <= now then ready = ready + 1 end
        end
    end
    local cards = self.cards
    cards[1].caption:SetText("TOTAL GOLD")
    cards[1].value:SetText(ns.GoldText(gold))
    Skin.SetColor(cards[1].value, C.gold)
    cards[1].note:SetText(ns.HAS_WARBAND and "with warband" or "")
    cards[2].caption:SetText("CHARACTERS SEEN")
    cards[2].value:SetText(tostring(seen))
    cards[2].note:SetText("of " .. #rows)
    cards[3].caption:SetText("HIGHEST ITEM LEVEL")
    cards[3].value:SetText(best and Skin.ItemLevel(best) or "-")
    if bestKey then
        cards[3].note:SetText(Short(bestKey))
        Skin.SetColor(cards[3].note, Skin.ClassColor(AltInventoryDB.chars[bestKey].class))
    end
    cards[4].caption:SetText("COOLDOWNS READY")
    cards[4].value:SetText(tostring(ready))
    Skin.SetColor(cards[4].value, ready > 0 and C.green or C.text)
    cards[4].note:SetText(ready > 0 and "professions" or "")

    Window:SetStatus("Click a character to see their bags, bank and mail. Click a column to sort.",
        waiting > 0 and (waiting .. " not seen yet: log in once on each") or "")
end

Window:AddPage(Page)
