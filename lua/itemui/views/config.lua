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

--- Render grid of epic class checkboxes. Writes to epic_classes.ini and invalidates sell/loot caches.
local function renderEpicClassGrid()
    if not EPIC_CLASSES or #EPIC_CLASSES == 0 then return end
    ImGui.Spacing()
    ImGui.Text("Epic quest classes:")
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.TextWrapped("Check classes whose epic quest items should always be looted and never sold (when the flags above are on). If none are checked, all epic items from all classes are used.")
        ImGui.EndTooltip()
    end
    ImGui.SameLine()
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
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Uncheck all classes (all epic items used when flags are on)"); ImGui.EndTooltip() end
    local cols = 4
    if ImGui.BeginTable("EpicClassGrid", cols, ImGuiTableFlags.BordersOuter + ImGuiTableFlags.BordersInnerH) then
        for i, cls in ipairs(EPIC_CLASSES) do
            if (i - 1) % cols == 0 then ImGui.TableNextRow() end
            ImGui.TableNextColumn()
            local v = ImGui.Checkbox(classLabel(cls) .. "##epic_" .. cls, configEpicClasses[cls] == true)
            if v ~= (configEpicClasses[cls] == true) then
                configEpicClasses[cls] = v
                config.writeSharedINIValue("epic_classes.ini", "Classes", cls, v and "TRUE" or "FALSE")
                invalidateSellConfigCache()
                invalidateLootConfigCache()
            end
        end
        ImGui.EndTable()
    end
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
    ImGui.BeginChild(sectionId .. "List", ImVec2(0, 120), true)
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
    local childHeight = math.max(200, availY - 8)
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
        ImGui.TextWrapped("Never loot unless a qualification is met. Value thresholds (min loot, tribute override) are in the Loot tab. Add items to Always loot or Skip (never loot).")
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

-- Simple mode: flat list UX for exact-name item lists
-- Renders: header text, text input + Add + From cursor, scrollable list with X to remove
local function renderSimpleItemList(sectionId, headerText, listKey, iniFile, writeFn, lists, invalidateFn)
    ImGui.TextColored(theme.ToVec4(theme.Colors.HeaderAlt), headerText)
    local inputKey = "simple_" .. sectionId
    filterState.configListInputs[inputKey] = filterState.configListInputs[inputKey] or ""
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
                writeFn(iniFile, "Items", "exact", config.joinList(list))
                if invalidateFn then invalidateFn() end
            end
        end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Add item name to list"); ImGui.EndTooltip() end
    ImGui.SameLine()
    do
        local hc = hasItemOnCursor()
        if not hc then ImGui.BeginDisabled() end
        if ImGui.Button("From cursor##" .. sectionId, ImVec2(90, 0)) then
            local raw = mq.TLO.Cursor and mq.TLO.Cursor.Name and mq.TLO.Cursor.Name()
            if raw and raw ~= "" then
                filterState.configListInputs[inputKey] = config.sanitizeItemName(raw)
            end
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Pick up an item, then click to fill its name"); ImGui.EndTooltip() end
        if not hc then ImGui.EndDisabled() end
    end
    local list = lists[listKey]
    ImGui.BeginChild(sectionId .. "SimpleList", ImVec2(0, 120), true)
    for i = #list, 1, -1 do
        ImGui.PushID(sectionId .. "item" .. i)
        ImGui.Text(list[i])
        ImGui.SameLine(ImGui.GetContentRegionAvail() - 30)
        if ImGui.Button("X", ImVec2(22, 0)) then
            table.remove(list, i)
            writeFn(iniFile, "Items", "exact", config.joinList(list))
            if invalidateFn then invalidateFn() end
        end
        ImGui.PopID()
    end
    ImGui.EndChild()
end

-- Simple mode Protection tab: 6 key checkboxes + epic grid + General window settings
local function renderSimpleProtectionTab()
    ImGui.Spacing()
    if ImGui.CollapsingHeader("General", ImGuiTreeNodeFlags.DefaultOpen) then
        local prevAlign = uiState.alignToContext
        uiState.alignToContext = ImGui.Checkbox("Snap to Inventory", uiState.alignToContext)
        if prevAlign ~= uiState.alignToContext then scheduleLayoutSave() end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Lock ItemUI position to the built-in Inventory window.")
            ImGui.EndTooltip()
        end
        local prevSync = uiState.syncBankWindow
        uiState.syncBankWindow = ImGui.Checkbox("Sync Bank Window", uiState.syncBankWindow)
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
            ImGui.Text("Keep bank window synced with ItemUI position.")
            ImGui.EndTooltip()
        end
        local prevSuppress = uiState.suppressWhenLootMac
        uiState.suppressWhenLootMac = ImGui.Checkbox("Suppress when loot.mac running", uiState.suppressWhenLootMac)
        if prevSuppress ~= uiState.suppressWhenLootMac then scheduleLayoutSave() end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Don't auto-show ItemUI when inventory opens while loot.mac runs.")
            ImGui.EndTooltip()
        end
        local prevConfirm = uiState.confirmBeforeDelete
        uiState.confirmBeforeDelete = ImGui.Checkbox("Confirm before delete", uiState.confirmBeforeDelete)
        if prevConfirm ~= uiState.confirmBeforeDelete then scheduleLayoutSave() end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Show a confirmation dialog before destroying an item from the inventory context menu.")
            ImGui.EndTooltip()
        end
    end
    ImGui.Spacing()
    if ImGui.CollapsingHeader("Sell protection", ImGuiTreeNodeFlags.DefaultOpen) then
        ImGui.TextColored(theme.ToVec4(theme.Colors.HeaderAlt), "Items with these flags are never sold.")
        ImGui.Spacing()
        local function sellFlag(name, key, tooltip)
            local v = ImGui.Checkbox(name, configSellFlags[key])
            if v ~= configSellFlags[key] then configSellFlags[key] = v; config.writeINIValue("sell_flags.ini", "Settings", key, v and "TRUE" or "FALSE"); invalidateSellConfigCache() end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
        end
        sellFlag("Protect No-Drop", "protectNoDrop", "Never sell items with the No-Drop flag")
        sellFlag("Protect No-Trade", "protectNoTrade", "Never sell items with the No-Trade flag")
        sellFlag("Protect Lore", "protectLore", "Never sell items with the Lore flag")
        sellFlag("Protect Quest", "protectQuest", "Never sell items with the Quest flag")
        sellFlag("Protect Collectible", "protectCollectible", "Never sell items with the Collectible flag")
        sellFlag("Protect Epic", "protectEpic", "Never sell Epic quest items")
        if ImGui.CollapsingHeader("Epic class filter") then
            renderEpicClassGrid()
        end
    end
end

-- Simple mode Item Lists tab: Never Sell, Always Sell, Valuable (exact names only)
local function renderSimpleItemListsTab()
    ImGui.Spacing()
    renderSimpleItemList("simpleKeep", "Never Sell — these items are always kept",
        "keepExact", "sell_keep_exact.ini", writeListValue, configSellLists, invalidateSellConfigCache)
    ImGui.Spacing()
    renderSimpleItemList("simpleJunk", "Always Sell — these items are always sold",
        "junkExact", "sell_always_sell_exact.ini", writeListValue, configSellLists, invalidateSellConfigCache)
    ImGui.Spacing()
    renderSimpleItemList("simpleValuable", "Valuable — never sell + always loot (shared)",
        "sharedExact", "valuable_exact.ini", writeSharedListValue, configLootLists, invalidateSellConfigCache)
end

-- Simple mode Values & Stats tab: sell + loot thresholds + statistics
local function renderSimpleValuesTab()
    ImGui.Spacing()
    if ImGui.CollapsingHeader("Sell thresholds", ImGuiTreeNodeFlags.DefaultOpen) then
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "All values in copper (1 platinum = 1000 copper).")
        local function valueInput(label, key, tooltip, writeKey)
            ImGui.Text(label)
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
            ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
            local vs = tostring(configSellValues[key])
            vs, _ = ImGui.InputText(label .. "##SellSimple", vs, ImGuiInputTextFlags.CharsDecimal)
            local n = tonumber(vs)
            if n and n ~= configSellValues[key] then
                configSellValues[key] = math.max(0, math.floor(n))
                config.writeINIValue("sell_value.ini", "Settings", writeKey, tostring(configSellValues[key]))
                invalidateSellConfigCache()
            end
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configSellValues[key]))
        end
        valueInput("Min sell value", "minSell", "Minimum value to sell a single item (0 = sell all)", "minSellValue")
        valueInput("Min stack value", "minStack", "Minimum value per unit for stackable items", "minSellValueStack")
        valueInput("Max keep value", "maxKeep", "Items above this value are always kept (0 = disabled)", "maxKeepValue")
    end
    ImGui.Spacing()
    if ImGui.CollapsingHeader("Loot thresholds", ImGuiTreeNodeFlags.DefaultOpen) then
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "All values in copper (1 platinum = 1000 copper).")
        ImGui.SetNextItemWidth(120)
        local vs = tostring(configLootValues.minLoot)
        vs, _ = ImGui.InputText("Min loot value##SimpleL", vs, ImGuiInputTextFlags.CharsDecimal)
        local n = tonumber(vs)
        if n and n ~= configLootValues.minLoot then configLootValues.minLoot = math.max(0, math.floor(n)); config.writeLootINIValue("loot_value.ini", "Settings", "minLootValue", tostring(configLootValues.minLoot)) end
        ImGui.SameLine(); ImGui.Text("Min value (non-stack)")
        ImGui.SameLine(); ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.minLoot))

        ImGui.SetNextItemWidth(120)
        vs = tostring(configLootValues.minStack)
        vs, _ = ImGui.InputText("Min loot stack##SimpleL", vs, ImGuiInputTextFlags.CharsDecimal)
        n = tonumber(vs)
        if n and n ~= configLootValues.minStack then configLootValues.minStack = math.max(0, math.floor(n)); config.writeLootINIValue("loot_value.ini", "Settings", "minLootValueStack", tostring(configLootValues.minStack)) end
        ImGui.SameLine(); ImGui.Text("Min value (stack)")
        ImGui.SameLine(); ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.minStack) .. "/unit")

        ImGui.SetNextItemWidth(120)
        vs = tostring(configLootValues.tributeOverride)
        vs, _ = ImGui.InputText("Tribute override##SimpleL", vs, ImGuiInputTextFlags.CharsDecimal)
        n = tonumber(vs)
        if n and n ~= configLootValues.tributeOverride then configLootValues.tributeOverride = math.max(0, math.floor(n)); config.writeLootINIValue("loot_value.ini", "Settings", "tributeOverride", tostring(configLootValues.tributeOverride)) end
        ImGui.SameLine(); ImGui.Text("Tribute override (0=off)")
        ImGui.SameLine(); ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.tributeOverride))
    end
    ImGui.Spacing()
    if ImGui.CollapsingHeader("Statistics") then
        local stats = safeGetStats()
        local sellStats = stats and stats.sell or nil
        local lootStats = stats and stats.loot or nil
        if not sellStats and not lootStats then
            ImGui.TextColored(theme.ToVec4(theme.Colors.Warning), "No stats yet. Run sell.mac or loot.mac.")
        else
            local function safeNumber(v, fmt)
                if v == nil then return "N/A" end
                if fmt then return fmt(v) end
                return tostring(tonumber(v) or "N/A")
            end
            if sellStats then
                ImGui.TextColored(theme.ToVec4(theme.Colors.HeaderAlt), "Sell stats")
                ImGui.Text(string.format("Runs: %s  Items sold: %s  Failed: %s", safeNumber(sellStats.totalRuns), safeNumber(sellStats.totalItemsSold), safeNumber(sellStats.totalItemsFailed)))
            end
            if lootStats then
                ImGui.TextColored(theme.ToVec4(theme.Colors.HeaderAlt), "Loot stats")
                ImGui.Text(string.format("Runs: %s  Avg: %s", safeNumber(lootStats.totalRuns), safeNumber(lootStats.avgDurationMs, formatDurationMs)))
            end
        end
    end
end

local function renderConfigWindow()
    local ok = ImGui.Begin("ItemUI & Loot Config##ItemUIConfig", uiState.configWindowOpen)
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

    ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "ItemUI & Loot settings")
    ImGui.SameLine()
    -- B1: Simple/Advanced mode toggle
    local modeLabel = uiState.configAdvancedMode and "Advanced" or "Simple"
    if ImGui.Button(modeLabel .. "##ConfigMode", ImVec2(80, 0)) then
        uiState.configAdvancedMode = not uiState.configAdvancedMode
        -- Reset tab to first tab of the new mode
        filterState.configTab = uiState.configAdvancedMode and 1 or 10
        scheduleLayoutSave()
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(uiState.configAdvancedMode and "Switch to Simple mode (fewer options)" or "Switch to Advanced mode (all options)"); ImGui.EndTooltip() end
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
    local function renderTabButton(label, tabId, width, tooltip)
        if ImGui.Button(label, ImVec2(width, 0)) then filterState.configTab = tabId; scheduleLayoutSave() end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
        if filterState.configTab == tabId then ImGui.SameLine(0, 0); ImGui.TextColored(theme.ToVec4(theme.Colors.Success), "  <") end
    end

    -- B2: Simple mode = 3 tabs; Advanced mode = existing 5 tabs
    -- Guard: ensure tab ID is valid for current mode
    if uiState.configAdvancedMode and filterState.configTab >= 10 then
        filterState.configTab = 1
    elseif not uiState.configAdvancedMode and filterState.configTab < 10 then
        filterState.configTab = 10
    end
    if uiState.configAdvancedMode then
        renderTabButton("General", 1, 90, "UI behavior, layout, and window settings")
        ImGui.SameLine()
        renderTabButton("Sell Rules", 2, 90, "Sell flags, value thresholds, and lists")
        ImGui.SameLine()
        renderTabButton("Loot Rules", 3, 90, "Loot flags, value thresholds, and lists")
        ImGui.SameLine()
        renderTabButton("Shared", 4, 90, "Valuable shared lists used by sell and loot")
        ImGui.SameLine()
        renderTabButton("Statistics", 5, 90, "Macro run history and performance stats")
    else
        -- Simple mode tabs: Protection (tab 10), Item Lists (tab 11), Values & Stats (tab 12)
        renderTabButton("Protection", 10, 90, "Which item flags prevent selling")
        ImGui.SameLine()
        renderTabButton("Item Lists", 11, 90, "Never Sell, Always Sell, and Valuable item lists")
        ImGui.SameLine()
        renderTabButton("Values & Stats", 12, 110, "Sell/Loot value thresholds and statistics")
    end
    ImGui.Separator()

    -- Simple mode tabs (10, 11, 12)
    if filterState.configTab == 10 then
        renderSimpleProtectionTab()
    elseif filterState.configTab == 11 then
        renderSimpleItemListsTab()
    elseif filterState.configTab == 12 then
        renderSimpleValuesTab()
    -- Advanced mode tabs (1-5)
    elseif filterState.configTab == 1 then
        ImGui.Spacing()
        renderBreadcrumb("General", "Overview")
        if ImGui.CollapsingHeader("Window behavior", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("General", "Window behavior")
            local prevAlign = uiState.alignToContext
            uiState.alignToContext = ImGui.Checkbox("Snap to Inventory", uiState.alignToContext)
            if prevAlign ~= uiState.alignToContext then scheduleLayoutSave() end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Lock ItemUI position to the built-in Inventory window.")
                ImGui.Text("Keeps ItemUI aligned to the left; height is unchanged.")
                ImGui.Text("Disable if you want to place ItemUI freely.")
                ImGui.EndTooltip()
            end
            local prevSync = uiState.syncBankWindow
            uiState.syncBankWindow = ImGui.Checkbox("Sync Bank Window", uiState.syncBankWindow)
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
                ImGui.Text("Keep bank window synced with ItemUI position.")
                ImGui.Text("Enabled: bank window follows ItemUI.")
                ImGui.Text("Disabled: bank window moves independently.")
                ImGui.EndTooltip()
            end
            local prevSuppress = uiState.suppressWhenLootMac
            uiState.suppressWhenLootMac = ImGui.Checkbox("Suppress when loot.mac running", uiState.suppressWhenLootMac)
            if prevSuppress ~= uiState.suppressWhenLootMac then scheduleLayoutSave() end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Don't auto-show ItemUI when inventory opens while loot.mac runs.")
                ImGui.Text("Useful when looting many corpses quickly.")
                ImGui.Text("You can still open ItemUI manually if needed.")
                ImGui.EndTooltip()
            end
            local prevConfirm = uiState.confirmBeforeDelete
            uiState.confirmBeforeDelete = ImGui.Checkbox("Confirm before delete", uiState.confirmBeforeDelete)
            if prevConfirm ~= uiState.confirmBeforeDelete then scheduleLayoutSave() end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Show a confirmation dialog before destroying an item from the inventory context menu.")
                ImGui.EndTooltip()
            end
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
            ImGui.SameLine()
            ImGui.PushStyleColor(ImGuiCol.Button, theme.ToVec4(theme.Colors.Keep.Normal))
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, theme.ToVec4(theme.Colors.Keep.Hover))
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, theme.ToVec4(theme.Colors.Keep.Active))
            if ImGui.Button("Capture as Default", ImVec2(140, 0)) then
                captureCurrentLayoutAsDefault()
            end
            ImGui.PopStyleColor(3)
            if ImGui.IsItemHovered() then 
                ImGui.BeginTooltip()
                ImGui.Text("Save current layout configuration as default.")
                ImGui.Text("Captures window sizes, column widths, and all settings.")
                ImGui.EndTooltip()
            end
            ImGui.SameLine()
            ImGui.PushStyleColor(ImGuiCol.Button, theme.ToVec4(theme.Colors.Delete.Normal))
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, theme.ToVec4(theme.Colors.Delete.Hover))
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, theme.ToVec4(theme.Colors.Delete.Active))
            if ImGui.Button("Reset to Default", ImVec2(140, 0)) then
                resetLayoutToDefault()
            end
            ImGui.PopStyleColor(3)
            if ImGui.IsItemHovered() then 
                ImGui.BeginTooltip()
                ImGui.Text("Reset layout to saved default configuration.")
                ImGui.Text("Restores window sizes, column widths, and settings.")
                ImGui.EndTooltip()
            end
        end
    elseif filterState.configTab == 2 then
        ImGui.Spacing()
        renderBreadcrumb("Sell Rules", "Overview")
        if ImGui.CollapsingHeader("How sell rules work", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("Sell Rules", "Overview")
            ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.HeaderAlt))
            ImGui.TextWrapped("sell.mac and ItemUI use the same logic: SELL unless a KEEP rule matches. Rules are checked in this order:")
            ImGui.PopStyleColor()
            ImGui.BulletText("1. Unsellable flags: NoDrop, NoTrade (always kept if protected)")
            ImGui.BulletText("2. Never sell (Keep): exact names, keywords, item types")
            ImGui.BulletText("3. Always sell: exact names, keywords (can override Keep keyword matches)")
            ImGui.BulletText("4. Protected flags: Lore, Quest, Collectible, Heirloom, Attuneable, AugSlots")
            ImGui.BulletText("5. Value rules: max keep value, tribute override, min sell value")
            ImGui.TextWrapped("Valuable (shared) items are merged into Keep lists. Always sell exact overrides Keep keyword matches.")
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Example: Item 'Rusty Dagger of Power' matches Keep keyword 'Power'.")
                ImGui.Text("Add 'Rusty Dagger of Power' to Always sell exact to sell it anyway.")
                ImGui.EndTooltip()
            end
        end
        ImGui.Spacing()
        if ImGui.CollapsingHeader("Sell protection", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("Sell Rules", "Protection flags")
            ImGui.TextWrapped("Items with these flags are never sold.")
            local function sellFlag(name, key, tooltip)
                local v = ImGui.Checkbox(name, configSellFlags[key])
                if v ~= configSellFlags[key] then configSellFlags[key] = v; config.writeINIValue("sell_flags.ini", "Settings", key, v and "TRUE" or "FALSE"); invalidateSellConfigCache() end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
            end
            sellFlag("Protect No-Drop", "protectNoDrop", "Never sell items with the No-Drop flag")
            sellFlag("Protect No-Trade", "protectNoTrade", "Never sell items with the No-Trade flag")
            sellFlag("Protect Lore", "protectLore", "Never sell items with the Lore flag")
            sellFlag("Protect Quest", "protectQuest", "Never sell items with the Quest flag")
            sellFlag("Protect Collectible", "protectCollectible", "Never sell items with the Collectible flag")
            sellFlag("Protect Heirloom", "protectHeirloom", "Never sell items with the Heirloom flag")
            sellFlag("Protect Epic", "protectEpic", "Never sell Epic quest items. When on, only items for classes checked below are protected (or all classes if none checked).")
            renderEpicClassGrid()
        end
        ImGui.Spacing()
        if ImGui.CollapsingHeader("Sell value thresholds", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("Sell Rules", "Value thresholds")
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "All values in copper (1 platinum = 1000 copper).")
            ImGui.Text("Min value (single)")
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Minimum value in copper to consider selling a single item.")
                ImGui.Text("Example: 100 = only sell items worth 10 silver or more.")
                ImGui.Text("Set to 0 to sell all non-protected items.")
                ImGui.EndTooltip()
            end
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
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Minimum value per unit in copper for stackable items.")
                ImGui.Text("Example: 50 per unit = sell a stack of 20 if each worth 5 silver.")
                ImGui.Text("Lower than single value to sell cheap stacks.")
                ImGui.EndTooltip()
            end
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
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Items ABOVE this value are always kept (never sold).")
                ImGui.Text("Example: 100000 = keep items worth more than 100 platinum.")
                ImGui.Text("Set to 0 to disable (no maximum).")
                ImGui.EndTooltip()
            end
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
        if ImGui.CollapsingHeader("Sell item lists", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("Sell Rules", "Item lists")
            renderFiltersSection(1, false)
        end
    elseif filterState.configTab == 3 then
        ImGui.Spacing()
        renderBreadcrumb("Loot Rules", "Overview")
        if ImGui.CollapsingHeader("Run loot macro", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("Loot Rules", "Quick actions")
            if ImGui.Button("Auto Loot", ImVec2(100, 0)) then
                mq.cmd('/macro loot')
                setStatusMessage("Running loot macro...")
            end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Run loot.mac to auto-loot nearby corpses"); ImGui.EndTooltip() end
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "/macro loot  or  /doloot")
        end
        ImGui.Spacing()
        if ImGui.CollapsingHeader("How loot rules work", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("Loot Rules", "Overview")
            ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.HeaderAlt))
            ImGui.TextWrapped("loot.mac uses this order: SKIP first, then Always Loot, then value/flags. Valuable (shared) is merged into Always Loot.")
            ImGui.PopStyleColor()
            ImGui.BulletText("1. Lore duplicate: skip if already owned")
            ImGui.BulletText("2. Skip lists: exact names, keywords, types (never loot)")
            ImGui.BulletText("3. Tribute override: loot if tribute value >= threshold")
            ImGui.BulletText("4. Always loot: exact names, keywords, types (shared + macro)")
            ImGui.BulletText("5. Value checks: min loot value (stack vs single)")
            ImGui.BulletText("6. Flag checks: clickies, quest, collectible, heirloom, attuneable, aug slots")
        end
        ImGui.Spacing()
        if ImGui.CollapsingHeader("Loot flags", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("Loot Rules", "Flag rules")
            ImGui.TextColored(theme.ToVec4(theme.Colors.Success), "Loot items with these flags (loot.mac)")
            local function lootFlag(name, key, tooltip)
                local v = ImGui.Checkbox(name, configLootFlags[key])
                if v ~= configLootFlags[key] then configLootFlags[key] = v; config.writeLootINIValue("loot_flags.ini", "Settings", key, v and "TRUE" or "FALSE") end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
            end
            lootFlag("Always loot Epic", "alwaysLootEpic", "Always loot EPIC quest items. When on, only items for classes checked below are always looted (or all classes if none checked).")
            renderEpicClassGrid()
            lootFlag("Loot clickies", "lootClickies", "Loot wearable items with clicky effects")
            lootFlag("Loot quest items", "lootQuest", "Loot items with the Quest flag")
            lootFlag("Loot collectible", "lootCollectible", "Loot items with the Collectible flag")
            lootFlag("Loot heirloom", "lootHeirloom", "Loot items with the Heirloom flag")
            lootFlag("Loot attuneable", "lootAttuneable", "Loot items with the Attuneable flag")
            lootFlag("Loot augment slots", "lootAugSlots", "Loot items that can have augments")
            ImGui.Spacing()
            lootFlag("Pause on Mythical NoDrop/NoTrade", "pauseOnMythicalNoDropNoTrade", "When a Mythical item with NoDrop or NoTrade is found, pause the loot macro, beep twice, alert group, and leave the item on corpse so the group can decide who loots.")
            lootFlag("Alert group when Mythical pause", "alertMythicalGroupChat", "When pause triggers, send the item and corpse name to group chat (only if grouped).")
        end
        ImGui.Spacing()
        if ImGui.CollapsingHeader("Loot value thresholds", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("Loot Rules", "Value thresholds")
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "All values in copper (1 platinum = 1000 copper).")
            ImGui.SetNextItemWidth(120)
            local vs = tostring(configLootValues.minLoot)
            vs, _ = ImGui.InputText("Min loot value##LootMin", vs, ImGuiInputTextFlags.CharsDecimal)
            local n = tonumber(vs)
            if n and n ~= configLootValues.minLoot then configLootValues.minLoot = math.max(0, math.floor(n)); config.writeLootINIValue("loot_value.ini", "Settings", "minLootValue", tostring(configLootValues.minLoot)) end
            ImGui.SameLine(); ImGui.Text("Min value (non-stack)")
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Minimum value in copper to loot a single item.")
                ImGui.Text("Example: 200 = loot items worth at least 2 silver.")
                ImGui.EndTooltip()
            end
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.minLoot))

            ImGui.SetNextItemWidth(120)
            vs = tostring(configLootValues.minStack)
            vs, _ = ImGui.InputText("Min stack value##LootStack", vs, ImGuiInputTextFlags.CharsDecimal)
            n = tonumber(vs)
            if n and n ~= configLootValues.minStack then configLootValues.minStack = math.max(0, math.floor(n)); config.writeLootINIValue("loot_value.ini", "Settings", "minLootValueStack", tostring(configLootValues.minStack)) end
            ImGui.SameLine(); ImGui.Text("Min value (stack)")
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Minimum value per unit for stackable items.")
                ImGui.Text("Example: 50 = loot stack if each is worth 5 silver.")
                ImGui.EndTooltip()
            end
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.minStack) .. "/unit")

            ImGui.SetNextItemWidth(120)
            vs = tostring(configLootValues.tributeOverride)
            vs, _ = ImGui.InputText("Tribute override##LootTrib", vs, ImGuiInputTextFlags.CharsDecimal)
            n = tonumber(vs)
            if n and n ~= configLootValues.tributeOverride then configLootValues.tributeOverride = math.max(0, math.floor(n)); config.writeLootINIValue("loot_value.ini", "Settings", "tributeOverride", tostring(configLootValues.tributeOverride)) end
            ImGui.SameLine(); ImGui.Text("Tribute override (0=off)")
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Tribute value override in copper; 0 disables.")
                ImGui.Text("If tribute value >= override, item is looted.")
                ImGui.EndTooltip()
            end
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.tributeOverride))
        end
        ImGui.Spacing()
        if ImGui.CollapsingHeader("Loot sorting", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("Loot Rules", "Sorting")
            local v = ImGui.Checkbox("Enable sorting", configLootSorting.enableSorting)
            if v ~= configLootSorting.enableSorting then configLootSorting.enableSorting = v; config.writeLootINIValue("loot_sorting.ini", "Settings", "enableSorting", v and "TRUE" or "FALSE") end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Master toggle for loot sorting"); ImGui.EndTooltip() end
            v = ImGui.Checkbox("Enable weight sort", configLootSorting.enableWeightSort)
            if v ~= configLootSorting.enableWeightSort then configLootSorting.enableWeightSort = v; config.writeLootINIValue("loot_sorting.ini", "Settings", "enableWeightSort", v and "TRUE" or "FALSE") end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Sort inventory by weight when looting"); ImGui.EndTooltip() end
            ImGui.SetNextItemWidth(120)
            local vs = tostring(configLootSorting.minWeight)
            vs, _ = ImGui.InputText("Weight threshold##LootWt", vs, ImGuiInputTextFlags.CharsDecimal)
            local n = tonumber(vs)
            if n and n ~= configLootSorting.minWeight then configLootSorting.minWeight = math.max(0, math.floor(n)); config.writeLootINIValue("loot_sorting.ini", "Settings", "minWeight", tostring(configLootSorting.minWeight)) end
            ImGui.SameLine(); ImGui.Text("Weight threshold (tenths)")
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Weight in tenths of a pound (40 = 4.0 lbs)"); ImGui.EndTooltip() end
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), string.format("%.1f lbs", (tonumber(configLootSorting.minWeight) or 0) / 10))
        end
        ImGui.Spacing()
        if ImGui.CollapsingHeader("Loot item lists", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("Loot Rules", "Item lists")
            renderFiltersSection(3, false)
        end
    elseif filterState.configTab == 4 then
        ImGui.Spacing()
        renderBreadcrumb("Shared", "Overview")
        if ImGui.CollapsingHeader("Valuable shared lists", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("Shared", "Valuable lists")
            renderFiltersSection(2, false)
        end
    else
        ImGui.Spacing()
        renderBreadcrumb("Statistics", "Overview")
        if ImGui.CollapsingHeader("Macro statistics", ImGuiTreeNodeFlags.DefaultOpen) then
            renderBreadcrumb("Statistics", "Macro statistics")
            local stats = safeGetStats()
            local sellStats = stats and stats.sell or nil
            local lootStats = stats and stats.loot or nil
            if not sellStats and not lootStats then
                ImGui.TextColored(theme.ToVec4(theme.Colors.Warning), "Stats are not available yet.")
                ImGui.TextWrapped("Run sell.mac or loot.mac to populate statistics.")
            else
                local function safeNumber(v, fmt)
                    if v == nil then return "N/A" end
                    if fmt then return fmt(v) end
                    local n = tonumber(v)
                    return n and tostring(n) or "N/A"
                end
                local function statLine(label, value)
                    ImGui.Text(label)
                    ImGui.SameLine(220)
                    ImGui.Text(value)
                end

                ImGui.TextColored(theme.ToVec4(theme.Colors.HeaderAlt), "Sell stats")
                local sellRuns = sellStats and sellStats.totalRuns
                statLine("Total runs", safeNumber(sellRuns))
                statLine("Items sold", safeNumber(sellStats and sellStats.totalItemsSold))
                statLine("Items failed", safeNumber(sellStats and sellStats.totalItemsFailed))
                statLine("Avg items/run", safeNumber(sellStats and sellStats.avgItemsPerRun, function(v) return string.format("%.1f", v) end))
                statLine("Avg duration", safeNumber(sellStats and sellStats.avgDurationMs, formatDurationMs))
                statLine("Last run duration", safeNumber(sellStats and sellStats.lastRunDurationMs, formatDurationMs))

                local totalItems = (tonumber(sellStats and sellStats.totalItemsSold) or 0) + (tonumber(sellStats and sellStats.totalItemsFailed) or 0)
                if totalItems > 0 then
                    local successRate = (tonumber(sellStats.totalItemsSold) or 0) / totalItems * 100
                    local rateColor = successRate >= 90 and theme.Colors.Success or theme.Colors.Warning
                    ImGui.TextColored(theme.ToVec4(rateColor), string.format("Sell success rate: %.1f%%", successRate))
                end

                ImGui.Spacing()
                ImGui.TextColored(theme.ToVec4(theme.Colors.HeaderAlt), "Loot stats")
                statLine("Total runs", safeNumber(lootStats and lootStats.totalRuns))
                statLine("Avg duration", safeNumber(lootStats and lootStats.avgDurationMs, formatDurationMs))
                statLine("Last run duration", safeNumber(lootStats and lootStats.lastRunDurationMs, formatDurationMs))

                if (tonumber(sellRuns) or 0) == 0 and (tonumber(lootStats and lootStats.totalRuns) or 0) == 0 then
                    ImGui.Spacing()
                    ImGui.TextColored(theme.ToVec4(theme.Colors.Warning), "No runs recorded yet.")
                end
            end

            ImGui.Spacing()
            local canReset = macroBridge and macroBridge.resetStats
            if not canReset then ImGui.BeginDisabled() end
            if ImGui.Button("Reset statistics##Stats", ImVec2(160, 0)) then
                ImGui.OpenPopup("ResetStatsConfirm##ItemUI")
            end
            if not canReset then ImGui.EndDisabled() end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Clear all sell/loot statistics"); ImGui.EndTooltip() end
            if ImGui.BeginPopupModal("ResetStatsConfirm##ItemUI", nil, ImGuiWindowFlags.AlwaysAutoResize) then
                ImGui.TextWrapped("Reset all sell and loot statistics?")
                ImGui.Spacing()
                if ImGui.Button("Reset now##Stats", ImVec2(120, 0)) then
                    if macroBridge and macroBridge.resetStats then
                        macroBridge.resetStats()
                        setStatusMessage("Statistics reset")
                    end
                    ImGui.CloseCurrentPopup()
                end
                ImGui.SameLine()
                if ImGui.Button("Cancel##Stats", ImVec2(120, 0)) then ImGui.CloseCurrentPopup() end
                ImGui.EndPopup()
            end
        end
    end
    ImGui.End()
end

function ConfigView.render(ctx)
    bindContext(ctx)
    refreshTargets()
    renderConfigWindow()
end

return ConfigView
