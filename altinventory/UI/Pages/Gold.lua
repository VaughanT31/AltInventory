-- Alt Inventory - Gold page (2.1): gold over time as a bar chart, for all
-- your gold, the Warband Bank or one character, over 30 days, 90 days or a
-- year (weekly bars), with the list under it to pick which (GoldHistory.lua).

local _, ns = ...
local Skin = ns.Skin
local C = Skin.C
local Window = ns.SearchWindow
local History = ns.GoldHistory

local Page = { key = "gold", label = "Gold", order = 2.5 }
local RANGES = {
    { key = "30", label = "30 days", count = 30, step = 1 },
    { key = "90", label = "90 days", count = 90, step = 1 },
    { key = "365", label = "1 year", count = 52, step = 7 },
}
local CHART_TOP, CHART_HEIGHT = -64, 170
local AXIS = 70
local ROW = 28

local function Short(key) return key:match("^[^%-]+") or key end

local function Range()
    for _, r in ipairs(RANGES) do
        if r.key == (AltInventoryDB.goldRange or "30") then return r end
    end
    return RANGES[1]
end

local function Label(which)
    if which == "all" then return "All your gold" end
    if which == "warband" then return "Warband Bank" end
    return Short(which)
end

local function Signed(copper)
    if not copper then return "" end
    local sign = copper > 0 and "+" or (copper < 0 and "-" or "")
    return sign .. ns.GoldText(math.abs(copper))
end

-- First and last known value of a series, for the change over the range.
local function Ends(series)
    local first, last
    for _, point in ipairs(series) do
        if point.value then
            first = first or point.value
            last = point.value
        end
    end
    return first, last
end

-- List rows -------------------------------------------------------------

local function InitRow(row, data)
    if not row.name then
        row.bg = Skin.Fill(row, C.rowAlt, "BACKGROUND")
        row.bg:SetAllPoints()
        row.sel = Skin.Fill(row, C.goldDeep, "BACKGROUND", 0.9)
        row.sel:SetAllPoints()
        row.hover = row:CreateTexture(nil, "HIGHLIGHT")
        row.hover:SetAllPoints()
        row.hover:SetColorTexture(1, 1, 1, 0.04)
        row.name = Skin.Text(row, 12, C.text)
        row.name:SetPoint("LEFT", 12, 0)
        row.now = Skin.Text(row, 12, C.gold)
        row.now:SetPoint("RIGHT", -180, 0)
        row.now:SetJustifyH("RIGHT")
        row.change = Skin.Text(row, 12, C.muted)
        row.change:SetPoint("RIGHT", -12, 0)
        row.change:SetJustifyH("RIGHT")
    end
    row.bg:SetShown(data.alt)
    row.sel:SetShown(data.which == Page.which)
    row.name:SetText(Label(data.which))
    if data.which == "all" or data.which == "warband" then
        Skin.SetColor(row.name, data.which == "all" and C.gold or C.warband)
    else
        Skin.SetColor(row.name, Skin.ClassColor(data.class))
    end
    row.now:SetText(data.now and ns.GoldText(data.now) or "-")
    row.change:SetText(data.change and Signed(data.change) or "")
    Skin.SetColor(row.change, (data.change or 0) > 0 and C.good or ((data.change or 0) < 0 and C.bad or C.muted))
    row:SetScript("OnClick", function()
        Page.which = data.which
        Page:Refresh()
    end)
end

-- Chart -------------------------------------------------------------------

function Page:BuildChart(frame)
    local chart = Skin.Frame(frame, C.window, C.lineSoft)
    chart:SetPoint("TOPLEFT", 16, CHART_TOP)
    chart:SetPoint("TOPRIGHT", -16, CHART_TOP)
    chart:SetHeight(CHART_HEIGHT)
    self.chart = chart
    chart.top = Skin.Text(chart, 10, C.dim)
    chart.top:SetPoint("TOPLEFT", 8, -10)
    chart.bottom = Skin.Text(chart, 10, C.dim)
    chart.bottom:SetPoint("BOTTOMLEFT", 8, 22)
    chart.first = Skin.Text(chart, 10, C.dim)
    chart.first:SetPoint("BOTTOMLEFT", AXIS, 6)
    chart.last = Skin.Text(chart, 10, C.dim)
    chart.last:SetPoint("BOTTOMRIGHT", -10, 6)
    chart.last:SetJustifyH("RIGHT")
    chart.empty = Skin.Text(chart, 13, C.dim)
    chart.empty:SetPoint("CENTER", 0, 0)
    chart.bars = {}
end

local function Bar(chart, i)
    local bar = chart.bars[i]
    if bar then return bar end
    bar = CreateFrame("Frame", nil, chart)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetPoint("BOTTOMRIGHT")
    bar:EnableMouse(true)
    bar:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.fill:SetAlpha(1)
    end)
    chart.bars[i] = bar
    return bar
end

function Page:DrawChart(series, range)
    local chart = self.chart
    local width = chart:GetWidth()
    if not width or width < 100 then width = 786 end
    local plotWidth = width - AXIS - 10
    local plotHeight = CHART_HEIGHT - 50
    local low, high
    for _, p in ipairs(series) do
        if p.value then
            low = math.min(low or p.value, p.value)
            high = math.max(high or p.value, p.value)
        end
    end
    for _, bar in ipairs(chart.bars) do bar:Hide() end
    if not low then
        chart.empty:SetText("No gold saved yet for this. It's noted each day you log in.")
        chart.top:SetText("")
        chart.bottom:SetText("")
        chart.first:SetText("")
        chart.last:SetText("")
        return
    end
    chart.empty:SetText("")
    -- A little room above and below, so small changes still show.
    local span = high - low
    local pad = math.max(span * 0.15, high * 0.01, 10000)
    local floor = math.max(0, low - pad)
    local ceiling = high + pad
    chart.top:SetText(ns.GoldText(ceiling))
    chart.bottom:SetText(ns.GoldText(floor))
    chart.first:SetText(series[1].day)
    chart.last:SetText(range.step > 1 and ("week to " .. series[#series].day) or series[#series].day)

    local count = #series
    local slot = plotWidth / count
    local gap = slot > 6 and 2 or 1
    local previous
    for i, p in ipairs(series) do
        local bar = Bar(chart, i)
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", AXIS + (i - 1) * slot, 22)
        bar:SetSize(math.max(1, slot - gap), plotHeight)
        if p.value then
            local h = math.max(2, (p.value - floor) / (ceiling - floor) * plotHeight)
            bar.fill:SetHeight(h)
            local up = previous == nil or p.value >= previous
            local color = up and C.gold or C.warn
            bar.fill:SetColorTexture(color[1], color[2], color[3], i == count and 1 or 0.75)
            local before = previous
            bar:SetScript("OnEnter", function(self)
                self.fill:SetAlpha(0.6)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(range.step > 1 and ("Week to " .. p.day) or p.day, 1, 0.82, 0)
                GameTooltip:AddLine(ns.GoldText(p.value), 1, 1, 1)
                if before then
                    local d = p.value - before
                    GameTooltip:AddLine(Signed(d) .. (range.step > 1 and " that week" or " that day"),
                        d >= 0 and 0.3 or 1, d >= 0 and 1 or 0.4, d >= 0 and 0.5 or 0.4)
                end
                GameTooltip:Show()
            end)
            bar:Show()
            previous = p.value
        end
    end
end

-- Page --------------------------------------------------------------------

function Page:Build(frame)
    self.which = "all"
    self.rangeButtons = {}
    local previous
    for _, r in ipairs(RANGES) do
        local b = Skin.Button(frame, r.label, nil, 26, true)
        if previous then b:SetPoint("LEFT", previous, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 16, -18) end
        b:SetScript("OnClick", function()
            AltInventoryDB.goldRange = r.key
            Page:Refresh()
        end)
        b.range = r.key
        self.rangeButtons[#self.rangeButtons + 1] = b
        previous = b
    end

    local summary = Skin.Frame(frame, C.bar, C.lineSoft)
    summary:SetSize(300, 40)
    summary:SetPoint("TOPRIGHT", -16, -12)
    summary.name = Skin.Caption(summary, "")
    summary.name:SetPoint("TOPLEFT", 12, -7)
    summary.value = Skin.Text(summary, 14, C.gold)
    summary.value:SetPoint("TOPLEFT", summary.name, "BOTTOMLEFT", 0, -4)
    summary.change = Skin.Text(summary, 12, C.muted)
    summary.change:SetPoint("RIGHT", -12, -6)
    summary.change:SetJustifyH("RIGHT")
    self.summary = summary

    self:BuildChart(frame)

    local listFrame = Skin.Frame(frame, C.window, C.lineSoft)
    listFrame:SetPoint("TOPLEFT", 16, CHART_TOP - CHART_HEIGHT - 10)
    listFrame:SetPoint("BOTTOMRIGHT", -16, 12)
    self.list = Skin.List(listFrame, ROW, InitRow)
    self.list:SetPoint("TOPLEFT", 4, -4)
    self.list:SetPoint("BOTTOMRIGHT", -18, 4)
end

function Page:Refresh()
    if not self.frame then return end
    local range = Range()
    for _, b in ipairs(self.rangeButtons) do b:SetActive(b.range == range.key) end
    if self.which ~= "all" and self.which ~= "warband" and not AltInventoryDB.chars[self.which] then self.which = "all" end

    local series = History.Series(self.which, range.count, range.step)
    self:DrawChart(series, range)
    local first, last = Ends(series)
    self.summary.name:SetText(Label(self.which):upper())
    self.summary.value:SetText(last and ns.GoldText(last) or "-")
    local change = first and last and last - first
    self.summary.change:SetText(change and (Signed(change) .. " in " .. range.label) or "")
    Skin.SetColor(self.summary.change, (change or 0) > 0 and C.good or ((change or 0) < 0 and C.bad or C.muted))

    -- The list: all, the warband, then characters with gold, most first.
    local rows = {}
    local function Add(which, now, class)
        local f, l = Ends(History.Series(which, range.count, range.step))
        rows[#rows + 1] = { which = which, now = now or l, class = class, change = f and l and (l - f) or nil }
    end
    local total = AltInventoryDB.warbandMoney or 0
    local chars = {}
    for key, data in pairs(AltInventoryDB.chars) do
        if data.money then
            total = total + data.money
            chars[#chars + 1] = { key = key, data = data }
        end
    end
    table.sort(chars, function(a, b) return a.data.money > b.data.money end)
    Add("all", total)
    if ns.HAS_WARBAND then Add("warband", AltInventoryDB.warbandMoney) end
    for _, c in ipairs(chars) do Add(c.key, c.data.money, c.data.class) end
    for i, row in ipairs(rows) do row.alt = i % 2 == 0 end
    self.list:SetRows(rows)

    Window:SetStatus("Click a row to chart it. Hover a bar for that day.",
        "Saved each day a character's gold is read")
end

Window:AddPage(Page)
