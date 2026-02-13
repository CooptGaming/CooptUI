--[[
    Config View - Configuration window for ItemUI and Loot settings
    
    Part of ItemUI Phase 7: View Extraction
    Renders the full config window directly from the view module.
--]]

local mq = require('mq')
require('ImGui')

local ConfigView = {}

local uiState
local filterState
local layoutConfig
local config
local theme
local scheduleLayoutSave
local loadLayoutConfig
local captureCurrentLayoutAsDefault
local resetLayoutToDefault
local saveLayoutToFile
local loadConfigCache
local invalidateSellConfigCache
local invalidateLootConfigCache
local setStatusMessage
local hasItemOnCursor
local macroBridge

local configSellFlags
local configSellValues
local configSellLists
local configLootFlags
local configLootValues
local configLootSorting
local configLootLists
local configEpicClasses
local EPIC_CLASSES

local writeListValue
local writeLootListValue
local writeSharedListValue

local SELL_FILTER_TARGETS
local VALUABLE_FILTER_TARGET
local LOOT_FILTER_TARGETS

local DEFAULT_PROTECT_KEYWORDS = { "Legendary", "Mythical", "Script", "Epic", "Fabled", "Heirloom" }
local DEFAULT_PROTECT_TYPES = { "Food", "Gem", "Augment", "Quest" }

local filterConflictData = nil

local function formatCurrency(copper)
    local n = tonumber(copper) or 0
    n = math.max(0, math.floor(n))
    local platinum = math.floor(n / 1000)
    local gold = math.floor((n % 1000) / 100)
    local silver = math.floor((n % 100) / 10)
    local copperOnly = n % 10
    local parts = {}
    if platinum > 0 then parts[#parts + 1] = string.format("%dp", platinum) end
    if gold > 0 then parts[#parts + 1] = string.format("%dg", gold) end
    if silver > 0 then parts[#parts + 1] = string.format("%ds", silver) end
    parts[#parts + 1] = string.format("%dc", copperOnly)
    return table.concat(parts, " ")
end

local function formatDurationMs(ms)
    local n = tonumber(ms)
    if not n or n < 0 then return "N/A" end
    local totalSeconds = math.floor(n / 1000)
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    return string.format("%dm %02ds", minutes, seconds)
end

local function safeGetStats()
    if not macroBridge or not macroBridge.getStats then return nil end
    local ok, stats = pcall(macroBridge.getStats)
    if not ok then return nil end
    return stats
end

local function renderBreadcrumb(tabLabel, sectionLabel)
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), string.format("You are here: %s > %s", tabLabel, sectionLabel))
    ImGui.Separator()
end

local function bindContext(ctx)
    uiState = ctx.uiState
    filterState = ctx.filterState
    layoutConfig = ctx.layoutConfig
    config = ctx.config
    theme = ctx.theme
    scheduleLayoutSave = ctx.scheduleLayoutSave
    loadLayoutConfig = ctx.loadLayoutConfig
    captureCurrentLayoutAsDefault = ctx.captureCurrentLayoutAsDefault
    resetLayoutToDefault = ctx.resetLayoutToDefault
    saveLayoutToFile = ctx.saveLayoutToFile
    loadConfigCache = ctx.loadConfigCache
    invalidateSellConfigCache = ctx.invalidateSellConfigCache
    invalidateLootConfigCache = ctx.invalidateLootConfigCache
    setStatusMessage = ctx.setStatusMessage
    hasItemOnCursor = ctx.hasItemOnCursor
    macroBridge = ctx.macroBridge

    configSellFlags = ctx.configSellFlags
    configSellValues = ctx.configSellValues
    configSellLists = ctx.configSellLists
    configLootFlags = ctx.configLootFlags
    configLootValues = ctx.configLootValues
    configLootSorting = ctx.configLootSorting
    configLootLists = ctx.configLootLists
    configEpicClasses = ctx.configEpicClasses
    EPIC_CLASSES = ctx.EPIC_CLASSES or {}

    writeListValue = config.writeListValue
    writeLootListValue = config.writeLootListValue
    writeSharedListValue = config.writeSharedListValue
end

--- Format class id for display (e.g. shadow_knight -> Shadow Knight)
local function classLabel(cls)
    if not cls or cls == "" then return "" end
    return (cls:gsub("_", " "):gsub("(%a)(%S*)", function(a, b) return a:upper() .. b:lower() end))
end

local function refreshTargets()
    SELL_FILTER_TARGETS = {
        { id = "keep", label = "Keep (never sell)", hasExact = true, hasContains = true, hasTypes = true,
          exact = { "keepExact", "sell_keep_exact.ini", "exact", writeListValue, configSellLists },
          contains = { "keepContains", "sell_keep_contains.ini", "contains", writeListValue, configSellLists },
          types = { "keepTypes", "sell_keep_types.ini", "types", writeListValue, configSellLists } },
        { id = "junk", label = "Always sell", hasExact = true, hasContains = true, hasTypes = false,
          exact = { "junkExact", "sell_always_sell_exact.ini", "exact", writeListValue, configSellLists },
          contains = { "junkContains", "sell_always_sell_contains.ini", "contains", writeListValue, configSellLists },
          types = nil },
        { id = "protected", label = "Never sell by type", hasExact = false, hasContains = false, hasTypes = true,
          exact = nil, contains = nil,
          types = { "protectedTypes", "sell_protected_types.ini", "types", writeListValue, configSellLists } },
    }

    VALUABLE_FILTER_TARGET = {
        id = "valuable", label = "Valuable (never sell + always loot)", hasExact = true, hasContains = true, hasTypes = true,
        exact = { "sharedExact", "valuable_exact.ini", "exact", writeSharedListValue, configLootLists },
        contains = { "sharedContains", "valuable_contains.ini", "contains", writeSharedListValue, configLootLists },
        types = { "sharedTypes", "valuable_types.ini", "types", writeSharedListValue, configLootLists },
    }

    LOOT_FILTER_TARGETS = {
        { id = "always", label = "Always loot", hasExact = true, hasContains = true, hasTypes = true,
          exact = { "alwaysExact", "loot_always_exact.ini", "exact", writeLootListValue, configLootLists },
          contains = { "alwaysContains", "loot_always_contains.ini", "contains", writeLootListValue, configLootLists },
          types = { "alwaysTypes", "loot_always_types.ini", "types", writeLootListValue, configLootLists } },
        { id = "skip", label = "Skip (never loot)", hasExact = true, hasContains = true, hasTypes = true,
          exact = { "skipExact", "loot_skip_exact.ini", "exact", writeLootListValue, configLootLists },
          contains = { "skipContains", "loot_skip_contains.ini", "contains", writeLootListValue, configLootLists },
          types = { "skipTypes", "loot_skip_types.ini", "types", writeLootListValue, configLootLists } },
    }
end

local function renderUnifiedListSection(sectionId, title, exactKey, containsKey, typesKey, exactIni, containsIni, typesIni, writeFn, lists, hasExact, hasContains, hasTypes, invalidateFn)
    if not ImGui.CollapsingHeader(title) then return end
    filterState.configUnifiedMode[sectionId] = filterState.configUnifiedMode[sectionId] or 0
    local mode = filterState.configUnifiedMode[sectionId]
    local modeNames = {"Full name", "Keyword", "Item type"}
    local modeKeys = {"exact", "contains", "types"}
    local modeLabels = {"Must match whole name", "Name contains this", "e.g. Armor, Weapon"}
    local available = {}
    if hasExact then available[#available + 1] = {idx = 0, key = "exact"} end
    if hasContains then available[#available + 1] = {idx = 1, key = "contains"} end
    if hasTypes then available[#available + 1] = {idx = 2, key = "types"} end
    if #available == 0 then return end
    local modeValid = false
    for _, a in ipairs(available) do if a.idx == mode then modeValid = true; break end end
    if not modeValid then mode = available[1].idx; filterState.configUnifiedMode[sectionId] = mode end
    local listKey = (mode == 0 and exactKey) or (mode == 1 and containsKey) or typesKey
    local iniFile = (mode == 0 and exactIni) or (mode == 1 and containsIni) or typesIni
    local iniKey = modeKeys[mode + 1]
    local inputKey = sectionId .. "_unified"
    filterState.configListInputs[inputKey] = filterState.configListInputs[inputKey] or ""
    if ImGui.BeginCombo("##mode" .. sectionId, modeNames[mode + 1], ImGuiComboFlags.None) then
        for _, a in ipairs(available) do
            if ImGui.Selectable(modeNames[a.idx + 1], mode == a.idx) then
                filterState.configUnifiedMode[sectionId] = a.idx
            end
        end
        ImGui.EndCombo()
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(modeLabels[mode + 1]); ImGui.EndTooltip() end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(200)
    filterState.configListInputs[inputKey], _ = ImGui.InputText("##" .. inputKey, filterState.configListInputs[inputKey] or "")
    ImGui.SameLine()
    if ImGui.Button("Add##" .. sectionId, ImVec2(50, 0)) then
        local name = (filterState.configListInputs[inputKey] or ""):match("^%s*(.-)%s*$")
        if name ~= "" then
            local list = lists[listKey]
            local found = false
            for _, s in ipairs(list) do if s == name then found = true; break end end
            if not found then
                list[#list + 1] = name
                filterState.configListInputs[inputKey] = ""
                writeFn(iniFile, "Items", iniKey, config.joinList(list))
                if invalidateFn then invalidateFn() end
            end
        end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Add to list"); ImGui.EndTooltip() end
    ImGui.SameLine()
    do
        local hc = hasItemOnCursor()
        if not hc then ImGui.BeginDisabled() end
        if ImGui.Button("From cursor##" .. sectionId, ImVec2(80, 0)) then
            local toAdd = nil
            if mode == 0 or mode == 1 then
                local raw = mq.TLO.Cursor and mq.TLO.Cursor.Name and mq.TLO.Cursor.Name()
                if raw and raw ~= "" then toAdd = config.sanitizeItemName(raw) end
            else
                local raw = mq.TLO.Cursor and mq.TLO.Cursor.Type and mq.TLO.Cursor.Type()
                if raw and raw ~= "" then toAdd = raw:match("^%s*(.-)%s*$") end
            end
            if toAdd and toAdd ~= "" then
                filterState.configListInputs[inputKey] = toAdd
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            if mode == 0 then ImGui.Text("Pick up an item, then click to fill its full name into the field.")
            elseif mode == 1 then ImGui.Text("Pick up an item, then click to fill its name as a keyword.")
            else ImGui.Text("Pick up an item, then click to fill its type (e.g. Armor, Weapon) into the field.") end
            ImGui.EndTooltip()
        end
        if not hc then ImGui.EndDisabled() end
    end
    local function addEntry(kind, listKey, iniFile, iniKey, lists)
        local list = lists[listKey]
        for i = #list, 1, -1 do
            local it = list[i]
            ImGui.PushID(sectionId .. kind .. i)
            local badge = (kind == "exact" and "[name]") or (kind == "contains" and "[keyword]") or "[type]"
            ImGui.TextColored(theme.ToVec4(theme.Colors.Header), badge)
            ImGui.SameLine(60)
            ImGui.Text(it)
            ImGui.SameLine(ImGui.GetContentRegionAvail() - 30)
            if ImGui.Button("X", ImVec2(22, 0)) then
                table.remove(list, i)
                writeFn(iniFile, "Items", iniKey, config.joinList(list))
                if invalidateFn then invalidateFn() end
            end
            ImGui.PopID()
        end
    end
    local _, listAvailY = ImGui.GetContentRegionAvail()
    local listHeight = math.max(220, math.floor(listAvailY * 0.5))
    ImGui.BeginChild(sectionId .. "List", ImVec2(0, listHeight), true)
    if exactKey and lists[exactKey] then
        addEntry("exact", exactKey, exactIni, "exact", lists)
    end
    if containsKey and lists[containsKey] then
        addEntry("contains", containsKey, containsIni, "contains", lists)
    end
    if typesKey and lists[typesKey] then
        addEntry("types", typesKey, typesIni, "types", lists)
    end
    ImGui.EndChild()
end

local function getSellTargetById(id)
    for _, t in ipairs(SELL_FILTER_TARGETS) do if t.id == id then return t end end
    return nil
end

local function getLootTargetById(id)
    for _, t in ipairs(LOOT_FILTER_TARGETS) do if t.id == id then return t end end
    return nil
end

local function checkSellFilterConflicts(targetId, typeKey, value)
    local conflicts = {}
    if targetId == "keep" or targetId == "junk" then
        local otherId = (targetId == "keep") and "junk" or "keep"
        local other = getSellTargetById(otherId)
        if other and other[typeKey] then
            local def = other[typeKey]
            local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
            local list = lists[listKey]
            for _, s in ipairs(list) do
                if s == value then
                    conflicts[#conflicts + 1] = { targetId = otherId, label = other.label }
                    break
                end
            end
        end
    end
    if targetId == "junk" then
        local v = VALUABLE_FILTER_TARGET
        if v and v[typeKey] then
            local def = v[typeKey]
            local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
            local list = lists[listKey]
            for _, s in ipairs(list) do
                if s == value then
                    conflicts[#conflicts + 1] = { targetId = "valuable", label = v.label }
                    break
                end
            end
        end
    end
    return conflicts
end

local function checkValuableFilterConflicts(typeKey, value)
    local conflicts = {}
    local junk = getSellTargetById("junk")
    if junk and junk[typeKey] then
        local def = junk[typeKey]
        local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
        local list = lists[listKey]
        for _, s in ipairs(list) do
            if s == value then
                conflicts[#conflicts + 1] = { targetId = "junk", label = junk.label }
                break
            end
        end
    end
    local skip = getLootTargetById("skip")
    if skip and skip[typeKey] then
        local def = skip[typeKey]
        local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
        local list = lists[listKey]
        for _, s in ipairs(list) do
            if s == value then
                conflicts[#conflicts + 1] = { targetId = "skip", label = skip.label }
                break
            end
        end
    end
    return conflicts
end

local function checkLootFilterConflicts(targetId, typeKey, value)
    local conflicts = {}
    if targetId == "always" then
        local skip = getLootTargetById("skip")
        if skip and skip[typeKey] then
            local def = skip[typeKey]
            local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
            local list = lists[listKey]
            for _, s in ipairs(list) do
                if s == value then
                    conflicts[#conflicts + 1] = { targetId = "skip", label = skip.label }
                    break
                end
            end
        end
    elseif targetId == "skip" then
        local always = getLootTargetById("always")
        if always then
            local function inList(def)
                if not def then return false end
                local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
                local list = lists[listKey]
                for _, s in ipairs(list) do if s == value then return true end end
                return false
            end
            if inList(always[typeKey]) then
                conflicts[#conflicts + 1] = { targetId = "always", label = always.label }
            end
            local v = VALUABLE_FILTER_TARGET
            if inList(v[typeKey]) then
                conflicts[#conflicts + 1] = { targetId = "valuable", label = v.label }
            end
        end
    end
    return conflicts
end

local function performSellFilterAdd(targetId, typeKey, value)
    local target = getSellTargetById(targetId)
    if not target then return false end
    local def = target[typeKey]
    if not def then return false end
    local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
    local list = lists[listKey]
    for _, s in ipairs(list) do if s == value then return false end end
    list[#list + 1] = value
    writeFn(iniFile, "Items", iniKey, config.joinList(list))
    invalidateSellConfigCache()
    return true
end

local function performValuableFilterAdd(typeKey, value)
    local v = VALUABLE_FILTER_TARGET
    if not v or not v[typeKey] then return false end
    local def = v[typeKey]
    local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
    local list = lists[listKey]
    for _, s in ipairs(list) do if s == value then return false end end
    list[#list + 1] = value
    writeFn(iniFile, "Items", iniKey, config.joinList(list))
    invalidateSellConfigCache()
    return true
end

local function performLootFilterAdd(targetId, typeKey, value)
    local target = getLootTargetById(targetId)
    if not target then return false end
    local def = target[typeKey]
    if not def then return false end
    local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
    local list = lists[listKey]
    for _, s in ipairs(list) do if s == value then return false end end
    list[#list + 1] = value
    writeFn(iniFile, "Items", iniKey, config.joinList(list))
    invalidateSellConfigCache()
    invalidateLootConfigCache()
    return true
end

local function removeFromSellFilterList(targetId, typeKey, value)
    local target = getSellTargetById(targetId)
    if not target or not target[typeKey] then return false end
    local def = target[typeKey]
    local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
    local list = lists[listKey]
    for i = #list, 1, -1 do
        if list[i] == value then
            table.remove(list, i)
            writeFn(iniFile, "Items", iniKey, config.joinList(list))
            invalidateSellConfigCache()
            return true
        end
    end
    return false
end

local function removeFromLootFilterList(targetId, typeKey, value)
    local target = getLootTargetById(targetId)
    if not target or not target[typeKey] then return false end
    local def = target[typeKey]
    local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
    local list = lists[listKey]
    for i = #list, 1, -1 do
        if list[i] == value then
            table.remove(list, i)
            writeFn(iniFile, "Items", iniKey, config.joinList(list))
            invalidateSellConfigCache()
            invalidateLootConfigCache()
            return true
        end
    end
    return false
end

local function removeFromValuableFilterList(typeKey, value)
    local v = VALUABLE_FILTER_TARGET
    if not v or not v[typeKey] then return false end
    local def = v[typeKey]
    local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
    local list = lists[listKey]
    for i = #list, 1, -1 do
        if list[i] == value then
            table.remove(list, i)
            writeFn(iniFile, "Items", iniKey, config.joinList(list))
            invalidateSellConfigCache()
            return true
        end
    end
    return false
end

local function renderFilterConflictModal()
    if filterConflictData and not ImGui.IsPopupOpen("FilterConflict##ItemUI") then
        filterConflictData = nil
    end
    if not filterConflictData or not ImGui.BeginPopupModal("FilterConflict##ItemUI", nil, ImGuiWindowFlags.AlwaysAutoResize) then return end
    local d = filterConflictData
    local target = nil
    if d.section == "sell" then target = getSellTargetById(d.targetId)
    elseif d.section == "valuable" then target = VALUABLE_FILTER_TARGET
    else target = getLootTargetById(d.targetId) end
    local targetLabel = target and target.label or d.targetId
    local conflictLabels = {}
    for _, c in ipairs(d.conflicts) do conflictLabels[#conflictLabels + 1] = c.label end
    ImGui.TextColored(theme.ToVec4(theme.Colors.Warning), "Filter conflict")
    ImGui.Separator()
    ImGui.TextWrapped(string.format("'%s' is already in: %s", d.value, table.concat(conflictLabels, ", ")))
    ImGui.TextWrapped(string.format("Adding to %s would create a conflict.", targetLabel))
    ImGui.Spacing()
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), d.section == "sell" and "Sell: Keep vs Always sell. Valuable vs Always sell." or (d.section == "valuable" and "Valuable vs Always sell, Skip." or "Loot: Always loot vs Skip. Valuable vs Skip."))
    ImGui.Spacing()
    if ImGui.Button("Add anyway##FilterConflict", ImVec2(120, 0)) then
        local ok = false
        if d.section == "sell" then ok = performSellFilterAdd(d.targetId, d.typeKey, d.value)
        elseif d.section == "valuable" then ok = performValuableFilterAdd(d.typeKey, d.value)
        else ok = performLootFilterAdd(d.targetId, d.typeKey, d.value) end
        if ok then
            if d.section == "sell" then filterState.sellFilterInputValue = ""
            elseif d.section == "valuable" then filterState.valuableFilterInputValue = ""
            else filterState.lootFilterInputValue = "" end
            setStatusMessage("Added to " .. targetLabel .. " (conflict ignored)")
        end
        filterConflictData = nil
        ImGui.CloseCurrentPopup()
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Add to list without removing from conflicting list(s)"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("Remove from conflicting, then add##FilterConflict", ImVec2(220, 0)) then
        local function removeConflict(c)
            if c.targetId == "valuable" then removeFromValuableFilterList(d.typeKey, d.value)
            elseif c.targetId == "junk" or c.targetId == "keep" or c.targetId == "protected" then removeFromSellFilterList(c.targetId, d.typeKey, d.value)
            else removeFromLootFilterList(c.targetId, d.typeKey, d.value) end
        end
        for _, c in ipairs(d.conflicts) do removeConflict(c) end
        local ok = false
        if d.section == "sell" then ok = performSellFilterAdd(d.targetId, d.typeKey, d.value)
        elseif d.section == "valuable" then ok = performValuableFilterAdd(d.typeKey, d.value)
        else ok = performLootFilterAdd(d.targetId, d.typeKey, d.value) end
        if ok then
            if d.section == "sell" then filterState.sellFilterInputValue = ""
            elseif d.section == "valuable" then filterState.valuableFilterInputValue = ""
            else filterState.lootFilterInputValue = "" end
            setStatusMessage("Removed from conflicting list(s), added to " .. targetLabel)
        end
        filterConflictData = nil
        ImGui.CloseCurrentPopup()
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Remove from conflicting list(s) first, then add to selected list"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("Cancel##FilterConflict", ImVec2(80, 0)) then
        filterConflictData = nil
        ImGui.CloseCurrentPopup()
    end
    ImGui.EndPopup()
end

local function loadDefaultProtectList()
    local added = 0
    for _, kw in ipairs(DEFAULT_PROTECT_KEYWORDS) do
        local list = configSellLists.keepContains
        local found = false
        for _, s in ipairs(list) do if s == kw then found = true; break end end
        if not found then list[#list + 1] = kw; config.writeListValue("sell_keep_contains.ini", "Items", "contains", config.joinList(list)); added = added + 1 end
    end
    for _, typ in ipairs(DEFAULT_PROTECT_TYPES) do
        local list = configSellLists.protectedTypes
        local found = false
        for _, s in ipairs(list) do if s == typ then found = true; break end end
        if not found then list[#list + 1] = typ; config.writeListValue("sell_protected_types.ini", "Items", "types", config.joinList(list)); added = added + 1 end
    end
    invalidateSellConfigCache()
    setStatusMessage(added > 0 and string.format("Added %d default protect entries", added) or "Default protect list already loaded")
end

local function renderFilterSection(section, targets, targetId, typeMode, inputValue, editTarget, listShow, setTargetId, setTypeMode, setInputValue, setEditTarget, setListShow, checkConflicts, performAdd, removeFromList)
    local typeNames = {"Full name", "Keyword", "Item type"}
    local typeKeys = {"exact", "contains", "types"}
    local typeLabels = {"Must match whole item name", "Item name contains this text", "e.g. Armor, Weapon"}
    local filterPlaceholders = {"e.g. Rusty Dagger", "e.g. Epic", "e.g. Armor, Weapon"}

    if editTarget then
        setTargetId(editTarget.targetId)
        setTypeMode((editTarget.typeKey == "exact" and 0) or (editTarget.typeKey == "contains" and 1) or 2)
        setInputValue(editTarget.value or "")
        setEditTarget(nil)
    end

    local target = nil
    for _, t in ipairs(targets) do if t.id == targetId then target = t; break end end
    if not target then target = targets[1]; setTargetId(target.id) end

    local available = {}
    if target.hasExact then available[#available + 1] = { idx = 0, key = "exact" } end
    if target.hasContains then available[#available + 1] = { idx = 1, key = "contains" } end
    if target.hasTypes then available[#available + 1] = { idx = 2, key = "types" } end
    local modeValid = false
    for _, a in ipairs(available) do if a.idx == typeMode then modeValid = true; break end end
    if not modeValid then setTypeMode(available[1] and available[1].idx or 0) end

    ImGui.SetNextItemWidth(220)
    if ImGui.BeginCombo("List##" .. section, target.label, ImGuiComboFlags.None) then
        for _, t in ipairs(targets) do
            if ImGui.Selectable(t.label, targetId == t.id) then
                setTargetId(t.id)
                local avail = {}
                if t.hasExact then avail[#avail + 1] = 0 end
                if t.hasContains then avail[#avail + 1] = 1 end
                if t.hasTypes then avail[#avail + 1] = 2 end
                local valid = false
                for _, m in ipairs(avail) do if m == typeMode then valid = true; break end end
                if not valid then setTypeMode(avail[1] or 0) end
            end
        end
        ImGui.EndCombo()
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Which list to add to"); ImGui.EndTooltip() end

    ImGui.SameLine()
    ImGui.SetNextItemWidth(85)
    if ImGui.BeginCombo("##Type" .. section, typeNames[typeMode + 1], ImGuiComboFlags.None) then
        for _, a in ipairs(available) do
            if ImGui.Selectable(typeNames[a.idx + 1], typeMode == a.idx) then setTypeMode(a.idx) end
        end
        ImGui.EndCombo()
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(typeLabels[typeMode + 1]); ImGui.EndTooltip() end

    ImGui.SetNextItemWidth(-200)
    local submitted
    if section == "sell" then
        filterState.sellFilterInputValue, submitted = ImGui.InputTextWithHint("##FilterInputSell", filterPlaceholders[typeMode + 1], filterState.sellFilterInputValue or "", ImGuiInputTextFlags.EnterReturnsTrue)
    else
        filterState.lootFilterInputValue, submitted = ImGui.InputTextWithHint("##FilterInputLoot", filterPlaceholders[typeMode + 1], filterState.lootFilterInputValue or "", ImGuiInputTextFlags.EnterReturnsTrue)
    end

    ImGui.SameLine()
    do
        local hc = hasItemOnCursor()
        if not hc then ImGui.BeginDisabled() end
        if ImGui.Button("From cursor##" .. section, ImVec2(95, 0)) then
            local toAdd = nil
            if typeMode == 0 or typeMode == 1 then
                local raw = mq.TLO.Cursor and mq.TLO.Cursor.Name and mq.TLO.Cursor.Name()
                if raw and raw ~= "" then toAdd = config.sanitizeItemName(raw) end
            else
                local raw = mq.TLO.Cursor and mq.TLO.Cursor.Type and mq.TLO.Cursor.Type()
                if raw and raw ~= "" then toAdd = raw:match("^%s*(.-)%s*$") end
            end
            if toAdd and toAdd ~= "" then
                setInputValue(toAdd)
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            if typeMode == 0 then ImGui.Text("Pick up an item, then click to fill its full name into the field.")
            elseif typeMode == 1 then ImGui.Text("Pick up an item, then click to fill its name as a keyword.")
            else ImGui.Text("Pick up an item, then click to fill its type (e.g. Armor, Weapon) into the field.") end
            ImGui.EndTooltip()
        end
        if not hc then ImGui.EndDisabled() end
    end

    ImGui.SameLine()
    local addClicked = ImGui.Button("Add item##" .. section, ImVec2(80, 0))
    local val = (section == "sell" and filterState.sellFilterInputValue or filterState.lootFilterInputValue or ""):match("^%s*(.-)%s*$")
    if (addClicked or submitted) and val ~= "" then
        local typeKey = typeKeys[typeMode + 1]
        local def = target[typeKey]
        if def then
            local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
            local list = lists[listKey]
            local found = false
            for _, s in ipairs(list) do if s == val then found = true; break end end
            if not found then
                local conflicts = checkConflicts(target.id, typeKey, val)
                if #conflicts > 0 then
                    filterConflictData = { section = section, targetId = target.id, typeKey = typeKey, value = val, conflicts = conflicts }
                    ImGui.OpenPopup("FilterConflict##ItemUI")
                else
                    if performAdd(target.id, typeKey, val) then
                        if section == "sell" then filterState.sellFilterInputValue = "" else filterState.lootFilterInputValue = "" end
                        setStatusMessage("Added to " .. target.label)
                    end
                end
            end
        end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Add to list (or press Enter)"); ImGui.EndTooltip() end
end

local function renderFiltersSection(forcedSubTab, showTabs)
    renderFilterConflictModal()

    local activeSubTab = forcedSubTab or filterState.filterSubTab or 1
    if showTabs ~= false then
        if ImGui.Button("Sell", ImVec2(70, 0)) then filterState.filterSubTab = 1; activeSubTab = 1; scheduleLayoutSave() end
        if filterState.filterSubTab == 1 then ImGui.SameLine(0, 0); ImGui.TextColored(theme.ToVec4(theme.Colors.Success), " <") end
        ImGui.SameLine()
        if ImGui.Button("Valuable", ImVec2(80, 0)) then filterState.filterSubTab = 2; activeSubTab = 2; scheduleLayoutSave() end
        if filterState.filterSubTab == 2 then ImGui.SameLine(0, 0); ImGui.TextColored(theme.ToVec4(theme.Colors.Success), " <") end
        ImGui.SameLine()
        if ImGui.Button("Loot", ImVec2(70, 0)) then filterState.filterSubTab = 3; activeSubTab = 3; scheduleLayoutSave() end
        if filterState.filterSubTab == 3 then ImGui.SameLine(0, 0); ImGui.TextColored(theme.ToVec4(theme.Colors.Success), " <") end
        ImGui.Separator()
    else
        filterState.filterSubTab = activeSubTab
    end

    local _, availY = ImGui.GetContentRegionAvail()
    local childHeight = math.max(240, availY - 8)
    ImGui.BeginChild("FiltersContent", ImVec2(0, childHeight), true, ImGuiWindowFlags.AlwaysVerticalScrollbar)

    if activeSubTab == 1 then
        ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.HeaderAlt))
        ImGui.TextWrapped("Always sell unless a qualification is met. Add items to Keep (never sell), Always sell, or Never sell by type.")
        ImGui.PopStyleColor()
        ImGui.Spacing()

        renderFilterSection("sell", SELL_FILTER_TARGETS, filterState.sellFilterTargetId, filterState.sellFilterTypeMode, filterState.sellFilterInputValue, filterState.sellFilterEditTarget, filterState.sellFilterListShow,
            function(v) filterState.sellFilterTargetId = v end, function(v) filterState.sellFilterTypeMode = v end, function(v) filterState.sellFilterInputValue = v end,
            function(v) filterState.sellFilterEditTarget = v end, function(v) filterState.sellFilterListShow = v end,
            function(tid, tk, val) return checkSellFilterConflicts(tid, tk, val) end,
            function(tid, tk, val) return performSellFilterAdd(tid, tk, val) end,
            removeFromSellFilterList)

        if ImGui.Button("Load default protect list##Sell", ImVec2(180, 0)) then loadDefaultProtectList() end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Add default keywords (Legendary, Mythical, Script, etc.) and types (Food, Gem, Augment, Quest)"); ImGui.EndTooltip() end

        ImGui.Spacing()
        ImGui.SetNextItemWidth(180)
        local showLabels = { ["all"] = "Show: All" }
        for _, t in ipairs(SELL_FILTER_TARGETS) do showLabels[t.id] = "Show: " .. t.label end
        if ImGui.BeginCombo("##SellFilterShow", showLabels[filterState.sellFilterListShow] or "Show: All", ImGuiComboFlags.None) then
            if ImGui.Selectable("Show: All", filterState.sellFilterListShow == "all") then filterState.sellFilterListShow = "all" end
            for _, t in ipairs(SELL_FILTER_TARGETS) do
                if ImGui.Selectable("Show: " .. t.label, filterState.sellFilterListShow == t.id) then filterState.sellFilterListShow = t.id end
            end
            ImGui.EndCombo()
        end
        ImGui.Separator()

        local FILTER_BADGE = 85
        local FILTER_LIST_W = 200
        local FILTER_X_W = 32
        local sellEntries = {}
        for _, t in ipairs(SELL_FILTER_TARGETS) do
            if filterState.sellFilterListShow ~= "all" and filterState.sellFilterListShow ~= t.id then goto sell_collect_cont end
            local function collectEntries(kind, def)
                if not def then return end
                local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
                local list = lists[listKey]
                local badge = (kind == "exact" and "[name]") or (kind == "contains" and "[keyword]") or "[type]"
                for i = 1, #list do
                    local it = list[i]
                    sellEntries[#sellEntries + 1] = { listLabel = t.label, typeBadge = badge, value = it, targetId = t.id, typeKey = kind, list = list, listIndex = i, iniFile = iniFile, iniKey = iniKey, writeFn = writeFn }
                end
            end
            collectEntries("exact", t.exact)
            collectEntries("contains", t.contains)
            collectEntries("types", t.types)
            ::sell_collect_cont::
        end
        if ImGui.BeginTable("SellFiltersTable", 4, ImGuiTableFlags.BordersOuter + ImGuiTableFlags.BordersInnerH + ImGuiTableFlags.ScrollX + ImGuiTableFlags.SizingStretchProp + ImGuiTableFlags.Sortable) then
            ImGui.TableSetupColumn("List", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), FILTER_LIST_W, 0)
            ImGui.TableSetupColumn("Type", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), FILTER_BADGE, 1)
            ImGui.TableSetupColumn("Value", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable, ImGuiTableColumnFlags.DefaultSort), 1, 2)
            ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, FILTER_X_W, 3)
            local sortSpecs = ImGui.TableGetSortSpecs()
            if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
                local spec = sortSpecs:Specs(1)
                if spec and spec.ColumnIndex >= 0 and spec.ColumnIndex <= 2 then
                    filterState.sellFilterSortColumn = spec.ColumnIndex
                    filterState.sellFilterSortDirection = spec.SortDirection
                end
                sortSpecs.SpecsDirty = false
            end
            ImGui.TableHeadersRow()
            table.sort(sellEntries, function(a, b)
                local av, bv
                if filterState.sellFilterSortColumn == 0 then av, bv = a.listLabel or "", b.listLabel or ""
                elseif filterState.sellFilterSortColumn == 1 then av, bv = a.typeBadge or "", b.typeBadge or ""
                else av, bv = a.value or "", b.value or "" end
                av, bv = tostring(av):lower(), tostring(bv):lower()
                if filterState.sellFilterSortDirection == ImGuiSortDirection.Ascending then return av < bv else return av > bv end
            end)
            for _, e in ipairs(sellEntries) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                ImGui.TextColored(theme.ToVec4(theme.Colors.Info), e.listLabel)
                ImGui.TableNextColumn()
                ImGui.TextColored(theme.ToVec4(theme.Colors.Header), e.typeBadge)
                ImGui.TableNextColumn()
                ImGui.TextWrapped(e.value)
                ImGui.TableNextColumn()
                ImGui.PushID("sell" .. e.targetId .. e.typeKey .. e.listIndex)
                if ImGui.Button("X##Sell", ImVec2(-1, 0)) then
                    table.remove(e.list, e.listIndex)
                    e.writeFn(e.iniFile, "Items", e.iniKey, config.joinList(e.list))
                    invalidateSellConfigCache()
                    filterState.sellFilterEditTarget = { targetId = e.targetId, typeKey = e.typeKey, value = e.value }
                    setStatusMessage("Removed; form filled for edit")
                end
                ImGui.PopID()
            end
            ImGui.EndTable()
        end
    elseif activeSubTab == 2 then
        ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.HeaderAlt))
        ImGui.TextWrapped("Valuable items are never sold and always looted. Shared between sell.mac and loot.mac.")
        ImGui.PopStyleColor()
        ImGui.Spacing()

        local typeNames = {"Full name", "Keyword", "Item type"}
        local typeKeys = {"exact", "contains", "types"}
        local filterPlaceholders = {"e.g. Rusty Dagger", "e.g. Epic", "e.g. Armor, Weapon"}
        if filterState.valuableFilterEditTarget then
            filterState.valuableFilterTypeMode = (filterState.valuableFilterEditTarget.typeKey == "exact" and 0) or (filterState.valuableFilterEditTarget.typeKey == "contains" and 1) or 2
            filterState.valuableFilterInputValue = filterState.valuableFilterEditTarget.value or ""
            filterState.valuableFilterEditTarget = nil
        end
        local v = VALUABLE_FILTER_TARGET
        ImGui.SetNextItemWidth(85)
        if ImGui.BeginCombo("##ValuableType", typeNames[filterState.valuableFilterTypeMode + 1], ImGuiComboFlags.None) then
            for i = 0, 2 do
                if ImGui.Selectable(typeNames[i + 1], filterState.valuableFilterTypeMode == i) then filterState.valuableFilterTypeMode = i end
            end
            ImGui.EndCombo()
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(-200)
        local submitted
        filterState.valuableFilterInputValue, submitted = ImGui.InputTextWithHint("##ValuableInput", filterPlaceholders[filterState.valuableFilterTypeMode + 1], filterState.valuableFilterInputValue or "", ImGuiInputTextFlags.EnterReturnsTrue)
        ImGui.SameLine()
        do
            local hc = hasItemOnCursor()
            if not hc then ImGui.BeginDisabled() end
            if ImGui.Button("From cursor##Valuable", ImVec2(95, 0)) then
                local toAdd = nil
                if filterState.valuableFilterTypeMode == 0 or filterState.valuableFilterTypeMode == 1 then
                    local raw = mq.TLO.Cursor and mq.TLO.Cursor.Name and mq.TLO.Cursor.Name()
                    if raw and raw ~= "" then toAdd = config.sanitizeItemName(raw) end
                else
                    local raw = mq.TLO.Cursor and mq.TLO.Cursor.Type and mq.TLO.Cursor.Type()
                    if raw and raw ~= "" then toAdd = raw:match("^%s*(.-)%s*$") end
                end
                if toAdd and toAdd ~= "" then
                    filterState.valuableFilterInputValue = toAdd
                end
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                if filterState.valuableFilterTypeMode == 0 then ImGui.Text("Pick up an item, then click to fill its full name into the field.")
                elseif filterState.valuableFilterTypeMode == 1 then ImGui.Text("Pick up an item, then click to fill its name as a keyword.")
                else ImGui.Text("Pick up an item, then click to fill its type (e.g. Armor, Weapon) into the field.") end
                ImGui.EndTooltip()
            end
            if not hc then ImGui.EndDisabled() end
        end
        ImGui.SameLine()
        local addClicked = ImGui.Button("Add item##Valuable", ImVec2(80, 0))
        local val = (filterState.valuableFilterInputValue or ""):match("^%s*(.-)%s*$")
        if (addClicked or submitted) and val ~= "" then
            local typeKey = typeKeys[filterState.valuableFilterTypeMode + 1]
            local def = v[typeKey]
            if def then
                local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
                local list = lists[listKey]
                local found = false
                for _, s in ipairs(list) do if s == val then found = true; break end end
                if not found then
                    local conflicts = checkValuableFilterConflicts(typeKey, val)
                    if #conflicts > 0 then
                        filterConflictData = { section = "valuable", targetId = "valuable", typeKey = typeKey, value = val, conflicts = conflicts }
                        ImGui.OpenPopup("FilterConflict##ItemUI")
                    else
                        if performValuableFilterAdd(typeKey, val) then
                            filterState.valuableFilterInputValue = ""
                            setStatusMessage("Added to " .. v.label)
                        end
                    end
                end
            end
        end
        ImGui.Separator()

        local FILTER_BADGE = 85
        local FILTER_X_W = 32
        local valuableEntries = {}
        local function collectValuableEntries(kind, def)
            if not def then return end
            local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
            local list = lists[listKey]
            local badge = (kind == "exact" and "[name]") or (kind == "contains" and "[keyword]") or "[type]"
            for i = 1, #list do
                local it = list[i]
                valuableEntries[#valuableEntries + 1] = { typeBadge = badge, value = it, typeKey = kind, list = list, listIndex = i, iniFile = iniFile, iniKey = iniKey, writeFn = writeFn }
            end
        end
        collectValuableEntries("exact", v.exact)
        collectValuableEntries("contains", v.contains)
        collectValuableEntries("types", v.types)
        if ImGui.BeginTable("ValuableFiltersTable", 3, ImGuiTableFlags.BordersOuter + ImGuiTableFlags.BordersInnerH + ImGuiTableFlags.ScrollX + ImGuiTableFlags.SizingStretchProp + ImGuiTableFlags.Sortable) then
            ImGui.TableSetupColumn("Type", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), FILTER_BADGE, 0)
            ImGui.TableSetupColumn("Value", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable, ImGuiTableColumnFlags.DefaultSort), 1, 1)
            ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, FILTER_X_W, 2)
            local sortSpecs = ImGui.TableGetSortSpecs()
            if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
                local spec = sortSpecs:Specs(1)
                if spec and spec.ColumnIndex >= 0 and spec.ColumnIndex <= 1 then
                    filterState.valuableFilterSortColumn = spec.ColumnIndex
                    filterState.valuableFilterSortDirection = spec.SortDirection
                end
                sortSpecs.SpecsDirty = false
            end
            ImGui.TableHeadersRow()
            table.sort(valuableEntries, function(a, b)
                local av, bv
                if filterState.valuableFilterSortColumn == 0 then av, bv = a.typeBadge or "", b.typeBadge or ""
                else av, bv = a.value or "", b.value or "" end
                av, bv = tostring(av):lower(), tostring(bv):lower()
                if filterState.valuableFilterSortDirection == ImGuiSortDirection.Ascending then return av < bv else return av > bv end
            end)
            for _, e in ipairs(valuableEntries) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                ImGui.TextColored(theme.ToVec4(theme.Colors.Header), e.typeBadge)
                ImGui.TableNextColumn()
                ImGui.TextWrapped(e.value)
                ImGui.TableNextColumn()
                ImGui.PushID("valuable" .. e.typeKey .. e.listIndex)
                if ImGui.Button("X##Valuable", ImVec2(-1, 0)) then
                    table.remove(e.list, e.listIndex)
                    e.writeFn(e.iniFile, "Items", e.iniKey, config.joinList(e.list))
                    invalidateSellConfigCache()
                    filterState.valuableFilterEditTarget = { targetId = "valuable", typeKey = e.typeKey, value = e.value }
                    setStatusMessage("Removed; form filled for edit")
                end
                ImGui.PopID()
            end
            ImGui.EndTable()
        end
    elseif filterState.filterSubTab == 3 then
        ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.HeaderAlt))
        ImGui.TextWrapped("Never loot unless a qualification is met. Value thresholds are in General > Loot. Add items to Always loot or Skip (never loot).")
        ImGui.PopStyleColor()
        ImGui.Spacing()

        renderFilterSection("loot", LOOT_FILTER_TARGETS, filterState.lootFilterTargetId, filterState.lootFilterTypeMode, filterState.lootFilterInputValue, filterState.lootFilterEditTarget, filterState.lootFilterListShow,
            function(v) filterState.lootFilterTargetId = v end, function(v) filterState.lootFilterTypeMode = v end, function(v) filterState.lootFilterInputValue = v end,
            function(v) filterState.lootFilterEditTarget = v end, function(v) filterState.lootFilterListShow = v end,
            function(tid, tk, val) return checkLootFilterConflicts(tid, tk, val) end,
            function(tid, tk, val) return performLootFilterAdd(tid, tk, val) end,
            removeFromLootFilterList)

        ImGui.Spacing()
        ImGui.SetNextItemWidth(180)
        local showLabels = { ["all"] = "Show: All" }
        for _, t in ipairs(LOOT_FILTER_TARGETS) do showLabels[t.id] = "Show: " .. t.label end
        if ImGui.BeginCombo("##LootFilterShow", showLabels[filterState.lootFilterListShow] or "Show: All", ImGuiComboFlags.None) then
            if ImGui.Selectable("Show: All", filterState.lootFilterListShow == "all") then filterState.lootFilterListShow = "all" end
            for _, t in ipairs(LOOT_FILTER_TARGETS) do
                if ImGui.Selectable("Show: " .. t.label, filterState.lootFilterListShow == t.id) then filterState.lootFilterListShow = t.id end
            end
            ImGui.EndCombo()
        end
        ImGui.Separator()

        local FILTER_BADGE = 85
        local FILTER_LIST_W = 200
        local FILTER_X_W = 32
        local lootEntries = {}
        for _, t in ipairs(LOOT_FILTER_TARGETS) do
            if filterState.lootFilterListShow ~= "all" and filterState.lootFilterListShow ~= t.id then goto loot_collect_cont end
            local function collectEntries(kind, def)
                if not def then return end
                local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
                local list = lists[listKey]
                local badge = (kind == "exact" and "[name]") or (kind == "contains" and "[keyword]") or "[type]"
                for i = 1, #list do
                    local it = list[i]
                    lootEntries[#lootEntries + 1] = { listLabel = t.label, typeBadge = badge, value = it, targetId = t.id, typeKey = kind, list = list, listIndex = i, iniFile = iniFile, iniKey = iniKey, writeFn = writeFn }
                end
            end
            collectEntries("exact", t.exact)
            collectEntries("contains", t.contains)
            collectEntries("types", t.types)
            ::loot_collect_cont::
        end
        if ImGui.BeginTable("LootFiltersTable", 4, ImGuiTableFlags.BordersOuter + ImGuiTableFlags.BordersInnerH + ImGuiTableFlags.ScrollX + ImGuiTableFlags.SizingStretchProp + ImGuiTableFlags.Sortable) then
            ImGui.TableSetupColumn("List", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), FILTER_LIST_W, 0)
            ImGui.TableSetupColumn("Type", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), FILTER_BADGE, 1)
            ImGui.TableSetupColumn("Value", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable, ImGuiTableColumnFlags.DefaultSort), 1, 2)
            ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, FILTER_X_W, 3)
            local sortSpecs = ImGui.TableGetSortSpecs()
            if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
                local spec = sortSpecs:Specs(1)
                if spec and spec.ColumnIndex >= 0 and spec.ColumnIndex <= 2 then
                    filterState.lootFilterSortColumn = spec.ColumnIndex
                    filterState.lootFilterSortDirection = spec.SortDirection
                end
                sortSpecs.SpecsDirty = false
            end
            ImGui.TableHeadersRow()
            table.sort(lootEntries, function(a, b)
                local av, bv
                if filterState.lootFilterSortColumn == 0 then av, bv = a.listLabel or "", b.listLabel or ""
                elseif filterState.lootFilterSortColumn == 1 then av, bv = a.typeBadge or "", b.typeBadge or ""
                else av, bv = a.value or "", b.value or "" end
                av, bv = tostring(av):lower(), tostring(bv):lower()
                if filterState.lootFilterSortDirection == ImGuiSortDirection.Ascending then return av < bv else return av > bv end
            end)
            for _, e in ipairs(lootEntries) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                ImGui.TextColored(theme.ToVec4(theme.Colors.Info), e.listLabel)
                ImGui.TableNextColumn()
                ImGui.TextColored(theme.ToVec4(theme.Colors.Header), e.typeBadge)
                ImGui.TableNextColumn()
                ImGui.TextWrapped(e.value)
                ImGui.TableNextColumn()
                ImGui.PushID("loot" .. e.targetId .. e.typeKey .. e.listIndex)
                if ImGui.Button("X##Loot", ImVec2(-1, 0)) then
                    table.remove(e.list, e.listIndex)
                    e.writeFn(e.iniFile, "Items", e.iniKey, config.joinList(e.list))
                    invalidateSellConfigCache()
                    invalidateLootConfigCache()
                    filterState.lootFilterEditTarget = { targetId = e.targetId, typeKey = e.typeKey, value = e.value }
                    setStatusMessage("Removed; form filled for edit")
                end
                ImGui.PopID()
            end
            ImGui.EndTable()
        end
    end

    ImGui.EndChild()
end

local function renderConfigWindow()
    -- Apply saved config window size before Begin (FirstUseEver so user resize is preserved)
    local w = layoutConfig.WidthConfig or 0
    local h = layoutConfig.HeightConfig or 0
    if w and h and w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.FirstUseEver)
    end
    local ok = ImGui.Begin("CoOpt UI Settings##ItemUIConfig", uiState.configWindowOpen)
    uiState.configWindowOpen = ok
    if not ok then uiState.configNeedsLoad = true; ImGui.End(); return end
    if ImGui.IsKeyPressed(ImGuiKey.Escape) then uiState.configWindowOpen = false; ImGui.End(); return end
    if uiState.configNeedsLoad then loadConfigCache(); uiState.configNeedsLoad = false end

    -- B4: Smart defaults for new users — detect first run (no sell_flags.ini)
    if uiState.configNeedsLoad == false and not uiState._firstRunChecked then
        uiState._firstRunChecked = true
        local flagsPath = config.getConfigFile and config.getConfigFile("sell_flags.ini")
        if flagsPath then
            local f = io.open(flagsPath, "r")
            if not f then
                -- First run: load default protect list
                loadDefaultProtectList()
                setStatusMessage("Welcome! Default protection loaded.")
            else
                f:close()
            end
        end
    end

    ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "CoOpt UI Settings")
    ImGui.SameLine()
    if ImGui.Button("Reload from files##Config", ImVec2(130, 0)) then loadConfigCache() end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Reload all settings from INI files"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("Open Config Folder##Config", ImVec2(150, 0)) then
        local path = config.CONFIG_PATH
        if path and path ~= "" then
            path = path:gsub("/", "\\")
            mq.cmd(string.format('/execute explorer.exe "%s"', path))
            os.execute(('start "" "%s"'):format(path))
            setStatusMessage("Opened config folder")
        else
            setStatusMessage("Config path not available")
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Open the config folder in Windows Explorer.")
        ImGui.Text("Quick access to all INI files.")
        ImGui.EndTooltip()
    end
    ImGui.Separator()

    filterState.configTab = filterState.configTab or 1
    if filterState.configTab < 1 or filterState.configTab > 4 then
        filterState.configTab = 1
    end
    local function renderTabButton(label, tabId, width, tooltip)
        if ImGui.Button(label, ImVec2(width, 0)) then filterState.configTab = tabId; scheduleLayoutSave() end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
        if filterState.configTab == tabId then ImGui.SameLine(0, 0); ImGui.TextColored(theme.ToVec4(theme.Colors.Success), "  <") end
    end

    renderTabButton("General", 1, 90, "Window behavior, Sell options, and Loot options")
    ImGui.SameLine()
    renderTabButton("Sell Rules", 2, 90, "Sell item lists (Keep, Always sell, Never sell by type)")
    ImGui.SameLine()
    renderTabButton("Loot Rules", 3, 90, "Loot item lists (Always loot, Skip)")
    ImGui.SameLine()
    renderTabButton("Shared", 4, 90, "Valuable list (never sell, always loot)")
    ImGui.Separator()

    if filterState.configTab == 1 then
        ImGui.Spacing()
        renderBreadcrumb("General", "Overview")
        if ImGui.CollapsingHeader("Features", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("General", "Features")
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Turn features on or off. All are enabled by default; uncheck to disable.")
            ImGui.Spacing()
            local prevAlign = uiState.alignToContext
            uiState.alignToContext = ImGui.Checkbox("Enable snap to Inventory", uiState.alignToContext)
            if prevAlign ~= uiState.alignToContext then scheduleLayoutSave() end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("When enabled, CoOpt UI Inventory Companion stays locked to the built-in Inventory window.")
                ImGui.Text("Uncheck to place CoOpt UI Inventory Companion freely.")
                ImGui.EndTooltip()
            end
            local prevSync = uiState.syncBankWindow
            uiState.syncBankWindow = ImGui.Checkbox("Enable bank window sync", uiState.syncBankWindow)
            if prevSync ~= uiState.syncBankWindow then
                saveLayoutToFile()
                if uiState.syncBankWindow and uiState.bankWindowOpen and uiState.bankWindowShouldDraw then
                    local itemUIX, itemUIY = ImGui.GetWindowPos()
                    local itemUIW = ImGui.GetWindowWidth()
                    if itemUIX and itemUIY and itemUIW then
                        layoutConfig.BankWindowX = itemUIX + itemUIW + 10
                        layoutConfig.BankWindowY = itemUIY
                        saveLayoutToFile()
                    end
                end
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("When enabled, the bank window follows CoOpt UI Inventory Companion position.")
                ImGui.Text("Uncheck to move the bank window independently.")
                ImGui.EndTooltip()
            end
            -- Loot UI: stored as suppressWhenLootMac (true = hide Loot UI). Show as "Enable Loot UI" so checked = show = not suppress.
            local enableLootUI = not uiState.suppressWhenLootMac
            local prevEnableLootUI = enableLootUI
            enableLootUI = ImGui.Checkbox("Enable Loot UI during looting", enableLootUI)
            if prevEnableLootUI ~= enableLootUI then
                uiState.suppressWhenLootMac = not enableLootUI
                scheduleLayoutSave()
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("When enabled, the Loot UI window opens when you loot (manual or macro).")
                ImGui.Text("Uncheck to keep the Loot UI closed during looting.")
                ImGui.EndTooltip()
            end
            local prevConfirm = uiState.confirmBeforeDelete
            uiState.confirmBeforeDelete = ImGui.Checkbox("Enable confirm before delete", uiState.confirmBeforeDelete)
            if prevConfirm ~= uiState.confirmBeforeDelete then scheduleLayoutSave() end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("When enabled, a confirmation dialog appears before destroying an item from the context menu.")
                ImGui.Text("Uncheck to destroy without confirming.")
                ImGui.EndTooltip()
            end
            ImGui.Spacing()
            -- Combined epic: never sell + always loot epic quest items (both INIs kept in sync from one checkbox)
            local epicEnabled = configSellFlags.protectEpic or configLootFlags.alwaysLootEpic
            local prevEpic = epicEnabled
            epicEnabled = ImGui.Checkbox("Enable Epic Loot and Protection", epicEnabled)
            if prevEpic ~= epicEnabled then
                configSellFlags.protectEpic = epicEnabled
                configLootFlags.alwaysLootEpic = epicEnabled
                config.writeINIValue("sell_flags.ini", "Settings", "protectEpic", epicEnabled and "TRUE" or "FALSE")
                config.writeLootINIValue("loot_flags.ini", "Settings", "alwaysLootEpic", epicEnabled and "TRUE" or "FALSE")
                invalidateSellConfigCache()
                invalidateLootConfigCache()
                scheduleLayoutSave()
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("When enabled, epic quest items are never sold and are always looted. Optionally limit by class below.")
                ImGui.Text("Uncheck to allow selling epic items and to stop always-looting them.")
                ImGui.EndTooltip()
            end
            if epicEnabled and EPIC_CLASSES and #EPIC_CLASSES > 0 then
                ImGui.Indent()
                local nSelected = 0
                for _, cls in ipairs(EPIC_CLASSES) do
                    if configEpicClasses[cls] == true then nSelected = nSelected + 1 end
                end
                local preview = (nSelected == 0) and "All classes (none selected)" or (nSelected == #EPIC_CLASSES) and "All classes" or string.format("%d class%s", nSelected, nSelected == 1 and "" or "es")
                ImGui.SetNextItemWidth(320)
                if ImGui.BeginCombo("Classes for epic##epic", preview, ImGuiComboFlags.None) then
                    local rowHeight = (ImGui.GetFrameHeight and ImGui.GetFrameHeight()) or 24
                    local popupHeight = (1 + #EPIC_CLASSES) * rowHeight + 24
                    if ImGui.SetWindowSize then
                        ImGui.SetWindowSize(ImVec2(320, math.max(200, popupHeight)))
                    end
                    if ImGui.SmallButton("Select all##epic") then
                        for _, cls in ipairs(EPIC_CLASSES) do
                            configEpicClasses[cls] = true
                            config.writeSharedINIValue("epic_classes.ini", "Classes", cls, "TRUE")
                        end
                        invalidateSellConfigCache()
                        invalidateLootConfigCache()
                    end
                    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Check all classes"); ImGui.EndTooltip() end
                    ImGui.SameLine()
                    if ImGui.SmallButton("Clear all##epic") then
                        for _, cls in ipairs(EPIC_CLASSES) do
                            configEpicClasses[cls] = false
                            config.writeSharedINIValue("epic_classes.ini", "Classes", cls, "FALSE")
                        end
                        invalidateSellConfigCache()
                        invalidateLootConfigCache()
                    end
                    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Uncheck all (no epic items when none selected)"); ImGui.EndTooltip() end
                    ImGui.Spacing()
                    for _, cls in ipairs(EPIC_CLASSES) do
                        local v = ImGui.Checkbox(classLabel(cls) .. "##epic_" .. cls, configEpicClasses[cls] == true)
                        if v ~= (configEpicClasses[cls] == true) then
                            configEpicClasses[cls] = v
                            config.writeSharedINIValue("epic_classes.ini", "Classes", cls, v and "TRUE" or "FALSE")
                            invalidateSellConfigCache()
                            invalidateLootConfigCache()
                        end
                    end
                    ImGui.EndCombo()
                end
                if ImGui.IsItemHovered() then
                    if ImGui.SetNextWindowSize then
                        ImGui.SetNextWindowSize(ImVec2(320, 0), ImGuiCond.Always)
                    end
                    ImGui.BeginTooltip()
                    ImGui.TextWrapped("Choose which classes' epic quest items are protected and always looted. If none are checked, no epic items are included.")
                    ImGui.EndTooltip()
                end
                ImGui.Unindent()
            end
        end
        ImGui.Spacing()
        if ImGui.CollapsingHeader("Sell", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("General", "Sell")
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Options for what is never sold. Item lists are on the Sell Rules tab.")
            ImGui.Spacing()
            ImGui.Text("Protection flags")
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Items with these flags are never sold."); ImGui.EndTooltip() end
            local function sellFlag(name, key, tooltip)
                local v = ImGui.Checkbox(name, configSellFlags[key])
                if v ~= configSellFlags[key] then configSellFlags[key] = v; config.writeINIValue("sell_flags.ini", "Settings", key, v and "TRUE" or "FALSE"); invalidateSellConfigCache() end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
            end
            sellFlag("Enable No-Drop protection", "protectNoDrop", "Never sell items with the No-Drop flag")
            sellFlag("Enable No-Trade protection", "protectNoTrade", "Never sell items with the No-Trade flag")
            sellFlag("Enable Lore protection", "protectLore", "Never sell items with the Lore flag")
            sellFlag("Enable Quest protection", "protectQuest", "Never sell items with the Quest flag")
            sellFlag("Enable Collectible protection", "protectCollectible", "Never sell items with the Collectible flag")
            sellFlag("Enable Heirloom protection", "protectHeirloom", "Never sell items with the Heirloom flag")
            ImGui.Spacing()
            ImGui.Text("Value thresholds (copper)")
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("1 platinum = 1000 copper"); ImGui.EndTooltip() end
            ImGui.Text("Min value (single)")
            ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
            local vs = tostring(configSellValues.minSell)
            vs, _ = ImGui.InputText("Min value (single)##SellMin", vs, ImGuiInputTextFlags.CharsDecimal)
            local n = tonumber(vs)
            if n and n ~= configSellValues.minSell then
                configSellValues.minSell = math.max(0, math.floor(n))
                config.writeINIValue("sell_value.ini", "Settings", "minSellValue", tostring(configSellValues.minSell))
                invalidateSellConfigCache()
            end
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configSellValues.minSell))
            ImGui.Text("Min value (stack)")
            ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
            vs = tostring(configSellValues.minStack)
            vs, _ = ImGui.InputText("Min value (stack)##SellStack", vs, ImGuiInputTextFlags.CharsDecimal)
            n = tonumber(vs)
            if n and n ~= configSellValues.minStack then
                configSellValues.minStack = math.max(0, math.floor(n))
                config.writeINIValue("sell_value.ini", "Settings", "minSellValueStack", tostring(configSellValues.minStack))
                invalidateSellConfigCache()
            end
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configSellValues.minStack) .. "/unit")
            ImGui.Text("Max keep value")
            ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
            vs = tostring(configSellValues.maxKeep)
            vs, _ = ImGui.InputText("Max keep value##SellKeep", vs, ImGuiInputTextFlags.CharsDecimal)
            n = tonumber(vs)
            if n and n ~= configSellValues.maxKeep then
                configSellValues.maxKeep = math.max(0, math.floor(n))
                config.writeINIValue("sell_value.ini", "Settings", "maxKeepValue", tostring(configSellValues.maxKeep))
                invalidateSellConfigCache()
            end
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configSellValues.maxKeep))
        end
        ImGui.Spacing()
        if ImGui.CollapsingHeader("Loot", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("General", "Loot")
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Options for what to loot (loot.mac). Item lists are on the Loot Rules tab.")
            ImGui.Spacing()
            local function lootFlag(name, key, tooltip)
                local v = ImGui.Checkbox(name, configLootFlags[key])
                if v ~= configLootFlags[key] then configLootFlags[key] = v; config.writeLootINIValue("loot_flags.ini", "Settings", key, v and "TRUE" or "FALSE") end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
            end
            lootFlag("Enable loot clickies", "lootClickies", "Loot wearable items with clicky effects")
            lootFlag("Enable loot quest items", "lootQuest", "Loot items with the Quest flag")
            lootFlag("Enable loot collectible", "lootCollectible", "Loot items with the Collectible flag")
            lootFlag("Enable loot heirloom", "lootHeirloom", "Loot items with the Heirloom flag")
            lootFlag("Enable loot attuneable", "lootAttuneable", "Loot items with the Attuneable flag")
            lootFlag("Enable loot augment slots", "lootAugSlots", "Loot items that can have augments")
            ImGui.Spacing()
            lootFlag("Enable pause on Mythical NoDrop/NoTrade", "pauseOnMythicalNoDropNoTrade", "When a Mythical item with NoDrop or NoTrade is found, pause the loot macro, beep twice, alert group, and leave the item on corpse.")
            lootFlag("Enable alert group when Mythical pause", "alertMythicalGroupChat", "When pause triggers, send the item and corpse name to group chat (only if grouped).")
            ImGui.Spacing()
            ImGui.Text("Loot delay (ticks)")
            local ticks = tonumber(configLootFlags.lootDelayTicks)
            if not ticks or ticks < 1 or ticks > 10 then ticks = 3 end
            local val, changed = ImGui.SliderInt("##lootDelayTicks", ticks, 1, 10, "%d")
            if changed then
                val = math.max(1, math.min(10, tonumber(val) or 3))
                configLootFlags.lootDelayTicks = val
                config.writeLootINIValue("loot_flags.ini", "Settings", "lootDelayTicks", tostring(val))
            end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Ticks to wait after itemnotify/cursor/window. 2 = faster, 3 = default, 4+ if laggy."); ImGui.EndTooltip() end
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), tostring(configLootFlags.lootDelayTicks or 3))
            ImGui.Spacing()
            ImGui.Text("Value thresholds (copper)")
            ImGui.Text("Min value (non-stack)")
            ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
            vs = tostring(configLootValues.minLoot)
            vs, _ = ImGui.InputText("Min loot value##LootMin", vs, ImGuiInputTextFlags.CharsDecimal)
            n = tonumber(vs)
            if n and n ~= configLootValues.minLoot then configLootValues.minLoot = math.max(0, math.floor(n)); config.writeLootINIValue("loot_value.ini", "Settings", "minLootValue", tostring(configLootValues.minLoot)) end
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.minLoot))
            ImGui.Text("Min value (stack)")
            ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
            vs = tostring(configLootValues.minStack)
            vs, _ = ImGui.InputText("Min stack value##LootStack", vs, ImGuiInputTextFlags.CharsDecimal)
            n = tonumber(vs)
            if n and n ~= configLootValues.minStack then configLootValues.minStack = math.max(0, math.floor(n)); config.writeLootINIValue("loot_value.ini", "Settings", "minLootValueStack", tostring(configLootValues.minStack)) end
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.minStack) .. "/unit")
            ImGui.Text("Tribute override (0=off)")
            ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
            vs = tostring(configLootValues.tributeOverride)
            vs, _ = ImGui.InputText("Tribute override##LootTrib", vs, ImGuiInputTextFlags.CharsDecimal)
            n = tonumber(vs)
            if n and n ~= configLootValues.tributeOverride then configLootValues.tributeOverride = math.max(0, math.floor(n)); config.writeLootINIValue("loot_value.ini", "Settings", "tributeOverride", tostring(configLootValues.tributeOverride)) end
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.tributeOverride))
            ImGui.Spacing()
            ImGui.Text("Sorting")
            local v = ImGui.Checkbox("Enable sorting", configLootSorting.enableSorting)
            if v ~= configLootSorting.enableSorting then configLootSorting.enableSorting = v; config.writeLootINIValue("loot_sorting.ini", "Settings", "enableSorting", v and "TRUE" or "FALSE") end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Master toggle for loot sorting"); ImGui.EndTooltip() end
            v = ImGui.Checkbox("Enable weight sort", configLootSorting.enableWeightSort)
            if v ~= configLootSorting.enableWeightSort then configLootSorting.enableWeightSort = v; config.writeLootINIValue("loot_sorting.ini", "Settings", "enableWeightSort", v and "TRUE" or "FALSE") end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Sort inventory by weight when looting"); ImGui.EndTooltip() end
            ImGui.SetNextItemWidth(120)
            vs = tostring(configLootSorting.minWeight)
            vs, _ = ImGui.InputText("Weight threshold##LootWt", vs, ImGuiInputTextFlags.CharsDecimal)
            n = tonumber(vs)
            if n and n ~= configLootSorting.minWeight then configLootSorting.minWeight = math.max(0, math.floor(n)); config.writeLootINIValue("loot_sorting.ini", "Settings", "minWeight", tostring(configLootSorting.minWeight)) end
            ImGui.SameLine(); ImGui.Text("Weight threshold (tenths)")
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), string.format("%.1f lbs", (tonumber(configLootSorting.minWeight) or 0) / 10))
        end
        ImGui.Spacing()
        if ImGui.CollapsingHeader("Layout setup", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("General", "Layout setup")
            local setupWasOn = uiState.setupMode
            if setupWasOn then ImGui.PushStyleColor(ImGuiCol.Button, theme.ToVec4(theme.Colors.Warning)) end
            if ImGui.Button("Initial Setup", ImVec2(120, 0)) then
                uiState.setupMode = not uiState.setupMode
                if uiState.setupMode then uiState.setupStep = 1; loadLayoutConfig() else uiState.setupStep = 0 end
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Save window sizes for Inventory, Sell, and Inv+Bank.")
                ImGui.Text("Follow the on-screen steps to capture positions.")
                ImGui.EndTooltip()
            end
            if setupWasOn then ImGui.PopStyleColor(1) end
        end
    elseif filterState.configTab == 2 then
        ImGui.Spacing()
        renderBreadcrumb("Sell Rules", "Item lists")
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Keep (never sell), Always sell, Never sell by type. Options are in General > Sell.")
        ImGui.Spacing()
        renderFiltersSection(1, false)
    elseif filterState.configTab == 3 then
        ImGui.Spacing()
        renderBreadcrumb("Loot Rules", "Item lists")
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Always loot, Skip (never loot). Options are in General > Loot.")
        ImGui.Spacing()
        renderFiltersSection(3, false)
    elseif filterState.configTab == 4 then
        ImGui.Spacing()
        renderBreadcrumb("Shared", "Valuable list")
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Items never sold and always looted. Shared between sell.mac and loot.mac.")
        ImGui.Spacing()
        renderFiltersSection(2, false)
    end
    -- Persist config window size on resize (tolerance 1px to avoid save storms)
    local cw, ch = ImGui.GetWindowSize()
    local savedW = layoutConfig.WidthConfig or 0
    local savedH = layoutConfig.HeightConfig or 0
    if cw and ch and (math.abs(cw - savedW) > 1 or math.abs(ch - savedH) > 1) then
        layoutConfig.WidthConfig = cw
        layoutConfig.HeightConfig = ch
        scheduleLayoutSave()
    end
    ImGui.End()
end

function ConfigView.render(ctx)
    bindContext(ctx)
    refreshTargets()
    renderConfigWindow()
end

return ConfigView
