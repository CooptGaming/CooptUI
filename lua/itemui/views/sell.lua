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
        local invO, bankO, merchO = (mq.TLO.Window("InventoryWindow") and mq.TLO.Window("InventoryWindow").Open()) or false, (ctx.windowState and ctx.windowState.isBankWindowOpen and ctx.windowState.isBankWindowOpen()), (ctx.windowState and ctx.windowState.isMerchantWindowOpen and ctx.windowState.isMerchantWindowOpen())
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
    if ImGui.Button("Refresh##Sell", ImVec2(70, 0)) then ctx.setStatusMessage("Scanning..."); ctx.scanInventory(); ctx.scanSellItems(); ctx.setStatusMessage("Refreshed") end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Rescan inventory and sell list"); ImGui.EndTooltip() end
    ImGui.SameLine()
    ctx.uiState.showOnlySellable = ImGui.Checkbox("Show only sellable", ctx.uiState.showOnlySellable)
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Hide items that won't be sold"); ImGui.EndTooltip() end
    ImGui.SameLine()
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(160)
    ctx.uiState.searchFilterInv, _ = ImGui.InputText("##InvSearch", ctx.uiState.searchFilterInv)
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Filter items by name"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("X##InvSearchClear", ImVec2(22, 0)) then ctx.uiState.searchFilterInv = "" end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Clear search"); ImGui.EndTooltip() end
    ImGui.Separator()
    
    -- Sell progress bar: prominent placement when sell.mac is running (visible in sell view)
    do
        local macroName = mq.TLO.Macro and mq.TLO.Macro.Name and (mq.TLO.Macro.Name() or "") or ""
        local mn = macroName:lower()
        -- Macro.Name may return "sell" or "sell.mac" depending on MQ version
        local sellMacRunning = (mn == "sell" or mn == "sell.mac")
        if sellMacRunning and ctx.perfCache.sellLogPath then
            local progPath = ctx.perfCache.sellLogPath .. "\\sell_progress.ini"
            local totalStr = mq.TLO.Ini.File(progPath).Section("Progress").Key("total").Value()
            local currentStr = mq.TLO.Ini.File(progPath).Section("Progress").Key("current").Value()
            local remainingStr = mq.TLO.Ini.File(progPath).Section("Progress").Key("remaining").Value()
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
                ctx.theme.PushProgressBarColors()
                if total > 0 then
                    -- Fixed-width format to prevent layout shift when numbers change (reduces flashing)
                    local overlay = string.format("%3d / %3d sold  (%3d remaining)", current, total, remaining)
                    ImGui.ProgressBar(ctx.sellMacState.smoothedFrac, ImVec2(-1, 24), overlay)
                else
                    ctx.theme.TextSuccess("Sell macro running...")
                end
                ctx.theme.PopProgressBarColors()
            end
            ImGui.EndChild()
            ImGui.Separator()
        end
    end
    
    -- Summary: Keeping / Selling / Protected counts and sell total (one pass over sellItems)
    local keepCount, sellCount, protectCount = 0, 0, 0
    local sellTotal = 0
    for _, it in ipairs(ctx.sellItems) do
        if it.inKeep then keepCount = keepCount + 1 end
        if it.willSell then sellCount = sellCount + 1; sellTotal = sellTotal + (it.totalValue or 0) end
        if it.isProtected then protectCount = protectCount + 1 end
    end
    ctx.theme.TextInfo(string.format("Keeping: %d  ·  Selling: %d  ·  Protected: %d", keepCount, sellCount, protectCount))
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Keeping = in keep list (never sell); Selling = marked to sell; Protected = blocked by flags"); ImGui.EndTooltip() end
    ImGui.SameLine()
    ctx.theme.TextWarning(string.format("Sell total: %s", ItemUtils.formatValue(sellTotal)))
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Total value of items that will be sold"); ImGui.EndTooltip() end
    ImGui.Separator()
    
    -- Cache once per frame to avoid TLO/string work per row
    local hasCursor = ctx.hasItemOnCursor()
    local searchLower = (ctx.uiState.searchFilterInv or ""):lower()
    
    -- Pre-filter the list BEFORE clipping (fixes scrollbar and clipper behavior)
    local filteredSellItems = {}
    for _, item in ipairs(ctx.sellItems) do
        local passFilter = true
        if ctx.uiState.showOnlySellable and not item.willSell then passFilter = false end
        if passFilter and searchLower ~= "" and not (item.name or ""):lower():find(searchLower, 1, true) then passFilter = false end
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
        
        -- Sort cache: skip sort when key/dir/filter/list unchanged
        local sellSortKey = type(ctx.sortState.sellColumn) == "string" and ctx.sortState.sellColumn or (type(ctx.sortState.sellColumn) == "number" and ctx.sortState.sellColumn or "")
        local sellSortDir = ctx.sortState.sellDirection or ImGuiSortDirection.Ascending
        local sellCacheValid = ctx.perfCache.sell.key == sellSortKey and ctx.perfCache.sell.dir == sellSortDir and ctx.perfCache.sell.filter == searchLower and ctx.perfCache.sell.showOnly == ctx.uiState.showOnlySellable and ctx.perfCache.sell.n == #ctx.sellItems and ctx.perfCache.sell.nFiltered == #filteredSellItems and #ctx.perfCache.sell.sorted > 0
        if not sellCacheValid then
            if type(ctx.sortState.sellColumn) == "string" then
                local sortKey = ctx.sortState.sellColumn
                local isNumeric = (sortKey == "Value" or sortKey == "Stack")
                table.sort(filteredSellItems, function(a, b)
                    local av = ctx.sortColumns.getSortValByKey(a, sortKey, "Sell")
                    local bv = ctx.sortColumns.getSortValByKey(b, sortKey, "Sell")
                    if isNumeric then
                        local an, bn = tonumber(av) or 0, tonumber(bv) or 0
                        if ctx.sortState.sellDirection == ImGuiSortDirection.Ascending then return an < bn else return an > bn end
                    else
                        local as, bs = tostring(av or ""):lower(), tostring(bv or ""):lower()
                        if ctx.sortState.sellDirection == ImGuiSortDirection.Ascending then return as < bs else return as > bs end
                    end
                end)
            elseif type(ctx.sortState.sellColumn) == "number" and ctx.sortState.sellColumn >= 3 and ctx.sortState.sellColumn <= 7 then
                table.sort(filteredSellItems, ctx.sortColumns.makeComparator(ctx.sortColumns.getSellSortVal, ctx.sortState.sellColumn, ctx.sortState.sellDirection, {5, 6}))
            end
            ctx.perfCache.sell.key, ctx.perfCache.sell.dir, ctx.perfCache.sell.filter = sellSortKey, sellSortDir, searchLower
            ctx.perfCache.sell.showOnly, ctx.perfCache.sell.n, ctx.perfCache.sell.nFiltered, ctx.perfCache.sell.sorted = ctx.uiState.showOnlySellable, #ctx.sellItems, #filteredSellItems, filteredSellItems
        else
            filteredSellItems = ctx.perfCache.sell.sorted
        end
        
        local n = #filteredSellItems
        local clipper = ImGuiListClipper.new()
        clipper:Begin(n)
        while clipper:Step() do
            for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                local item = filteredSellItems[i]
                if not item then goto continue end  -- safety check
                ImGui.TableNextRow()
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
                    ItemTooltip.beginItemTooltip()
                    ImGui.Text("Stats")
                    ImGui.Separator()
                    local showItem = (ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip(item, "inv")) or item
                    ItemTooltip.renderStatsTooltip(showItem, ctx, { source = "inv" })
                    ImGui.EndTooltip()
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
                    if actualInKeep then
                        if ctx.removeFromKeepList(item.name) then
                            ctx.updateSellStatusForItemName(item.name, false, item.inJunk)
                        end
                    else
                        if ctx.addToKeepList(item.name) then
                            ctx.updateSellStatusForItemName(item.name, true, false)
                        end
                    end
                end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Add/remove from keep list (never sell)"); ImGui.EndTooltip() end
                ctx.theme.PopButtonColors()
                ImGui.SameLine()
                ctx.theme.PushJunkButton(not actualInJunk)  -- disabled style when not in junk list
                if ImGui.Button("Junk##"..rid, ImVec2(58, 0)) then
                    if actualInJunk then
                        if ctx.removeFromJunkList(item.name) then
                            ctx.updateSellStatusForItemName(item.name, item.inKeep, false)
                        end
                    else
                        if ctx.addToJunkList(item.name) then
                            ctx.updateSellStatusForItemName(item.name, false, true)
                        end
                    end
                end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Add/remove from Always sell list"); ImGui.EndTooltip() end
                ctx.theme.PopButtonColors()
                ImGui.TableNextColumn()
                local dn = item.name or ""
                if (item.stackSize or 1) > 1 then dn = dn .. string.format(" (x%d)", item.stackSize) end
                ImGui.Selectable(dn, false, ImGuiSelectableFlags.None, ImVec2(0,0))
                if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) and not hasCursor then
                    ctx.uiState.lastPickup.bag, ctx.uiState.lastPickup.slot, ctx.uiState.lastPickup.source = item.bag, item.slot, "inv"
                    mq.cmdf('/itemnotify in pack%d %d leftmouseup', item.bag, item.slot)
                end
                if ImGui.IsItemHovered() and ImGui.IsMouseReleased(ImGuiMouseButton.Right) then
                    if hasCursor then ctx.removeItemFromCursor()
                    else
                        local tlo = mq.TLO.Me.Inventory("pack"..item.bag).Item(item.slot)
                        if tlo and tlo.ID() and tlo.ID()>0 then tlo.Inspect() end
                    end
                end
                ImGui.TableNextColumn()
                local statusText = item.sellReason or ""
                local statusColor = item.willSell and ctx.theme.ToVec4(ctx.theme.Colors.Warning) or ctx.theme.ToVec4(ctx.theme.Colors.Success)
                if item.isProtected then
                    -- Show specific reason (EpicQuest, NoDrop, NoTrade, etc.) so users know why it's protected
                    statusText = (item.sellReason and item.sellReason ~= "") and item.sellReason or "Protected"
                    if statusText == "Epic" then
                        statusText = "EpicQuest"
                        statusColor = ctx.theme.ToVec4(ctx.theme.Colors.EpicQuest or ctx.theme.Colors.Muted)
                    else
                        statusColor = ctx.theme.ToVec4(ctx.theme.Colors.Error)
                    end
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
