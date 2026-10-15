-- Alt Inventory - the lines added to item tooltips.

local _, ns = ...

local function OnTooltipSetItem(tooltip, tooltipData)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if not AltInventoryDB then return end

    local itemID = tooltipData and tooltipData.id
    if not itemID then
        local _, link = tooltip:GetItem()
        if link then
            itemID = tonumber(link:match("item:(%d+)"))
        end
    end
    if not itemID then return end

    local lines = {}
    local total = 0

    for charKey, charData in pairs(AltInventoryDB.chars) do
        local text, sum = ns.HoldingText(charData, itemID)
        if sum > 0 then
            total = total + sum
            table.insert(lines, { key = charKey, name = ns.ClassName(charKey, charData.class), text = text })
        end
    end
    table.sort(lines, function(a, b) return a.key < b.key end)

    local warbandCount = (AltInventoryDB.warband and AltInventoryDB.warband[itemID]) or 0
    total = total + warbandCount

    if total == 0 then return end

    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("Alt Inventory", "Total: " .. total, 1, 0.82, 0, 1, 0.82, 0)
    for _, line in ipairs(lines) do
        tooltip:AddDoubleLine(line.name, line.text, 1, 1, 1, 0.8, 0.8, 0.8)
    end
    if warbandCount > 0 then
        tooltip:AddDoubleLine("Warband Bank", ns.WithAge(tostring(warbandCount), AltInventoryDB.warbandScannedAt), 0.6, 0.8, 1, 0.8, 0.8, 0.8)
    end
    tooltip:Show()
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
