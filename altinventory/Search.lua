-- Alt Inventory - finding items by name across every character.
--
-- Search.Find(text, filters) -> results, newest data only (what was saved
-- the last time each character was on):
--   { { itemID, name, quality, icon, total,
--       holders = { { key, name, text, count }, ... },  -- one per character
--       warband = count }, ... }
-- text matches anywhere in the item's name, ignoring case. A number, or an
-- item link, matches that item ID. filters: { char = "Name-Realm" | nil,
-- place = "bags" | "bank" | "mail" | "warband" | nil, sort = "name" | "total" }.

local _, ns = ...

local Search = {}
ns.Search = Search

local MAX_RESULTS = 200

-- What was typed, as { id = itemID } or { text = lowercased plain text }.
local function ParseQuery(text)
    text = strtrim and strtrim(text or "") or (text or ""):match("^%s*(.-)%s*$")
    if text == "" then return nil end
    local linked = text:match("|Hitem:(%d+)")
    if linked then return { id = tonumber(linked) } end
    if text:match("^%d+$") then return { id = tonumber(text) } end
    -- A typed name pasted with its brackets still matches.
    return { text = text:gsub("^%[", ""):gsub("%]$", ""):lower() }
end
Search.ParseQuery = ParseQuery

local function Matches(query, itemID, entry)
    if query.id then return itemID == query.id end
    return entry ~= nil and entry.n:lower():find(query.text, 1, true) ~= nil
end

function Search.Find(text, filters)
    filters = filters or {}
    local query = ParseQuery(text)
    if not query or not AltInventoryDB then return {}, 0 end
    local names = AltInventoryDB.names or {}
    local places = nil
    if filters.place and filters.place ~= "warband" then places = { [filters.place] = true } end
    local skipChars = filters.place == "warband"
    local skipWarband = filters.char ~= nil or (filters.place ~= nil and filters.place ~= "warband")

    -- Every item ID worth looking at: named items that match, plus the
    -- typed ID even if its name isn't known yet.
    local byID = {}
    local function Result(itemID)
        local result = byID[itemID]
        if not result then
            local entry = names[itemID]
            result = {
                itemID = itemID, name = entry and entry.n or ("Item " .. itemID),
                quality = entry and entry.q, icon = entry and entry.i,
                total = 0, holders = {}, warband = 0,
            }
            byID[itemID] = result
        end
        return result
    end

    if not skipChars then
        for charKey, charData in pairs(AltInventoryDB.chars or {}) do
            if not filters.char or filters.char == charKey then
                local seen = {}
                for _, place in ipairs(ns.PLACES) do
                    if not places or places[place] then
                        for itemID in pairs(charData[place] or {}) do
                            if not seen[itemID] and Matches(query, itemID, names[itemID]) then
                                seen[itemID] = true
                                local holdingText, count = ns.HoldingText(charData, itemID, places)
                                if count > 0 then
                                    local result = Result(itemID)
                                    result.total = result.total + count
                                    table.insert(result.holders, {
                                        key = charKey, name = ns.ClassName(charKey, charData.class),
                                        text = holdingText, count = count,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if not skipWarband then
        for itemID, count in pairs(AltInventoryDB.warband or {}) do
            if count > 0 and Matches(query, itemID, names[itemID]) then
                local result = Result(itemID)
                result.warband = count
                result.total = result.total + count
            end
        end
    end

    local results = {}
    for _, result in pairs(byID) do
        table.sort(result.holders, function(a, b) return a.count > b.count or (a.count == b.count and a.key < b.key) end)
        results[#results + 1] = result
    end
    if filters.sort == "total" then
        table.sort(results, function(a, b) return a.total > b.total or (a.total == b.total and a.name < b.name) end)
    else
        table.sort(results, function(a, b) return a.name < b.name or (a.name == b.name and a.itemID < b.itemID) end)
    end
    local found = #results
    for i = #results, MAX_RESULTS + 1, -1 do results[i] = nil end
    return results, found
end

-- Every tracked character key, sorted.
function Search.Characters()
    local keys = {}
    for key in pairs(AltInventoryDB and AltInventoryDB.chars or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end
