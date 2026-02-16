--[[
    Augment Utility View - Standalone window for insert/remove augments.
    Target item from current CoOpt Item Display tab; slot selector; compatible list + Insert; Remove per slot.
--]]

require('ImGui')

local AugmentUtilityView = {}

local WINDOW_WIDTH = 520
local WINDOW_HEIGHT = 480

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

    if not winOpen then ImGui.End(); return end
    if ImGui.IsKeyPressed(ImGuiKey.Escape) then
        ctx.uiState.augmentUtilityWindowOpen = false
        ctx.uiState.augmentUtilityWindowShouldDraw = false
        ImGui.End()
        return
    end
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
        ImGui.TextColored(ImVec4(0.85, 0.6, 0.2, 1.0), "No item selected.")
        ImGui.TextWrapped("Open an item in CoOpt UI Item Display (right-click an item -> CoOp UI Item Display), then use this utility to add or remove augments.")
        ImGui.End()
        return
    end

    local targetItem = tab.item
    local bag, slot, source = tab.bag, tab.slot, tab.source or "inv"
    local itemName = (targetItem.name or targetItem.Name or "?"):sub(1, 50)
    if (targetItem.name or ""):len() > 50 then itemName = itemName .. "..." end

    ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Target item")
    ImGui.SameLine()
    ImGui.Text(itemName)
    ImGui.TextColored(ImVec4(0.55, 0.55, 0.6, 1.0), string.format("Source: %s | Bag %s, Slot %s", source == "bank" and "Bank" or "Inventory", tostring(bag), tostring(slot)))
    ImGui.Spacing()

    -- Slot selector: only show slots that exist on this item (1-4 standard augment slots; ornament excluded for now).
    local maxSlots = 4
    if ctx.getItemTLO and ctx.getAugSlotsCountFromTLO then
        local it = ctx.getItemTLO(bag, slot, source)
        local count = it and ctx.getAugSlotsCountFromTLO(it) or 0
        if count > 0 then maxSlots = math.min(count, 4) end
    end
    local slotIdx = ctx.uiState.augmentUtilitySlotIndex
    if type(slotIdx) ~= "number" or slotIdx < 1 or slotIdx > maxSlots then
        slotIdx = 1
        ctx.uiState.augmentUtilitySlotIndex = 1
    end
    ImGui.Text("Augment slot:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(120)
    local slotNames = {}
    for i = 1, maxSlots do slotNames[i] = string.format("Slot %d (augment)", i) end
    local newIdx = ImGui.Combo("##AugmentUtilitySlot", slotIdx, slotNames, maxSlots)
    if type(newIdx) == "number" and newIdx >= 1 and newIdx <= maxSlots then
        slotIdx = newIdx
    end
    ctx.uiState.augmentUtilitySlotIndex = slotIdx
    ImGui.Spacing()

    -- Compatible augments list
    if ctx.getCompatibleAugments then
        local entry = { bag = bag, slot = slot, source = source, item = targetItem }
        local candidates = ctx.getCompatibleAugments(entry, slotIdx)
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Compatible augments for Slot " .. tostring(slotIdx))
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(0.6, 0.65, 0.7, 1.0), string.format("(%d)", #candidates))
        ImGui.Spacing()
        if ImGui.BeginChild("##AugmentUtilityList", ImVec2(0, -80), true) then
            if #candidates == 0 then
                ImGui.TextColored(ImVec4(0.7, 0.6, 0.5, 1.0), "No compatible augments in inventory or bank.")
            else
                for _, cand in ipairs(candidates) do
                    if ctx.drawItemIcon and cand.icon and cand.icon > 0 then
                        pcall(function() ctx.drawItemIcon(cand.icon, 24) end)
                    else
                        ImGui.Dummy(ImVec2(24, 24))
                    end
                    ImGui.SameLine()
                    local locStr = (cand.source or "inv") == "bank" and ("Bank " .. tostring(cand.bag) .. "/" .. tostring(cand.slot)) or ("Pack " .. tostring(cand.bag) .. "/" .. tostring(cand.slot))
                    ImGui.Text((cand.name or "?") .. " (" .. locStr .. ")")
                    ImGui.SameLine()
                    local btnId = "Insert##AU_" .. tostring(cand.id or 0) .. "_" .. tostring(cand.bag or 0) .. "_" .. tostring(cand.slot or 0)
                    if ImGui.SmallButton(btnId) then
                        if ctx.insertAugment then
                            if ctx.insertAugment(targetItem, cand) then
                                if ctx.getItemStatsForTooltip and tab then
                                    local fresh = ctx.getItemStatsForTooltip({ bag = tab.bag, slot = tab.slot }, tab.source)
                                    if fresh then tab.item = fresh end
                                end
                            end
                        end
                    end
                end
            end
            ImGui.EndChild()
        end
    else
        ImGui.TextColored(ImVec4(0.8, 0.4, 0.2, 1.0), "getCompatibleAugments not available.")
    end

    ImGui.Spacing()
    -- Remove section
    ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Remove augment")
    ImGui.SameLine()
    if ctx.removeAugment then
        if ImGui.SmallButton("Remove from slot " .. tostring(slotIdx) .. "##AU") then
            ctx.removeAugment(bag, slot, source, slotIdx)
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Opens game Item Display and removes augment from this slot (game picks distiller).")
            ImGui.EndTooltip()
        end
    end

    ImGui.End()
end

return AugmentUtilityView
