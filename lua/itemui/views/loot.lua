--[[
    Loot View - Live loot view for corpse items
    
    Part of ItemUI Phase 5: View Extraction
    Renders loot window content when corpse is open (CURRENTLY DISABLED in main code)
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')

local LootView = {}

-- Module interface: render loot view content
-- Params: context table containing all necessary state and functions from init.lua
function LootView.render(ctx)
    ctx.maybeScanLootItems(true)
    
    -- Macro.Name may return "loot" or "loot.mac" depending on MQ version
    local lootMacName = (mq.TLO.Macro and mq.TLO.Macro.Name and (mq.TLO.Macro.Name() or ""):lower()) or ""
    local lootMacRunning = (lootMacName == "loot" or lootMacName == "loot.mac")
    
    ImGui.TextColored(ctx.theme.ToVec4(ctx.theme.Colors.Header), lootMacRunning and "Corpse Loot (macro)" or "Corpse Loot")
    ImGui.SameLine()
    if ImGui.Button("Refresh##Loot", ImVec2(70, 0)) then 
        ctx.scanLootItems(); ctx.setStatusMessage("Loot refreshed") 
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Rescan corpse items"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("Done", ImVec2(70, 0)) then
        mq.cmd('/notify LootWnd DoneButton leftmouseup')
        ctx.closeItemUI()
        ctx.uiState.configWindowOpen = false
        ctx.setStatusMessage("Loot closed")
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Close loot window and CoOpt UI Inventory Companion"); ImGui.EndTooltip() end
    ImGui.Separator()
    
    local lootCount, skipCount = 0, 0
    for _, it in ipairs(ctx.lootItems) do
        if it.willLoot then lootCount = lootCount + 1 else skipCount = skipCount + 1 end
    end
    ImGui.TextColored(ctx.theme.ToVec4(ctx.theme.Colors.Success), string.format("Will Loot: %d  ·  Will Skip: %d", lootCount, skipCount))
    ImGui.Separator()
    
    if ImGui.BeginTable("ItemUI_Loot", 7, ctx.uiState.tableFlags) then
        ImGui.TableSetupColumn("Slot", ImGuiTableColumnFlags.WidthFixed, 40, 0)
        ImGui.TableSetupColumn("Name", ImGuiTableColumnFlags.WidthStretch, 0, 1)
        ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthFixed, 75, 2)
        ImGui.TableSetupColumn("Auto", ImGuiTableColumnFlags.WidthFixed, 65, 3)
        ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, 90, 4)
        ImGui.TableSetupColumn("Actions", ImGuiTableColumnFlags.WidthFixed, 300, 5)
        ImGui.TableHeadersRow()
        
        for _, it in ipairs(ctx.lootItems) do
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text(tostring(it.slot))
            ImGui.TableNextColumn()
            local disp = it.name or ""
            if (it.stackSize or 1) > 1 then disp = disp .. string.format(" (x%d)", it.stackSize) end
            ImGui.Text(disp)
            ImGui.TableNextColumn()
            ImGui.Text(ItemUtils.formatValue(it.totalValue or 0))
            ImGui.TableNextColumn()
            if it.willLoot then
                ImGui.TextColored(ctx.theme.ToVec4(ctx.theme.Colors.Success), "Loot")
            else
                ImGui.TextColored(ctx.theme.ToVec4(ctx.theme.Colors.Error), "Skip")
            end
            ImGui.TableNextColumn()
            local lootStatusText = it.lootReason or (it.willLoot and "Loot" or "Skip")
            local lootStatusColor = it.willLoot and ctx.theme.ToVec4(ctx.theme.Colors.Success) or ctx.theme.ToVec4(ctx.theme.Colors.Error)
            if lootStatusText == "Epic" then
                lootStatusText = "EpicQuest"
                lootStatusColor = ctx.theme.ToVec4(ctx.theme.Colors.EpicQuest or ctx.theme.Colors.Muted)
            end
            ImGui.TextColored(lootStatusColor, lootStatusText)
            ImGui.TableNextColumn()
            ImGui.PushID("LootRow" .. (it.slot or 0) .. (it.name or ""))
            ctx.theme.PushLootButton()
            if ImGui.Button("Loot", ImVec2(50, 0)) then
                mq.cmdf('/itemnotify loot%d rightmouseup', it.slot or 1)
                ctx.setStatusMessage(string.format("Looting: %s", it.name or ""))
                ctx.uiState.pendingLootRescan = true
            end
            ctx.theme.PopButtonColors()
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Move item to first open inventory slot"); ImGui.EndTooltip() end
            ImGui.SameLine()
            ctx.theme.PushSkipButton()
            if ImGui.Button("Skip", ImVec2(50, 0)) then
                ctx.uiState.pendingLootRemove = ctx.uiState.pendingLootRemove or {}
                ctx.uiState.pendingLootRemove[#ctx.uiState.pendingLootRemove + 1] = it.slot
            end
            ctx.theme.PopButtonColors()
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Skip item, remove from view"); ImGui.EndTooltip() end
            ImGui.SameLine()
            if not it.willLoot then
                ctx.theme.PushLootButton()
                if ImGui.Button("Always Loot", ImVec2(80, 0)) then
                    local name = ctx.config.sanitizeItemName(it.name)
                    if name then
                        local list = ctx.config.parseList(ctx.config.readLootListValue("loot_always_exact.ini", "Items", "exact", ""))
                        local found = false
                        for _, s in ipairs(list) do if s == name then found = true; break end end
                        if not found then
                            list[#list + 1] = name
                            ctx.config.writeLootListValue("loot_always_exact.ini", "Items", "exact", ctx.config.joinList(list))
                            ctx.configLootLists.alwaysExact = list
                            ctx.invalidateLootConfigCache()
                            ctx.setStatusMessage(string.format("Added to Always Loot: %s", name))
                        end
                    end
                    mq.cmdf('/itemnotify loot%d rightmouseup', it.slot or 1)
                    ctx.uiState.pendingLootRescan = true
                end
                ctx.theme.PopButtonColors()
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Add to Always Loot list, then loot item"); ImGui.EndTooltip() end
                ImGui.SameLine()
            end
            if it.willLoot then
                ctx.theme.PushSkipButton()
                if ImGui.Button("Always Skip", ImVec2(80, 0)) then
                    local name = ctx.config.sanitizeItemName(it.name)
                    if name then
                        local list = ctx.config.parseList(ctx.config.readLootListValue("loot_skip_exact.ini", "Items", "exact", ""))
                        local found = false
                        for _, s in ipairs(list) do if s == name then found = true; break end end
                        if not found then
                            list[#list + 1] = name
                            ctx.config.writeLootListValue("loot_skip_exact.ini", "Items", "exact", ctx.config.joinList(list))
                            ctx.configLootLists.skipExact = list
                            ctx.invalidateLootConfigCache()
                            ctx.setStatusMessage(string.format("Added to Always Skip: %s", name))
                        end
                    end
                    ctx.uiState.pendingLootRemove = ctx.uiState.pendingLootRemove or {}
                    ctx.uiState.pendingLootRemove[#ctx.uiState.pendingLootRemove + 1] = it.slot
                end
                ctx.theme.PopButtonColors()
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Add to Always Skip list, remove from view"); ImGui.EndTooltip() end
            end
            ImGui.PopID()
        end
        ImGui.EndTable()
    end
    
    -- Process deferred loot actions (avoids modifying lootItems during iteration)
    if ctx.uiState.pendingLootRescan then
        ctx.uiState.pendingLootRescan = nil
        ctx.scanLootItems()
        if #ctx.lootItems == 0 then
            mq.cmd('/notify LootWnd DoneButton leftmouseup')
            ctx.setStatusMessage("Loot complete")
        end
    elseif ctx.uiState.pendingLootRemove and #ctx.uiState.pendingLootRemove > 0 then
        for _, slot in ipairs(ctx.uiState.pendingLootRemove) do
            if ctx.sortColumns and ctx.sortColumns.removeLootItemBySlot then ctx.sortColumns.removeLootItemBySlot(slot) end
        end
        ctx.uiState.pendingLootRemove = nil
        if #ctx.lootItems == 0 then
            mq.cmd('/notify LootWnd DoneButton leftmouseup')
            ctx.setStatusMessage("Loot complete")
        end
    end
end

return LootView
