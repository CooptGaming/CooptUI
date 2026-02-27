--[[
    Augments View - Pop-out window (like Bank)

    Shows all items of type "Augmentation" in a compact table for quick review.
    Filter section: Add to Aug List / Add to Mythical List (reroll companion lists).
    Columns: Icon (hover = full stats) | Name | Effects | Value | Add to Aug List | Add to Mythical List
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')
local context = require('itemui.context')
local registry = require('itemui.core.registry')

local AugmentsView = {}

-- Per 4.2 state ownership: search and sort state
local state = {
    searchFilterAugments = "",
    augmentsSortColumn = nil,
    augmentsSortDirection = nil,
}
function AugmentsView.getState()
    return state
end

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
    if not registry.shouldDraw("augments") then return end

    local layoutConfig = ctx.layoutConfig

    -- Position: use saved or default (Always when forceApply so revert takes effect)
    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    local condPos = forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver
    local ax = layoutConfig.AugmentsWindowX or 0
    local ay = layoutConfig.AugmentsWindowY or 0
    if ax and ay and ax ~= 0 and ay ~= 0 then
        ImGui.SetNextWindowPos(ImVec2(ax, ay), condPos)
    end

    local w = layoutConfig.WidthAugmentsPanel or AUGMENTS_WINDOW_WIDTH
    local h = layoutConfig.HeightAugments or AUGMENTS_WINDOW_HEIGHT
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), condPos)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Augments Companion##ItemUIAugments", registry.isOpen("augments"), windowFlags)
    registry.setWindowState("augments", winOpen, winOpen)

    if not winOpen then ImGui.End(); return end
    -- Escape closes this window via main Inventory Companion's LIFO handler only
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
    ctx.renderRefreshButton(ctx, "Refresh##Augments", "Rescan inventory", function() ctx.scanInventory() end, { messageBefore = "Scanning...", messageAfter = "Refreshed" })
    ImGui.SameLine()
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(160)
    state.searchFilterAugments, _ = ImGui.InputText("##AugmentsSearch", state.searchFilterAugments or "")
    ImGui.SameLine()
    if ImGui.Button("X##AugmentsSearchClear", ImVec2(22, 0)) then state.searchFilterAugments = "" end
    ImGui.Separator()

    local searchLower = (state.searchFilterAugments or ""):lower()
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

    -- Compact table: Icon (stats on hover) | Name | Effects | Value | [Add to Aug List | Add to Mythical List when Reroll enabled]
    local showRerollColumns = registry.isEnabled("reroll")
    local nCols = showRerollColumns and 6 or 4
    local tableFlagsAug = bit32.bor(ctx.uiState.tableFlags or 0, ImGuiTableFlags.Sortable)
    if ImGui.BeginTable("ItemUI_Augments", nCols, tableFlagsAug) then
        ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 28, 0)   -- Icon (not sortable)
        ImGui.TableSetupColumn("Name", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable, ImGuiTableColumnFlags.DefaultSort), 0, 1)
        ImGui.TableSetupColumn("Effects", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable), 0, 2)
        ImGui.TableSetupColumn("Value", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), 60, 3)
        if showRerollColumns then
            ImGui.TableSetupColumn("Add to Aug List", ImGuiTableColumnFlags.WidthFixed, 100, 4)
            ImGui.TableSetupColumn("Add to Mythical List", ImGuiTableColumnFlags.WidthFixed, 120, 5)
        end
        ImGui.TableSetupScrollFreeze(1, 1)
        ImGui.TableHeadersRow()

        -- Read sort spec and sort filtered list
        local sortSpecs = ImGui.TableGetSortSpecs()
        if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
            local spec = sortSpecs:Specs(1)
            if spec then
                state.augmentsSortColumn = spec.ColumnIndex
                state.augmentsSortDirection = spec.SortDirection
            end
            sortSpecs.SpecsDirty = false
        end
        local sortCol = (state.augmentsSortColumn ~= nil) and state.augmentsSortColumn or 1
        if not showRerollColumns and sortCol > 3 then sortCol = 1 end
        local sortDir = state.augmentsSortDirection or ImGuiSortDirection.Ascending
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
                local itemId = item.id or item.ID
                local rerollService = ctx.rerollService
                local augList = rerollService and rerollService.getAugList and rerollService.getAugList() or {}
                local mythicalList = rerollService and rerollService.getMythicalList and rerollService.getMythicalList() or {}
                local onAugList = false
                local onMythicalList = false
                if itemId then
                    for _, e in ipairs(augList) do if e.id == itemId then onAugList = true; break end end
                    for _, e in ipairs(mythicalList) do if e.id == itemId then onMythicalList = true; break end end
                end
                if not onAugList then
                    for _, e in ipairs(augList) do if (e.name or ""):match("^%s*(.-)%s*$") == nameKey then onAugList = true; break end end
                end
                if not onMythicalList then
                    for _, e in ipairs(mythicalList) do if (e.name or ""):match("^%s*(.-)%s*$") == nameKey then onMythicalList = true; break end end
                end
                -- Mythical list only applies to items whose name starts with "Mythical" (augments view shows augments; mythicals can appear if user has them)
                local itemNameTrim = (item.name or ""):match("^%s*(.-)%s*$")
                local mythicalPrefix = "Mythical"
                local isMythicalEligible = itemNameTrim:sub(1, #mythicalPrefix) == mythicalPrefix

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
                if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                    ImGui.OpenPopup("ItemContextAugmentsIcon_" .. rid)
                end
                ctx.renderItemContextMenu(ctx, item, { source = "augments", popupId = "ItemContextAugmentsIcon_" .. rid, bankOpen = (ctx.isBankWindowOpen and ctx.isBankWindowOpen()) or false, hasCursor = hasCursor })

                -- Column: Name
                ImGui.TableNextColumn()
                local dn = item.name or ""
                if (item.stackSize or 1) > 1 then dn = dn .. string.format(" (x%d)", item.stackSize) end
                ImGui.Selectable(dn, false, ImGuiSelectableFlags.None, ImVec2(0, 0))
                if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) and not hasCursor then
                    ctx.pickupFromSlot(item.bag, item.slot, "inv")
                end
                if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                    ImGui.OpenPopup("ItemContextAugmentsIcon_" .. rid)
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

                if showRerollColumns then
                    -- Column: Add to Aug List (reroll companion list; augments only)
                    ImGui.TableNextColumn()
                    local augDisabled = onAugList or (ctx.uiState.pendingRerollAdd and ctx.uiState.pendingRerollAdd.list == "aug")
                    if augDisabled then
                        ctx.theme.PushKeepButton(true)
                    else
                        ctx.theme.PushKeepButton(false)
                    end
                    if ImGui.Button("Aug List##" .. rid, ImVec2(90, 0)) then
                        if not onAugList and ctx.requestAddToRerollList then
                            ctx.requestAddToRerollList("aug", item)
                        end
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.BeginTooltip()
                        if onAugList then ImGui.Text("Already on augment reroll list.") else ImGui.Text("Add to augment reroll list (!augadd).") end
                        ImGui.EndTooltip()
                    end
                    ctx.theme.PopButtonColors()

                    -- Column: Add to Mythical List (reroll companion list; items whose name starts with Mythical)
                    ImGui.TableNextColumn()
                    local mythicalDisabled = not isMythicalEligible or onMythicalList or (ctx.uiState.pendingRerollAdd and ctx.uiState.pendingRerollAdd.list == "mythical")
                    if mythicalDisabled then
                        ctx.theme.PushKeepButton(true)
                    else
                        ctx.theme.PushKeepButton(false)
                    end
                    if ImGui.Button("Mythical List##" .. rid, ImVec2(110, 0)) then
                        if isMythicalEligible and not onMythicalList and ctx.requestAddToRerollList then
                            ctx.requestAddToRerollList("mythical", item)
                        end
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.BeginTooltip()
                        if not isMythicalEligible then ImGui.Text("Item name must start with Mythical.") elseif onMythicalList then ImGui.Text("Already on mythical reroll list.") else ImGui.Text("Add to mythical reroll list (!mythicaladd).") end
                        ImGui.EndTooltip()
                    end
                    ctx.theme.PopButtonColors()
                end

                ImGui.PopID()
                ::continue::
            end
        end
        ImGui.EndTable()
    end

    ImGui.End()
end

-- Registry: Augments module (4.2 state ownership — window in registry, search/sort in view)
registry.register({
    id          = "augments",
    label       = "Augments",
    buttonWidth = 55,
    tooltip     = "Browse all augments in your inventory with stat filtering",
    layoutKeys  = { x = "AugmentsWindowX", y = "AugmentsWindowY" },
    enableKey   = "ShowAugmentsWindow",
    render      = function(refs)
        local ctx = context.build()
        ctx = context.extend(ctx)
        AugmentsView.render(ctx)
    end,
})

return AugmentsView
