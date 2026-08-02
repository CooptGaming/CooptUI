--[[
    Augment Utility View - Standalone window for insert/remove augments.
    Target item from current CoOpt Item Display tab; slot selector; compatible list (table + search + tooltips) + Insert; Remove per slot.
    Uses CoOpt UI theme and patterns (Augments view, Item Display).
--]]

require('ImGui')
local ItemTooltip = require('itemui.utils.item_tooltip')
local augmentRanking = require('itemui.utils.augment_ranking')

local constants = require('itemui.constants')
local context = require('itemui.context')
local registry = require('itemui.core.registry')
local ItemDisplayView = require('itemui.views.item_display')
local AugmentsView = require('itemui.views.augments')
local windowHeader = require('itemui.components.window_header')
local TooltipData = require('itemui.utils.tooltip_data')

local AugmentUtilityView = {}

local renderForSlotContent  -- declared ahead: render()'s tab bar calls it before its definition

-- Per 4.2 state ownership: slot, search filter, only-show-usable
local state = {
    augmentUtilitySlotIndex = 1,
    searchFilterAugmentUtility = "",
    augmentUtilityOnlyShowUsable = true,
    -- 23b subject link: nil = follow Item Display's active tab live (the link); a table
    -- (a captured tab entry) = the pin — the subject freezes until unpinned.
    pinnedTarget = nil,
}

-- FontAwesome glyph (merged into the default font): thumbtack f08d. The link glyph moved
-- to windowHeader.GLYPHS.LINK (item 10) - one marker, one meaning, one definition.
local GLYPH_PIN  = "\xEF\x82\x8D"

--- The live subject: Item Display's active tab (the one selection bus this pair needs —
--- Aug Utility answers a different question about the same item, spec §8's "link" kind).
local function currentLiveTarget()
    local ids = ItemDisplayView.getState()
    local tabs = ids.itemDisplayTabs or {}
    local activeIdx = ids.itemDisplayActiveTabIndex or 1
    if activeIdx < 1 or activeIdx > #tabs then activeIdx = #tabs > 0 and 1 or 0 end
    return (activeIdx >= 1 and activeIdx <= #tabs) and tabs[activeIdx] or nil
end

--- Pinned beats live; both may be nil (no subject).
local function resolveTarget()
    return state.pinnedTarget or currentLiveTarget()
end

-- Cache for optimize plan: recompute only when item/slot/bank state changes
local optimizeCache = {
    itemId = nil,
    bag = nil,
    slot = nil,
    source = nil,
    slotCount = nil,
    bankOpen = nil,
    usable = nil,
    steps = nil,
    canOptimize = false,
}
-- True while the optimize queue is draining; used to detect completion and invalidate caches.
local optimizeWasRunning = false
-- Cache for the compatible-candidate list + scores (mirrors optimizeCache's key pattern):
-- the full scan + per-candidate scoring runs only when the key changes, not every frame.
local candidateCache = {
    key = nil,        -- itemId|bag|slot|source|slotIdx|bankOpen|usable|search|inv/bank signature
    candCount = 0,    -- pre-search candidate count (header + empty-state messages)
    list = nil,       -- search-filtered, scored, rank-ordered candidates
    sortKey = nil,    -- column-sort cache key
    sorted = nil,     -- column-sorted copy for table display
}
function AugmentUtilityView.getState()
    return state
end

function AugmentUtilityView.render(ctx)
    if not registry.shouldDraw("augmentUtility") then return end

    local layoutConfig = ctx.layoutConfig

    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    local condPos = forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver
    local px = layoutConfig.AugmentUtilityWindowX or 0
    local py = layoutConfig.AugmentUtilityWindowY or 0
    if px and py and (px ~= 0 or py ~= 0) then
        ImGui.SetNextWindowPos(ImVec2(px, py), condPos)
    end

    local w = layoutConfig.WidthAugmentUtilityPanel or constants.VIEWS.WidthAugmentUtilityPanel
    local h = layoutConfig.HeightAugmentUtility or constants.VIEWS.HeightAugmentUtility
    if w > 0 and h > 0 then
        -- Size floor (handoff item 6): band + table header + three rows - below this the
        -- 26px band stat is the first casualty.
        ImGui.SetNextWindowSizeConstraints(ImVec2(460, 240), ImVec2(16384, 16384))
        ImGui.SetNextWindowSize(ImVec2(w, h), condPos)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Augment Utility##ItemUIAugmentUtility", registry.isOpen("augmentUtility"), windowFlags)
    registry.setWindowState("augmentUtility", winOpen, winOpen)

    if not winOpen then
        ctx.uiState.removeAllQueue = nil   -- Phase 1: window closed
        ctx.uiState.optimizeQueue = nil   -- Phase 2: window closed
        ImGui.End(); return
    end
    -- Escape closes this window via main Inventory Companion's LIFO handler only
    if not winVis then ImGui.End(); return end
    if tostring(layoutConfig.UIMode or "classic") ~= "bars" and ctx.renderWindowLock then
        ctx.renderWindowLock(ctx, "augmentUtility")
    end

    if not ctx.uiState.uiLocked then
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            layoutConfig.WidthAugmentUtilityPanel = cw
            layoutConfig.HeightAugmentUtility = ch
        end
    end
    local cx, cy = ImGui.GetWindowPos()
    if cx and cy then
        if not layoutConfig.AugmentUtilityWindowX or math.abs(layoutConfig.AugmentUtilityWindowX - cx) > 1 or
           not layoutConfig.AugmentUtilityWindowY or math.abs(layoutConfig.AugmentUtilityWindowY - cy) > 1 then
            layoutConfig.AugmentUtilityWindowX = cx
            layoutConfig.AugmentUtilityWindowY = cy
            if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
        end
    end

    local subject = resolveTarget()
    local subjectName = subject and subject.item and subject.item.name or nil
    if tostring(layoutConfig.UIMode or "classic") == "bars" then
        -- 23b: the band states the link — windowHeader.GLYPHS.LINK + the subject — and the pin action
        -- freezes it. Restating the target's identity beyond the chip is §9 redundancy;
        -- Item Display is beside this window and owns the full card.
        windowHeader.render({
            id = "augmentUtility", title = "Aug Utility",
            stat = subjectName and (windowHeader.GLYPHS.LINK .. " " .. subjectName)
                or (windowHeader.GLYPHS.LINK .. " no subject - open an item"),
            actions = {
                {
                    label = GLYPH_PIN,
                    tooltip = state.pinnedTarget and "Unpin: follow Item Display again"
                        or "Pin: keep this subject while Item Display moves on",
                    disabled = (subject == nil),
                    onClick = function()
                        if state.pinnedTarget then
                            state.pinnedTarget = nil
                        else
                            state.pinnedTarget = currentLiveTarget()
                        end
                    end,
                },
            },
            lock = {
                locked = registry.isPinned("augmentUtility"),
                onToggle = function()
                    registry.setPinned("augmentUtility", not registry.isPinned("augmentUtility"))
                    if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
                end,
            },
        })
    end

    -- Bars mode (spec §8's one consolidation): a tab bar — the slot-driven flow, plus the
    -- Augments window's whole list as "All augments" (that window is classicOnly now; same
    -- list, one window, one shortcut). Classic keeps the un-tabbed layout untouched.
    local barsOn = tostring(layoutConfig.UIMode or "classic") == "bars"
    if barsOn then
        if ImGui.BeginTabBar("##AugUtilTabs") then
            -- Single-arg BeginTabItem returns show FIRST in this binding (tuple (show, show)).
            local showSlot = ImGui.BeginTabItem("For this slot")
            if showSlot then
                renderForSlotContent(ctx)
                ImGui.EndTabItem()
            end
            local showAll = ImGui.BeginTabItem("All augments")
            if showAll then
                AugmentsView.renderListContent(ctx)
                ImGui.EndTabItem()
            end
            ImGui.EndTabBar()
        end
    else
        renderForSlotContent(ctx)
    end

    ImGui.End()
end

--- The slot-driven flow (target item, slot picker, candidate list) — the window's whole
--- body before the fold. No Begin/End in here: render() owns the window, the tab owns
--- the region. Early returns are plain returns for the same reason.
renderForSlotContent = function(ctx)
    -- Target: the subject link (pinned target beats Item Display's live tab).
    local tab = resolveTarget()

    if not tab or not tab.item then
        ctx.theme.TextWarning("No item selected.")
        ImGui.TextWrapped("Open an item in CoOpt UI Item Display (right-click an item -> Item info), then use this utility to add or remove augments.")
        return
    end

    local targetItem = tab.item
    local bag, slot, source = tab.bag, tab.slot, tab.source or "inv"
    local itemName = (targetItem.name or targetItem.Name or "?"):sub(1, 50)
    if (targetItem.name or ""):len() > 50 then itemName = itemName .. "..." end

    -- Bars mode: the band's link chip IS the target's identity (23b), and the slot map
    -- says the rest — restating name/source here was two rows of §9 redundancy the
    -- 2026-07-31 field pass called out as wasted vertical space. Classic keeps the block.
    if tostring(ctx.layoutConfig.UIMode or "classic") ~= "bars" then
        ctx.theme.TextHeader("Target item")
        ImGui.SameLine()
        ImGui.Text(itemName)
        ctx.theme.TextMuted(string.format("Source: %s | Bag %s, Slot %s", source == "bank" and "Bank" or "Inventory", tostring(bag), tostring(slot)))
        ImGui.Spacing()
    end

    -- Slot selector: show only standard augment slots (1-4). Ornament (slot 5, type 20) is excluded so we
    -- don't show a phantom "Slot 3" when the item has e.g. slots 1, 2 and an ornament. Ornament add/remove
    -- can be added later as a separate dropdown option or section (slot 5; behavior differs from augments).
    local maxSlots = 4
    if ctx.getItemTLO and ctx.getStandardAugSlotsCountFromTLO then
        local it = ctx.getItemTLO(bag, slot, source)
        local count = it and ctx.getStandardAugSlotsCountFromTLO(it) or 0
        if count > 0 then maxSlots = math.min(count, 4) end
    end
    local slotIdx = state.augmentUtilitySlotIndex
    if type(slotIdx) ~= "number" or slotIdx < 1 or slotIdx > maxSlots then
        slotIdx = 1
        state.augmentUtilitySlotIndex = 1
    end
    local itForSlot = ctx.getItemTLO and ctx.getItemTLO(bag, slot, source)
    if tostring(ctx.layoutConfig.UIMode or "classic") == "bars" then
        -- 20c: the slot map IS the picker — one Selectable cell per socket, filled cells
        -- named from the same scan-invalidated cache Item Display's AUGMENTS section
        -- reads, the active cell in open-blue on the active-tab fill. This replaces the
        -- "Augment slot:" combo; classic keeps the combo below.
        local tipOpts = { source = source, bag = bag, slot = slot }
        pcall(function() ItemTooltip.prepareTooltipContent(targetItem, ctx, tipOpts) end)
        local tip = TooltipData.getCachedTooltipEntry(targetItem, tipOpts)
        local byIndex = {}
        if tip and type(tip.augLines) == "table" then
            for _, r in ipairs(tip.augLines) do byIndex[r.slotIndex] = r end
        end
        for i = 1, maxSlots do
            local r = byIndex[i]
            local cell
            if r and r.augName and r.augName ~= "empty" and r.augName ~= "" then
                cell = r.augName
            elseif r and r.prefix and r.prefix ~= "" then
                cell = r.prefix .. "empty"
            else
                local typ = (ctx.getSlotType and itForSlot) and ctx.getSlotType(itForSlot, i) or 0
                cell = (typ and typ > 0) and string.format("empty . type %d", typ) or "empty"
            end
            local active = (i == slotIdx)
            ImGui.PushStyleColor(ImGuiCol.Text, ctx.theme.ToVec4(active and ctx.theme.Kit.OpenBlue or ctx.theme.Colors.TextContent))
            ImGui.PushStyleColor(ImGuiCol.HeaderHovered, ctx.theme.ToVec4(ctx.theme.Kit.Header))
            ImGui.PushStyleColor(ImGuiCol.HeaderActive, ctx.theme.ToVec4(ctx.theme.Kit.Header))
            local okSel, _sel, pressed = pcall(ImGui.Selectable,
                string.format("SLOT %d   %s##augmap%d", i, cell, i), active)
            ImGui.PopStyleColor(3)
            if okSel and pressed then slotIdx = i end
        end
        if tip and tip.ornamentLine then
            local o = tip.ornamentLine
            local oname = (o.augName and o.augName ~= "empty" and o.augName ~= "") and o.augName
                or "empty . type 20"
            ImGui.PushStyleColor(ImGuiCol.Text, ctx.theme.ToVec4(ctx.theme.Kit.Mythic))
            pcall(ImGui.Selectable, "ORNAMENT   " .. oname .. "##augmapOrn", false)
            ImGui.PopStyleColor(1)
        end
        ctx.theme.TextFurniture("click a slot to work on it")
        state.augmentUtilitySlotIndex = slotIdx
    else
        ImGui.Text("Augment slot:")
        ImGui.SameLine()
        ImGui.SetNextItemWidth(140)
        local slotNames = {}
        for i = 1, maxSlots do
            if ctx.getSlotType and itForSlot then
                local typ = ctx.getSlotType(itForSlot, i)
                slotNames[i] = (typ and typ > 0) and string.format("Slot %d (type %d)", i, typ) or string.format("Slot %d", i)
            else
                slotNames[i] = string.format("Slot %d (augment)", i)
            end
        end
        local newIdx = ImGui.Combo("##AugmentUtilitySlot", slotIdx, slotNames, maxSlots)
        if type(newIdx) == "number" and newIdx >= 1 and newIdx <= maxSlots then
            slotIdx = newIdx
        end
        state.augmentUtilitySlotIndex = slotIdx
    end
    ImGui.Spacing()

    -- Phase 2: detect optimize-queue completion (main_loop drains steps then clears the queue).
    -- On completion, invalidate the plan + candidate caches: slots are now filled and augments
    -- consumed, but the cache keys alone would not change.
    local runningQueue = ctx.uiState.optimizeQueue
    if runningQueue and runningQueue.steps and #runningQueue.steps > 0 then
        optimizeWasRunning = true
    elseif optimizeWasRunning then
        optimizeWasRunning = false
        optimizeCache.itemId = nil
        candidateCache.key = nil
    end

    -- Phase 2: Build optimize plan (cached — only recompute when item/slot/bank/usable changes).
    local optimizeSteps = {}
    local canOptimize = false
    if ctx.getCompatibleAugments and ctx.getFilledStandardAugmentSlotIndices then
        local bankOpen = (ctx.isBankWindowOpen and ctx.isBankWindowOpen()) or false
        local onlyShowUsable = (state.augmentUtilityOnlyShowUsable ~= false)
        local itemId = targetItem.id or targetItem.ID or 0
        -- Invalidate cache when inputs change
        if optimizeCache.itemId ~= itemId or optimizeCache.bag ~= bag or optimizeCache.slot ~= slot
            or optimizeCache.source ~= source or optimizeCache.slotCount ~= maxSlots
            or optimizeCache.bankOpen ~= bankOpen or optimizeCache.usable ~= onlyShowUsable then
            local entry = { bag = bag, slot = slot, source = source, item = targetItem }
            local canUseFilter = onlyShowUsable and function(i)
                local info = ItemTooltip.getCanUseInfo(i, i.source or "inv")
                return info and info.canUse
            end or nil
            local filledSlotsAU = ctx.getFilledStandardAugmentSlotIndices(bag, slot, source) or {}
            local filledSetAU = {}
            for _, idx in ipairs(filledSlotsAU) do filledSetAU[idx] = true end
            local emptySlotsAU = {}
            for i = 1, maxSlots do if not filledSetAU[i] then emptySlotsAU[#emptySlotsAU + 1] = i end end
            local function usedKeyAU(a) return tostring(a.bag or 0) .. "_" .. tostring(a.slot or 0) .. "_" .. (a.source or "inv") end
            local usedAU = {}
            local parentContextAU = { bag = bag, slot = slot, source = source }
            local rankConfigAU = augmentRanking.getDefaultConfig()
            local steps = {}
            for _, si in ipairs(emptySlotsAU) do
                local compat = ctx.getCompatibleAugments(entry, si, { canUseFilter = canUseFilter })
                if not bankOpen then
                    local invOnly = {}
                    for _, c in ipairs(compat) do
                        if (c.source or "inv") ~= "bank" then invOnly[#invOnly + 1] = c end
                    end
                    compat = invOnly
                end
                local available = {}
                for _, c in ipairs(compat) do if not usedAU[usedKeyAU(c)] then available[#available + 1] = c end end
                if #available > 0 then
                    for _, c in ipairs(available) do
                        local sc = augmentRanking.scoreAugment(c, parentContextAU, ctx, rankConfigAU)
                        c._optScore = (type(sc) == "number") and sc or 0
                    end
                    table.sort(available, function(a, b) return (a._optScore or 0) > (b._optScore or 0) end)
                    local best = available[1]
                    usedAU[usedKeyAU(best)] = true
                    steps[#steps + 1] = { slotIndex = si, augmentItem = best }
                end
            end
            optimizeCache.itemId = itemId
            optimizeCache.bag = bag
            optimizeCache.slot = slot
            optimizeCache.source = source
            optimizeCache.slotCount = maxSlots
            optimizeCache.bankOpen = bankOpen
            optimizeCache.usable = onlyShowUsable
            optimizeCache.steps = steps
            optimizeCache.canOptimize = #steps > 0
        end
        optimizeSteps = optimizeCache.steps or {}
        canOptimize = optimizeCache.canOptimize
    end

    -- Compatible augments: header + search + Refresh + table with tooltips
    if not ctx.getCompatibleAugments then
        ctx.theme.TextWarning("getCompatibleAugments not available.")
        ImGui.Spacing()
    else
        local onlyShowUsable = (state.augmentUtilityOnlyShowUsable ~= false)
        local bankOpenAU = (ctx.isBankWindowOpen and ctx.isBankWindowOpen()) or false
        local candItemId = targetItem.id or targetItem.ID or 0
        local searchLower = (state.searchFilterAugmentUtility or ""):lower()
        -- Candidate cache (same key signals as optimizeCache + search text). Inventory/bank
        -- signature = count + first-item identity: scans refill the tables in place with fresh
        -- item objects, so identity changes even when counts do not.
        local invItemsAU = ctx.inventoryItems or {}
        local bankItemsAU = ctx.bankItems or {}
        local candKey = string.format("%s|%s|%s|%s|%d|%s|%s|%d|%s|%d|%s|%s",
            tostring(candItemId), tostring(bag), tostring(slot), tostring(source), slotIdx,
            tostring(bankOpenAU), tostring(onlyShowUsable),
            #invItemsAU, tostring(invItemsAU[1]), #bankItemsAU, tostring(bankItemsAU[1]),
            searchLower)
        if candidateCache.key ~= candKey then
            local entry = { bag = bag, slot = slot, source = source, item = targetItem }
            -- Apply socket type + augment restrictions + (when on) class/race/deity/level in one place so list is strict before ranking
            local canUseFilter = onlyShowUsable and function(i)
                local info = ItemTooltip.getCanUseInfo(i, i.source or "inv")
                return info and info.canUse
            end or nil
            -- List is already restricted to: fits slot, restrictions, equipment slot, and (when on) class/race/deity/level
            local candidates = ctx.getCompatibleAugments(entry, slotIdx, { canUseFilter = canUseFilter }) or {}
            local rebuilt = {}
            for _, cand in ipairs(candidates) do
                if searchLower == "" or (cand.name or ""):lower():find(searchLower, 1, true) then
                    rebuilt[#rebuilt + 1] = cand
                end
            end
            -- Score each candidate, then assign rank position (1 = best). scoreAugment takes
            -- parent coordinates and resolves the parent item TLO itself; with this cache that
            -- happens once per rebuild instead of once per candidate every frame.
            local parentContext = { bag = bag, slot = slot, source = source }
            local rankConfig = augmentRanking.getDefaultConfig()
            for _, cand in ipairs(rebuilt) do
                local s = augmentRanking.scoreAugment(cand, parentContext, ctx, rankConfig)
                cand._rankScore = (type(s) == "number") and s or 0
            end
            table.sort(rebuilt, function(a, b) return (a._rankScore or 0) > (b._rankScore or 0) end)
            for i, cand in ipairs(rebuilt) do
                cand._rankPosition = i
            end
            candidateCache.key = candKey
            candidateCache.candCount = #candidates
            candidateCache.list = rebuilt
            candidateCache.sortKey = nil
            candidateCache.sorted = nil
        end
        local filtered = candidateCache.list or {}
        local candCount = candidateCache.candCount or 0

        ctx.theme.TextHeader("Compatible augments")
        ImGui.SameLine()
        ctx.theme.TextInfo(string.format("(%d)", candCount))
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Only augments that fit this slot and pass all qualifications (restrictions, equipment slot, class/race/deity/level) are listed.")
            ImGui.EndTooltip()
        end
        ImGui.SameLine()
        -- MQ2 ImGui.Checkbox returns (newValue, changed); just use first return like all other checkboxes
        state.augmentUtilityOnlyShowUsable = ImGui.Checkbox("Only show usable by me##AU_OnlyUsable", state.augmentUtilityOnlyShowUsable)
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("When checked, only augments your character can use (class, race, deity, level) are shown.\nUncheck to see all compatible augments (e.g. for another character).")
            ImGui.EndTooltip()
        end
        ImGui.SameLine()
        ctx.renderRefreshButton(ctx, "Refresh##AugmentUtility", "Rescan inventory and bank for compatible augments", function()
            if ctx.scanInventory then ctx.scanInventory() end
            if source == "bank" and ctx.scanBank then ctx.scanBank() end
        end, { messageBefore = "Scanning...", messageAfter = "Refreshed" })
        ImGui.SameLine()
        ImGui.Text("Search:")
        ImGui.SameLine()
        ImGui.SetNextItemWidth(160)
        state.searchFilterAugmentUtility, _ = ImGui.InputText("##AugmentUtilitySearch", state.searchFilterAugmentUtility or "")
        ImGui.SameLine()
        if ImGui.Button("X##AugmentUtilitySearchClear", ImVec2(22, 0)) then
            state.searchFilterAugmentUtility = ""
        end
        ImGui.Separator()

        if ImGui.BeginChild("##AugmentUtilityList", ImVec2(0, -72), true) then
            if #filtered == 0 then
                if candCount == 0 then
                    ctx.theme.TextMuted("No compatible augments in inventory or bank.")
                elseif onlyShowUsable and candCount == 0 then
                    ctx.theme.TextMuted("No augments you can use in this slot.")
                    ImGui.TextWrapped("Uncheck \"Only show usable by me\" to see all compatible augments (e.g. for another character).")
                else
                    ctx.theme.TextMuted("No compatible augments match your search.")
                end
            else
                local tableFlags = bit32.bor(ctx.uiState.tableFlags or 0, ImGuiTableFlags.Sortable)
                if ImGui.BeginTable("ItemUI_AugmentUtility", 5, tableFlags) then
                    ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 32, 0)
                    ImGui.TableSetupColumn("Rank", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable, ImGuiTableColumnFlags.DefaultSort), 48, 1)
                    ImGui.TableSetupColumn("Name", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable), 0, 2)
                    ImGui.TableSetupColumn("Clicky", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable), 0, 3)
                    ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 56, 4)
                    ImGui.TableHeadersRow()

                    -- Read sort spec and sort filtered list (1 = Rank, 2 = Name, 3 = Clicky)
                    local sortSpecs = ImGui.TableGetSortSpecs()
                    if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
                        local spec = sortSpecs:Specs(1)
                        if spec then
                            ctx.uiState.augmentUtilitySortColumn = spec.ColumnIndex
                            ctx.uiState.augmentUtilitySortDirection = spec.SortDirection
                        end
                        sortSpecs.SpecsDirty = false
                    end
                    -- Default: sort by Rank ascending (1 = best, first)
                    local sortCol = (ctx.uiState.augmentUtilitySortColumn ~= nil) and ctx.uiState.augmentUtilitySortColumn or 1
                    local sortDir = ctx.uiState.augmentUtilitySortDirection
                    if sortDir == nil then
                        sortDir = ImGuiSortDirection.Ascending
                        ctx.uiState.augmentUtilitySortDirection = sortDir
                    end
                    local asc = (sortDir == ImGuiSortDirection.Ascending)
                    local function getClickyName(c)
                        if not c or not c.clicky or c.clicky <= 0 then return "" end
                        return (ctx.getSpellName and ctx.getSpellName(c.clicky)) or ""
                    end
                    local rows = filtered
                    if sortCol == 1 or sortCol == 2 or sortCol == 3 then
                        local sortKey = string.format("%d|%s|%s", sortCol, tostring(sortDir), candidateCache.key or "")
                        if candidateCache.sortKey ~= sortKey or not candidateCache.sorted then
                            local sorted = {}
                            for i = 1, #filtered do sorted[i] = filtered[i] end
                            table.sort(sorted, function(a, b)
                                local av, bv
                                if sortCol == 1 then
                                    av = (a._rankPosition or 9999)
                                    bv = (b._rankPosition or 9999)
                                    if asc then return av < bv else return av > bv end
                                elseif sortCol == 2 then
                                    av = (a.name or ""):lower()
                                    bv = (b.name or ""):lower()
                                    if asc then return av < bv else return av > bv end
                                else
                                    av = getClickyName(a):lower()
                                    bv = getClickyName(b):lower()
                                    if asc then return av < bv else return av > bv end
                                end
                            end)
                            candidateCache.sortKey = sortKey
                            candidateCache.sorted = sorted
                        end
                        rows = candidateCache.sorted
                    end

                    local clipper = ImGuiListClipper.new()
                    clipper:Begin(#rows)
                    while clipper:Step() do
                        for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                            local cand = rows[i]
                            if not cand then goto continue end
                            local rid = "au_" .. tostring(cand.bag or 0) .. "_" .. tostring(cand.slot or 0) .. "_" .. (cand.source or "inv")
                            ImGui.PushID(rid)
                            ImGui.TableNextRow()

                            -- Icon (hover = full stats tooltip)
                            ImGui.TableNextColumn()
                            if ctx.drawItemIcon and cand.icon and cand.icon > 0 then
                                pcall(function() ctx.drawItemIcon(cand.icon, 24) end)
                            else
                                ImGui.Dummy(ImVec2(24, 24))
                            end
                            if ImGui.IsItemHovered() then
                                local showItem = (ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip(cand, cand.source or "inv")) or cand
                                local opts = { source = cand.source or "inv", bag = cand.bag, slot = cand.slot }
                                local effects, w, h = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
                                opts.effects = effects
                                ItemTooltip.beginItemTooltip(w, h)
                                ImGui.Text("Stats")
                                ImGui.Separator()
                                ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
                                ImGui.EndTooltip()
                            end

                            -- Rank (1 = best)
                            ImGui.TableNextColumn()
                            ImGui.Text(tostring(cand._rankPosition or 0))
                            if ImGui.IsItemHovered() then
                                ImGui.BeginTooltip()
                                ImGui.Text("Rank (1 = best)")
                                ImGui.EndTooltip()
                            end

                            -- Name + compact class/race/deity line
                            ImGui.TableNextColumn()
                            ImGui.Text(cand.name or "?")
                            -- The shared menu (item 7). This was the one host with no
                            -- right-click at all, so the same augment offered a full menu
                            -- in Bags and nothing here. Pure wiring: candidates ARE real
                            -- bag or bank items, so each passes its own source's context.
                            if ctx.renderItemContextMenu then
                                ctx.renderItemContextMenu(ctx, cand, {
                                    source = cand.source or "inv",
                                    popupId = "ItemContextAugUtil_" .. rid,
                                })
                            end
                            if ImGui.IsItemHovered() then
                                ImGui.BeginTooltip()
                                ImGui.Text(cand.name or "?")
                                ImGui.EndTooltip()
                            end
                            local subParts = {}
                            if cand.class and cand.class ~= "" then subParts[#subParts + 1] = tostring(cand.class):gsub("|", " ") end
                            if cand.race and cand.race ~= "" then subParts[#subParts + 1] = tostring(cand.race):gsub("|", " ") end
                            if cand.deity and cand.deity ~= "" then subParts[#subParts + 1] = tostring(cand.deity):gsub("|", " ") end
                            if #subParts > 0 then
                                ctx.theme.TextMuted(table.concat(subParts, " | "))
                            end

                            -- Clicky (spell name or —)
                            ImGui.TableNextColumn()
                            local clickyStr = getClickyName(cand)
                            if clickyStr and clickyStr ~= "" then
                                ImGui.Text(clickyStr)
                            else
                                ctx.theme.TextMuted("-")
                            end

                            -- Insert button (themed)
                            ImGui.TableNextColumn()
                            ctx.theme.PushKeepButton(false)
                            local btnId = "Insert##AU_" .. tostring(cand.id or 0) .. "_" .. tostring(cand.bag or 0) .. "_" .. tostring(cand.slot or 0)
                            if ImGui.SmallButton(btnId) then
                                if ctx.insertAugment then
                                    local targetLoc = { bag = tab.bag, slot = tab.slot, source = tab.source or "inv" }
                                    ctx.insertAugment(targetItem, cand, slotIdx, targetLoc)
                                    -- Phase 0: main loop runs one scan when insert completes and refreshes tab.item
                                end
                            end
                            ctx.theme.PopButtonColors()
                            if ImGui.IsItemHovered() then
                                ImGui.BeginTooltip()
                                ImGui.Text("Insert this augment into the selected slot")
                                ImGui.EndTooltip()
                            end

                            ImGui.PopID()
                            ::continue::
                        end
                    end
                    ImGui.EndTable()
                end
            end
        end
        ImGui.EndChild()
    end

    ImGui.Spacing()
    -- Remove section (themed)
    ctx.theme.TextHeader("Remove augment")
    ImGui.SameLine()
    if ctx.removeAugment then
        ctx.theme.PushDeleteButton()
        if ImGui.SmallButton("Remove from slot " .. tostring(slotIdx) .. "##AU") then
            ctx.removeAugment(bag, slot, source, slotIdx)
        end
        ctx.theme.PopButtonColors()
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Opens game Item Display and removes augment from this slot (game picks distiller).")
            ImGui.EndTooltip()
        end
    end
    -- Phase 1: Remove All (queue filled slots; one scan when queue finishes)
    local filledSlots = (ctx.getFilledStandardAugmentSlotIndices and ctx.getFilledStandardAugmentSlotIndices(bag, slot, source)) or {}
    local canRemoveAll = #filledSlots > 0
    if not canRemoveAll then ImGui.BeginDisabled() end
    ImGui.SameLine()
    if ctx.theme then ctx.theme.PushDeleteButton() end
    if ImGui.SmallButton("Remove All##AU") and canRemoveAll then
        ctx.uiState.removeAllQueue = { bag = bag, slot = slot, source = source or "inv", slotIndices = filledSlots, total = #filledSlots }
    end
    if ctx.theme then ctx.theme.PopButtonColors() end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        if canRemoveAll then
            ImGui.Text("Remove augments from all filled slots on this item (one at a time).")
        else
            ImGui.Text("No augments to remove on this item.")
        end
        ImGui.EndTooltip()
    end
    if not canRemoveAll then ImGui.EndDisabled() end
    -- Phase 3.1: progress while Remove All is running
    if ctx.uiState.removeAllQueue and ctx.uiState.removeAllQueue.slotIndices and ctx.uiState.removeAllQueue.total then
        local rem = ctx.uiState.removeAllQueue
        ImGui.SameLine()
        ctx.theme.TextInfo(string.format("Removing %d/%d", #rem.slotIndices, rem.total))
    end

    -- Phase 2: Fill empty slots with best augments (whole-item action, grouped with Remove)
    ImGui.Spacing()
    ctx.theme.TextHeader("Fill empty slots")
    ImGui.SameLine()
    local optimizeRunning = ctx.uiState.optimizeQueue ~= nil
    local fillDisabled = not canOptimize or optimizeRunning
    if fillDisabled then ImGui.BeginDisabled() end
    if ImGui.Button("Fill with best##AU", ImVec2(100, 0)) and not fillDisabled then
        -- Copy the steps into the queue: main_loop drains the queue with table.remove, and
        -- handing it optimizeCache.steps directly would hollow out the cached plan.
        local queueSteps = {}
        for i, st in ipairs(optimizeSteps) do
            queueSteps[i] = { slotIndex = st.slotIndex, augmentItem = st.augmentItem }
        end
        ctx.uiState.optimizeQueue = { targetLoc = { bag = bag, slot = slot, source = source or "inv" }, steps = queueSteps, total = #queueSteps }
    end
    if fillDisabled then ImGui.EndDisabled() end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        if canOptimize then
            ImGui.Text("Fill all empty augment slots with the top-ranked compatible augments (best first; each used at most once).")
            ImGui.Text("Uses inventory only when bank is closed; includes bank when open.")
        else
            ImGui.Text("No empty slots or no compatible augments available to fill them.")
        end
        ImGui.EndTooltip()
    end
    -- Phase 3.1: progress while Optimize is running (total > 0, not just truthy)
    if ctx.uiState.optimizeQueue and ctx.uiState.optimizeQueue.steps and (ctx.uiState.optimizeQueue.total or 0) > 0 then
        local oq = ctx.uiState.optimizeQueue
        ImGui.SameLine()
        ctx.theme.TextInfo(string.format("Optimizing %d/%d", #oq.steps, oq.total))
    end
end

-- Registry: Augment Utility module (4.2 state ownership — window in registry, slot/search in view)
registry.register({
    id          = "augmentUtility",
    zone        = "L2",  -- window_zones placement column/slot (mockup 10a)
    label       = "Augment Utility",
    buttonWidth = 100,
    tooltip     = "Add or remove augments from your gear",
    layoutKeys  = { x = "AugmentUtilityWindowX", y = "AugmentUtilityWindowY" },
    enableKey   = "ShowAugmentUtilityWindow",
    render      = function(refs)
        local ctx = context.build()
        AugmentUtilityView.render(ctx)
    end,
})

return AugmentUtilityView
