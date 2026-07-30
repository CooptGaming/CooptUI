--[[
    Item Display View - CoOpt UI Item Display window

    Tabbed window: each "CoOp UI Item Display" open adds a tab. Toolbar: Can I use?, Source,
    Locate, Refresh, Recent.
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')
local ItemCompare = require('itemui.utils.item_compare')
local constants = require('itemui.constants')
local context = require('itemui.context')
local registry = require('itemui.core.registry')
local uiState = require('itemui.state').uiState

local ItemDisplayView = {}

-- Per 4.2 state ownership: tabs, active index, recent, locate request, augment slot active
local state = {
    itemDisplayTabs = {},
    itemDisplayActiveTabIndex = 1,
    itemDisplayRecent = {},
    itemDisplayLocateRequest = nil,
    itemDisplayLocateRequestAt = nil,
    itemDisplayAugmentSlotActive = nil,
}
function ItemDisplayView.getState()
    return state
end

-- ============================================================================
-- Verdict card (design pass 3e): header, equipped-item comparison, tile grid, rules.
-- ============================================================================

--- Resolve the item's first (lowest-index) worn slot (0-22), and attach Augs filled/total onto
--- the item row for item_compare's pure "augs" tile (item_compare itself never touches a TLO —
--- see item_compare.lua's header comment). Returns nil when the item can't be worn, or is worn
--- "anywhere" (WornSlots >= 20 — too rare/ambiguous a case for one specific equipped-slot
--- comparison, so it's treated the same as "not wearable" here).
--- Multi-slot items (Ear, Wrist, Ring): comparing against the LOWEST slot index is a simple,
--- deterministic choice rather than "best of both" — keeps the verdict box to one comparison.
local function resolveCompareSlot(ctx, entry)
    local item = entry.item
    if not ctx.getItemTLO then return nil end
    local it = ctx.getItemTLO(entry.bag, entry.slot, entry.source or "inv")
    if not it then return nil end

    if ctx.getStandardAugSlotsCountFromTLO then
        local total = ctx.getStandardAugSlotsCountFromTLO(it) or 0
        item.augsTotal = total
        if total > 0 and ctx.getFilledStandardAugmentSlotIndices then
            local filled = ctx.getFilledStandardAugmentSlotIndices(entry.bag, entry.slot, entry.source or "inv")
            item.augsFilled = (filled and #filled) or 0
        else
            item.augsFilled = 0
        end
    end

    if not ctx.getWornSlotIndicesFromTLO then return nil end
    local indices = ctx.getWornSlotIndicesFromTLO(it)
    if type(indices) ~= "table" then return nil end
    local first = nil
    for idx in pairs(indices) do
        if first == nil or idx < first then first = idx end
    end
    return first
end

-- ============================================================================
-- Verdict memo (design pass 3e follow-up): renderOneItemContent runs every frame for the active
-- tab. resolveCompareSlot alone is ~15-25 TLO probes (worn-slot + aug-slot walks), and
-- ctx.getSellStatusForItem shallow-copies the whole ~85+-field item table on top of that.
-- Neither needs to run more than once per TTL window per tab identity. Mirrors the
-- tooltipStatsMemo precedent (app.lua's getItemStatsForTooltipRef) — same TTL, same "one fresh
-- read, then reuse" shape.
-- ============================================================================
local verdictMemo = {}
local VERDICT_TTL_MS = 1500

local function verdictMemoKey(entry)
    local item = entry.item
    return (entry.source or "inv") .. ":" .. tostring(entry.bag) .. ":" .. tostring(entry.slot) .. ":" .. tostring(item and item.id)
end

--- Returns { wornSlotIndex, augsTotal, augsFilled, reason, willSell, inKeep, inJunk }, refreshed
--- at most once per VERDICT_TTL_MS per (source,bag,slot,item.id). On a cache hit, re-attaches
--- augsTotal/augsFilled onto entry.item — Refresh swaps in a brand new item table, so those
--- plain fields need re-stamping every frame even though the TLO walk that produced them didn't
--- re-run. The reroll list-membership check in renderRulesBlock is deliberately NOT part of this
--- memo: rerollService.getListStatus is already an O(1) cached-set lookup, so it's called live.
local function getVerdictMemo(ctx, entry)
    local key = verdictMemoKey(entry)
    local now = mq.gettime()
    local memo = verdictMemo[key]
    if memo and (now - memo.at) < VERDICT_TTL_MS then
        if entry.item then
            entry.item.augsTotal = memo.augsTotal
            entry.item.augsFilled = memo.augsFilled
        end
        return memo
    end
    local wornSlotIndex = resolveCompareSlot(ctx, entry)
    local reason, willSell, inKeep, inJunk
    if ctx.getSellStatusForItem then
        reason, willSell, inKeep, inJunk = ctx.getSellStatusForItem(entry.item)
    end
    memo = {
        at = now,
        wornSlotIndex = wornSlotIndex,
        augsTotal = entry.item and entry.item.augsTotal,
        augsFilled = entry.item and entry.item.augsFilled,
        reason = reason, willSell = willSell, inKeep = inKeep, inJunk = inJunk,
    }
    verdictMemo[key] = memo
    return memo
end

--- Resolve "what's currently equipped in slotIndex" for the verdict box. Primary and normal
--- path: a live, TTL-memoized TLO probe (ctx.getItemStatsForTooltip with source="equipped") —
--- this does NOT depend on the Equipment Companion window ever having been opened, since the
--- underlying TLOs (Me.Inventory / InvSlot) are live MQ state, not a CoOpt cache. When the probe
--- reports "no item" AND the TLO infra (Me.Inventory) is reachable, that is trusted as a
--- genuinely empty slot — no cache fallback, so an item removed via native inventory can never
--- linger in the verdict box. Fallback: ctx.equipmentCache, which IS only populated while the
--- Equipment window is open (see app.lua's refreshEquipmentCache, gated in main_window.lua) — is
--- consulted ONLY when the TLO infra itself is unreachable (e.g. a mid-zone frame), which is the
--- one case the live probe cannot resolve to "empty" on its own.
--- Returns the equipped item table, or nil when the slot is genuinely empty (or, rarely, no data
--- is available from either path during that mid-zone window).
local function resolveEquippedForSlot(ctx, slotIndex)
    if slotIndex == nil then return nil end
    if ctx.getItemStatsForTooltip then
        local ok, fresh = pcall(ctx.getItemStatsForTooltip, { bag = 0, slot = slotIndex, source = "equipped" }, "equipped")
        if ok and fresh and fresh.id and fresh.id ~= 0 then return fresh end
        -- Live probe found no item. If Me.Inventory is reachable, the slot is genuinely
        -- empty -- do NOT fall back to the (possibly stale) cache. Only fall through to the
        -- cache when the TLO infra itself is unavailable (e.g. a mid-zone frame).
        local infraOk, infraUp = pcall(function() return (mq.TLO and mq.TLO.Me and mq.TLO.Me.Inventory) ~= nil end)
        if ok and infraOk and infraUp then return nil end
    end
    local cached = ctx.equipmentCache and ctx.equipmentCache[slotIndex + 1]
    if cached and cached.id and cached.id ~= 0 then return cached end
    return nil
end

--- One stat tile: label, value (large-ish), delta line (colored + / − / muted =).
local function renderCompareTile(ctx, row)
    local w = constants.UI.ITEM_DISPLAY_TILE_WIDTH
    local h = constants.UI.ITEM_DISPLAY_TILE_HEIGHT
    if ImGui.BeginChild("##ItemDisplayTile_" .. row.key, ImVec2(w, h), true) then
        ctx.theme.TextMuted(row.label)
        local valStr
        if type(row.value) == "number" then
            valStr = tostring(row.value) .. (row.suffix or "")
        else
            valStr = tostring(row.value)
        end
        ImGui.Text(valStr)
        if row.isRatio then
            ctx.theme.TextMuted(" ")
        elseif row.delta == nil then
            ctx.theme.TextMuted("—")
        elseif row.delta > 0 then
            ImGui.TextColored(ctx.theme.ToVec4(ctx.theme.Colors.Success), string.format("+%d%s", row.delta, row.suffix or ""))
        elseif row.delta < 0 then
            ImGui.TextColored(ctx.theme.ToVec4(ctx.theme.Colors.Error), string.format("%d%s", row.delta, row.suffix or ""))
        else
            ctx.theme.TextMuted("=")
        end
    end
    ImGui.EndChild()
end

--- 3x2 (wraps to 6x1 on wide windows) tile grid, one tile per item_compare row.
local function renderCompareTileGrid(ctx, rows)
    if not rows or #rows == 0 then return end
    local tileW = constants.UI.ITEM_DISPLAY_TILE_WIDTH
    local spacing = constants.UI.ITEM_DISPLAY_TILE_SPACING
    local availX = constants.UI.ITEM_DISPLAY_AVAIL_X
    do
        local ax, ay = ImGui.GetContentRegionAvail()
        if type(ax) == "number" and ax > 0 then availX = ax end
        if type(ax) == "table" and ax.x then availX = ax.x end
    end
    local perRow = math.max(1, math.floor((availX + spacing) / (tileW + spacing)))
    for i, row in ipairs(rows) do
        if (i - 1) % perRow ~= 0 then ImGui.SameLine(0, spacing) end
        renderCompareTile(ctx, row)
    end
end

-- Verdict -> theme color key + headline verb. "none" covers both "not wearable" (box isn't
-- shown at all — see renderVerdictBox) and "wearable but no comparison data".
local VERDICT_COLOR_KEY = { upgrade = "Success", downgrade = "Error", sidegrade = "Muted", none = "Muted" }

--- Bordered verdict box: "Upgrade over <equipped name>" / delta summary, or an honest
--- "nothing to compare" note when there's no worn slot or no equipped-item data. isSelfView
--- means the tab IS the item currently worn in that slot (identity match, not id match — see
--- renderOneItemContent) — that gets its own truthful text instead of the generic "nothing
--- equipped" message, which would otherwise lie (something IS equipped: this exact item).
local function renderVerdictBox(ctx, cmp, equippedItem, hasWornSlot, isSelfView)
    if not hasWornSlot then return end
    local color = ctx.theme.ToVec4(ctx.theme.Colors[VERDICT_COLOR_KEY[cmp.verdict] or "Muted"])
    ImGui.PushStyleColor(ImGuiCol.Border, color)
    ImGui.PushStyleVar(ImGuiStyleVar.ChildBorderSize, 2)
    if ImGui.BeginChild("##ItemDisplayVerdict", ImVec2(0, constants.UI.ITEM_DISPLAY_VERDICT_HEIGHT), true) then
        if cmp.verdict == "none" and isSelfView then
            ctx.theme.TextMuted("No comparison needed")
            ImGui.TextWrapped("This is your equipped item — open a bag copy or another candidate to compare.")
        elseif cmp.verdict == "none" then
            ctx.theme.TextMuted("No comparison available")
            ImGui.TextWrapped("Nothing is equipped there right now, or the comparison data isn't fresh — equip something, or open Equipment once, to compare.")
        else
            local eqName = (equippedItem and equippedItem.name and equippedItem.name ~= "") and equippedItem.name or "your current item"
            local headline
            if cmp.verdict == "upgrade" then headline = "Upgrade over " .. eqName
            elseif cmp.verdict == "downgrade" then headline = "Downgrade from " .. eqName
            else headline = "Sidegrade — similar to " .. eqName end
            ImGui.TextColored(color, headline)
            ctx.theme.TextMuted(cmp.summary ~= "" and cmp.summary or "No stat difference.")
        end
    end
    ImGui.EndChild()
    ImGui.PopStyleVar()
    ImGui.PopStyleColor()
end

--- Header: icon + name (theme-colored by usability), subtitle (type · location · value), and
--- the can-use banner (folded in from the old standalone banner; themed instead of hardcoded).
local function renderHeader(ctx, entry)
    local item = entry.item
    local source = entry.source or "inv"
    local canUseInfo = ItemTooltip.getCanUseInfo(item, source)

    if ctx.drawItemIcon and item.icon and item.icon > 0 then
        ctx.drawItemIcon(item.icon, 32)
        ImGui.SameLine()
    end
    local nameColorKey = canUseInfo.canUse and "Success" or "Error"
    ImGui.PushStyleColor(ImGuiCol.Text, ctx.theme.ToVec4(ctx.theme.Colors[nameColorKey]))
    ImGui.TextWrapped(item.name or "—")
    ImGui.PopStyleColor()

    local subtitle = {}
    if item.type and item.type ~= "" then subtitle[#subtitle + 1] = item.type end
    subtitle[#subtitle + 1] = string.format("Bag %s, Slot %s", tostring(entry.bag), tostring(entry.slot))
    local val = item.totalValue or item.value
    if val and val ~= 0 then
        subtitle[#subtitle + 1] = (ItemUtils and ItemUtils.formatValue) and ItemUtils.formatValue(val) or tostring(val)
    end
    if #subtitle > 0 then ctx.theme.TextMuted(table.concat(subtitle, "  ·  ")) end

    if canUseInfo.canUse then
        ctx.theme.TextSuccess("You can use this item.")
    else
        ctx.theme.TextError("You cannot use: " .. (canUseInfo.reason or "restriction"))
    end
end

--- Rules block: sell status line (all sources) + action buttons gated per-action rather than by
--- a single source check. Keep/Junk are name-keyed INI edits needing no bag/slot, so they render
--- for every sellListSource (inv/sell/bank/augments/reroll — mirrors ui_common.lua's context-menu
--- gate). Add to Reroll / Aug Utility need a live pickup or getItemTLO path, so they render only
--- for packBacked sources (inv/sell/augments) or bank (explicit bank branch in both the pickup
--- and getItemTLO paths); "reroll"-sourced tabs are excluded from both — the item is already on
--- a list, and its bag/slot may be bank coordinates that getItemTLO's pack-fallback branch would
--- misresolve. reason/willSell/inKeep/inJunk come from the caller's per-tab memo (see
--- getVerdictMemo) instead of a fresh ctx.getSellStatusForItem call every frame; reroll list
--- membership is looked up live since rerollService.getListStatus is already O(1).
local function renderRulesBlock(ctx, entry, memo)
    local item = entry.item
    local source = entry.source or "inv"
    if not ctx.getSellStatusForItem then return end

    ImGui.Spacing()
    ctx.theme.SectionBreak()
    ctx.theme.TextHeader("Rules")

    local reason, willSell, inKeep, inJunk = memo.reason, memo.willSell, memo.inKeep, memo.inJunk
    local label = willSell and "Sells because: " or "Stays because: "
    if ctx.formatSellStatus then
        local statusText, statusColor = ctx.formatSellStatus(reason, willSell, ctx.theme)
        ImGui.TextColored(statusColor, label .. statusText)
    else
        ImGui.Text(label .. tostring(reason))
    end

    local packBacked = (source == "inv" or source == "sell" or source == "augments")
    local sellListSource = packBacked or source == "bank" or source == "reroll"  -- mirror ui_common.lua:339
    if not sellListSource then return end  -- equipped/corpse tabs: status line only, as today

    ImGui.Spacing()
    if item.name and item.name ~= "" and ctx.applySellListChange then
        ctx.theme.PushKeepButton(not inKeep)
        if ImGui.Button("Keep##ItemDisplayRules") then
            if inKeep then ctx.applySellListChange(item.name, false, inJunk)
            else ctx.applySellListChange(item.name, true, false) end
            verdictMemo[verdictMemoKey(entry)] = nil  -- Rules line reflects the change next frame
        end
        ctx.theme.PopButtonColors()
        ImGui.SameLine()
        ctx.theme.PushJunkButton(not inJunk)
        if ImGui.Button("Junk##ItemDisplayRules") then
            if inJunk then ctx.applySellListChange(item.name, inKeep, false)
            else ctx.applySellListChange(item.name, false, true) end
            verdictMemo[verdictMemoKey(entry)] = nil
        end
        ctx.theme.PopButtonColors()
    end

    if (packBacked or source == "bank") and ctx.resolveRerollList and ctx.requestAddToRerollList then
        local resolvedList = ctx.resolveRerollList(item.name, item.type)
        if resolvedList then
            ImGui.SameLine()
            local itemId = item.id or item.ID
            -- listStatus covers both the confirmed server list and the pending-sync list, so an
            -- out-of-guild-hall click ("Already on pending list") also renders as a disabled
            -- button with truthful feedback instead of a silent no-op.
            local listStatus = (itemId and ctx.rerollService and ctx.rerollService.getListStatus)
                and ctx.rerollService.getListStatus(resolvedList, itemId) or nil
            local rerollDisabled = (listStatus ~= nil)
                or (ctx.uiState.pendingRerollAdd ~= nil and ctx.uiState.pendingRerollAdd.list == resolvedList)
            ctx.theme.PushKeepButton(rerollDisabled)
            if ImGui.Button("Add to Reroll##ItemDisplayRules") then
                -- Re-check at click time (matches augments.lua's pattern) so a same-frame
                -- double-click can't queue a duplicate server add.
                if not rerollDisabled then
                    local payload = (source == "bank")
                        and { bag = entry.bag, slot = entry.slot, id = itemId, name = item.name, source = "bank" }
                        or item
                    ctx.requestAddToRerollList(resolvedList, payload)
                end
            end
            if listStatus and ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text(listStatus == "listed"
                    and ((resolvedList == "mythical") and "Already on mythical reroll list." or "Already on augment reroll list.")
                    or "Already on pending list (syncs in guild hall).")
                ImGui.EndTooltip()
            end
            ctx.theme.PopButtonColors()
        end
    end

    if packBacked or source == "bank" then
        ImGui.SameLine()
        if ImGui.Button("Aug Utility##ItemDisplayRules") then
            -- Augment Utility's own target resolution reads the active Item Display tab (this
            -- window) — see augment_utility.lua — so opening it here is enough, no bag/slot needed.
            ctx.uiState.augmentUtilitySlotIndex = 1
            registry.setWindowState("augmentUtility", true, true)
        end
    end
end

--- Draw the full verdict card + full detail for one tab entry. entry = { bag, slot, source, item, label }
local function renderOneItemContent(ctx, entry)
    if not entry or not entry.item then return end
    local item = entry.item
    local source = entry.source or "inv"

    -- Prewarm lazy stat/worn/aug fields before item_compare and the slot/aug resolution below
    -- touch them (buildItemFromMQ batch-loads all STAT_FIELDS off the first access to any one).
    local _ = item.ac
    _ = item.wornSlots
    _ = item.augSlots

    renderHeader(ctx, entry)
    ImGui.Spacing()

    local memo = getVerdictMemo(ctx, entry)
    local wornSlotIndex = memo.wornSlotIndex
    local equippedItem = resolveEquippedForSlot(ctx, wornSlotIndex)
    -- Self-view: an equipped-source tab whose worn slot resolves back to itself. Match on
    -- identity (source+slot), NOT item.id -- EQ ids are template ids, so a bag copy of an item
    -- you already wear would false-positive on an id compare and lose its legitimate
    -- "identical" comparison (which item_compare already renders honestly as a sidegrade with
    -- "No stat difference."). Cross-slot equipped views (e.g. a Ring2 item vs the Ring1
    -- occupant) are NOT a self-view and still compare normally.
    local isSelfView = (source == "equipped" and entry.slot == wornSlotIndex)
    if isSelfView then equippedItem = nil end
    local cmp = ItemCompare.compare(item, equippedItem)
    renderVerdictBox(ctx, cmp, equippedItem, wornSlotIndex ~= nil, isSelfView)
    if wornSlotIndex ~= nil then ImGui.Spacing() end

    renderCompareTileGrid(ctx, cmp.rows)
    if cmp.rows and #cmp.rows > 0 then ImGui.Spacing() end

    ImGui.Separator()
    ImGui.Spacing()
    if ImGui.CollapsingHeader("All stats & effects##ItemDisplayFull", ImGuiTreeNodeFlags.DefaultOpen) then
        local opts = {
            source = source,
            bag = entry.bag,
            slot = entry.slot,
            isItemDisplayWindow = true,
            entry = entry,
        }
        local effects, _w, _h = ItemTooltip.prepareTooltipContent(item, ctx, opts)
        opts.effects = effects
        opts.tooltipColWidth = nil
        local ok, err = pcall(function()
            ItemTooltip.renderItemDisplayContent(item, ctx, opts)
        end)
        if not ok then
            ctx.theme.TextError("Error drawing item stats.")
            local diagnostics = require('itemui.core.diagnostics')
            diagnostics.recordError("Item Display", "Error drawing item stats", err)
        end
    end

    renderRulesBlock(ctx, entry, memo)
end

local function sourceLabel(source)
    if source == "bank" then return "Bank" end
    if source == "inv" then return "Inventory" end
    return tostring(source)
end

-- Module interface: render main Item Display window (tabbed)
function ItemDisplayView.render(ctx)
    if not registry.shouldDraw("itemDisplay") then return end

    local layoutConfig = ctx.layoutConfig
    local tabs = state.itemDisplayTabs
    local activeIdx = state.itemDisplayActiveTabIndex
    if activeIdx < 1 or activeIdx > #tabs then
        state.itemDisplayActiveTabIndex = #tabs > 0 and 1 or 0
        activeIdx = state.itemDisplayActiveTabIndex
    end

    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    local condPos = forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver
    local px = layoutConfig.ItemDisplayWindowX or 0
    local py = layoutConfig.ItemDisplayWindowY or 0
    if px and py and (px ~= 0 or py ~= 0) then
        ImGui.SetNextWindowPos(ImVec2(px, py), condPos)
    end

    local w = layoutConfig.WidthItemDisplayPanel or constants.VIEWS.WidthItemDisplayPanel
    local h = layoutConfig.HeightItemDisplay or constants.VIEWS.HeightItemDisplay
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), condPos)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Item Display##ItemUIItemDisplay", registry.isOpen("itemDisplay"), windowFlags)
    registry.setWindowState("itemDisplay", winOpen, winOpen)

    if not winOpen then
        state.itemDisplayTabs = {}
        state.itemDisplayActiveTabIndex = 1
        ImGui.End()
        return
    end
    -- Escape closes this window via main Inventory Companion's LIFO handler only
    if not winVis then ImGui.End(); return end
    if ctx.renderWindowLock then ctx.renderWindowLock(ctx, "itemDisplay") end

    if not ctx.uiState.uiLocked then
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            layoutConfig.WidthItemDisplayPanel = cw
            layoutConfig.HeightItemDisplay = ch
        end
    end
    local cx, cy = ImGui.GetWindowPos()
    if cx and cy then
        if not layoutConfig.ItemDisplayWindowX or math.abs(layoutConfig.ItemDisplayWindowX - cx) > 1 or
           not layoutConfig.ItemDisplayWindowY or math.abs(layoutConfig.ItemDisplayWindowY - cy) > 1 then
            layoutConfig.ItemDisplayWindowX = cx
            layoutConfig.ItemDisplayWindowY = cy
            if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
        end
    end

    -- Custom tab row: button (click to select tab) + X button (click to close); wrap to next line when width exceeded
    if #tabs > 0 then
        local closeSet = {}
        local closeIndices = {}
        local style = ImGui.GetStyle()
        local framePadX = (style and style.FramePadding and style.FramePadding.x) or 4
        local availX = constants.UI.ITEM_DISPLAY_AVAIL_X
        do
            local ax, ay = ImGui.GetContentRegionAvail()
            if type(ax) == "number" and ax > 0 then availX = ax end
            if type(ax) == "table" and ax.x then availX = ax.x end
        end
        local X_BUTTON_W = 20
        local lineWidth = 0
        for i, tab in ipairs(tabs) do
            local tabLabel = tab.label or ("Item " .. tostring(i))
            local isSelected = (activeIdx == i)
            local tw = constants.UI.ITEM_DISPLAY_TAB_LABEL_WIDTH
            do
                local cw, ch = ImGui.CalcTextSize(tabLabel)
                if type(cw) == "number" then tw = cw
                elseif type(cw) == "table" and cw.x then tw = cw.x
                end
            end
            local btnW = tw + framePadX * 2
            if btnW < 80 then btnW = 80 end
            local tabTotalW = btnW + 2 + X_BUTTON_W + (i < #tabs and 6 or 0)
            if i > 1 and (lineWidth + tabTotalW > availX) then
                ImGui.NewLine()
                lineWidth = 0
            elseif i > 1 then
                ImGui.SameLine(0, 6)
            end
            if isSelected then
                ImGui.PushStyleColor(ImGuiCol.Button, ImGui.GetStyleColorVec4(ImGuiCol.HeaderActive))
                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImGui.GetStyleColorVec4(ImGuiCol.Header))
                ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImGui.GetStyleColorVec4(ImGuiCol.Header))
            end
            if ImGui.Button(tabLabel .. "##ItemDisplayTab" .. tostring(i), ImVec2(btnW, 0)) then
                state.itemDisplayActiveTabIndex = i
            end
            if isSelected then
                ImGui.PopStyleColor(3)
            end
            if ImGui.IsItemHovered() and ImGui.IsItemClicked(ImGuiMouseButton.Middle) then
                if not closeSet[i] then closeSet[i] = true; closeIndices[#closeIndices + 1] = i end
            end
            ImGui.SameLine(0, 2)
            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.5, 0.2, 0.2, 0.6))
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(0.7, 0.25, 0.25, 0.9))
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImVec4(0.8, 0.3, 0.3, 1.0))
            if ImGui.SmallButton("X##CloseTab" .. tostring(i)) then
                if not closeSet[i] then closeSet[i] = true; closeIndices[#closeIndices + 1] = i end
            end
            ImGui.PopStyleColor(3)
            lineWidth = lineWidth + btnW + 2 + X_BUTTON_W + (i < #tabs and 6 or 0)
        end
        ImGui.NewLine()
        -- Remove closed tabs (from high index down so indices stay valid)
        local t = state.itemDisplayTabs
        local curActive = state.itemDisplayActiveTabIndex
        table.sort(closeIndices, function(a, b) return a > b end)
        for _, idx in ipairs(closeIndices) do
            if idx >= 1 and idx <= #t then
                table.remove(t, idx)
                if curActive > idx then
                    curActive = curActive - 1
                elseif curActive == idx then
                    curActive = math.max(1, math.min(idx, #t))
                end
            end
        end
        state.itemDisplayActiveTabIndex = curActive
        if #state.itemDisplayTabs > 0 and (state.itemDisplayActiveTabIndex < 1 or state.itemDisplayActiveTabIndex > #state.itemDisplayTabs) then
            state.itemDisplayActiveTabIndex = 1
        end
        if #state.itemDisplayTabs == 0 then
            registry.setWindowState("itemDisplay", false, false)
        end
        -- Use current selection for content (updated by tab click or close)
        activeIdx = state.itemDisplayActiveTabIndex
        if activeIdx < 1 or activeIdx > #state.itemDisplayTabs then
            activeIdx = math.max(1, #state.itemDisplayTabs)
        end
    end

    -- Toolbar and content
    if #tabs == 0 then
        if ImGui.BeginChild("##ItemDisplayScroll", ImVec2(0, 0), true) then
            ImGui.TextColored(ImVec4(0.7, 0.7, 0.7, 1.0), "No item selected. Right-click an item and choose \"CoOp UI Item Display\" to open.")
        end
        ImGui.EndChild()
    else
        local tab = tabs[activeIdx]
        if tab then
            -- Toolbar: row 1 = Locate, Refresh, Recent; row 2 = Source
            ImGui.Spacing()
            if ImGui.SmallButton("Locate##ItemDisplay") then
                state.itemDisplayLocateRequest = { source = tab.source, bag = tab.bag, slot = tab.slot }
                state.itemDisplayLocateRequestAt = mq.gettime()
            end
            ImGui.SameLine()
            if ImGui.SmallButton("Refresh##ItemDisplay") then
                if ctx.getItemStatsForTooltip then
                    local fresh = ctx.getItemStatsForTooltip({ bag = tab.bag, slot = tab.slot }, tab.source)
                    if fresh and fresh.id and fresh.id ~= 0 then
                        tab.item = fresh
                        verdictMemo = {}  -- Refresh should not show stale verdict/rules data
                    end
                end
            end
            ImGui.SameLine()
            local recent = state.itemDisplayRecent
            if #recent > 0 then
                local currentLabel = tab.label or ""
                local comboW = 280
                do
                    local cw, ch = ImGui.CalcTextSize(("W"):rep(35))
                    if type(cw) == "number" then comboW = cw end
                    if type(cw) == "table" and cw and cw.x then comboW = cw.x end
                    comboW = comboW + 24
                end
                ImGui.SetNextItemWidth(comboW)
                if ImGui.BeginCombo("Recent##ItemDisplay", currentLabel, ImGuiComboFlags.None) then
                    for _, r in ipairs(recent) do
                        local sel = (r.bag == tab.bag and r.slot == tab.slot and r.source == tab.source)
                        if ImGui.Selectable((r.label or "?") .. "##Recent" .. tostring(r.bag) .. "_" .. tostring(r.slot), sel) then
                            -- Find or add tab for this recent entry
                            local found
                            for i, t in ipairs(tabs) do
                                if t.bag == r.bag and t.slot == r.slot and t.source == r.source then
                                    state.itemDisplayActiveTabIndex = i
                                    found = true
                                    break
                                end
                            end
                            if not found and ctx.getItemStatsForTooltip then
                                local showItem = ctx.getItemStatsForTooltip({ bag = r.bag, slot = r.slot }, r.source)
                                if showItem and showItem.id and showItem.id ~= 0 then
                                    local label = (showItem.name and showItem.name ~= "" and showItem.name:sub(1, 35)) or "Item"
                                    if #label == 35 and (showItem.name or ""):len() > 35 then label = label .. "…" end
                                    tabs[#tabs + 1] = { bag = r.bag, slot = r.slot, source = r.source, item = showItem, label = label }
                                    state.itemDisplayActiveTabIndex = #tabs
                                end
                            end
                        end
                    end
                    ImGui.EndCombo()
                end
            end
            ImGui.TextColored(ImVec4(0.6, 0.6, 0.65, 1.0), "Source: " .. sourceLabel(tab.source) .. " | Bag " .. tostring(tab.bag) .. ", Slot " .. tostring(tab.slot))
            ImGui.Spacing()
            if ImGui.BeginChild("##ItemDisplayScroll", ImVec2(0, 0), true) then
                renderOneItemContent(ctx, tab)
            end
            ImGui.EndChild()
        end
    end

    ImGui.End()
end

-- Registry: Item Display module (4.2 state ownership — window in registry, tabs/recent/locate in view)
registry.register({
    id          = "itemDisplay",
    zone        = "R1",  -- window_zones placement column/slot (mockup 10a)
    label       = "Item Display",
    buttonWidth = 90,
    tooltip     = "Inspect item stats and augments",
    layoutKeys  = { x = "ItemDisplayWindowX", y = "ItemDisplayWindowY" },
    enableKey   = "ShowItemDisplayWindow",
    onClose     = function()
        state.itemDisplayTabs = {}
        state.itemDisplayActiveTabIndex = 1
        uiState.removeAllQueue = nil
        uiState.optimizeQueue = nil
        verdictMemo = {}  -- bound growth across the window's lifetime, not just per-tab TTL
    end,
    render      = function(refs)
        local ctx = context.build()
        ItemDisplayView.render(ctx)
    end,
})

return ItemDisplayView
