--[[
    Bank View - Separate window showing live bank data or cached snapshot
    
    Part of ItemUI Phase 5: View Extraction
    Renders the bank window with online/offline modes
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')

local constants = require('itemui.constants')
local context = require('itemui.context')
local registry = require('itemui.core.registry')

local BankView = {}

-- Module interface: render bank window
-- Params: context table containing all necessary state and functions from init.lua
function BankView.render(ctx)
    if not registry.shouldDraw("bank") then return end
    
    local bankOpen = ctx.isBankWindowOpen and ctx.isBankWindowOpen() or false
    ctx.ensureBankCacheFromStorage()
    local list = bankOpen and ctx.bankItems or ctx.bankCache
    
    -- Window positioning: free-float with saved position; hub-relative default when 0,0 is set in main_window
    local bankX = ctx.layoutConfig.BankWindowX
    local bankY = ctx.layoutConfig.BankWindowY
    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    if bankX and bankY then
        ImGui.SetNextWindowPos(ImVec2(bankX, bankY), forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver)
    end
    
    -- Window size (Always when forceApply so revert takes effect)
    local w = ctx.layoutConfig.WidthBankPanel or constants.VIEWS.WidthBankPanel
    local h = ctx.layoutConfig.HeightBank or constants.VIEWS.HeightBank
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver)
    end
    
    -- Window flags - allow resizing unless UI is locked
    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end
    
    local winOpen, winVis = ImGui.Begin("CoOpt UI Bank Companion##ItemUIBank", registry.isOpen("bank"), windowFlags)
    registry.setWindowState("bank", winOpen, winOpen)
    
    if not winOpen then ImGui.End(); return end
    -- Escape closes this window via main Inventory Companion's LIFO handler only
    if not winVis then ImGui.End(); return end
    
    -- Save window size when resized (if unlocked)
    if not ctx.uiState.uiLocked then
        local currentW, currentH = ImGui.GetWindowSize()
        if currentW and currentH and currentW > 0 and currentH > 0 then
            ctx.layoutConfig.WidthBankPanel = currentW
            ctx.layoutConfig.HeightBank = currentH
        end
    end
    
    -- Save position when window is moved
    local currentX, currentY = ImGui.GetWindowPos()
    if currentX and currentY then
        if not ctx.layoutConfig.BankWindowX or math.abs(ctx.layoutConfig.BankWindowX - currentX) > 1 or
           not ctx.layoutConfig.BankWindowY or math.abs(ctx.layoutConfig.BankWindowY - currentY) > 1 then
            ctx.layoutConfig.BankWindowX = currentX
            ctx.layoutConfig.BankWindowY = currentY
            ctx.scheduleLayoutSave()
        end
    end
    
    -- Header
    ctx.theme.TextHeader("Bank")
    ImGui.SameLine()
    ctx.renderRefreshButton(ctx, "Refresh##BankHeader", "Rescan bank", function() ctx.scanBank() end, { width = 80, messageBefore = "Scanning bank...", messageAfter = "Bank refreshed" })
    ImGui.Separator()
    
    -- Bank status
    if bankOpen then
        ctx.theme.TextSuccess("Online")
        ImGui.SameLine()
        ctx.theme.TextInfo("— Shift+click item to move to inventory")
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Bank window is open; hold Shift and left-click an item to move it to inventory"); ImGui.EndTooltip() end
    else
        ctx.theme.TextWarning("Offline")
        ImGui.SameLine()
        ctx.theme.TextMuted(ctx.perfCache.lastBankCacheTime > 0 and string.format("(last: %s)", os.date("%m/%d %H:%M", ctx.perfCache.lastBankCacheTime)) or "(no data)")
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Bank window closed; showing last saved snapshot"); ImGui.EndTooltip() end
    end
    ImGui.Separator()
    
    -- Search
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(120)
    ctx.uiState.searchFilterBank, _ = ImGui.InputText("##BankSearch", ctx.uiState.searchFilterBank)
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Filter bank items by name"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("X##BankSearchClear", ImVec2(22, 0)) then ctx.uiState.searchFilterBank = "" end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Clear search"); ImGui.EndTooltip() end
    if bankOpen then
        ImGui.SameLine()
        ctx.renderRefreshButton(ctx, "Refresh##Bank", "Rescan bank", function() ctx.scanBank() end, { width = 60, messageBefore = "Scanning bank...", messageAfter = "Bank refreshed" })
    end
    ImGui.Separator()
    
    local hasCursor = ctx.hasItemOnCursor()
    local lp = ctx.uiState.lastPickup
    -- Pre-filter bank list
    local filteredBank = {}
    local searchBankLower = (ctx.uiState.searchFilterBank or ""):lower()
    for _, item in ipairs(list) do
        if searchBankLower == "" or (item.name or ""):lower():find(searchBankLower, 1, true) then
            if not ctx.shouldHideRowForCursor(item, "bank") then
                table.insert(filteredBank, item)
            end
        end
    end
    
    -- Build fixed columns list (from config; ImGui SaveSettings handles sort/order)
    local visibleCols = ctx.getFixedColumns("Bank")
    local nCols = #visibleCols
    if nCols == 0 then 
        nCols = 6
        visibleCols = {
            {key = "Name", label = "Name", numeric = false},
            {key = "Bag", label = "Bag", numeric = true},
            {key = "Slot", label = "Slot", numeric = true},
            {key = "Value", label = "Value", numeric = true},
            {key = "Stack", label = "Stack", numeric = true},
            {key = "Type", label = "Type", numeric = false}
        }
    end
    
    if ImGui.BeginTable("ItemUI_Bank", nCols, ctx.uiState.tableFlags) then
        -- Setup columns dynamically
        local function simpleHash(str)
            local h = 0
            for i = 1, #str do
                h = (h * 31 + string.byte(str, i)) % 2147483647
            end
            return h
        end
        
        local bankSortCol = (ctx.sortState.bankColumn and type(ctx.sortState.bankColumn) == "string" and ctx.sortState.bankColumn) or "Name"
        for i, colDef in ipairs(visibleCols) do
            -- Set base flags: Name = WidthStretch, others = WidthFixed
            local flags = (colDef.key == "Name") and ImGuiTableColumnFlags.WidthStretch or ImGuiTableColumnFlags.WidthFixed
            
            -- Add DefaultSort flag if this is the current sort column
            if colDef.key == bankSortCol then
                flags = bit32.bor(flags, ImGuiTableColumnFlags.DefaultSort)
            end
            
            -- Set width: 0 for Name (stretch column), specific widths for fixed columns
            local width = 0
            if colDef.key ~= "Name" then
                if ctx.columnAutofitWidths["Bank"][colDef.key] then
                    width = ctx.columnAutofitWidths["Bank"][colDef.key]
                else
                    -- Default widths
                    if colDef.key == "Bag" then width = 36
                    elseif colDef.key == "Slot" then width = 36
                    elseif colDef.key == "Value" then width = 60
                    elseif colDef.key == "Stack" then width = 40
                    elseif colDef.key == "Type" then width = 70
                    elseif colDef.key == "Icon" then width = 28
                    else width = 60 end
                end
            end
            local userID = simpleHash(colDef.key)
            ImGui.TableSetupColumn(colDef.label, flags, width, userID)
        end
        ImGui.TableSetupScrollFreeze(0, 1)
        
        -- Build column mapping for sort handler
        local colKeyByUserID = {}
        for i, colDef in ipairs(visibleCols) do
            colKeyByUserID[simpleHash(colDef.key)] = colDef.key
        end
        
        -- Handle sort clicks
        local sortSpecs = ImGui.TableGetSortSpecs()
        if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
            local spec = sortSpecs:Specs(1)
            if spec then
                local userID = spec.ColumnUserID
                local colKey = colKeyByUserID[userID]
                if not colKey and visibleCols[spec.ColumnIndex + 1] then
                    colKey = visibleCols[spec.ColumnIndex + 1].key
                end
                if not colKey then colKey = ctx.getColumnKeyByIndex("Bank", spec.ColumnIndex + 1) end
                if colKey then
                    ctx.sortState.bankColumn = colKey
                    ctx.sortState.bankDirection = spec.SortDirection
                    ctx.scheduleLayoutSave()
                    ctx.flushLayoutSave()
                end
            end
            sortSpecs.SpecsDirty = false
        end
        
        -- Capture header rect before/after TableHeadersRow for header-only right-click
        local headerTop = ImGui.GetCursorScreenPosVec and ImGui.GetCursorScreenPosVec()
        ImGui.TableHeadersRow()
        local bodyTop = ImGui.GetCursorScreenPosVec and ImGui.GetCursorScreenPosVec()
        -- Right-click on column headers only (not body) to show column visibility menu
        local hoveredColumn = ImGui.TableGetHoveredColumn()
        local inHeader = false
        if headerTop and bodyTop and ImGui.IsMouseHoveringRect then
            local w = (ImGui.GetWindowWidth and ImGui.GetWindowWidth()) or 9999
            inHeader = ImGui.IsMouseHoveringRect(
                ImVec2(headerTop.x, headerTop.y),
                ImVec2(headerTop.x + w, bodyTop.y),
                false)
        end
        if hoveredColumn >= 0 and ImGui.IsMouseReleased(ImGuiMouseButton.Right) and inHeader then
            ImGui.OpenPopup("ColumnMenu_Bank")
        end
        
        if ImGui.BeginPopup("ColumnMenu_Bank") then
            ImGui.Text("Columns (changes apply on next open)")
            ImGui.Separator()
            for _, colDef in ipairs(ctx.availableColumns["Bank"] or {}) do
                local inFixed = ctx.isColumnInFixedSet("Bank", colDef.key)
                if ImGui.MenuItem(colDef.label, "", inFixed) then
                    ctx.toggleFixedColumn("Bank", colDef.key)
                    ctx.setStatusMessage("Column changes apply when you reopen CoOpt UI Inventory Companion")
                end
            end
            ImGui.Separator()
            if ImGui.MenuItem("Autofit Columns") then
                ctx.autofitColumns("Bank", filteredBank, visibleCols)
            end
            ImGui.EndPopup()
        end
        
        -- Sort cache (Phase 3: shared getSortedList helper)
        local bankSortKey = (ctx.sortState.bankColumn and type(ctx.sortState.bankColumn) == "string" and ctx.sortState.bankColumn) or "Name"
        local bankSortDir = ctx.sortState.bankDirection or ImGuiSortDirection.Ascending
        local bankFilterStr = ctx.uiState.searchFilterBank or ""
        local bankHidingNow = not not (lp and lp.source == "bank" and lp.bag and lp.slot)
        local validity = {
            filter = bankFilterStr,
            hidingSlot = bankHidingNow,
            fullListLen = #list,
            nFiltered = #filteredBank,
        }
        filteredBank = ctx.getSortedList(ctx.perfCache.bank, filteredBank, bankSortKey, bankSortDir, validity, "Bank", ctx.sortColumns)

        local nBank = #filteredBank
        local clipperBank = ImGuiListClipper.new()
        clipperBank:Begin(nBank)
        while clipperBank:Step() do
            for i = clipperBank.DisplayStart + 1, clipperBank.DisplayEnd do
                local item = filteredBank[i]
                if not item then goto bank_continue end
                ImGui.TableNextRow()
                local loc = ctx.uiState.itemDisplayLocateRequest
                if loc and loc.source == "bank" and loc.bag == item.bag and loc.slot == item.slot then
                    ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, ImGui.GetColorU32(ImVec4(0.25, 0.45, 0.75, 0.45)))
                end
                local rid = "bank_" .. item.bag .. "_" .. item.slot
                ImGui.PushID(rid)
                if rawget(item, "_statsPending") then
                    if ctx.uiState then ctx.uiState.pendingStatRescanBags = ctx.uiState.pendingStatRescanBags or {}; ctx.uiState.pendingStatRescanBags[item.bag] = true end
                    for _ in ipairs(visibleCols) do ImGui.TableNextColumn(); ImGui.TextColored(ImVec4(0.7, 0.7, 0.5, 1), "...") end
                    ImGui.PopID()
                    goto bank_continue
                end
                -- Render columns dynamically based on visibleCols
                for _, colDef in ipairs(visibleCols) do
                    ImGui.TableNextColumn()
                    local colKey = colDef.key
                    
                    if colKey == "Name" then
                        -- Name column with special interaction logic
                        local dn = item.name or ""
                        if (item.stackSize or 1) > 1 then dn = dn .. string.format(" (x%d)", item.stackSize) end
                        local nameColor = ctx.getSellStatusNameColor and ctx.getSellStatusNameColor(ctx, item) or ImVec4(1, 1, 1, 1)
                        ImGui.PushStyleColor(ImGuiCol.Text, nameColor)
                        ImGui.Selectable(dn, false, ImGuiSelectableFlags.None, ImVec2(0,0))
                        ImGui.PopStyleColor(1)
                        if bankOpen then
                            if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
                                if ImGui.GetIO().KeyShift then
                                    ctx.moveBankToInv(item.bag, item.slot)
                                elseif not hasCursor then
                                    if item.stackSize and item.stackSize > 1 then
                                        ctx.uiState.pendingQuantityPickup = {
                                            bag = item.bag,
                                            slot = item.slot,
                                            source = "bank",
                                            maxQty = item.stackSize,
                                            itemName = item.name
                                        }
                                        ctx.uiState.pendingQuantityPickupTimeoutAt = mq.gettime() + constants.TIMING.QUANTITY_PICKUP_TIMEOUT_MS
                                        ctx.uiState.quantityPickerValue = tostring(item.stackSize)
                                        ctx.uiState.quantityPickerMax = item.stackSize
                                        -- Set lastPickup so activation guard does not treat the upcoming stack pickup as unexpected
                                        ctx.uiState.lastPickup.bag = item.bag
                                        ctx.uiState.lastPickup.slot = item.slot
                                        ctx.uiState.lastPickup.source = "bank"
                                        ctx.uiState.lastPickupSetThisFrame = true
                                    else
                                        ctx.pickupFromSlot(item.bag, item.slot, "bank")
                                    end
                                end
                            end
                        end
                        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                            ImGui.OpenPopup("ItemContextBankIcon_" .. rid)
                        end
                    elseif colKey == "Icon" then
                        if ctx.drawItemIcon then
                            ctx.drawItemIcon(item.icon)
                        else
                            ImGui.Text(tostring(item.icon or 0))
                        end
                        if ImGui.IsItemHovered() then
                            local showItem = (ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip(item, "bank")) or item
                            local opts = { source = "bank", bag = item.bag, slot = item.slot }
                            local effects, w, h = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
                            opts.effects = effects
                            ItemTooltip.beginItemTooltip(w, h)
                            ImGui.Text("Stats")
                            ImGui.Separator()
                            ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
                            ImGui.EndTooltip()
                        end
                        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                            ImGui.OpenPopup("ItemContextBankIcon_" .. rid)
                        end
                        ctx.renderItemContextMenu(ctx, item, { source = "bank", popupId = "ItemContextBankIcon_" .. rid, bankOpen = bankOpen, hasCursor = hasCursor })
                    elseif colKey == "Status" then
                        local statusText, willSell = "", false
                        if item.sellReason ~= nil and item.willSell ~= nil then
                            statusText = item.sellReason or "—"
                            willSell = item.willSell
                        elseif ctx.getSellStatusForItem then
                            statusText, willSell = ctx.getSellStatusForItem(item)
                        end
                        if statusText == "" then statusText = "—" end
                        local statusColor = willSell and ctx.theme.ToVec4(ctx.theme.Colors.Error) or ctx.theme.ToVec4(ctx.theme.Colors.Success)
                        if statusText == "Epic" then
                            statusText = "EpicQuest"
                            statusColor = ctx.theme.ToVec4(ctx.theme.Colors.EpicQuest or ctx.theme.Colors.Muted)
                        elseif statusText == "NoDrop" or statusText == "NoTrade" then
                            statusColor = ctx.theme.ToVec4(ctx.theme.Colors.Error)
                        elseif statusText == "RerollList" and ctx.theme.Colors.RerollList then
                            statusColor = ctx.theme.ToVec4(ctx.theme.Colors.RerollList)
                        end
                        ImGui.TextColored(statusColor, statusText)
                    else
                        -- All other columns use dynamic display text
                        ImGui.Text(ctx.sortColumns.getCellDisplayText(item, colKey, "Bank"))
                    end
                end
                
                ImGui.PopID()
                ::bank_continue::
            end
        end
        ImGui.EndTable()
    end
    
    ImGui.End()
end

-- Registry: Bank module (4.2 state ownership — window in registry only)
registry.register({
    id          = "bank",
    label       = "Bank",
    buttonWidth = 60,
    tooltip     = "View bank items; shift+click to move to inventory",
    layoutKeys  = { x = "BankWindowX", y = "BankWindowY" },
    render      = function(refs)
        local ctx = context.build()
        ctx = context.extend(ctx)
        BankView.render(ctx)
    end,
})

return BankView
