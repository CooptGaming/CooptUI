--[[
    Augment Utility View - Standalone window for insert/remove augments.
    Target item from current CoOpt Item Display tab; slot selector; compatible list (table + search + tooltips) + Insert; Remove per slot.
    Uses CoOpt UI theme and patterns (Augments view, Item Display).
--]]

require('ImGui')
local ItemTooltip = require('itemui.utils.item_tooltip')
local augmentRanking = require('itemui.utils.augment_ranking')

local AugmentUtilityView = {}

local WINDOW_WIDTH = 560
local WINDOW_HEIGHT = 520

function AugmentUtilityView.render(ctx)
    if not ctx.uiState.augmentUtilityWindowShouldDraw then return end

    local layoutConfig = ctx.layoutConfig
    local open = ctx.uiState.augmentUtilityWindowOpen

    local px = layoutConfig.AugmentUtilityWindowX or 0
    local py = layoutConfig.AugmentUtilityWindowY or 0
    if px and py and (px ~= 0 or py ~= 0) then
        ImGui.SetNextWindowPos(ImVec2(px, py), ImGuiCond.FirstUseEver)
    end

    local w = layoutConfig.WidthAugmentUtilityPanel or WINDOW_WIDTH
    local h = layoutConfig.HeightAugmentUtility or WINDOW_HEIGHT
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.FirstUseEver)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Augment Utility##ItemUIAugmentUtility", open, windowFlags)
    ctx.uiState.augmentUtilityWindowOpen = winOpen
    ctx.uiState.augmentUtilityWindowShouldDraw = winOpen

    if not winOpen then
        ctx.uiState.removeAllQueue = nil   -- Phase 1: window closed
        ctx.uiState.optimizeQueue = nil   -- Phase 2: window closed
        ImGui.End(); return
    end
    -- Escape closes this window via main Inventory Companion's LIFO handler only
    if not winVis then ImGui.End(); return end

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
            if ctx.flushLayoutSave then ctx.flushLayoutSave() end
        end
    end

    -- Target: current Item Display tab
    local tabs = ctx.uiState.itemDisplayTabs or {}
    local activeIdx = ctx.uiState.itemDisplayActiveTabIndex or 1
    if activeIdx < 1 or activeIdx > #tabs then activeIdx = #tabs > 0 and 1 or 0 end
    local tab = (activeIdx >= 1 and activeIdx <= #tabs) and tabs[activeIdx] or nil

    if not tab or not tab.item then
        ctx.theme.TextWarning("No item selected.")
        ImGui.TextWrapped("Open an item in CoOpt UI Item Display (right-click an item -> CoOp UI Item Display), then use this utility to add or remove augments.")
        ImGui.End()
        return
    end

    local targetItem = tab.item
    local bag, slot, source = tab.bag, tab.slot, tab.source or "inv"
    local itemName = (targetItem.name or targetItem.Name or "?"):sub(1, 50)
    if (targetItem.name or ""):len() > 50 then itemName = itemName .. "..." end

    ctx.theme.TextHeader("Target item")
    ImGui.SameLine()
    ImGui.Text(itemName)
    ctx.theme.TextMuted(string.format("Source: %s | Bag %s, Slot %s", source == "bank" and "Bank" or "Inventory", tostring(bag), tostring(slot)))
    ImGui.Spacing()

    -- Slot selector: show only standard augment slots (1-4). Ornament (slot 5, type 20) is excluded so we
    -- don't show a phantom "Slot 3" when the item has e.g. slots 1, 2 and an ornament. Ornament add/remove
    -- can be added later as a separate dropdown option or section (slot 5; behavior differs from augments).
    local maxSlots = 4
    if ctx.getItemTLO and ctx.getStandardAugSlotsCountFromTLO then
        local it = ctx.getItemTLO(bag, slot, source)
        local count = it and ctx.getStandardAugSlotsCountFromTLO(it) or 0
        if count > 0 then maxSlots = math.min(count, 4) end
    end
    local slotIdx = ctx.uiState.augmentUtilitySlotIndex
    if type(slotIdx) ~= "number" or slotIdx < 1 or slotIdx > maxSlots then
        slotIdx = 1
        ctx.uiState.augmentUtilitySlotIndex = 1
    end
    ImGui.Text("Augment slot:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(140)
    local slotNames = {}
    local itForSlot = ctx.getItemTLO and ctx.getItemTLO(bag, slot, source)
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
    ctx.uiState.augmentUtilitySlotIndex = slotIdx
    ImGui.Spacing()

    -- Phase 2: Build optimize plan once (used by Optimize button in Remove section). Requires getCompatibleAugments.
    -- When bank is closed: use only inventory augments. When bank is open: use inventory + bank.
    local optimizeSteps = {}
    local canOptimize = false
    if ctx.getCompatibleAugments and ctx.getFilledStandardAugmentSlotIndices then
        local bankOpen = (ctx.isBankWindowOpen and ctx.isBankWindowOpen()) or false
        local entry = { bag = bag, slot = slot, source = source, item = targetItem }
        local onlyShowUsable = (ctx.uiState.augmentUtilityOnlyShowUsable ~= false)
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
                optimizeSteps[#optimizeSteps + 1] = { slotIndex = si, augmentItem = best }
            end
        end
        canOptimize = #optimizeSteps > 0
    end

    -- Compatible augments: header + search + Refresh + table with tooltips
    if not ctx.getCompatibleAugments then
        ctx.theme.TextWarning("getCompatibleAugments not available.")
        ImGui.Spacing()
    else
        local entry = { bag = bag, slot = slot, source = source, item = targetItem }
        local onlyShowUsable = (ctx.uiState.augmentUtilityOnlyShowUsable ~= false)
        -- Apply socket type + augment restrictions + (when on) class/race/deity/level in one place so list is strict before ranking
        local canUseFilter = onlyShowUsable and function(i)
            local info = ItemTooltip.getCanUseInfo(i, i.source or "inv")
            return info and info.canUse
        end or nil
        -- List is already restricted to: fits slot, restrictions, equipment slot, and (when on) class/race/deity/level
        local candidates = ctx.getCompatibleAugments(entry, slotIdx, { canUseFilter = canUseFilter })
        local filteredByUse = candidates

        ctx.theme.TextHeader("Compatible augments")
        ImGui.SameLine()
        ctx.theme.TextInfo(string.format("(%d)", #filteredByUse))
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Only augments that fit this slot and pass all qualifications (restrictions, equipment slot, class/race/deity/level) are listed.")
            ImGui.EndTooltip()
        end
        ImGui.SameLine()
        -- Persist checkbox state: support both single-return (new state) and two-return (changed, newState) bindings
        local cb1, cb2 = ImGui.Checkbox("Only show usable by me##AU_OnlyUsable", ctx.uiState.augmentUtilityOnlyShowUsable)
        ctx.uiState.augmentUtilityOnlyShowUsable = (cb2 ~= nil) and cb2 or cb1
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Filter list to augments your current character can use (class, race, deity, level)")
            ImGui.EndTooltip()
        end
        ImGui.SameLine()
        if ImGui.Button("Refresh##AugmentUtility", ImVec2(70, 0)) then
            ctx.setStatusMessage("Scanning...")
            if ctx.scanInventory then ctx.scanInventory() end
            if source == "bank" and ctx.scanBank then ctx.scanBank() end
            ctx.setStatusMessage("Refreshed")
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Rescan inventory and bank for compatible augments")
            ImGui.EndTooltip()
        end
        ImGui.SameLine()
        ImGui.Text("Search:")
        ImGui.SameLine()
        ImGui.SetNextItemWidth(160)
        ctx.uiState.searchFilterAugmentUtility, _ = ImGui.InputText("##AugmentUtilitySearch", ctx.uiState.searchFilterAugmentUtility or "")
        ImGui.SameLine()
        if ImGui.Button("X##AugmentUtilitySearchClear", ImVec2(22, 0)) then
            ctx.uiState.searchFilterAugmentUtility = ""
        end
        ImGui.Separator()

        local searchLower = (ctx.uiState.searchFilterAugmentUtility or ""):lower()
        local filtered = {}
        for _, cand in ipairs(filteredByUse) do
            if searchLower == "" or (cand.name or ""):lower():find(searchLower, 1, true) then
                filtered[#filtered + 1] = cand
            end
        end

        -- Score each candidate, then assign rank position (1 = best)
        local parentContext = { bag = bag, slot = slot, source = source }
        local rankConfig = augmentRanking.getDefaultConfig()
        for _, cand in ipairs(filtered) do
            local s = augmentRanking.scoreAugment(cand, parentContext, ctx, rankConfig)
            cand._rankScore = (type(s) == "number") and s or 0
        end
        table.sort(filtered, function(a, b) return (a._rankScore or 0) > (b._rankScore or 0) end)
        for i, cand in ipairs(filtered) do
            cand._rankPosition = i
        end

        if ImGui.BeginChild("##AugmentUtilityList", ImVec2(0, -72), true) then
            if #filtered == 0 then
                if #candidates == 0 then
                    ctx.theme.TextMuted("No compatible augments in inventory or bank.")
                elseif onlyShowUsable and #filteredByUse == 0 then
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
                    if sortCol == 1 or sortCol == 2 or sortCol == 3 then
                        table.sort(filtered, function(a, b)
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
                    end

                    local clipper = ImGuiListClipper.new()
                    clipper:Begin(#filtered)
                    while clipper:Step() do
                        for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                            local cand = filtered[i]
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
                            if ImGui.IsItemHovered() then
                                ImGui.BeginTooltip()
                                ImGui.Text(cand.name or "?")
                                ImGui.EndTooltip()
                            end
                            local subParts = {}
                            if cand.class and cand.class ~= "" then subParts[#subParts + 1] = tostring(cand.class) end
                            if cand.race and cand.race ~= "" then subParts[#subParts + 1] = tostring(cand.race) end
                            if cand.deity and cand.deity ~= "" then subParts[#subParts + 1] = tostring(cand.deity) end
                            if #subParts > 0 then
                                ctx.theme.TextMuted(table.concat(subParts, " | "))
                            end

                            -- Clicky (spell name or —)
                            ImGui.TableNextColumn()
                            local clickyStr = getClickyName(cand)
                            if clickyStr and clickyStr ~= "" then
                                ImGui.Text(clickyStr)
                            else
                                ctx.theme.TextMuted("—")
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
            ImGui.EndChild()
        end
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
    if not canOptimize then ImGui.BeginDisabled() end
    if ImGui.Button("Fill with best##AU", ImVec2(100, 0)) and canOptimize then
        ctx.uiState.optimizeQueue = { targetLoc = { bag = bag, slot = slot, source = source or "inv" }, steps = optimizeSteps, total = #optimizeSteps }
    end
    if not canOptimize then ImGui.EndDisabled() end
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
    -- Phase 3.1: progress while Optimize is running
    if ctx.uiState.optimizeQueue and ctx.uiState.optimizeQueue.steps and ctx.uiState.optimizeQueue.total then
        local oq = ctx.uiState.optimizeQueue
        ImGui.SameLine()
        ctx.theme.TextInfo(string.format("Optimizing %d/%d", #oq.steps, oq.total))
    end

    ImGui.End()
end

return AugmentUtilityView
