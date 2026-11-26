-- Alt Inventory - Weekly page (2.1): this week's progress for every
-- character, one row each: the Great Vault's three rows as pips, the
-- Mythic+ keys done, raid lockouts, and when it resets (Weekly.lua).
-- On WoW Forever and the Classic versions only the raid column shows.

local _, ns = ...
local Skin = ns.Skin
local C = Skin.C
local Window = ns.SearchWindow
local Weekly = ns.Weekly

local Page = { key = "weekly", label = "Weekly", order = 2.7 }
local ROW = 44
local PIP = 7

local VAULT = { { "raid", "RAID" }, { "dungeons", "DUNGEONS" }, { "world", "WORLD" } }

local function Short(key) return key:match("^[^%-]+") or key end
local function Realm(key) return key:match("%-(.+)$") or "" end

local function Columns()
    local cols = { { key = "name", label = "CHARACTER", width = 190 } }
    if Weekly.HasVault() then cols[#cols + 1] = { key = "vault", label = "GREAT VAULT", width = 250 } end
    if Weekly.HasKeys() then cols[#cols + 1] = { key = "keys", label = "KEYS THIS WEEK", width = 130 } end
    cols[#cols + 1] = { key = "raids", label = "RAID LOCKOUTS", width = Weekly.HasVault() and 200 or 560 }
    return cols
end

local function Left(seconds)
    seconds = math.max(0, seconds or 0)
    local days, hours = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
    if days > 0 then return days .. "d " .. hours .. "h" end
    return hours .. "h " .. math.floor(seconds % 3600 / 60) .. "m"
end

local function Rows()
    local rows, now = {}, time()
    for key, data in pairs(AltInventoryDB.chars) do
        rows[#rows + 1] = { key = key, data = data, w = data.weekly, now = now }
    end
    -- Characters with something this week first, then item level.
    local function Score(row)
        local w = row.w
        if not w then return -1 end
        local score = 0
        if not Weekly.IsOld(w, now) then
            for _, slots in pairs(w.vault or {}) do score = score + Weekly.Unlocked(slots) end
            score = score + #(w.keys or {})
        end
        return score + #Weekly.Lockouts(w, now)
    end
    table.sort(rows, function(a, b)
        local sa, sb = Score(a), Score(b)
        if (sa > 0) ~= (sb > 0) then return sa > 0 end
        local ia, ib = a.data.ilvl or 0, b.data.ilvl or 0
        if ia ~= ib then return ia > ib end
        return a.key < b.key
    end)
    for i, row in ipairs(rows) do row.alt = i % 2 == 0 end
    return rows
end

-- One vault row: caption over three pips, gold when unlocked, with the
-- progress towards the next one as a dim fill.
local function VaultBlock(parent)
    local block = CreateFrame("Frame", nil, parent)
    block:SetSize(76, ROW)
    block.caption = Skin.Caption(block, "")
    block.caption:SetPoint("TOPLEFT", 0, -8)
    block.pips = {}
    for i = 1, 3 do
        local pip = Skin.Fill(block, C.deep, "ARTWORK")
        pip:SetSize(PIP * 2, PIP)
        pip:SetPoint("TOPLEFT", (i - 1) * (PIP * 2 + 4), -24)
        block.pips[i] = pip
    end
    block.count = Skin.Text(block, 10, C.dim)
    block.count:SetPoint("LEFT", block.pips[3], "RIGHT", 6, 0)
    return block
end

local function SetVaultBlock(block, label, slots, old)
    block.caption:SetText(label)
    local unlocked = Weekly.Unlocked(slots)
    for i, pip in ipairs(block.pips) do
        local slot = slots and slots[i]
        local color = C.deep
        if slot and slot.threshold > 0 and slot.progress >= slot.threshold then
            color = old and C.dim or C.gold
        elseif slot and slot.progress > 0 then
            color = C.goldLine
        end
        pip:SetColorTexture(color[1], color[2], color[3], 1)
    end
    block.count:SetText(slots and (unlocked .. "/3") or "")
end

local function VaultLevelText(kind, slot)
    if kind == "dungeons" then
        return slot.level > 0 and ("+" .. slot.level) or "Heroic"
    elseif kind == "raid" then
        local name = slot.level and GetDifficultyInfo and GetDifficultyInfo(slot.level)
        return name or ""
    end
    return slot.level > 0 and ("Tier " .. slot.level) or ""
end

local function Tooltip(row, data)
    local d, w, now = data.data, data.w, data.now
    local color = Skin.ClassColor(d.class)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(data.key, color[1], color[2], color[3])
    if not w then
        GameTooltip:AddLine("Log in on this character once to read its week.", 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    local old = Weekly.IsOld(w, now)
    if old then GameTooltip:AddLine("From before the weekly reset.", 1, 0.7, 0.3, true) end
    if Weekly.RewardsWaiting(w, now) then GameTooltip:AddLine("Great Vault rewards waiting.", 0.3, 1, 0.3) end
    if w.vault then
        for _, v in ipairs(VAULT) do
            local slots = w.vault[v[1]]
            if slots and #slots > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(v[2]:sub(1, 1) .. v[2]:sub(2):lower(), 1, 0.82, 0)
                for i, slot in ipairs(slots) do
                    local done = slot.threshold > 0 and slot.progress >= slot.threshold
                    local right = done and (VaultLevelText(v[1], slot) .. (slot.ilvl and ("  ilvl " .. slot.ilvl) or ""))
                        or (math.min(slot.progress, slot.threshold) .. " / " .. slot.threshold)
                    GameTooltip:AddDoubleLine("Slot " .. i, right, 1, 1, 1, done and 0.3 or 0.7, done and 1 or 0.7, done and 0.3 or 0.7)
                end
            end
        end
    end
    if w.keys and not old then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Keys this week (" .. #w.keys .. ")", 1, 0.82, 0)
        local parts = {}
        for i, level in ipairs(w.keys) do
            if i > 16 then break end
            parts[#parts + 1] = "+" .. level
        end
        GameTooltip:AddLine(#parts > 0 and table.concat(parts, "  ") or "None yet", 1, 1, 1, true)
    end
    local lockouts = Weekly.Lockouts(w, now)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Raid lockouts", 1, 0.82, 0)
    if #lockouts == 0 then GameTooltip:AddLine("None", 0.7, 0.7, 0.7) end
    for _, l in ipairs(lockouts) do
        GameTooltip:AddDoubleLine(l.name .. (l.difficulty and (" (" .. l.difficulty .. ")") or ""),
            l.killed .. "/" .. l.total .. "  " .. Left(l.resetAt - now), 1, 1, 1, 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Read " .. date("%d %b %H:%M", w.at) .. ". Click to see their bags.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
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
            if col.key == "vault" then
                cell.blocks = {}
                for i = 1, 3 do
                    local block = VaultBlock(cell)
                    block:SetPoint("TOPLEFT", (i - 1) * 80, 0)
                    cell.blocks[i] = block
                end
            else
                cell.text = Skin.Text(cell, 12, C.text)
                cell.text:SetPoint("TOPLEFT", 0, -8)
                cell.text:SetPoint("RIGHT", 0, 0)
                cell.text:SetWordWrap(false)
                cell.sub = Skin.Text(cell, 10, C.dim)
                cell.sub:SetPoint("TOPLEFT", cell.text, "BOTTOMLEFT", 0, -4)
                cell.sub:SetPoint("RIGHT", 0, 0)
                cell.sub:SetWordWrap(false)
            end
            row.cells[col.key] = cell
            x = x + col.width
        end
    end
    row.bg:SetShown(data.alt)
    local d, w, now = data.data, data.w, data.now
    local old = Weekly.IsOld(w, now)
    local color = Skin.ClassColor(d.class)

    local name = row.cells.name
    name.text:SetText(Short(data.key))
    Skin.SetColor(name.text, w and color or C.dim)
    name.sub:SetText((d.ilvl and (Skin.ItemLevel(d.ilvl) .. "  ") or "") .. Realm(data.key))

    local vault = row.cells.vault
    if vault then
        for i, v in ipairs(VAULT) do SetVaultBlock(vault.blocks[i], v[2], w and w.vault and w.vault[v[1]], old) end
    end

    local keys = row.cells.keys
    if keys then
        local list = (w and not old and w.keys) or {}
        if #list == 0 then
            keys.text:SetText(w and "-" or "")
            keys.sub:SetText(w and (old and "last week" or "none yet") or "")
        else
            local top = {}
            for i = 1, math.min(3, #list) do top[#top + 1] = "+" .. list[i] end
            keys.text:SetText(table.concat(top, "  "))
            keys.sub:SetText(#list .. (#list == 1 and " key" or " keys"))
        end
        Skin.SetColor(keys.text, C.text)
    end

    local raids = row.cells.raids
    local lockouts = Weekly.Lockouts(w, now)
    if not w then
        raids.text:SetText("log in once to see")
        raids.sub:SetText("")
        Skin.SetColor(raids.text, C.dim)
    elseif #lockouts == 0 then
        raids.text:SetText("-")
        raids.sub:SetText(Weekly.RewardsWaiting(w, now) and "vault rewards waiting" or "")
        Skin.SetColor(raids.text, C.dim)
        Skin.SetColor(raids.sub, C.good)
    else
        local first = lockouts[1]
        raids.text:SetText(first.name .. "  " .. (first.difficulty or "") .. "  " .. first.killed .. "/" .. first.total)
        Skin.SetColor(raids.text, first.killed >= first.total and C.good or C.text)
        local more = #lockouts - 1
        raids.sub:SetText((more > 0 and ("+" .. more .. " more  ") or "") .. "resets in " .. Left(first.resetAt - now))
        Skin.SetColor(raids.sub, C.dim)
    end

    row:SetScript("OnClick", function() Window:OpenCharacter(data.key) end)
    row:SetScript("OnEnter", function(self) Tooltip(self, data) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Card(parent)
    local card = Skin.Frame(parent, C.bar, C.lineSoft)
    card:SetHeight(56)
    card.caption = Skin.Caption(card)
    card.caption:SetPoint("TOPLEFT", 12, -10)
    card.value = Skin.Text(card, 17, C.text)
    card.value:SetPoint("TOPLEFT", card.caption, "BOTTOMLEFT", 0, -6)
    card.side = Skin.Text(card, 11, C.dim)
    card.side:SetPoint("BOTTOMRIGHT", -12, 12)
    card.side:SetJustifyH("RIGHT")
    card.side:SetPoint("LEFT", card.value, "RIGHT", 8, 0)
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
        local h = Skin.Caption(self.header, col.label)
        h:SetPoint("LEFT", x, 0)
        self.headers[#self.headers + 1] = h
        x = x + col.width
    end
end

function Page:Show()
    Weekly:Request()
end

function Page:Refresh()
    if not self.frame then return end
    local cols = Columns()
    if not self.columns or #self.columns ~= #cols then
        self.columns = cols
        self:BuildHeader()
    end
    local rows = Rows()
    self.list:SetRows(rows)

    local now = time()
    local waiting, keys, bosses, resetAt, unseen = 0, 0, 0, nil, 0
    for _, row in ipairs(rows) do
        local w = row.w
        if not w then
            unseen = unseen + 1
        else
            if Weekly.RewardsWaiting(w, now) then waiting = waiting + 1 end
            if not Weekly.IsOld(w, now) then
                keys = keys + #(w.keys or {})
                if w.resetAt and (not resetAt or w.resetAt < resetAt) then resetAt = w.resetAt end
            end
            for _, l in ipairs(Weekly.Lockouts(w, now)) do bosses = bosses + l.killed end
        end
    end
    local cards = self.cards
    cards[1].caption:SetText("VAULT REWARDS WAITING")
    cards[1].value:SetText(Weekly.HasVault() and tostring(waiting) or "-")
    Skin.SetColor(cards[1].value, waiting > 0 and C.green or C.text)
    cards[1].side:SetText(waiting > 0 and (waiting == 1 and "character" or "characters") or "")
    cards[2].caption:SetText("KEYS THIS WEEK")
    cards[2].value:SetText(Weekly.HasKeys() and tostring(keys) or "-")
    cards[2].side:SetText(Weekly.HasKeys() and "all characters" or "")
    cards[3].caption:SetText("RAID BOSSES DOWN")
    cards[3].value:SetText(tostring(bosses))
    cards[3].side:SetText("this lockout")
    cards[4].caption:SetText("WEEKLY RESET")
    cards[4].value:SetText(resetAt and Left(resetAt - now) or "-")
    Skin.SetColor(cards[4].value, C.gold)
    cards[4].side:SetText(resetAt and date("%a %H:%M", resetAt) or "")

    Window:SetStatus("Hover a character for every slot, key and lockout. Click for their bags.",
        unseen > 0 and (unseen .. " not read yet: log in once on each") or "")
end

Window:AddPage(Page)
