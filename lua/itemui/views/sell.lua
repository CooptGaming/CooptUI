--[[
    Sell View - Merchant view for selling items
    
    Part of ItemUI Phase 5: View Extraction
    Renders the sell view when merchant window is open
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')

local SellView = {}

-- Module interface: render sell view content
-- Params: context table containing all necessary state and functions from init.lua
function SellView.render(ctx, simulateSellView)
    -- Sell view: filters and columns tuned for selling
    if #ctx.sellItems == 0 then
        local invO, bankO, merchO = (mq.TLO.Window("InventoryWindow") and mq.TLO.Window("InventoryWindow").Open()) or false, (ctx.isBankWindowOpen and ctx.isBankWindowOpen() or false), (ctx.isMerchantWindowOpen and ctx.isMerchantWindowOpen() or false)
        ctx.maybeScanInventory(invO); ctx.maybeScanSellItems(merchO)
    end
    
    if simulateSellView then
        ctx.theme.TextWarning("[Setup Mode: Simulated Sell View]")
        ImGui.SameLine()
    end
    
    if ImGui.Button("Auto Sell", ImVec2(100, 0)) then
        if not simulateSellView then
            ctx.uiState.autoSellRequested = true
            ctx.setStatusMessage("Running sell macro...")
        end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(simulateSellView and "Simulated view - Auto Sell disabled" or "Run /macro sell confirm to sell marked items"); ImGui.EndTooltip() end
    if not simulateSellView then
        ImGui.SameLine()
        ctx.theme.TextMuted("/macro sell confirm")
    end
    ImGui.SameLine()
    if ImGui.Button("Refresh##Sell", ImVec2(70, 0)) then ctx.setStatusMessage("Scanning..."); ctx.refreshAllScans() end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Rescan inventory, bank (if open), sell list, and loot"); ImGui.EndTooltip() end
    ImGui.SameLine()
    ctx.uiState.showOnlySellable = ImGui.Checkbox("Show only sellable", ctx.uiState.showOnlySellable)
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Hide items that won't be sold"); ImGui.EndTooltip() end
    ImGui.SameLine()
    do
        local ch, txt = ctx.renderSearchLine("InvSearchSell", ctx.uiState.searchFilterInv, 160, "Filter items by name")
        if ch then ctx.uiState.searchFilterInv = txt end
    end
    ImGui.Separator()
    
    -- Sell progress bar: prominent placement when sell.mac is running (visible in sell view)
    do
        local macroName = mq.TLO.Macro and mq.TLO.Macro.Name and (mq.TLO.Macro.Name() or "") or ""
        local mn = macroName:lower()
        -- Macro.Name may return "sell" or "sell.mac" depending on MQ version
        local sellMacRunning = (mn == "sell" or mn == "sell.mac")
        if sellMacRunning and ctx.perfCache.sellLogPath then
            local config = require('itemui.config')
            local progPath = ctx.perfCache.sellLogPath .. "\\sell_progress.ini"
            local totalStr = config.safeIniValueByPath(progPath, "Progress", "total", "0")
            local currentStr = config.safeIniValueByPath(progPath, "Progress", "current", "0")
            local remainingStr = config.safeIniValueByPath(progPath, "Progress", "remaining", "0")
            local total = tonumber(totalStr) or 0
            local current = tonumber(currentStr) or 0
            local remaining = tonumber(remainingStr) or 0
            -- Smooth bar: lerp toward target to avoid jumpy updates and flashing
            local targetFrac = (total > 0) and math.min(1, math.max(0, current / total)) or 0
            local lerpSpeed = 0.35  -- higher = faster catch-up
            ctx.sellMacState.smoothedFrac = ctx.sellMacState.smoothedFrac + (targetFrac - ctx.sellMacState.smoothedFrac) * lerpSpeed
            ctx.sellMacState.smoothedFrac = math.min(1, math.max(0, ctx.sellMacState.smoothedFrac))
            -- Fixed-size child to prevent layout shift (reduces flashing)
            if ImGui.BeginChild("##SellProgressBar", ImVec2(-1, 32), false, ImGuiWindowFlags.NoScrollbar) then
                if total > 0 then
                    local overlay = string.format("%3d / %3d sold  (%3d remaining)", current, total, remaining)
                    ctx.renderThemedProgressBar(ctx.sellMacState.smoothedFrac, ImVec2(-1, 24), overlay)
                else
                    ctx.theme.TextSuccess("Sell macro running...")
                end
            end
            ImGui.EndChild()
            ImGui.Separator()
        end
    end
    
    -- Summary: Keeping / Selling / Protected counts, trust indicator, augment warning (one pass over sellItems)
    local keepCount, sellCount, protectCount = 0, 0, 0
    local sellTotal = 0
    local keepInSellQueue = 0  -- items with inKeep=true AND willSell=true (trust check)
    local augmentSellCount = 0 -- augmentation-type items that will be sold
    for _, it in ipairs(ctx.sellItems) do
        if it.inKeep then keepCount = keepCount + 1 end
        if it.willSell then
            sellCount = sellCount + 1
            sellTotal = sellTotal + (it.totalValue or 0)
            if it.inKeep then keepInSellQueue = keepInSellQueue + 1 end
            if it.type and it.type:lower() == "augmentation" then augmentSellCount = augmentSellCount + 1 end
        end
        if it.isProtected then protectCount = protectCount + 1 end
    end
    ctx.theme.TextInfo(string.format("Keeping: %d  ·  Selling: %d  ·  Protected: %d", keepCount, sellCount, protectCount))
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Keeping = in keep list (never sell); Selling = marked to sell; Protected = blocked by flags"); ImGui.EndTooltip() end
    ImGui.SameLine()
    ctx.theme.TextWarning(string.format("Sell total: %s", ItemUtils.formatValue(sellTotal)))
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Total value of items that will be sold"); ImGui.EndTooltip() end
    -- C2: Trust indicator
    if keepInSellQueue > 0 then
        ImGui.TextColored(ImVec4(1, 0.3, 0.3, 1), string.format("!! %d keep-list items still in sell queue -- review before selling", keepInSellQueue))
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Items marked Keep are still set to Sell. This may indicate a filter conflict."); ImGui.EndTooltip() end
    else
        ImGui.TextColored(ImVec4(0.3, 0.9, 0.3, 1), "All keep-list items protected")
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("No items with inKeep=true have willSell=true"); ImGui.EndTooltip() end
    end
    -- C3: Augment safety banner
    if augmentSellCount > 0 then
        ImGui.TextColored(ImVec4(1, 0.85, 0.2, 1), string.format("! %d augment(s) will be sold -- review carefully", augmentSellCount))
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Augmentation-type items are in the sell queue. Consider adding them to Never Sell or Protected Types."); ImGui.EndTooltip() end
    end
    ImGui.Separator()
    
    -- Cache once per frame to avoid TLO/string work per row
    local hasCursor = ctx.hasItemOnCursor()
    local searchLower = (ctx.uiState.searchFilterInv or ""):lower()
    
    -- Pre-filter the list BEFORE clipping (fixes scrollbar and clipper behavior)
    local filteredSellItems = {}
    local lp = ctx.uiState.lastPickup
    for _, item in ipairs(ctx.sellItems) do
        local passFilter = true
        if ctx.uiState.showOnlySellable and not item.willSell then passFilter = false end
        if passFilter and searchLower ~= "" and not (item.name or ""):lower():find(searchLower, 1, true) then passFilter = false end
        if passFilter and ctx.shouldHideRowForCursor(item, "inv") then passFilter = false end
        if passFilter then table.insert(filteredSellItems, item) end
    end
    
    local nCols = 7  -- Icon, Sell Keep Junk (left), Name, Status, Value, Stack, Type
    if ImGui.BeginTable("ItemUI_InvSell", nCols, ctx.uiState.tableFlags) then
        -- Use autofit widths if available, otherwise defaults
        local sellActionWidth = ctx.columnAutofitWidths["Sell"]["Action"] or 200
        local sellStatusWidth = ctx.columnAutofitWidths["Sell"]["Status"] or 110
        local sellValueWidth = ctx.columnAutofitWidths["Sell"]["Value"] or 85
        local sellStackWidth = ctx.columnAutofitWidths["Sell"]["Stack"] or 55
        local sellTypeWidth = ctx.columnAutofitWidths["Sell"]["Type"] or 100
        
        local sellSortCol = (ctx.sortState.sellColumn and type(ctx.sortState.sellColumn) == "string" and ctx.sortState.sellColumn) or "Name"
        local sellColKeys = {"", "", "Name", "Status", "Value", "Stack", "Type"}  -- col 1 = Icon, col 2 = Action
        ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 28, 0)  -- Icon (first column)
        ImGui.TableSetupColumn("Sell Keep Junk", ImGuiTableColumnFlags.WidthFixed, sellActionWidth, 0)
        for i = 1, 5 do
            local key = sellColKeys[i + 2] or "Name"
            local flags = (key == "Name") and ImGuiTableColumnFlags.WidthStretch or ImGuiTableColumnFlags.WidthFixed
            if key == sellSortCol then flags = bit32.bor(flags, ImGuiTableColumnFlags.DefaultSort) end
            local w = (i == 1) and 0 or (i == 2 and sellStatusWidth or i == 3 and sellValueWidth or i == 4 and sellStackWidth or sellTypeWidth)
            ImGui.TableSetupColumn(key, flags, w, i)
        end
        ImGui.TableSetupScrollFreeze(2, 1)  -- Freeze Icon + Action columns
        
        -- Handle sort clicks
        local sortSpecs = ImGui.TableGetSortSpecs()
        if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
            local spec = sortSpecs:Specs(1)
            if spec then
                local col = spec.ColumnIndex + 1  -- 0-based to 1-based
                if col >= 3 and col <= 7 then     -- Skip Icon (1) and Action (2) columns
                    -- Map column index to column key for sell view
                    local colKeys = {"", "", "Name", "Status", "Value", "Stack", "Type"}
                    ctx.sortState.sellColumn = colKeys[col] or "Name"
                    ctx.sortState.sellDirection = spec.SortDirection
                    ctx.scheduleLayoutSave()
                    ctx.flushLayoutSave()  -- Persist immediately so sort survives Lua reload / game restart
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
            ImGui.OpenPopup("ColumnMenu_Sell")
        end
        
        if ImGui.BeginPopup("ColumnMenu_Sell") then
            ImGui.Text("Column Visibility")
            ImGui.Separator()
            for _, colDef in ipairs(ctx.availableColumns["Sell"] or {}) do
                local isVisible = ctx.columnVisibility["Sell"][colDef.key] or false
                if ImGui.MenuItem(colDef.label, "", isVisible) then
                    ctx.columnVisibility["Sell"][colDef.key] = not isVisible
                    ctx.saveColumnVisibility()
                end
            end
            ImGui.Separator()
            if ImGui.MenuItem("Autofit Columns") then
                -- Create column definitions matching the sell view structure
                local sellCols = {
                    {key = "Icon", label = "Icon", numeric = true},
                    {key = "Action", label = "Sell Keep Junk", numeric = false},
                    {key = "Name", label = "Name", numeric = false},
                    {key = "Status", label = "Status", numeric = false},
                    {key = "Value", label = "Value", numeric = true},
                    {key = "Stack", label = "Stack", numeric = true},
                    {key = "Type", label = "Type", numeric = false}
                }
                ctx.autofitColumns("Sell", ctx.sellItems, sellCols)
            end
            ImGui.EndPopup()
        end
        
        -- Sort cache (Phase 3: shared getSortedList helper)
        local sellSortKey = type(ctx.sortState.sellColumn) == "string" and ctx.sortState.sellColumn or (type(ctx.sortState.sellColumn) == "number" and ctx.sortState.sellColumn or "")
        local sellSortDir = ctx.sortState.sellDirection or ImGuiSortDirection.Ascending
        local sellHidingNow = not not (lp and lp.source == "inv" and lp.bag and lp.slot)
        local validity = {
            filter = searchLower,
            hidingSlot = sellHidingNow,
            fullListLen = #ctx.sellItems,
            nFiltered = #filteredSellItems,
            showOnly = ctx.uiState.showOnlySellable,
        }
        filteredSellItems = ctx.getSortedList(ctx.perfCache.sell, filteredSellItems, sellSortKey, sellSortDir, validity, "Sell", ctx.sortColumns)

        local n = #filteredSellItems
        local clipper = ImGuiListClipper.new()
        clipper:Begin(n)
        while clipper:Step() do
            for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                local item = filteredSellItems[i]
                if not item then goto continue end  -- safety check
                ImGui.TableNextRow()
                local loc = ctx.uiState.itemDisplayLocateRequest
                if loc and loc.source == "inv" and loc.bag == item.bag and loc.slot == item.slot then
                    ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, ImGui.GetColorU32(ImVec4(0.25, 0.45, 0.75, 0.45)))
                end
                local rid = "sell_" .. item.bag .. "_" .. item.slot
                ImGui.PushID(rid)
                -- Use cached row state (no INI reads per frame); Keep/Junk handlers still call add/remove + updateSellStatusForItemName
                local actualInKeep = item.inKeep
                local actualInJunk = item.inJunk
                -- Column 1: Icon (same as inventory/bank: draw icon, hover = stats tooltip)
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
                if ImGui.BeginPopupContextItem("ItemContextSellIcon_" .. rid) then
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
                -- Column 2: Sell Keep Junk buttons
                ImGui.TableNextColumn()
                ctx.theme.PushDeleteButton()
                if ImGui.Button("Sell##"..rid, ImVec2(58, 0)) then ctx.queueItemForSelling(item) end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Sell Item to Vendor"); ImGui.EndTooltip() end
                ctx.theme.PopButtonColors()
                ImGui.SameLine()
                ctx.theme.PushKeepButton(not actualInKeep)  -- disabled style when not in keep list
                if ImGui.Button("Keep##"..rid, ImVec2(58, 0)) then
                    if ctx.applySellListChange then
                        if actualInKeep then ctx.applySellListChange(item.name, false, item.inJunk)
                        else ctx.applySellListChange(item.name, true, false) end
                    end
                end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Add/remove from keep list (never sell)"); ImGui.EndTooltip() end
                ctx.theme.PopButtonColors()
                ImGui.SameLine()
                ctx.theme.PushJunkButton(not actualInJunk)  -- disabled style when not in junk list
                if ImGui.Button("Junk##"..rid, ImVec2(58, 0)) then
                    if ctx.applySellListChange then
                        if actualInJunk then ctx.applySellListChange(item.name, item.inKeep, false)
                        else ctx.applySellListChange(item.name, false, true) end
                    end
                end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Add/remove from Always sell list"); ImGui.EndTooltip() end
                ctx.theme.PopButtonColors()
                ImGui.TableNextColumn()
                local dn = item.name or ""
                if (item.stackSize or 1) > 1 then dn = dn .. string.format(" (x%d)", item.stackSize) end
                ImGui.Selectable(dn, false, ImGuiSelectableFlags.None, ImVec2(0,0))
                if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) and not hasCursor then
                    ctx.pickupFromSlot(item.bag, item.slot, "inv")
                end
                if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                    if ctx.addItemDisplayTab then ctx.addItemDisplayTab(item, "inv") end
                end
                ImGui.TableNextColumn()
                -- Prefer row state (match Inventory/Bank); fallback to getSellStatusForItem so Status is never blank
                local statusText, willSell = "", false
                if item.sellReason ~= nil and item.willSell ~= nil then
                    statusText = item.sellReason or "—"
                    willSell = item.willSell
                elseif ctx.getSellStatusForItem then
                    statusText, willSell = ctx.getSellStatusForItem(item)
                    if statusText == "" then statusText = "—" end
                else
                    statusText = "—"
                end
                local statusColor = willSell and ctx.theme.ToVec4(ctx.theme.Colors.Warning) or ctx.theme.ToVec4(ctx.theme.Colors.Success)
                if statusText == "Epic" then
                    statusText = "EpicQuest"
                    statusColor = ctx.theme.ToVec4(ctx.theme.Colors.EpicQuest or ctx.theme.Colors.Muted)
                elseif statusText == "NoDrop" or statusText == "NoTrade" then
                    statusColor = ctx.theme.ToVec4(ctx.theme.Colors.Error)
                end
                ImGui.TextColored(statusColor, statusText)
                ImGui.TableNextColumn() ImGui.Text(ItemUtils.formatValue(item.totalValue or 0))
                ImGui.TableNextColumn() ImGui.Text(tostring(item.stackSize or 1))
                ImGui.TableNextColumn() ImGui.Text(item.type or "")
                ImGui.PopID()
                ::continue::
            end
        end
        ImGui.EndTable()
    end
end

return SellView
