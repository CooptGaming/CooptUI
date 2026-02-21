--[[
    Reroll Manager (dual-tab) - Pop-out window (like Bank)

    TAB 1 Augments: Items of type "Augmentation". 10-for-1 server exchange (!augroll).
    TAB 2 Mythicals: Items whose name contains "Mythical". 10-for-1 server exchange (!mythicalroll).

    Preserves: getEffectsLine(), cached never-loot set pattern, window position save/restore,
    icon+tooltip rendering, right-click context menu patterns.
    Columns: Icon (hover = full stats) | Name | Effects | Value | Protect
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')
local events = require('itemui.core.events')
local constants = require('itemui.constants')

local AugmentsView = {}

-- Cached "Never loot" set (augment skip list); invalidated on CONFIG_LOOT_CHANGED
local cachedAugmentNeverLootSet = {}
local augmentNeverLootCacheValid = false
events.on(events.EVENTS.CONFIG_LOOT_CHANGED, function() augmentNeverLootCacheValid = false end)

local AUGMENT_TYPE = "Augmentation"
local AUGMENTS_WINDOW_WIDTH = 560
local AUGMENTS_WINDOW_HEIGHT = 500
local REROLL_REQUIRED = constants.LIMITS.REROLL_REQUIRED_COUNT or 10
local REROLL_RESCAN_MS = constants.TIMING.REROLL_RESCAN_DELAY_MS or 2000
local PROGRESS_BAR_H = (constants.UI and constants.UI.REROLL_PROGRESS_BAR_HEIGHT) or 20

--- Build a single-line effects string (only non-empty: Clicky, Worn, Proc, Focus, Spell)
local function getEffectsLine(ctx, item)
    local parts = {}
    local function add(name, key)
        local id = ctx.getItemSpellId(item, key)
        if id and id > 0 then
            local spellName = ctx.getSpellName(id)
            if spellName and spellName ~= "" then
                parts[#parts + 1] = name .. ": " .. spellName
            end
        end
    end
    add("Clicky", "Clicky")
    add("Worn", "Worn")
    add("Proc", "Proc")
    add("Focus", "Focus")
    add("Spell", "Spell")
    return #parts > 0 and table.concat(parts, "  ·  ") or ""
end

--- Return true if item is an augmentation (type == "Augmentation")
local function isAugment(item)
    local t = (item.type or ""):match("^%s*(.-)%s*$")
    return t == AUGMENT_TYPE
end

--- Return true if item name contains "Mythical"
local function isMythical(item)
    return (item.name or ""):find("Mythical") and true or false
end

--- Render one tab's table (augments or mythicals) with shared pattern: Icon | Name | Effects | Value | Protect
--- items: array of item tables; isProtected(itemName) -> boolean; toggleProtect(itemName) adds/removes from protect list
--- sortKey: prefix for uiState sort column/direction (e.g. "augments" or "mythicals")
--- tableId: unique ImGui table ID
--- rowIdPrefix: e.g. "aug_" or "myth_"
local function renderRerollTable(ctx, items, filtered, isProtected, toggleProtect, sortKey, tableId, rowIdPrefix)
    local sortCol = (ctx.uiState[sortKey .. "SortColumn"] ~= nil) and ctx.uiState[sortKey .. "SortColumn"] or 1
    local sortDir = ctx.uiState[sortKey .. "SortDirection"] or ImGuiSortDirection.Ascending
    local asc = (sortDir == ImGuiSortDirection.Ascending)
    if sortCol >= 1 and sortCol <= 3 then
        table.sort(filtered, function(a, b)
            local av, bv
            if sortCol == 1 then
                av, bv = (a.name or ""):lower(), (b.name or ""):lower()
                return asc and (av < bv) or (av > bv)
            elseif sortCol == 2 then
                av, bv = getEffectsLine(ctx, a):lower(), getEffectsLine(ctx, b):lower()
                return asc and (av < bv) or (av > bv)
            else
                av = tonumber(a.totalValue) or 0
                bv = tonumber(b.totalValue) or 0
                return asc and (av < bv) or (av > bv)
            end
        end)
    end

    local nCols = 5
    local tableFlags = bit32.bor(ctx.uiState.tableFlags or 0, ImGuiTableFlags.Sortable)
    if not ImGui.BeginTable(tableId, nCols, tableFlags) then return end

    ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 28, 0)
    ImGui.TableSetupColumn("Name", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable, ImGuiTableColumnFlags.DefaultSort), 0, 1)
    ImGui.TableSetupColumn("Effects", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable), 0, 2)
    ImGui.TableSetupColumn("Value", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), 60, 3)
    ImGui.TableSetupColumn("Protect", ImGuiTableColumnFlags.WidthFixed, 72, 4)
    ImGui.TableSetupScrollFreeze(1, 1)
    ImGui.TableHeadersRow()

    local sortSpecs = ImGui.TableGetSortSpecs()
    if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
        local spec = sortSpecs:Specs(1)
        if spec then
            ctx.uiState[sortKey .. "SortColumn"] = spec.ColumnIndex
            ctx.uiState[sortKey .. "SortDirection"] = spec.SortDirection
        end
        sortSpecs.SpecsDirty = false
    end

    local hasCursor = ctx.hasItemOnCursor and ctx.hasItemOnCursor() or false
    local clipper = ImGuiListClipper.new()
    clipper:Begin(#filtered)
    while clipper:Step() do
        for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
            local item = filtered[i]
            if not item then goto continue end
            ImGui.TableNextRow()
            local rid = rowIdPrefix .. item.bag .. "_" .. item.slot
            ImGui.PushID(rid)
            local nameKey = (item.name or ""):match("^%s*(.-)%s*$")
            local protected = isProtected(nameKey)

            -- Icon (hover = full stats)
            ImGui.TableNextColumn()
            if ctx.drawItemIcon then
                ctx.drawItemIcon(item.icon)
            else
                ImGui.Text(tostring(item.icon or 0))
            end
            if ImGui.IsItemHovered() then
                local showItem = (ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip(item, "inv")) or item
                local opts = { source = "inv", bag = item.bag, slot = item.slot }
                local effects, w, h = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
                opts.effects = effects
                ItemTooltip.beginItemTooltip(w, h)
                ImGui.Text("Stats")
                ImGui.Separator()
                ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
                ImGui.EndTooltip()
            end
            if ImGui.BeginPopupContextItem("ItemContextRerollIcon_" .. rid) then
                if ImGui.MenuItem("CoOp UI Item Display") then
                    if ctx.addItemDisplayTab then ctx.addItemDisplayTab(item, "inv") end
                end
                if ImGui.MenuItem("Inspect") then
                    if hasCursor and ctx.removeItemFromCursor then ctx.removeItemFromCursor()
                    else
                        local Me = mq.TLO and mq.TLO.Me
                        local pack = Me and Me.Inventory and Me.Inventory("pack" .. item.bag)
                        local tlo = pack and pack.Item and pack.Item(item.slot)
                        if tlo and tlo.ID and tlo.ID() and tlo.ID() > 0 and tlo.Inspect then tlo.Inspect() end
                    end
                end
                ImGui.EndPopup()
            end

            -- Name
            ImGui.TableNextColumn()
            local dn = item.name or ""
            if (item.stackSize or 1) > 1 then dn = dn .. string.format(" (x%d)", item.stackSize) end
            ImGui.Selectable(dn, false, ImGuiSelectableFlags.None, ImVec2(0, 0))
            if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) and not hasCursor then
                if ctx.pickupFromSlot then ctx.pickupFromSlot(item.bag, item.slot, "inv") end
            end
            if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                if ctx.addItemDisplayTab then ctx.addItemDisplayTab(item, "inv") end
            end

            -- Effects
            ImGui.TableNextColumn()
            local effectsStr = getEffectsLine(ctx, item)
            if effectsStr ~= "" then
                ImGui.TextWrapped(effectsStr)
            else
                ctx.theme.TextMuted("—")
            end

            -- Value
            ImGui.TableNextColumn()
            ImGui.Text(ItemUtils.formatValue(item.totalValue or 0))

            -- Protect
            ImGui.TableNextColumn()
            if protected then
                ctx.theme.PushKeepButton(false)
            else
                ctx.theme.PushSkipButton()
            end
            if ImGui.Button("Protect##" .. rid, ImVec2(70, 0)) then
                toggleProtect(nameKey)
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Protected items are excluded from reroll count.")
                ImGui.EndTooltip()
            end
            ctx.theme.PopButtonColors()

            ImGui.PopID()
            ::continue::
        end
    end
    ImGui.EndTable()
end

--- Draw Augments tab content
local function drawAugmentsTab(ctx)
    local augments = {}
    for _, it in ipairs(ctx.inventoryItems or {}) do
        if isAugment(it) then table.insert(augments, it) end
    end

    local searchLower = (ctx.uiState.searchFilterAugments or ""):lower()
    local filtered = {}
    for _, it in ipairs(augments) do
        if searchLower == "" or (it.name or ""):lower():find(searchLower, 1, true) then
            table.insert(filtered, it)
        end
    end

    local isInList = ctx.augmentLists and ctx.augmentLists.isInAugmentAlwaysSellList and ctx.augmentLists.isInAugmentAlwaysSellList
    local unprotectedCount = 0
    for _, it in ipairs(filtered) do
        local nameKey = (it.name or ""):match("^%s*(.-)%s*$")
        if isInList and isInList(nameKey) then unprotectedCount = unprotectedCount + 1 end
    end

    ctx.theme.TextHeader("Augment Reroll (" .. unprotectedCount .. "/" .. REROLL_REQUIRED .. ")")
    ImGui.SameLine()
    ctx.renderRefreshButton(ctx, "Refresh##Augments", "Rescan inventory", function() ctx.scanInventory() end, { messageBefore = "Scanning...", messageAfter = "Refreshed" })
    ImGui.SameLine()
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(160)
    ctx.uiState.searchFilterAugments, _ = ImGui.InputText("##AugmentsSearch", ctx.uiState.searchFilterAugments or "")
    ImGui.SameLine()
    if ImGui.Button("X##AugmentsSearchClear", ImVec2(22, 0)) then ctx.uiState.searchFilterAugments = "" end
    ImGui.Separator()

    local progressFrac = math.min(1.0, unprotectedCount / REROLL_REQUIRED)
    local overlay = unprotectedCount .. "/" .. REROLL_REQUIRED
    if ctx.theme and ctx.theme.RenderProgressBar then
        ctx.theme.RenderProgressBar(progressFrac, ImVec2(-1, PROGRESS_BAR_H), overlay)
    else
        ImGui.ProgressBar(progressFrac, ImVec2(-1, PROGRESS_BAR_H), overlay)
    end
    ImGui.Spacing()

    local canReroll = unprotectedCount >= REROLL_REQUIRED
    if ImGui.Button("Reroll##Augments", ImVec2(80, 0)) then
        if canReroll then ImGui.OpenPopup("ConfirmAugReroll") end
    end
    if not canReroll and ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(string.format("Need %d unprotected augments to reroll.", REROLL_REQUIRED))
        ImGui.EndTooltip()
    end
    ImGui.SameLine()
    ImGui.TextColored(ctx.theme.ToVec4(ctx.theme.Colors.Muted), "10 augments -> 1 new augment (!augroll)")

    if ImGui.BeginPopupModal("ConfirmAugReroll", nil, ImGuiWindowFlags.AlwaysAutoResize) then
        ImGui.Text("Reroll augments? This will destroy 10 augments and give you 1 new usable augment. This cannot be undone.")
        if ImGui.Button("Confirm", ImVec2(100, 0)) then
            mq.cmdf('!augroll')
            if ctx.uiState then ctx.uiState.deferredInventoryScanAt = mq.gettime() + REROLL_RESCAN_MS end
            ImGui.CloseCurrentPopup()
        end
        ImGui.SameLine()
        if ImGui.Button("Cancel", ImVec2(80, 0)) then ImGui.CloseCurrentPopup() end
        ImGui.EndPopup()
    end

    ImGui.Separator()
    if #filtered == 0 then
        if #augments == 0 then
            ctx.theme.TextMuted("No augmentations in inventory. Loot some and refresh.")
        else
            ctx.theme.TextMuted("No augmentations match your search.")
        end
        return
    end

    local function isProtectedAug(name)
        if not ctx.augmentLists or not ctx.augmentLists.isInAugmentAlwaysSellList then return true end
        return not ctx.augmentLists.isInAugmentAlwaysSellList(name)
    end
    local function toggleProtectAug(name)
        if not ctx.augmentLists then return end
        if isProtectedAug(name) then
            ctx.augmentLists.addToAugmentAlwaysSellList(name)
        else
            ctx.augmentLists.removeFromAugmentAlwaysSellList(name)
        end
    end
    renderRerollTable(ctx, augments, filtered, isProtectedAug, toggleProtectAug, "augments", "ItemUI_Augments", "aug_")
end

--- Draw Mythicals tab content
local function drawMythicalsTab(ctx)
    local mythicals = {}
    for _, it in ipairs(ctx.inventoryItems or {}) do
        if isMythical(it) then table.insert(mythicals, it) end
    end

    local searchLower = (ctx.uiState.searchFilterMythicals or ""):lower()
    local filtered = {}
    for _, it in ipairs(mythicals) do
        if searchLower == "" or (it.name or ""):lower():find(searchLower, 1, true) then
            table.insert(filtered, it)
        end
    end

    local isInSkip = ctx.isInLootSkipList
    local unprotectedCount = 0
    for _, it in ipairs(filtered) do
        local nameKey = (it.name or ""):match("^%s*(.-)%s*$")
        if not isInSkip or not isInSkip(nameKey) then unprotectedCount = unprotectedCount + 1 end
    end

    ctx.theme.TextHeader("Mythical Reroll (" .. unprotectedCount .. "/" .. REROLL_REQUIRED .. ")")
    ImGui.SameLine()
    ctx.renderRefreshButton(ctx, "Refresh##Mythicals", "Rescan inventory", function() ctx.scanInventory() end, { messageBefore = "Scanning...", messageAfter = "Refreshed" })
    ImGui.SameLine()
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(160)
    ctx.uiState.searchFilterMythicals, _ = ImGui.InputText("##MythicalsSearch", ctx.uiState.searchFilterMythicals or "")
    ImGui.SameLine()
    if ImGui.Button("X##MythicalsSearchClear", ImVec2(22, 0)) then ctx.uiState.searchFilterMythicals = "" end
    ImGui.Separator()

    local progressFrac = math.min(1.0, unprotectedCount / REROLL_REQUIRED)
    local overlay = unprotectedCount .. "/" .. REROLL_REQUIRED
    if ctx.theme and ctx.theme.RenderProgressBar then
        ctx.theme.RenderProgressBar(progressFrac, ImVec2(-1, PROGRESS_BAR_H), overlay)
    else
        ImGui.ProgressBar(progressFrac, ImVec2(-1, PROGRESS_BAR_H), overlay)
    end
    ImGui.Spacing()

    local canReroll = unprotectedCount >= REROLL_REQUIRED
    if ImGui.Button("Reroll##Mythicals", ImVec2(80, 0)) then
        if canReroll then ImGui.OpenPopup("ConfirmMythicalReroll") end
    end
    if not canReroll and ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(string.format("Need %d unprotected mythical items to reroll.", REROLL_REQUIRED))
        ImGui.EndTooltip()
    end
    ImGui.SameLine()
    ImGui.TextColored(ctx.theme.ToVec4(ctx.theme.Colors.Muted), "10 mythicals -> 1 new (!mythicalroll)")

    if ImGui.BeginPopupModal("ConfirmMythicalReroll", nil, ImGuiWindowFlags.AlwaysAutoResize) then
        ImGui.Text("Reroll mythical items? This will destroy 10 mythical items and give you 1 new usable mythical. This cannot be undone.")
        if ImGui.Button("Confirm", ImVec2(100, 0)) then
            mq.cmdf('!mythicalroll')
            if ctx.uiState then ctx.uiState.deferredInventoryScanAt = mq.gettime() + REROLL_RESCAN_MS end
            ImGui.CloseCurrentPopup()
        end
        ImGui.SameLine()
        if ImGui.Button("Cancel", ImVec2(80, 0)) then ImGui.CloseCurrentPopup() end
        ImGui.EndPopup()
    end

    ImGui.Separator()
    if #filtered == 0 then
        if #mythicals == 0 then
            ctx.theme.TextMuted("No mythical items in inventory. Loot some and refresh.")
        else
            ctx.theme.TextMuted("No mythical items match your search.")
        end
        return
    end

    local function isProtectedMyth(name)
        return ctx.isInLootSkipList and ctx.isInLootSkipList(name) or false
    end
    local function toggleProtectMyth(name)
        if not ctx.isInLootSkipList then return end
        if ctx.isInLootSkipList(name) then
            if ctx.removeFromLootSkipList then ctx.removeFromLootSkipList(name) end
        else
            if ctx.addToLootSkipList then ctx.addToLootSkipList(name) end
        end
    end
    renderRerollTable(ctx, mythicals, filtered, isProtectedMyth, toggleProtectMyth, "mythicals", "ItemUI_Mythicals", "myth_")
end

-- Module interface: render Reroll Manager pop-out window (owns ImGui.Begin/End like BankView)
function AugmentsView.render(ctx)
    if not ctx.uiState.augmentsWindowShouldDraw then return end

    local augmentsWindowOpen = ctx.uiState.augmentsWindowOpen
    local layoutConfig = ctx.layoutConfig

    local ax = layoutConfig.AugmentsWindowX or 0
    local ay = layoutConfig.AugmentsWindowY or 0
    if ax and ay and ax ~= 0 and ay ~= 0 then
        ImGui.SetNextWindowPos(ImVec2(ax, ay), ImGuiCond.FirstUseEver)
    end

    local w = layoutConfig.WidthAugmentsPanel or AUGMENTS_WINDOW_WIDTH
    local h = layoutConfig.HeightAugments or AUGMENTS_WINDOW_HEIGHT
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.FirstUseEver)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Augments Companion##ItemUIAugments", augmentsWindowOpen, windowFlags)
    ctx.uiState.augmentsWindowOpen = winOpen
    ctx.uiState.augmentsWindowShouldDraw = winOpen

    if not winOpen then ImGui.End(); return end
    if not winVis then ImGui.End(); return end

    if not ctx.uiState.uiLocked then
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            layoutConfig.WidthAugmentsPanel = cw
            layoutConfig.HeightAugments = ch
        end
    end
    local cx, cy = ImGui.GetWindowPos()
    if cx and cy then
        if not layoutConfig.AugmentsWindowX or math.abs(layoutConfig.AugmentsWindowX - cx) > 1 or
           not layoutConfig.AugmentsWindowY or math.abs(layoutConfig.AugmentsWindowY - cy) > 1 then
            layoutConfig.AugmentsWindowX = cx
            layoutConfig.AugmentsWindowY = cy
            ctx.scheduleLayoutSave()
            ctx.flushLayoutSave()
        end
    end

    -- Rebuild cached never-loot set when invalidated (preserved pattern)
    if not augmentNeverLootCacheValid then
        cachedAugmentNeverLootSet = {}
        if ctx.configLootLists and ctx.configLootLists.augmentSkipExact then
            for _, name in ipairs(ctx.configLootLists.augmentSkipExact) do
                if name and name ~= "" then cachedAugmentNeverLootSet[name] = true end
            end
        end
        augmentNeverLootCacheValid = true
    end

    local function drawContent()
        local hasTabBarAPI = ImGui.BeginTabBar ~= nil
        if hasTabBarAPI and ImGui.BeginTabBar("RerollManagerTabs", ImGuiTabBarFlags.None) then
            if ImGui.BeginTabItem("Augments") then
                local ok1, err1 = pcall(drawAugmentsTab, ctx)
                ImGui.EndTabItem()
                if not ok1 and mq and mq.log then mq.log("Reroll Manager Augments tab: %s", tostring(err1)) end
            end
            if ImGui.BeginTabItem("Mythicals") then
                local ok2, err2 = pcall(drawMythicalsTab, ctx)
                ImGui.EndTabItem()
                if not ok2 and mq and mq.log then mq.log("Reroll Manager Mythicals tab: %s", tostring(err2)) end
            end
            ImGui.EndTabBar()
        else
            drawAugmentsTab(ctx)
        end
    end

    local ok, err = pcall(drawContent)
    if not ok then
        if mq and mq.log then mq.log("Reroll Manager (Augments): %s", tostring(err)) else print("Reroll Manager:", err) end
    end

    ImGui.End()
end

return AugmentsView
