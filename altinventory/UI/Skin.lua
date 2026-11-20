-- Alt Inventory - the 2.0 look: dark panels, gold titles and active tabs,
-- class colours for characters, quality colours for items. Plain textures
-- and backdrops only, so it draws the same on Retail, WoW Forever and every
-- Classic client.

local _, ns = ...

local Skin = {}
ns.Skin = Skin

local function Hex(hex)
    local r, g, b = hex:match("^#?(%x%x)(%x%x)(%x%x)$")
    return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end
Skin.Hex = Hex

Skin.C = {
    backdrop = Hex("#07080a"),
    window = Hex("#14161b"),
    bar = Hex("#1a1d23"),       -- title bar, cards, table header
    side = Hex("#111318"),      -- left columns, status bar
    deep = Hex("#0d0f13"),      -- inputs, bar tracks
    line = Hex("#2c3039"),
    lineSoft = Hex("#262a32"),
    rowAlt = Hex("#16181d"),
    selected = Hex("#22252d"),
    button = Hex("#20232a"),
    buttonLine = Hex("#3a3f4a"),
    gold = Hex("#ffd100"),
    goldDeep = Hex("#2a2414"),
    goldLine = Hex("#6b5a1e"),
    text = Hex("#f1f2f5"),
    body = Hex("#d9dce3"),
    muted = Hex("#a3a8b4"),
    dim = Hex("#8d93a0"),
    good = Hex("#4cc38a"),
    warn = Hex("#ffb347"),
    bad = Hex("#ff5f5f"),
    green = Hex("#1eff00"),
    warband = Hex("#c7ccd6"),
}

Skin.TITLE_FONT = "Fonts\\FRIZQT__.TTF"

local FLAT = "Interface\\Buttons\\WHITE8x8"

-- n UI units rounded to whole screen pixels at this frame's scale, at least
-- n pixels' worth. A plain 1 can land between pixels at some UI scales and
-- the border vanishes on one side.
function Skin.Pixels(frame, n)
    if PixelUtil and PixelUtil.GetNearestPixelSize and frame.GetEffectiveScale then
        return PixelUtil.GetNearestPixelSize(n, frame:GetEffectiveScale(), n)
    end
    return n
end

-- A flat panel with a one-pixel border. bg and border are colour tables.
function Skin.Panel(frame, bg, border, alpha)
    if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = Skin.Pixels(frame, 1) })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], alpha or 1)
    if border then
        frame:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    else
        frame:SetBackdropBorderColor(bg[1], bg[2], bg[3], 0)
    end
    return frame
end

function Skin.Frame(parent, bg, border, kind)
    local f = CreateFrame(kind or "Frame", nil, parent, "BackdropTemplate")
    Skin.Panel(f, bg, border)
    return f
end

-- A solid colour texture.
function Skin.Fill(parent, color, layer, alpha)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    return t
end

-- Text in the given size and colour. font: "title" for Friz, else the
-- game's normal font object at that size.
local fontCache = {}
local function FontObject(size, title)
    local key = (title and "t" or "b") .. size
    if fontCache[key] then return fontCache[key] end
    local font = CreateFont("AltInventoryFont_" .. key)
    if title then
        font:SetFont(Skin.TITLE_FONT, size, "")
    else
        local path, _, flags = GameFontHighlight:GetFont()
        font:SetFont(path, size, flags or "")
    end
    fontCache[key] = font
    return font
end

function Skin.Text(parent, size, color, title, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFontObject(FontObject(size or 12, title))
    color = color or Skin.C.body
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

function Skin.SetColor(fs, color)
    fs:SetTextColor(color[1], color[2], color[3])
end

-- "|cffRRGGBB" for a colour table.
function Skin.Code(color)
    local function Byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return ("|cff%02x%02x%02x"):format(Byte(color[1]), Byte(color[2]), Byte(color[3]))
end

-- Item level with up to two decimals: 333.56, 315.75, 279.
function Skin.ItemLevel(level)
    if type(level) ~= "number" then return "" end
    if level == math.floor(level) then return tostring(level) end
    return (("%.2f"):format(level):gsub("0$", ""))
end

function Skin.ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b } end
    return Skin.C.warband
end

function Skin.QualityColor(quality)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then return { c.r, c.g, c.b } end
    return Skin.C.text
end

-- A pill or plain button with text. Call :SetActive(on) for the gold look.
function Skin.Button(parent, text, width, height, pill)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetHeight(height or 24)
    b.label = Skin.Text(b, 12, Skin.C.muted)
    b.label:SetPoint("CENTER", 0, 0)
    function b:SetLabel(value)
        self.label:SetText(value)
        if not width then self:SetWidth(self.label:GetStringWidth() + 24) end
    end
    if width then b:SetWidth(width) end
    b:SetLabel(text or "")
    function b:SetActive(on)
        self.active = on
        if on then
            Skin.Panel(self, Skin.C.goldDeep, Skin.C.goldLine)
            Skin.SetColor(self.label, Skin.C.gold)
        else
            Skin.Panel(self, pill and Skin.C.window or Skin.C.bar, Skin.C.buttonLine)
            Skin.SetColor(self.label, Skin.C.muted)
        end
    end
    b:SetScript("OnEnter", function(self)
        if not self.active then Skin.SetColor(self.label, Skin.C.text) end
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        if not self.active then Skin.SetColor(self.label, Skin.C.muted) end
        if self.tip then GameTooltip:Hide() end
    end)
    b:SetActive(false)
    return b
end

-- A small square close button with an X.
function Skin.CloseButton(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(28, 28)
    Skin.Panel(b, Skin.C.button, Skin.C.buttonLine)
    local x = Skin.Text(b, 14, Skin.C.muted, true)
    x:SetPoint("CENTER", 0, 1)
    x:SetText("x")
    b:SetScript("OnEnter", function() Skin.SetColor(x, Skin.C.text) end)
    b:SetScript("OnLeave", function() Skin.SetColor(x, Skin.C.muted) end)
    return b
end

-- A thin bar track with a fill, for bag space and play time.
function Skin.Bar(parent, height)
    local track = Skin.Fill(parent, Skin.C.deep, "ARTWORK")
    track:SetHeight(height or 5)
    local fill = parent:CreateTexture(nil, "OVERLAY")
    fill:SetHeight(height or 5)
    fill:SetPoint("LEFT", track, "LEFT")
    local bar = { track = track, fill = fill }
    -- share 0..1 of width px, in color.
    function bar:Set(share, width, color)
        fill:SetColorTexture(color[1], color[2], color[3], 1)
        fill:SetWidth(math.max(1, math.min(1, share or 0) * width))
    end
    return bar
end

-- A section label in small caps style: "DRAENOR", "TOTAL GOLD".
function Skin.Caption(parent, text)
    local fs = Skin.Text(parent, 10, Skin.C.dim)
    fs:SetText(text and text:upper() or "")
    return fs
end

-- A search box: dark input with a gold edge while it has focus.
function Skin.SearchBox(parent)
    local holder = Skin.Frame(parent, Skin.C.deep, Skin.C.buttonLine)
    holder:SetHeight(32)
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 10, 0)
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("common-search-magnifyingglass")
    if hasAtlas then icon:SetAtlas("common-search-magnifyingglass") else icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon") end
    icon:SetVertexColor(Skin.C.dim[1], Skin.C.dim[2], Skin.C.dim[3])
    local box = CreateFrame("EditBox", nil, holder)
    box:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    box:SetPoint("RIGHT", -30, 0)
    box:SetHeight(24)
    box:SetAutoFocus(false)
    box:SetFontObject(FontObject(13))
    box:SetTextColor(Skin.C.text[1], Skin.C.text[2], Skin.C.text[3])
    local hint = Skin.Text(holder, 13, Skin.C.dim)
    hint:SetPoint("LEFT", box, "LEFT", 0, 0)
    local clear = CreateFrame("Button", nil, holder)
    clear:SetSize(20, 20)
    clear:SetPoint("RIGHT", -6, 0)
    local cx = Skin.Text(clear, 12, Skin.C.dim, true)
    cx:SetPoint("CENTER", 0, 1)
    cx:SetText("x")
    clear:SetScript("OnClick", function() box:SetText(""); box:ClearFocus() end)
    local function Update()
        local empty = box:GetText() == ""
        hint:SetShown(empty and not box:HasFocus())
        clear:SetShown(not empty)
        Skin.Panel(holder, Skin.C.deep, box:HasFocus() and Skin.C.gold or Skin.C.buttonLine)
    end
    box:HookScript("OnTextChanged", Update)
    box:HookScript("OnEditFocusGained", Update)
    box:HookScript("OnEditFocusLost", Update)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() box:SetFocus() end)
    function holder:SetHint(text) hint:SetText(text); Update() end
    holder.box = box
    Update()
    return holder
end

-- A scroll list on Blizzard's ScrollBox (all clients have it), with a thin
-- scroll bar. extent: number, or function(data) -> height. init(row, data).
function Skin.List(parent, extent, init, rowKind)
    local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    if type(extent) == "function" then
        view:SetElementExtentCalculator(function(_, data) return extent(data) end)
    else
        view:SetElementExtent(extent)
    end
    view:SetElementInitializer(rowKind or "Button", init)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    box.scrollBar = bar
    function box:SetRows(rows)
        self:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
    end
    return box
end

-- Item and chat link helpers shared by the pages.
function Skin.ItemLink(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = getInfo(itemID)
    return link
end

function Skin.InsertLink(link)
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if link and insert then insert(link) end
end

-- Hover and shift-click behaviour for anything showing an item or currency.
function Skin.ItemScripts(frame)
    frame:SetScript("OnEnter", function(self)
        if not self.itemID and not self.currencyID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.currencyID then GameTooltip:SetCurrencyByID(self.currencyID) else GameTooltip:SetItemByID(self.itemID) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:SetScript("OnClick", function(self, button)
        if self.onRightClick and button == "RightButton" then return self:onRightClick() end
        if IsModifiedClick and IsModifiedClick("CHATLINK") then
            local link
            if self.currencyID then
                link = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink and C_CurrencyInfo.GetCurrencyLink(self.currencyID, 0)
            elseif self.itemID then
                link = Skin.ItemLink(self.itemID)
            end
            Skin.InsertLink(link)
        end
    end)
    if frame.RegisterForClicks then frame:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
end

-- An item icon with a quality-coloured border and a count.
function Skin.ItemIcon(parent, size)
    local f = CreateFrame("Button", nil, parent, "BackdropTemplate")
    f:SetSize(size, size)
    Skin.Panel(f, Skin.C.deep, Skin.C.buttonLine)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 2, -2)
    f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.count = Skin.Text(f, 11, Skin.C.text, false, "OVERLAY")
    f.count:SetPoint("BOTTOMRIGHT", -3, 2)
    f.count:SetShadowOffset(1, -1)
    function f:SetItem(icon, quality, count)
        self.icon:SetTexture(icon or 134400)
        local q = Skin.QualityColor(quality)
        self:SetBackdropBorderColor(q[1], q[2], q[3], 1)
        self.count:SetText(count and count > 1 and (count >= 10000 and (math.floor(count / 1000) .. "k") or tostring(count)) or "")
    end
    return f
end
