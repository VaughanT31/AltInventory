-- Alt Inventory - the minimap button and the addon compartment entry (the
-- addon list button on the minimap). Both open the search window.
--
--   AltInventoryDB.minimap = { angle = degrees around the minimap, hide = true|nil }

local _, ns = ...

local Button = {}
ns.MinimapButton = Button

local RADIAN = math.pi / 180
local DEFAULT_ANGLE = 225

local atan2 = math.atan2 or function(y, x)
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

local function Settings()
    AltInventoryDB.minimap = AltInventoryDB.minimap or {}
    return AltInventoryDB.minimap
end

local function Place(button)
    local angle = Settings().angle or DEFAULT_ANGLE
    local radius = (Minimap:GetWidth() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", radius * math.cos(angle * RADIAN), radius * math.sin(angle * RADIAN))
end

local function ShowTooltip(owner, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT")
    GameTooltip:SetText("Alt Inventory")
    GameTooltip:AddLine("Click to search all your characters, banks and mail.", 1, 1, 1, true)
    if owner == Button.frame then
        GameTooltip:AddLine("Drag to move. /altinv minimap hides it.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

function Button:Create()
    if self.frame or not Minimap then return end
    local button = CreateFrame("Button", "AltInventoryMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\AddOns\\AltInventory\\icon")
    local mask = button:CreateMaskTexture()
    mask:SetAllPoints(icon)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            Settings().angle = atan2(cy / scale - my, cx / scale - mx) / RADIAN
            Place(self)
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnClick", function() ns.SearchWindow:Toggle() end)
    button:SetScript("OnEnter", function(self) ShowTooltip(self) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.frame = button
    Place(button)
    button:SetShown(not Settings().hide)
end

-- /altinv minimap: show or hide the button. Returns whether it's shown now.
function Button:Toggle()
    local settings = Settings()
    settings.hide = not settings.hide or nil
    if not self.frame then self:Create() end
    if self.frame then self.frame:SetShown(not settings.hide) end
    return not settings.hide
end

-- Addon compartment (named in the .toc).
function AltInventory_OnAddonCompartmentClick()
    ns.SearchWindow:Toggle()
end

function AltInventory_OnAddonCompartmentEnter(_, button)
    ShowTooltip(button or GameTooltip:GetOwner() or UIParent, "ANCHOR_LEFT")
end

function AltInventory_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
