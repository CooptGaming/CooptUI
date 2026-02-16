--[[
    Augments View - Pop-out window (like Bank)
    
    Shows all items of type "Augmentation" in a compact table for quick review.
    Uses its own lists that override other sell/loot rules:
    - Always sell: augment-only list (sell_augment_always_sell_exact.ini); overrides Keep, shared, value rules.
    - Never loot: augment-only list (loot_augment_skip_exact.ini); overrides Always loot, valuable, etc.
    Columns: Icon (hover = full stats) | Name | Effects | Value | Always sell | Never loot
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')

local AugmentsView = {}

local AUGMENT_TYPE = "Augmentation"
local AUGMENTS_WINDOW_WIDTH = 560
local AUGMENTS_WINDOW_HEIGHT = 500

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

-- Module interface: render augments pop-out window (owns ImGui.Begin/End like BankView)
function AugmentsView.render(ctx)
    if not ctx.uiState.augmentsWindowShouldDraw then return end

    local augmentsWindowOpen = ctx.uiState.augmentsWindowOpen
    local layoutConfig = ctx.layoutConfig

    -- Position: use saved or default
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
    if ImGui.IsKeyPressed(ImGuiKey.Escape) then
        ctx.uiState.augmentsWindowOpen = false
        ctx.uiState.augmentsWindowShouldDraw = false
        ImGui.End()
        return
    end
    if not winVis then ImGui.End(); return end

    -- Save size/position when changed
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

    -- Filter to augmentations only
    local augments = {}
    for _, it in ipairs(ctx.inventoryItems or {}) do
        local t = (it.type or ""):match("^%s*(.-)%s*$")
        if t == AUGMENT_TYPE then
            table.insert(augments, it)
        end
    end

    ctx.theme.TextHeader("Augmentations")
    ImGui.SameLine()
    ctx.theme.TextInfo(string.format("(%d in inventory)", #augments))
    ImGui.SameLine()
    if ImGui.Button("Refresh##Augments", ImVec2(70, 0)) then
        ctx.setStatusMessage("Scanning..."); ctx.scanInventory(); ctx.setStatusMessage("Refreshed")
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Rescan inventory"); ImGui.EndTooltip() end
    ImGui.SameLine()
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(160)
    ctx.uiState.searchFilterAugments, _ = ImGui.InputText("##AugmentsSearch", ctx.uiState.searchFilterAugments or "")
    ImGui.SameLine()
    if ImGui.Button("X##AugmentsSearchClear", ImVec2(22, 0)) then ctx.uiState.searchFilterAugments = "" end
    ImGui.Separator()

    local searchLower = (ctx.uiState.searchFilterAugments or ""):lower()
    local filtered = {}
    for _, it in ipairs(augments) do
        if searchLower == "" or (it.name or ""):lower():find(searchLower, 1, true) then
            table.insert(filtered, it)
        end
    end

    if #filtered == 0 then
        if #augments == 0 then
            ctx.theme.TextMuted("No augmentations in inventory. Loot some and refresh.")
        else
            ctx.theme.TextMuted("No augmentations match your search.")
        end
        ImGui.End()
        return
    end

    -- Build a set of "Never loot" (augment-only skip list) names from cached config.
    local augmentNeverLootSet = {}
    if ctx.configLootLists and ctx.configLootLists.augmentSkipExact then
        for _, name in ipairs(ctx.configLootLists.augmentSkipExact) do
            if name and name ~= "" then augmentNeverLootSet[name] = true end
        end
    end

    -- Compact table: Icon (stats on hover) | Name | Effects | Value | Always sell | Never loot (Name, Effects, Value sortable)
    local nCols = 6
    local tableFlagsAug = bit32.bor(ctx.uiState.tableFlags or 0, ImGuiTableFlags.Sortable)
    if ImGui.BeginTable("ItemUI_Augments", nCols, tableFlagsAug) then
        ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 28, 0)   -- Icon (not sortable)
        ImGui.TableSetupColumn("Name", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable, ImGuiTableColumnFlags.DefaultSort), 0, 1)
        ImGui.TableSetupColumn("Effects", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable), 0, 2)
        ImGui.TableSetupColumn("Value", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), 60, 3)
        ImGui.TableSetupColumn("Always sell", ImGuiTableColumnFlags.WidthFixed, 72, 4)
        ImGui.TableSetupColumn("Never loot", ImGuiTableColumnFlags.WidthFixed, 72, 5)
        ImGui.TableSetupScrollFreeze(1, 1)
        ImGui.TableHeadersRow()

        -- Read sort spec and sort filtered list
        local sortSpecs = ImGui.TableGetSortSpecs()
        if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
            local spec = sortSpecs:Specs(1)
            if spec then
                ctx.uiState.augmentsSortColumn = spec.ColumnIndex
                ctx.uiState.augmentsSortDirection = spec.SortDirection
            end
            sortSpecs.SpecsDirty = false
        end
        local sortCol = (ctx.uiState.augmentsSortColumn ~= nil) and ctx.uiState.augmentsSortColumn or 1
        local sortDir = ctx.uiState.augmentsSortDirection or ImGuiSortDirection.Ascending
        local asc = (sortDir == ImGuiSortDirection.Ascending)
        if sortCol >= 1 and sortCol <= 3 then
            table.sort(filtered, function(a, b)
                local av, bv
                if sortCol == 1 then
                    av, bv = (a.name or ""):lower(), (b.name or ""):lower()
                    if asc then return av < bv else return av > bv end
                elseif sortCol == 2 then
                    av, bv = getEffectsLine(ctx, a):lower(), getEffectsLine(ctx, b):lower()
                    if asc then return av < bv else return av > bv end
                else
                    av = tonumber(a.totalValue) or 0
                    bv = tonumber(b.totalValue) or 0
                    if asc then return av < bv else return av > bv end
                end
            end)
        end

        local hasCursor = ctx.hasItemOnCursor()
        local clipper = ImGuiListClipper.new()
        clipper:Begin(#filtered)
        while clipper:Step() do
            for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                local item = filtered[i]
                if not item then goto continue end
                ImGui.TableNextRow()
                local rid = "aug_" .. item.bag .. "_" .. item.slot
                ImGui.PushID(rid)

                local nameKey = (item.name or ""):match("^%s*(.-)%s*$")
                local actualInAugmentAlwaysSell = ctx.augmentLists and ctx.augmentLists.isInAugmentAlwaysSellList and ctx.augmentLists.isInAugmentAlwaysSellList(nameKey) or false
                local actualInAugmentNeverLoot = augmentNeverLootSet[nameKey] == true

                -- Column: Icon (hover = full stats)
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

                -- Column: Name
                ImGui.TableNextColumn()
                local dn = item.name or ""
                if (item.stackSize or 1) > 1 then dn = dn .. string.format(" (x%d)", item.stackSize) end
                ImGui.Selectable(dn, false, ImGuiSelectableFlags.None, ImVec2(0, 0))
                if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) and not hasCursor then
                    ctx.uiState.lastPickup.bag, ctx.uiState.lastPickup.slot, ctx.uiState.lastPickup.source = item.bag, item.slot, "inv"
                    ctx.uiState.lastPickupSetThisFrame = true
                    mq.cmdf('/itemnotify in pack%d %d leftmouseup', item.bag, item.slot)
                end
                if ImGui.BeginPopupContextItem("ItemContextAugments_" .. rid) then
                    if ImGui.MenuItem("CoOp UI Item Display") then
                        if ctx.addItemDisplayTab then ctx.addItemDisplayTab(item, "inv") end
                    end
                    if ImGui.MenuItem("Inspect") then
                        if hasCursor then ctx.removeItemFromCursor()
                        else
                            local Me = mq.TLO and mq.TLO.Me
                            local pack = Me and Me.Inventory and Me.Inventory("pack" .. item.bag)
                            local tlo = pack and pack.Item and pack.Item(item.slot)
                            if tlo and tlo.ID and tlo.ID() and tlo.ID() > 0 and tlo.Inspect then tlo.Inspect() end
                        end
                    end
                    ImGui.EndPopup()
                end

                -- Column: Effects (only what exists)
                ImGui.TableNextColumn()
                local effectsStr = getEffectsLine(ctx, item)
                if effectsStr ~= "" then
                    ImGui.TextWrapped(effectsStr)
                else
                    ctx.theme.TextMuted("—")
                end

                -- Column: Value
                ImGui.TableNextColumn()
                ImGui.Text(ItemUtils.formatValue(item.totalValue or 0))

                -- Column: Always sell (augment-only list; overrides other sell rules)
                ImGui.TableNextColumn()
                if actualInAugmentAlwaysSell then
                    ctx.theme.PushKeepButton(false)  -- highlighted = in list
                else
                    ctx.theme.PushSkipButton()
                end
                if ImGui.Button("Always sell##" .. rid, ImVec2(70, 0)) then
                    if actualInAugmentAlwaysSell then
                        if ctx.augmentLists then ctx.augmentLists.removeFromAugmentAlwaysSellList(nameKey) end
                    else
                        if ctx.augmentLists then ctx.augmentLists.addToAugmentAlwaysSellList(nameKey) end
                    end
                end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Add/remove from Augment Always sell list (overrides Keep/sell rules)"); ImGui.EndTooltip() end
                ctx.theme.PopButtonColors()

                -- Column: Never loot (augment-only list; overrides other loot rules)
                ImGui.TableNextColumn()
                if actualInAugmentNeverLoot then
                    ctx.theme.PushKeepButton(false)  -- highlighted = in list
                else
                    ctx.theme.PushSkipButton()
                end
                if ImGui.Button("Never loot##" .. rid, ImVec2(70, 0)) then
                    if actualInAugmentNeverLoot then
                        if ctx.augmentLists then ctx.augmentLists.removeFromAugmentNeverLootList(nameKey) end
                    else
                        if ctx.augmentLists then ctx.augmentLists.addToAugmentNeverLootList(nameKey) end
                    end
                end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Add/remove from Augment Never loot list (overrides other loot rules)"); ImGui.EndTooltip() end
                ctx.theme.PopButtonColors()

                ImGui.PopID()
                ::continue::
            end
        end
        ImGui.EndTable()
    end

    ImGui.End()
end

return AugmentsView
