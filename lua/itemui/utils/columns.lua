--[[
    Column Utilities
    
    Extracted from init.lua for Phase 7 modularization.
    Handles column visibility, display text, and autofit behavior.
--]]

require('ImGui')
local ItemUtils = require('mq.ItemUtils')

local Columns = {}

function Columns.init(deps)
    Columns.availableColumns = deps.availableColumns
    Columns.columnVisibility = deps.columnVisibility
    Columns.columnAutofitWidths = deps.columnAutofitWidths
    Columns.setStatusMessage = deps.setStatusMessage
    Columns.getItemSpellId = deps.getItemSpellId
    Columns.getSpellName = deps.getSpellName
end

function Columns.getVisibleColumns(view)
    local visible = {}
    if Columns.columnVisibility and Columns.columnVisibility[view] then
        for _, colDef in ipairs(Columns.availableColumns[view] or {}) do
            if Columns.columnVisibility[view][colDef.key] then
                table.insert(visible, colDef)
            end
        end
    end
    return visible
end

function Columns.getColumnKeyByIndex(view, index)
    local visible = Columns.getVisibleColumns(view)
    if index > 0 and index <= #visible then
        return visible[index].key
    end
    return nil
end

function Columns.isNumericColumn(colKey)
    local numericKeys = {"Value", "Weight", "Bag", "Slot", "Stack", "StackSizeMax", "ID", "Icon", "AugSlots", "Container", "Size", "SizeCapacity", "Tribute", "RequiredLevel", "RecommendedLevel", "InstrumentMod"}
    for _, key in ipairs(numericKeys) do
        if colKey == key then return true end
    end
    return false
end

function Columns.getCellDisplayText(item, colKey, view)
    if not item then return "" end
    if colKey == "Name" then
        local n = item.name or ""
        if (item.stackSize or 1) > 1 then n = n .. string.format(" (x%d)", item.stackSize) end
        return n
    elseif colKey == "Value" then return ItemUtils.formatValue(item.totalValue or 0)
    elseif colKey == "Weight" then return ItemUtils.formatWeight(item.weight or 0)
    elseif colKey == "Type" then return item.type or ""
    elseif colKey == "Bag" then return tostring(item.bag)
    elseif colKey == "Slot" then return tostring(item.slot)
    elseif colKey == "Stack" then return tostring(item.stackSize or 1)
    elseif colKey == "StackSizeMax" then return tostring(item.stackSizeMax or 1)
    elseif colKey == "ID" then return tostring(item.id or 0)
    elseif colKey == "Icon" then return tostring(item.icon or 0)
    elseif colKey == "AugSlots" then return tostring(item.augSlots or 0)
    elseif colKey == "Container" then return tostring(item.container or 0)
    elseif colKey == "Size" then return tostring(item.size or 0)
    elseif colKey == "SizeCapacity" then return tostring(item.sizeCapacity or 0)
    elseif colKey == "Tribute" then return tostring(item.tribute or 0)
    elseif colKey == "RequiredLevel" then return tostring(item.requiredLevel or 0)
    elseif colKey == "RecommendedLevel" then return tostring(item.recommendedLevel or 0)
    elseif colKey == "InstrumentMod" then return tostring(item.instrumentMod or 0)
    elseif colKey == "Status" then return (view == "Sell" and (item.sellReason or "")) or (view == "Bank" and "") or ""
    elseif colKey == "NoDrop" then return item.nodrop and "Yes" or "No"
    elseif colKey == "NoTrade" then return item.notrade and "Yes" or "No"
    elseif colKey == "NoRent" then return item.norent and "Yes" or "No"
    elseif colKey == "Lore" then return item.lore and "Yes" or "No"
    elseif colKey == "Magic" then return item.magic and "Yes" or "No"
    elseif colKey == "Quest" then return item.quest and "Yes" or "No"
    elseif colKey == "Collectible" then return item.collectible and "Yes" or "No"
    elseif colKey == "Heirloom" then return item.heirloom and "Yes" or "No"
    elseif colKey == "Prestige" then return item.prestige and "Yes" or "No"
    elseif colKey == "Attuneable" then return item.attuneable and "Yes" or "No"
    elseif colKey == "Tradeskills" then return item.tradeskills and "Yes" or "No"
    elseif colKey == "Class" then return item.class or ""
    elseif colKey == "Race" then return item.race or ""
    elseif colKey == "WornSlots" then return item.wornSlots or ""
    elseif colKey == "InstrumentType" then return item.instrumentType or ""
    elseif colKey == "Clicky" then
        local cid = Columns.getItemSpellId(item, "Clicky")
        if cid > 0 then return Columns.getSpellName(cid) or "Unknown"
        else return "No" end
    elseif colKey == "Proc" then
        local pid = Columns.getItemSpellId(item, "Proc")
        if pid > 0 then return Columns.getSpellName(pid) or "Unknown"
        else return "No" end
    elseif colKey == "Focus" then
        local fid = Columns.getItemSpellId(item, "Focus")
        if fid > 0 then return Columns.getSpellName(fid) or "Unknown"
        else return "No" end
    elseif colKey == "Spell" then
        local sid = Columns.getItemSpellId(item, "Spell")
        if sid > 0 then return Columns.getSpellName(sid) or "Unknown"
        else return "No" end
    elseif colKey == "Worn" then
        local wid = Columns.getItemSpellId(item, "Worn")
        if wid > 0 then return Columns.getSpellName(wid) or "Unknown"
        else return "No" end
    end
    return ""
end

function Columns.autofitColumns(view, items, visibleCols)
    if not items or #items == 0 or not visibleCols or #visibleCols == 0 then return end
    local maxWidths = {}
    for i, colDef in ipairs(visibleCols) do
        local headerWidth = ImGui.CalcTextSize(colDef.label)
        maxWidths[i] = headerWidth + 20
    end
    local sampleSize = math.min(#items, 50)
    for idx = 1, sampleSize do
        local item = items[idx]
        if not item then break end
        for i, colDef in ipairs(visibleCols) do
            local colKey = colDef.key
            local text = ""
            if colKey == "Action" then
                text = "Sell Keep Junk"
            else
                text = Columns.getCellDisplayText(item, colKey, view)
            end
            if text ~= "" then
                local textWidth = ImGui.CalcTextSize(text)
                if not maxWidths[i] or textWidth + 20 > maxWidths[i] then
                    maxWidths[i] = textWidth + 20
                end
            end
        end
    end
    for i, colDef in ipairs(visibleCols) do
        if colDef.key ~= "Name" and maxWidths[i] then
            local minWidth = 30
            local targetWidth = math.max(minWidth, maxWidths[i])
            Columns.columnAutofitWidths[view][colDef.key] = targetWidth
        end
    end
    if Columns.setStatusMessage then Columns.setStatusMessage("Columns autofitted") end
end

return Columns
