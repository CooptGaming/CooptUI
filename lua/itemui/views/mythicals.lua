--[[
    Mythicals View - Pop-out window (mirror of the Augments Companion)

    Shows every "Mythical"-prefixed item in inventory in the same compact table
    so it's quick to decide what goes on the mythical reroll list.
    Columns: Icon (hover = full stats) | Name | Effects | Value | Reroll
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')
local context = require('itemui.context')
local registry = require('itemui.core.registry')
local constants = require('itemui.constants')

local MythicalsView = {}

local state = {
    searchFilterMythicals = "",
    mythicalsSortColumn = nil,
    mythicalsSortDirection = nil,
}
function MythicalsView.getState()
    return state
end

local MYTHICAL_PREFIX = (constants.REROLL and constants.REROLL.MYTHICAL_NAME_PREFIX) or "Mythical"
local MYTHICALS_WINDOW_WIDTH = 560
local MYTHICALS_WINDOW_HEIGHT = 500

-- Keyed caches (same pattern as augments.lua): list + filter + sort rebuilt only
-- when inputs change. Inventory signature = count + first-item identity.
local mythCache = { key = nil, list = {} }
local filterCache = { key = nil, list = {} }
local sortCache = { key = nil, list = {} }

local function isMythical(name)
    return name and name:sub(1, #MYTHICAL_PREFIX) == MYTHICAL_PREFIX
end

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

function MythicalsView.render(ctx)
    if not registry.shouldDraw("mythicals") then return end

    local layoutConfig = ctx.layoutConfig

    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    local condPos = forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver
    local ax = layoutConfig.MythicalsWindowX or 0
    local ay = layoutConfig.MythicalsWindowY or 0
    if ax and ay and ax ~= 0 and ay ~= 0 then
        ImGui.SetNextWindowPos(ImVec2(ax, ay), condPos)
    end

    local w = layoutConfig.WidthMythicalsPanel or MYTHICALS_WINDOW_WIDTH
    local h = layoutConfig.HeightMythicals or MYTHICALS_WINDOW_HEIGHT
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), condPos)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Mythicals Companion##ItemUIMythicals", registry.isOpen("mythicals"), windowFlags)
    registry.setWindowState("mythicals", winOpen, winOpen)

    if not winOpen then ImGui.End(); return end
    if not winVis then ImGui.End(); return end

    if not ctx.uiState.uiLocked then
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            layoutConfig.WidthMythicalsPanel = cw
            layoutConfig.HeightMythicals = ch
        end
    end
    local cx, cy = ImGui.GetWindowPos()
    if cx and cy then
        if not layoutConfig.MythicalsWindowX or math.abs(layoutConfig.MythicalsWindowX - cx) > 1 or
           not layoutConfig.MythicalsWindowY or math.abs(layoutConfig.MythicalsWindowY - cy) > 1 then
            layoutConfig.MythicalsWindowX = cx
            layoutConfig.MythicalsWindowY = cy
            ctx.scheduleLayoutSave()
            ctx.flushLayoutSave()
        end
    end

    -- Filter to Mythical-prefixed items (any type), cached until inventory rescans
    local invItems = ctx.inventoryItems or {}
    local mythKey = string.format("%d|%s", #invItems, tostring(invItems[1]))
    if mythCache.key ~= mythKey then
        local rebuilt = {}
        for _, it in ipairs(invItems) do
            if isMythical(it.name) then
                table.insert(rebuilt, it)
            end
        end
        mythCache.key = mythKey
        mythCache.list = rebuilt
    end
    local mythicals = mythCache.list

    ctx.theme.TextHeader("Mythicals")
    ImGui.SameLine()
    ctx.theme.TextInfo(string.format("(%d in inventory)", #mythicals))
    ImGui.SameLine()
    ctx.renderRefreshButton(ctx, "Refresh##Mythicals", "Rescan inventory", function() ctx.scanInventory() end, { messageBefore = "Scanning...", messageAfter = "Refreshed" })
    ImGui.SameLine()
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(160)
    state.searchFilterMythicals, _ = ImGui.InputText("##MythicalsSearch", state.searchFilterMythicals or "")
    ImGui.SameLine()
    if ImGui.Button("X##MythicalsSearchClear", ImVec2(22, 0)) then state.searchFilterMythicals = "" end
    ImGui.Separator()

    local searchLower = (state.searchFilterMythicals or ""):lower()
    local filterKey = searchLower .. "|" .. mythKey
    if filterCache.key ~= filterKey then
        local rebuilt = {}
        for _, it in ipairs(mythicals) do
            if searchLower == "" or (it.name or ""):lower():find(searchLower, 1, true) then
                table.insert(rebuilt, it)
            end
        end
        filterCache.key = filterKey
        filterCache.list = rebuilt
    end
    local filtered = filterCache.list

    if #filtered == 0 then
        if #mythicals == 0 then
            ctx.theme.TextMuted("No Mythical items in inventory. Loot some and refresh.")
        else
            ctx.theme.TextMuted("No Mythical items match your search.")
        end
        ImGui.End()
        return
    end

    local showRerollColumns = registry.isEnabled("reroll")
    local nCols = showRerollColumns and 5 or 4
    local tableFlagsMyth = bit32.bor(ctx.uiState.tableFlags or 0, ImGuiTableFlags.Sortable)
    if ImGui.BeginTable("ItemUI_Mythicals", nCols, tableFlagsMyth) then
        if showRerollColumns then
            ImGui.TableSetupColumn("Reroll", ImGuiTableColumnFlags.WidthFixed, 100, 4)
        end
        ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 28, 0)   -- Icon (not sortable)
        ImGui.TableSetupColumn("Name", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable, ImGuiTableColumnFlags.DefaultSort), 0, 1)
        ImGui.TableSetupColumn("Effects", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable), 0, 2)
        ImGui.TableSetupColumn("Value", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), 60, 3)
        ImGui.TableSetupScrollFreeze(1, 1)
        ImGui.TableHeadersRow()

        local sortSpecs = ImGui.TableGetSortSpecs()
        if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
            local spec = sortSpecs:Specs(1)
            if spec then
                -- Normalize to logical columns (1=Name 2=Effects 3=Value): with the
                -- Reroll column leading, every ColumnIndex is shifted right by one.
                local idx = spec.ColumnIndex
                state.mythicalsSortColumn = showRerollColumns and (idx - 1) or idx
                state.mythicalsSortDirection = spec.SortDirection
            end
            sortSpecs.SpecsDirty = false
        end
        local sortCol = (state.mythicalsSortColumn ~= nil) and state.mythicalsSortColumn or 1
        local sortDir = state.mythicalsSortDirection or ImGuiSortDirection.Ascending
        local asc = (sortDir == ImGuiSortDirection.Ascending)
        local rows = filtered
        if sortCol >= 1 and sortCol <= 3 then
            local sortKey = string.format("%d|%s|%s", sortCol, tostring(sortDir), filterKey)
            if sortCache.key ~= sortKey then
                local sorted = {}
                for i = 1, #filtered do sorted[i] = filtered[i] end
                if sortCol == 2 then
                    for _, it in ipairs(sorted) do
                        it._sortEffects = it._sortEffects or getEffectsLine(ctx, it):lower()
                    end
                end
                table.sort(sorted, function(a, b)
                    local av, bv
                    if sortCol == 1 then
                        av, bv = (a.name or ""):lower(), (b.name or ""):lower()
                        if asc then return av < bv else return av > bv end
                    elseif sortCol == 2 then
                        av, bv = a._sortEffects or "", b._sortEffects or ""
                        if asc then return av < bv else return av > bv end
                    else
                        av = tonumber(a.totalValue) or 0
                        bv = tonumber(b.totalValue) or 0
                        if asc then return av < bv else return av > bv end
                    end
                end)
                sortCache.key = sortKey
                sortCache.list = sorted
            end
            rows = sortCache.list
        end

        local hasCursor = ctx.hasItemOnCursor()

        -- Reroll-list lookups built once per frame (ID-only matching, same policy
        -- as augments.lua).
        local rerollService = ctx.rerollService
        local mythListById = {}
        if showRerollColumns and rerollService then
            local mythicalList = rerollService.getMythicalList and rerollService.getMythicalList() or {}
            for _, e in ipairs(mythicalList) do
                if e.id then mythListById[e.id] = true end
            end
        end

        local clipper = ImGuiListClipper.new()
        clipper:Begin(#rows)
        while clipper:Step() do
            for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                local item = rows[i]
                if not item then goto continue end
                ImGui.TableNextRow()
                local rid = "myth_" .. item.bag .. "_" .. item.slot
                ImGui.PushID(rid)

                local itemId = item.id or item.ID
                local onMythicalList = (itemId and mythListById[itemId]) or false

                if showRerollColumns then
                    -- Column: Reroll (leftmost, like the Augments layout in use)
                    ImGui.TableNextColumn()
                    local rerollDisabled = onMythicalList or (ctx.uiState.pendingRerollAdd and ctx.uiState.pendingRerollAdd.list == "mythical")
                    ctx.theme.PushKeepButton(rerollDisabled and true or false)
                    if ImGui.Button("Reroll##" .. rid, ImVec2(90, 0)) then
                        if not rerollDisabled and ctx.requestAddToRerollList then
                            ctx.requestAddToRerollList("mythical", item)
                        end
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.BeginTooltip()
                        if onMythicalList then
                            ImGui.Text("Already on mythical reroll list.")
                        else
                            ImGui.Text("Add to mythical reroll list (!mythicaladd).")
                        end
                        ImGui.EndTooltip()
                    end
                    ctx.theme.PopButtonColors()
                end

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
                    local effects, tw, th = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
                    opts.effects = effects
                    ItemTooltip.beginItemTooltip(tw, th)
                    ImGui.Text("Stats")
                    ImGui.Separator()
                    ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
                    ImGui.EndTooltip()
                end
                if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                    ImGui.OpenPopup("ItemContextMythIcon_" .. rid)
                end
                ctx.renderItemContextMenu(ctx, item, { source = "augments", popupId = "ItemContextMythIcon_" .. rid, bankOpen = (ctx.isBankWindowOpen and ctx.isBankWindowOpen()) or false, hasCursor = hasCursor })

                -- Column: Name (tinted red when your character can't use the item)
                ImGui.TableNextColumn()
                local dn = item.name or ""
                if (item.stackSize or 1) > 1 then dn = dn .. string.format(" (x%d)", item.stackSize) end
                local useInfo = ItemTooltip.getCanUseInfoCached and ItemTooltip.getCanUseInfoCached(item, "inv") or nil
                local unusable = (useInfo and useInfo.canUse == false) or false
                if unusable then ImGui.PushStyleColor(ImGuiCol.Text, 0.95, 0.45, 0.45, 1.0) end
                ImGui.Selectable(dn, false, ImGuiSelectableFlags.None, ImVec2(0, 0))
                if unusable then ImGui.PopStyleColor() end
                if unusable and ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.Text(useInfo.reason or "Cannot use this item")
                    ImGui.EndTooltip()
                end
                if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) and not hasCursor then
                    ctx.pickupFromSlot(item.bag, item.slot, "inv")
                end
                if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                    ImGui.OpenPopup("ItemContextMythIcon_" .. rid)
                end

                -- Column: Effects
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

                ImGui.PopID()
                ::continue::
            end
        end
        ImGui.EndTable()
    end

    ImGui.End()
end

registry.register({
    id          = "mythicals",
    label       = "Mythics",
    buttonWidth = 52,
    tooltip     = "Browse all Mythical items in your inventory and add them to the reroll list",
    layoutKeys  = { x = "MythicalsWindowX", y = "MythicalsWindowY" },
    enableKey   = "ShowMythicalsWindow",
    render      = function(refs)
        local ctx = context.build()
        MythicalsView.render(ctx)
    end,
})

return MythicalsView
