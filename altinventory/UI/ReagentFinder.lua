-- Alt Inventory - a small panel beside the profession window: which of your
-- other characters hold the materials for the recipe or crafting order on
-- screen. Only shows when somebody else has something. /altinv reagents or
-- its button beside the window's tabs turns it off and on, and it stacks
-- with the other CtrlShiftZed side panels (UI/SidePanels.lua). Retail and
-- Forever only: the Classic clients have no such window.

local _, ns = ...

local Finder = { rows = {} }
ns.ReagentFinder = Finder

local WIDTH, ROW, MAX_ROWS = 240, 16, 24

local function IsOn()
    return not (AltInventoryDB and AltInventoryDB.reagentFinderOff)
end

-- The materials you'd fill in yourself: { itemID, ... } with every quality.
local function Materials(recipeID, order)
    local T = C_TradeSkillUI
    local ok, schematic = pcall(T.GetRecipeSchematic, recipeID, false)
    if not (ok and schematic) then return {} end
    local provided = {}
    for _, reagent in ipairs(order and order.reagents or {}) do
        provided[reagent.slotIndex] = true
    end
    local items, seen = {}, {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        if slot.required and not provided[slot.slotIndex] then
            for _, reagent in ipairs(slot.reagents or {}) do
                if reagent.itemID and not seen[reagent.itemID] then
                    seen[reagent.itemID] = true
                    items[#items + 1] = reagent.itemID
                end
            end
        end
    end
    return items
end
Finder.Materials = Materials

-- The lines to show: { { kind, itemID, text, right }, ... }.
function Finder.Lines(items)
    local lines = {}
    for _, itemID in ipairs(items) do
        local holders, warband = ns.Characters.Holders(itemID)
        if #holders > 0 or warband > 0 then
            local known = AltInventoryDB.names[itemID]
            lines[#lines + 1] = { kind = "item", itemID = itemID, text = known and known.n or ("Item " .. itemID), quality = known and known.q, icon = known and known.i }
            for _, holder in ipairs(holders) do
                lines[#lines + 1] = { kind = "holder", itemID = itemID, text = holder.name, right = holder.text }
            end
            if warband > 0 then
                lines[#lines + 1] = { kind = "holder", itemID = itemID, text = "|cff99ccffWarband Bank|r", right = tostring(warband) }
            end
        end
    end
    return lines
end

function Finder:Build()
    local f = CreateFrame("Frame", "AltInventoryReagentFinder", ProfessionsFrame, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.06, 0.07, 0.96)
    f:SetBackdropBorderColor(0.3, 0.28, 0.24, 0.9)
    f:SetWidth(WIDTH)
    f:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 4, -30)
    f:Hide()
    self.frame = f
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 8, -7)
    f.title:SetText("On your other characters")
    -- Placed with the other side panels (UI/SidePanels.lua), below the rest.
    ns.SidePanels:Register("altinventory.reagents", {
        frame = f, label = "Other characters", order = 30, pages = { orders = true, recipes = true },
        tip = "Which of your other characters and your Warband Bank hold this recipe's materials. Shows when someone else has something.",
        isOn = IsOn,
        toggle = function() Finder:Toggle() end,
    })
end

function Finder:Show(recipeID, order)
    self.recipeID, self.order = recipeID, order
    if not ProfessionsFrame then return end
    if not self.frame then self:Build() end
    if not (IsOn() and recipeID) then
        self.frame:Hide()
        return
    end
    local lines = Finder.Lines(Materials(recipeID, order))
    if #lines == 0 then
        self.frame:Hide()
        return
    end
    local shown = math.min(#lines, MAX_ROWS)
    for i = 1, shown do
        local line = lines[i]
        local row = self.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, self.frame)
            row:SetHeight(ROW)
            row:SetPoint("TOPLEFT", 6, -24 - (i - 1) * ROW)
            row:SetPoint("RIGHT", -6, 0)
            row:EnableMouse(true)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(14, 14)
            row.icon:SetPoint("LEFT", 0, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.right:SetPoint("RIGHT", 0, 0)
            row.right:SetJustifyH("RIGHT")
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(self.itemID)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            self.rows[i] = row
        end
        row.itemID = line.itemID
        local isItem = line.kind == "item"
        row.icon:SetShown(isItem)
        row.icon:SetTexture(line.icon or 134400)
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", isItem and 18 or 14, 0)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row.text:SetText(line.text)
        local color = isItem and line.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[line.quality]
        if color then row.text:SetTextColor(color.r, color.g, color.b) else row.text:SetTextColor(1, 1, 1) end
        row.right:SetText(line.right and ("|cffcccccc" .. line.right .. "|r") or "")
        row:Show()
    end
    for i = shown + 1, #self.rows do self.rows[i]:Hide() end
    self.frame:SetHeight(32 + shown * ROW)
    self.frame:Show()
end

function Finder:Toggle()
    AltInventoryDB.reagentFinderOff = IsOn() or nil
    self:Show(self.recipeID, self.order)
    return IsOn()
end

-- Hooks the game's profession window once it has loaded.
local function Hook()
    if Finder.hooked or not ProfessionsFrame then return end
    Finder.hooked = true
    if EventRegistry then
        EventRegistry:RegisterCallback("ProfessionsRecipeListMixin.Event.OnRecipeSelected", function(_, recipeInfo)
            pcall(Finder.Show, Finder, recipeInfo and recipeInfo.recipeID)
        end, Finder)
    end
    local view = ProfessionsFrame.OrdersPage and ProfessionsFrame.OrdersPage.OrderView
    if view and view.SetOrder then
        hooksecurefunc(view, "SetOrder", function(_, order)
            pcall(Finder.Show, Finder, order and order.spellID, order)
        end)
    end
end

function Finder:Init()
    if not C_TradeSkillUI or not ns.HAS_WARBAND then return end
    if ProfessionsFrame then
        Hook()
    elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", Hook)
    end
end
