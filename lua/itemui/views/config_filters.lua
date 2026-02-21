--[[
    Config filters - Shared filter list infrastructure for Sell, Loot, and Shared (Valuable) tabs.
    Used by config_sell.lua, config_loot.lua, config_shared.lua. Exports refresh(ctx) and renderFiltersSection(ctx, forcedSubTab, showTabs).
--]]

local mq = require('mq')
require('ImGui')
local constants = require('itemui.constants')
local events = require('itemui.core.events')

local ConfigFilters = {}

local config
local theme
local filterState
local hasItemOnCursor
local setStatusMessage
local invalidateSellConfigCache
local invalidateLootConfigCache
local scheduleLayoutSave
local writeListValue
local writeLootListValue
local writeSharedListValue
local configSellLists
local configLootLists

local SELL_FILTER_TARGETS
local VALUABLE_FILTER_TARGET
local LOOT_FILTER_TARGETS

local filterConflictData = nil

local DEFAULT_PROTECT_KEYWORDS = { "Legendary", "Mythical", "Script", "Epic", "Fabled", "Heirloom" }
local DEFAULT_PROTECT_TYPES = { "Food", "Gem", "Augment", "Quest" }

function ConfigFilters.refresh(ctx)
    config = ctx.config
    theme = ctx.theme
    filterState = ctx.filterState
    hasItemOnCursor = ctx.hasItemOnCursor
    setStatusMessage = ctx.setStatusMessage
    invalidateSellConfigCache = ctx.invalidateSellConfigCache
    invalidateLootConfigCache = ctx.invalidateLootConfigCache
    scheduleLayoutSave = ctx.scheduleLayoutSave
    writeListValue = config.writeListValue
    writeLootListValue = config.writeLootListValue
    writeSharedListValue = config.writeSharedListValue
    configSellLists = ctx.configSellLists
    configLootLists = ctx.configLootLists

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

function ConfigFilters.renderBreadcrumb(ctx, tabLabel, sectionLabel)
    local t = ctx.theme
    ImGui.TextColored(t.ToVec4(t.Colors.Muted), string.format("You are here: %s > %s", tabLabel, sectionLabel))
    ImGui.Separator()
end

function ConfigFilters.classLabel(cls)
    if not cls or cls == "" then return "" end
    return (cls:gsub("_", " "):gsub("(%a)(%S*)", function(a, b) return a:upper() .. b:lower() end))
end

function ConfigFilters.loadDefaultProtectList(ctx)
    local cfg = ctx.config
    local flags = ctx.configSellFlags
    local lists = ctx.configSellLists
    local invSell = ctx.invalidateSellConfigCache
    local setMsg = ctx.setStatusMessage
    local added = 0
    for _, kw in ipairs(DEFAULT_PROTECT_KEYWORDS) do
        local list = lists.keepContains
        local found = false
        for _, s in ipairs(list) do if s == kw then found = true; break end end
        if not found then list[#list + 1] = kw; cfg.writeListValue("sell_keep_contains.ini", "Items", "contains", cfg.joinList(list)); added = added + 1 end
    end
    for _, typ in ipairs(DEFAULT_PROTECT_TYPES) do
        local list = lists.protectedTypes
        local found = false
        for _, s in ipairs(list) do if s == typ then found = true; break end end
        if not found then list[#list + 1] = typ; cfg.writeListValue("sell_protected_types.ini", "Items", "types", cfg.joinList(list)); added = added + 1 end
    end
    invSell()
    setMsg(added > 0 and string.format("Added %d default protect entries", added) or "Default protect list already loaded")
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
    events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
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
    events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
    events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
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
    events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
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
            events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
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
            events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
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
            events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
            events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
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

function ConfigFilters.renderFiltersSection(ctx, forcedSubTab, showTabs)
    ConfigFilters.refresh(ctx)
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
    local childHeight = math.max(constants.UI.FILTER_CONTENT_MIN_HEIGHT, availY - constants.UI.WINDOW_GAP)
    ImGui.BeginChild("FiltersContent", ImVec2(0, childHeight), true, ImGuiWindowFlags.AlwaysVerticalScrollbar)

    if activeSubTab == 1 then
        ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.HeaderAlt))
        ImGui.TextWrapped("Always sell unless a qualification is met. Add items to Keep (never sell), Always sell, or Never sell by type.")
        ImGui.PopStyleColor()
        ImGui.Spacing()

        renderFilterSection("sell", SELL_FILTER_TARGETS, filterState.sellFilterTargetId, filterState.sellFilterTypeMode, filterState.sellFilterInputValue, filterState.sellFilterEditTarget, filterState.sellFilterListShow,
            function(v) filterState.sellFilterTargetId = v end, function(v) filterState.sellFilterTypeMode = v end, function(v) filterState.sellFilterInputValue = v end,
            function(v) filterState.sellFilterEditTarget = v end, function(v) filterState.sellFilterListShow = v end,
            checkSellFilterConflicts, performSellFilterAdd, removeFromSellFilterList)

        if ImGui.Button("Load default protect list##Sell", ImVec2(180, 0)) then ConfigFilters.loadDefaultProtectList(ctx) end
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

        local FILTER_BADGE = constants.UI.FILTER_BADGE_WIDTH
        local FILTER_LIST_W = constants.UI.FILTER_LIST_WIDTH
        local FILTER_X_W = constants.UI.FILTER_X_BUTTON_WIDTH
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

        local FILTER_BADGE = constants.UI.FILTER_BADGE_WIDTH
        local FILTER_X_W = constants.UI.FILTER_X_BUTTON_WIDTH
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
            checkLootFilterConflicts, performLootFilterAdd, removeFromLootFilterList)

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

        local FILTER_BADGE = constants.UI.FILTER_BADGE_WIDTH
        local FILTER_LIST_W = constants.UI.FILTER_LIST_WIDTH
        local FILTER_X_W = constants.UI.FILTER_X_BUTTON_WIDTH
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

return ConfigFilters
