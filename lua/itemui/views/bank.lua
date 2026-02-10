--[[
    Bank View - Separate window showing live bank data or cached snapshot
    
    Part of ItemUI Phase 5: View Extraction
    Renders the bank window with online/offline modes
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')

local BankView = {}

-- Constants
local BANK_WINDOW_WIDTH = 520
local BANK_WINDOW_HEIGHT = 600

-- Module interface: render bank window
-- Params: context table containing all necessary state and functions from init.lua
function BankView.render(ctx)
    if not ctx.uiState.bankWindowShouldDraw then return end
    
    local bankOpen = ctx.windowState and ctx.windowState.isBankWindowOpen and ctx.windowState.isBankWindowOpen()
    ctx.ensureBankCacheFromStorage()
    local list = bankOpen and ctx.bankItems or ctx.bankCache
    
    -- Window positioning
    local bankX = ctx.layoutConfig.BankWindowX
    local bankY = ctx.layoutConfig.BankWindowY
    
    if ctx.uiState.syncBankWindow then
        -- When synced, use the position calculated in renderUI (stored in layoutConfig)
        -- This position is updated every frame when sync is enabled
        if bankX and bankY then
            ImGui.SetNextWindowPos(ImVec2(bankX, bankY), ImGuiCond.Always)
        end
    else
        -- When not synced, use saved position or calculate initial position
        if bankX and bankY and bankX ~= 0 and bankY ~= 0 then
            -- Use saved position
            ImGui.SetNextWindowPos(ImVec2(bankX, bankY), ImGuiCond.FirstUseEver)
        elseif ctx.uiState.alignToContext then
            -- Calculate initial position relative to ItemUI (if snapping is enabled)
            local invWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
            if invWnd and invWnd.Open and invWnd.Open() then
                local invX, invY = tonumber(invWnd.X and invWnd.X()) or 0, tonumber(invWnd.Y and invWnd.Y()) or 0
                local invW = tonumber(invWnd.Width and invWnd.Width()) or 0
                if invX and invY and invW > 0 then
                    -- ItemUI position = InventoryWindow.X + InventoryWindow.Width + spacing
                    local itemUIX = invX + invW + 10
                    local itemUIY = invY
                    local itemUIW = ctx.layoutConfig.WidthInventory or 600
                    local calculatedX = itemUIX + itemUIW + 10
                    ImGui.SetNextWindowPos(ImVec2(calculatedX, itemUIY), ImGuiCond.FirstUseEver)
                    -- Save this calculated position for future use
                    ctx.layoutConfig.BankWindowX = calculatedX
                    ctx.layoutConfig.BankWindowY = itemUIY
                    ctx.scheduleLayoutSave()  -- Schedule debounced save
                end
            end
        end
    end
    
    -- Window size
    local w = ctx.layoutConfig.WidthBankPanel or BANK_WINDOW_WIDTH
    local h = ctx.layoutConfig.HeightBank or BANK_WINDOW_HEIGHT
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.FirstUseEver)
    end
    
    -- Window flags - allow resizing unless UI is locked
    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end
    
    local winOpen, winVis = ImGui.Begin("Bank##ItemUIBank", ctx.uiState.bankWindowOpen, windowFlags)
    ctx.uiState.bankWindowOpen = winOpen
    ctx.uiState.bankWindowShouldDraw = winOpen
    
    if not winOpen then ImGui.End(); return end
    if ImGui.IsKeyPressed(ImGuiKey.Escape) then 
        ctx.uiState.bankWindowOpen = false
        ctx.uiState.bankWindowShouldDraw = false
        ImGui.End()
        return 
    end
    if not winVis then ImGui.End(); return end
    
    -- Save window size when resized (if unlocked)
    if not ctx.uiState.uiLocked then
        local currentW, currentH = ImGui.GetWindowSize()
        if currentW and currentH and currentW > 0 and currentH > 0 then
            ctx.layoutConfig.WidthBankPanel = currentW
            ctx.layoutConfig.HeightBank = currentH
        end
    end
    
    -- Save position when window is moved (only if not synced, or when sync is disabled)
    if not ctx.uiState.syncBankWindow then
        local currentX, currentY = ImGui.GetWindowPos()
        if currentX and currentY then
            -- Only save if position actually changed (to avoid constant file writes)
            if not ctx.layoutConfig.BankWindowX or math.abs(ctx.layoutConfig.BankWindowX - currentX) > 1 or 
               not ctx.layoutConfig.BankWindowY or math.abs(ctx.layoutConfig.BankWindowY - currentY) > 1 then
                ctx.layoutConfig.BankWindowX = currentX
                ctx.layoutConfig.BankWindowY = currentY
                ctx.scheduleLayoutSave()  -- Schedule debounced save (was immediate save causing spam)
            end
        end
    end
    
    -- Header
    ctx.theme.TextHeader("Bank")
    ImGui.SameLine()
    if ImGui.Button("Refresh##BankHeader", ImVec2(80,0)) then
        ctx.setStatusMessage("Scanning bank..."); ctx.scanBank(); ctx.setStatusMessage("Bank refreshed")
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Rescan bank"); ImGui.EndTooltip() end
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
        if ImGui.Button("Refresh##Bank", ImVec2(60, 0)) then ctx.setStatusMessage("Scanning bank..."); ctx.scanBank(); ctx.setStatusMessage("Bank refreshed") end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Rescan bank"); ImGui.EndTooltip() end
    end
    ImGui.Separator()
    
    -- Pre-filter bank list
    local filteredBank = {}
    local searchBankLower = (ctx.uiState.searchFilterBank or ""):lower()
    for _, item in ipairs(list) do
        if searchBankLower == "" or (item.name or ""):lower():find(searchBankLower, 1, true) then
            table.insert(filteredBank, item)
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
                    ctx.setStatusMessage("Column changes apply when you reopen ItemUI")
                end
            end
            ImGui.Separator()
            if ImGui.MenuItem("Autofit Columns") then
                ctx.autofitColumns("Bank", filteredBank, visibleCols)
            end
            ImGui.EndPopup()
        end
        
        -- Sort cache: skip sort when key/dir/filter/list unchanged
        local bankSortKey = (ctx.sortState.bankColumn and type(ctx.sortState.bankColumn) == "string" and ctx.sortState.bankColumn) or "Name"
        local bankSortDir = ctx.sortState.bankDirection or ImGuiSortDirection.Ascending
        local bankFilterStr = ctx.uiState.searchFilterBank or ""
        local bankCacheValid = ctx.perfCache.bank.key == bankSortKey and ctx.perfCache.bank.dir == bankSortDir and ctx.perfCache.bank.filter == bankFilterStr and ctx.perfCache.bank.n == #list and ctx.perfCache.bank.nFiltered == #filteredBank and #ctx.perfCache.bank.sorted > 0
        if not bankCacheValid and bankSortKey ~= "" then
            local isNumeric = ctx.sortColumns and ctx.sortColumns.isNumericColumn and ctx.sortColumns.isNumericColumn(bankSortKey)
            -- Schwartzian transform: pre-compute keys O(n) then sort by cached keys
            local Sort = ctx.sortColumns
            local decorated = Sort.precomputeKeys and Sort.precomputeKeys(filteredBank, bankSortKey, "Bank")
            if decorated then
                table.sort(decorated, function(a, b)
                    local av, bv = a.key, b.key
                    if isNumeric then
                        local an, bn = tonumber(av) or 0, tonumber(bv) or 0
                        if ctx.sortState.bankDirection == ImGuiSortDirection.Ascending then return an < bn else return an > bn end
                    else
                        local as, bs = tostring(av or ""), tostring(bv or "")
                        if ctx.sortState.bankDirection == ImGuiSortDirection.Ascending then return as < bs else return as > bs end
                    end
                end)
                Sort.undecorate(decorated, filteredBank)
            end
            ctx.perfCache.bank.key, ctx.perfCache.bank.dir, ctx.perfCache.bank.filter = bankSortKey, bankSortDir, bankFilterStr
            ctx.perfCache.bank.n, ctx.perfCache.bank.nFiltered, ctx.perfCache.bank.sorted = #list, #filteredBank, filteredBank
        else
            filteredBank = ctx.perfCache.bank.sorted
        end
        
        local nBank = #filteredBank
        local clipperBank = ImGuiListClipper.new()
        clipperBank:Begin(nBank)
        while clipperBank:Step() do
            for i = clipperBank.DisplayStart + 1, clipperBank.DisplayEnd do
                local item = filteredBank[i]
                if not item then goto bank_continue end
                ImGui.TableNextRow()
                local rid = "bank_" .. item.bag .. "_" .. item.slot
                ImGui.PushID(rid)
                
                -- Render columns dynamically based on visibleCols
                for _, colDef in ipairs(visibleCols) do
                    ImGui.TableNextColumn()
                    local colKey = colDef.key
                    
                    if colKey == "Name" then
                        -- Name column with special interaction logic
                        local dn = item.name or ""
                        if (item.stackSize or 1) > 1 then dn = dn .. string.format(" (x%d)", item.stackSize) end
                        ImGui.Selectable(dn, false, ImGuiSelectableFlags.None, ImVec2(0,0))
                        if bankOpen then
                            local hasCursor = ctx.hasItemOnCursor()
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
                                        ctx.uiState.quantityPickerValue = tostring(item.stackSize)
                                        ctx.uiState.quantityPickerMax = item.stackSize
                                    else
                                        ctx.uiState.lastPickup.bag, ctx.uiState.lastPickup.slot, ctx.uiState.lastPickup.source = item.bag, item.slot, "bank"
                                        mq.cmdf('/itemnotify in bank%d %d leftmouseup', item.bag, item.slot)
                                    end
                                end
                            end
                            if ImGui.IsItemHovered() and ImGui.IsMouseReleased(ImGuiMouseButton.Right) then
                                if hasCursor then ctx.removeItemFromCursor()
                                else
                                    local Me = mq.TLO and mq.TLO.Me
                                    local bn = Me and Me.Bank and Me.Bank(item.bag)
                                    local sz = bn and bn.Container and bn.Container()
                                    local it = (bn and sz and sz>0) and (bn.Item and bn.Item(item.slot)) or bn
                                    if it and it.ID and it.ID() and it.ID()>0 and it.Inspect then it.Inspect() end
                                end
                            end
                        end
                    elseif colKey == "Icon" then
                        if ctx.drawItemIcon then
                            ctx.drawItemIcon(item.icon)
                        else
                            ImGui.Text(tostring(item.icon or 0))
                        end
                        if ImGui.IsItemHovered() then
                            ItemTooltip.beginItemTooltip()
                            ImGui.Text("Stats")
                            ImGui.Separator()
                            local showItem = (ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip(item, "bank")) or item
                            ItemTooltip.renderStatsTooltip(showItem, ctx, { source = "bank" })
                            ImGui.EndTooltip()
                        end
                    elseif colKey == "Status" then
                        local statusText, willSell = "", false
                        if item.sellReason ~= nil and item.willSell ~= nil then
                            statusText = item.sellReason or "—"
                            willSell = item.willSell
                        elseif ctx.getSellStatusForItem then
                            statusText, willSell = ctx.getSellStatusForItem(item)
                        end
                        if statusText == "" then statusText = "—" end
                        local statusColor = willSell and ctx.theme.ToVec4(ctx.theme.Colors.Warning) or ctx.theme.ToVec4(ctx.theme.Colors.Success)
                        if statusText == "Epic" then
                            statusText = "EpicQuest"
                            statusColor = ctx.theme.ToVec4(ctx.theme.Colors.EpicQuest or ctx.theme.Colors.Muted)
                        elseif statusText == "NoDrop" or statusText == "NoTrade" then
                            statusColor = ctx.theme.ToVec4(ctx.theme.Colors.Error)
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

return BankView
