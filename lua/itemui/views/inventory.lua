--[[
    Inventory View - Gameplay view for inventory management

    Part of ItemUI Phase 5: View Extraction
    Renders the main inventory view with bag, slot, weight, flags

    Windows pass phase 10 (23a): render() is split into renderToolbar/renderTable so the
    bars-mode hub can compose the merged two-pane Inventory (renderMergedContent) from the
    same parts. Classic composes the identical pair — behavior there is unchanged.
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')
local constants = require('itemui.constants')
local ItemDisplayView = require('itemui.views.item_display')

local InventoryView = {}

-- The bank view is required LAZILY: bank.lua registers its module at require time, and a
-- top-level require here would move that registration from app.lua's slot (line order =
-- launcher button order in classic). By first render app.lua has loaded it anyway, so
-- this is a package.loaded lookup, not real work.
local BankViewLazy
local function bankView()
    BankViewLazy = BankViewLazy or require('itemui.views.bank')
    return BankViewLazy
end

-- Toolbar: search, newest-sort, refresh, and the status line (bank hint or items/value).
function InventoryView.renderToolbar(ctx, bankOpen)
    -- Gameplay view: bag, slot, weight, flags; Shift+click to move when bank open
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(180)
    ctx.uiState.searchFilterInv, _ = ImGui.InputText("##InvSearch", ctx.uiState.searchFilterInv)
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Filter items by name"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("X##InvSearchClear2", ImVec2(22, 0)) then ctx.uiState.searchFilterInv = "" end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Clear search"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("Newest##Inv", ImVec2(55, 0)) then
        -- Toggle newest-first sort (hidden Acquired column); restore Name sort on second click.
        if ctx.sortState.invColumn ~= "Acquired" then
            ctx.sortState.invColumn = "Acquired"
            ctx.sortState.invDirection = ImGuiSortDirection.Descending
        else
            ctx.sortState.invColumn = "Name"
            ctx.sortState.invDirection = ImGuiSortDirection.Ascending
        end
        -- Persist exactly like a header sort-spec change (see sort handler below);
        -- the sort cache revalidates via sortKey/sortDir in getSortedList.
        ctx.scheduleLayoutSave()
        ctx.flushLayoutSave()
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Sort by most recently looted; click again to restore Name"); ImGui.EndTooltip() end
    ImGui.SameLine()
    ctx.renderRefreshButton(ctx, "Refresh##Inv", "Rescan inventory, bank (if open), sell list, and loot", function() ctx.refreshAllScans() end, { messageBefore = "Scanning..." })
    ImGui.SameLine()
    ctx.theme.TextMuted(string.format("Last: %s", os.date("%H:%M:%S", ctx.perfCache.lastScanTimeInv/1000)))
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Last inventory scan time"); ImGui.EndTooltip() end
    ImGui.Separator()

    if bankOpen then
        ctx.theme.TextSuccess("Bank open — Shift+click item to move to bank")
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Hold Shift and left-click an item to move it to bank (or to inventory from the Bank Companion)"); ImGui.EndTooltip() end
    else
        -- Current items / total bag (container) spaces (cached; invalidated on scan/move)
        local used = #ctx.inventoryItems
        if ctx.perfCache.invTotalSlots == nil then
            local n = 0
            local Me = mq.TLO and mq.TLO.Me
            if Me and Me.Inventory then
                for i = 1, 10 do
                    local pack = Me.Inventory("pack" .. i)
                    if pack and pack.Container then n = n + (tonumber(pack.Container()) or 0) end
                end
            end
            ctx.perfCache.invTotalSlots = (n > 0) and n or 80
        end
        local totalSlots = ctx.perfCache.invTotalSlots
        if ctx.perfCache.invTotalValue == nil then
            local v = 0
            for _, it in ipairs(ctx.inventoryItems) do v = v + (it.totalValue or 0) end
            ctx.perfCache.invTotalValue = v
        end
        local totalValue = ctx.perfCache.invTotalValue
        ctx.theme.TextInfo(string.format("Items: %d / %d", used, totalSlots))
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Items in bags / total bag and container slots"); ImGui.EndTooltip() end
        if ImGui.IsItemHovered() and ctx.hasItemOnCursor() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
            if ctx.putCursorInBags then ctx.putCursorInBags() end
        end
        ImGui.SameLine()
        ctx.theme.TextMuted(string.format("Total value: %s", ItemUtils.formatValue(totalValue)))
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Total vendor value of all items in inventory"); ImGui.EndTooltip() end
        if ImGui.IsItemHovered() and ctx.hasItemOnCursor() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
            if ctx.putCursorInBags then ctx.putCursorInBags() end
        end
    end
    ImGui.Separator()
end

-- Everything between BeginTable and EndTable, split out so renderTable can pcall it
-- INSIDE the pair: a body throw that skips EndTable is an unbalanced-table
-- ImGuiException from C++ — uncatchable from Lua, kills the script (aec75c0's class).
local function renderInvTableInner(ctx, bankOpen, visibleCols)
        local simpleHash = ctx.sortColumns.simpleHash
        -- Setup columns with stable user IDs based on column key hash or index
        local sortCol = (ctx.sortState.invColumn and type(ctx.sortState.invColumn) == "string" and ctx.sortState.invColumn) or "Name"
        for i, colDef in ipairs(visibleCols) do
            local flags = (colDef.key == "Name") and ImGuiTableColumnFlags.WidthStretch or ImGuiTableColumnFlags.WidthFixed

            if colDef.key == sortCol then
                flags = bit32.bor(flags, ImGuiTableColumnFlags.DefaultSort)
            end

            local width = 0
            if colDef.key ~= "Name" then
                if ctx.columnAutofitWidths["Inventory"][colDef.key] then
                    width = ctx.columnAutofitWidths["Inventory"][colDef.key]
                else
                    if colDef.key == "Value" then width = 70
                    elseif colDef.key == "Weight" then width = 55
                    elseif colDef.key == "Type" then width = 80
                    elseif colDef.key == "Bag" then width = 40
                    elseif colDef.key == "Clicky" then width = 150
                    elseif colDef.key == "Icon" then width = 28
                    elseif colDef.key == "Slot" then width = 40
                    elseif colDef.key == "Stack" then width = 50
                    elseif colDef.key == "Status" then width = 100
                    elseif colDef.key == "Acquired" then width = 56
                    else width = 80 end
                end
            end
            local userID = simpleHash(colDef.key)
            ImGui.TableSetupColumn(colDef.label, flags, width, userID)
        end
        ImGui.TableSetupScrollFreeze(0, 1)

        -- Build column mapping: UserID (hash of column key) -> column key
        local colKeyByUserID = {}
        for i, colDef in ipairs(visibleCols) do
            colKeyByUserID[simpleHash(colDef.key)] = colDef.key
        end

        -- Handle sort clicks
        local sortSpecs = ImGui.TableGetSortSpecs()
        if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
            local spec = sortSpecs:Specs(1)
            if spec then
                -- Use ColumnUserID to find which column was clicked (handles reordering)
                local userID = spec.ColumnUserID
                local colKey = colKeyByUserID[userID]
                if colKey then
                    ctx.sortState.invColumn = colKey
                    ctx.sortState.invDirection = spec.SortDirection
                    ctx.scheduleLayoutSave()
                    ctx.flushLayoutSave()
                end
            end
            sortSpecs.SpecsDirty = false
        end

        -- Capture header rect before/after TableHeadersRow for header-only right-click
        local headerTop = ImGui.GetCursorScreenPosVec and ImGui.GetCursorScreenPosVec()
        -- Render headers
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
            ImGui.OpenPopup("ColumnMenu_Inventory")
        end

        if ImGui.BeginPopup("ColumnMenu_Inventory") then
            ImGui.Text("Columns (changes apply on next open)")
            ImGui.Separator()
            for _, colDef in ipairs(ctx.availableColumns["Inventory"] or {}) do
                local inFixed = ctx.isColumnInFixedSet("Inventory", colDef.key)
                if ImGui.MenuItem(colDef.label, "", inFixed) then
                    ctx.toggleFixedColumn("Inventory", colDef.key)
                    ctx.setStatusMessage("Column changes apply when you reopen CoOpt UI Inventory Companion")
                end
            end
            ImGui.Separator()
            if ImGui.MenuItem("Autofit Columns") then
                ctx.autofitColumns("Inventory", ctx.inventoryItems, visibleCols)
            end
            ImGui.EndPopup()
        end

        local hasCursor = ctx.hasItemOnCursor()
        local lp = ctx.uiState.lastPickup
        -- Session floor for the "NEW" badge (nil until stamped at startup; see app.lua main)
        local sessionFloor = ctx.getSessionStartAcquiredSeq and ctx.getSessionStartAcquiredSeq()
        local searchLower = (ctx.uiState.searchFilterInv or ""):lower()
        local filtered = {}
        for _, it in ipairs(ctx.inventoryItems) do
            if searchLower == "" or (it.name or ""):lower():find(searchLower, 1, true) then
                if not ctx.shouldHideRowForCursor(it, "inv") then
                    table.insert(filtered, it)
                end
            end
        end

        -- Sort cache (Phase 3: shared getSortedList helper)
        local sortKey = (ctx.sortState.invColumn and type(ctx.sortState.invColumn) == "string" and ctx.sortState.invColumn) or "Name"
        local sortDir = ctx.sortState.invDirection or ImGuiSortDirection.Ascending
        local filterStr = ctx.uiState.searchFilterInv or ""
        local hidingNow = not not (lp and lp.source == "inv" and lp.bag and lp.slot)
        local validity = {
            filter = filterStr,
            hidingSlot = hidingNow,
            fullListLen = #ctx.inventoryItems,
            scanTime = ctx.perfCache.lastScanTimeInv,
        }
        filtered = ctx.getSortedList(ctx.perfCache.inv, filtered, sortKey, sortDir, validity, "Inventory", ctx.sortColumns)

        local nInv = #filtered
        local clipperInv = ImGuiListClipper.new()
        clipperInv:Begin(nInv)
        while clipperInv:Step() do
            for i = clipperInv.DisplayStart + 1, clipperInv.DisplayEnd do
                local item = filtered[i]
                if not item then goto continue end
                ImGui.TableNextRow()
                local loc = ItemDisplayView.getState().itemDisplayLocateRequest
                if loc and loc.source == "inv" and loc.bag == item.bag and loc.slot == item.slot then
                    ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, ImGui.GetColorU32(ImVec4(0.25, 0.45, 0.75, 0.45)))
                end
                local rid = "inv_" .. item.bag .. "_" .. item.slot
                ImGui.PushID(rid)
                if rawget(item, "_statsPending") then
                    if ctx.uiState then ctx.uiState.pendingStatRescanBags = ctx.uiState.pendingStatRescanBags or {}; ctx.uiState.pendingStatRescanBags[item.bag] = true end
                    for _ in ipairs(visibleCols) do ImGui.TableNextColumn(); ImGui.TextColored(ImVec4(0.7, 0.7, 0.5, 1), "...") end
                    ImGui.PopID()
                    goto continue
                end
                for _, colDef in ipairs(visibleCols) do
                    ImGui.TableNextColumn()
                    local colKey = colDef.key
                    if colKey == "Name" then
                        local dn = item.name or ""
                        if (item.stackSize or 1) > 1 then dn = dn .. string.format(" (x%d)", item.stackSize) end
                        -- "NEW" badge for items acquired since UI start. Rendered before the
                        -- Selectable: the Selectable spans the rest of the column (SameLine after
                        -- it would clip), and it must stay the last item for the click handlers
                        -- below. Plain colored text — no interactive widget, so no ID concerns.
                        if sessionFloor and item.acquiredSeq and item.acquiredSeq >= sessionFloor then
                            ctx.theme.TextSuccess("NEW")
                            ImGui.SameLine()
                        end
                        ImGui.Selectable(dn, false, ImGuiSelectableFlags.None, ImVec2(0,0))
                        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
                            if ImGui.GetIO().KeyShift and bankOpen then
                                ctx.moveInvToBank(item.bag, item.slot)
                            elseif hasCursor then
                                ctx.dropAtSlot(item.bag, item.slot, "inv")
                            elseif not hasCursor then
                                if item.stackSize and item.stackSize > 1 then
                                    ctx.uiState.pendingQuantityPickup = {
                                        bag = item.bag,
                                        slot = item.slot,
                                        source = "inv",
                                        maxQty = item.stackSize,
                                        itemName = item.name
                                    }
                                    ctx.uiState.pendingQuantityPickupTimeoutAt = mq.gettime() + constants.TIMING.QUANTITY_PICKUP_TIMEOUT_MS
                                    ctx.uiState.quantityPickerValue = tostring(item.stackSize)
                                    ctx.uiState.quantityPickerMax = item.stackSize
                                    -- Set lastPickup so activation guard does not treat the upcoming stack pickup as unexpected
                                    ctx.uiState.lastPickup.bag = item.bag
                                    ctx.uiState.lastPickup.slot = item.slot
                                    ctx.uiState.lastPickup.source = "inv"
                                    ctx.uiState.lastPickupSetThisFrame = true
                                else
                                    ctx.pickupFromSlot(item.bag, item.slot, "inv")
                                end
                            end
                        end
                        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                            ImGui.OpenPopup("ItemContextInv_" .. rid)
                        end
                    elseif colKey == "Clicky" then
                        local cid = ctx.getItemSpellId(item, "Clicky") or 0
                        if cid > 0 then
                            local spellName = ctx.getSpellName(cid) or "Unknown"
                            local timerReady = ctx.getTimerReady(item.bag, item.slot)
                            local isOnCooldown = timerReady and timerReady > 0
                            if isOnCooldown then
                                ImGui.PushStyleColor(ImGuiCol.Text, ctx.theme.ToVec4(ctx.theme.Colors.Error))
                            else
                                ImGui.PushStyleColor(ImGuiCol.Text, ctx.theme.ToVec4(ctx.theme.Colors.Success))
                            end
                            ImGui.Selectable(spellName, false, ImGuiSelectableFlags.None, ImVec2(0, 0))
                            ImGui.PopStyleColor()
                            if ImGui.IsItemHovered() and ImGui.IsMouseReleased(ImGuiMouseButton.Right) then
                                if not isOnCooldown then
                                    mq.cmdf('/itemnotify in pack%d %d rightmouseup', item.bag, item.slot)
                                end
                            end
                            if ImGui.IsItemHovered() then
                                ImGui.BeginTooltip()
                                local desc = ctx.getSpellDescription(cid)
                                if desc and desc ~= "" then
                                    ImGui.TextWrapped(desc)
                                    ImGui.Spacing()
                                end
                                if isOnCooldown then
                                    ImGui.Text(string.format("On cooldown (%d seconds remaining)", timerReady))
                                else
                                    ImGui.Text("Right-click to activate clicky effect")
                                end
                                ImGui.EndTooltip()
                            end
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, ctx.theme.ToVec4(ctx.theme.Colors.Muted))
                            ImGui.Selectable("No", false, ImGuiSelectableFlags.None, ImVec2(0, 0))
                            ImGui.PopStyleColor()
                        end
                    elseif colKey == "Icon" then
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
                        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                            ImGui.OpenPopup("ItemContextInv_" .. rid)
                        end
                    elseif colKey == "Status" then
                        local statusText, statusColor = ctx.resolveSellStatusDisplay(ctx, item)
                        ImGui.TextColored(statusColor, statusText)
                    else
                        ImGui.Text(ctx.sortColumns.getCellDisplayText(item, colKey, "Inventory"))
                    end
                end
                -- Once per row (not per column): the Name column opens this popup too,
                -- and the Icon column is hidden by default.
                ctx.renderItemContextMenu(ctx, item, { source = "inv", popupId = "ItemContextInv_" .. rid, bankOpen = bankOpen or (ctx.uiState and ctx.uiState.bankOpen) or false, hasCursor = hasCursor })
                ImGui.PopID()
            ::continue::
            end
        end
end

-- The inventory table, host-agnostic: no window chrome, no toolbar.
function InventoryView.renderTable(ctx, bankOpen)
    -- Build fixed columns list (from config; ImGui SaveSettings handles sort/order)
    local visibleCols = ctx.getFixedColumns("Inventory")
    local nCols = #visibleCols
    if nCols == 0 then nCols = 1; visibleCols = {{key = "Name", label = "Name", numeric = false}} end

    if ImGui.BeginTable("ItemUI_InvGameplay", nCols, ctx.uiState.tableFlags) then
        -- pcall INSIDE the pair: EndTable is unconditional (see renderInvTableInner).
        pcall(renderInvTableInner, ctx, bankOpen, visibleCols)
        ImGui.EndTable()
    end
end

-- Module interface: render inventory view content (classic shape: toolbar + table)
-- Params: context table containing all necessary state and functions from init.lua
function InventoryView.render(ctx, bankOpen)
    InventoryView.renderToolbar(ctx, bankOpen)
    InventoryView.renderTable(ctx, bankOpen)
end

-- ---------------------------------------------------------------------------
-- Phase 10 (23a): the merged two-pane Inventory, hosted by the hub in bars mode.
-- One toolbar (its search filters BOTH panes — §9: Bags and Bank each had
-- search/refresh, the merge keeps one), a ResizeX splitter child for Bags, and
-- the Bank pane with its live/snapshot chip (20a — per-source state, visible first).
-- ---------------------------------------------------------------------------

local MERGED_MIN_PANE_W = 220   -- below this a pane's table is unusable; clamp the splitter
local MERGED_PANE_GAP = 4       -- GAP_INNER: inside-a-group spacing (§3.4)

-- Bank pane header stat ("242 items · 918,402p"), cached: summing 240 rows every frame is
-- exactly the per-frame recompute the perf pass removed elsewhere. Keyed on list length +
-- source + snapshot time; a same-length rescan with equal timestamp is indistinguishable
-- and acceptably stale for a header.
local bankPaneStat = { key = nil, text = "" }

local function bankPaneStatText(list, bankOpen, lastBankCacheTime)
    local n = #(list or {})
    local key = string.format("%d|%s|%s", n, bankOpen and "L" or "S", tostring(lastBankCacheTime or 0))
    if bankPaneStat.key ~= key then
        local total = 0
        for _, it in ipairs(list or {}) do total = total + (it.totalValue or 0) end
        bankPaneStat.key = key
        bankPaneStat.text = string.format("%d items · %s", n, ItemUtils.formatValue(total))
    end
    return bankPaneStat.text
end

-- "snapshot · 2d old" — age of the cached bank list, humanized (a raw timestamp is
-- furniture; the age is the fact you act on).
local function bankSnapshotAgeText(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return "no data yet" end
    local d = os.time() - ts
    if d < 0 then d = 0 end
    if d < 3600 then return string.format("%dm old", math.max(1, math.floor(d / 60))) end
    if d < 86400 then return string.format("%dh old", math.floor(d / 3600)) end
    return string.format("%dd old", math.floor(d / 86400))
end

function InventoryView.renderMergedContent(ctx, bankOpen)
    -- The pane is a standing fixture, gated by the same enable key that governed the
    -- classic Bank window. Off -> the content is exactly the classic single-pane shape.
    if (tonumber(ctx.layoutConfig.ShowBankWindow) or 1) == 0 then
        InventoryView.renderToolbar(ctx, bankOpen)
        InventoryView.renderTable(ctx, bankOpen)
        return
    end

    local BankView = bankView()
    local list = BankView.resolveList(ctx, bankOpen)

    InventoryView.renderToolbar(ctx, bankOpen)
    -- One search, both panes: the merged toolbar's box is the only search surface, so the
    -- bank filter mirrors it. (Classic keeps the two independent fields untouched.)
    ctx.uiState.searchFilterBank = ctx.uiState.searchFilterInv

    local availW = ImGui.GetContentRegionAvail()  -- tuple: first return is width
    availW = tonumber(availW) or 0
    local stored = tonumber(ctx.layoutConfig.InventoryBankSplitX) or 0
    local splitX = stored
    if splitX <= 0 then splitX = math.floor(availW * 0.55) end  -- unset: bags get the wider half
    if availW >= (MERGED_MIN_PANE_W * 2 + MERGED_PANE_GAP) then
        if splitX < MERGED_MIN_PANE_W then splitX = MERGED_MIN_PANE_W end
        if splitX > availW - MERGED_MIN_PANE_W then splitX = availW - MERGED_MIN_PANE_W end
    else
        -- Too narrow to honor both minimums; halve it rather than 0-width a pane.
        splitX = math.floor(availW * 0.5)
    end

    -- 23a: carrying an item rings the pane that will take it. Bags is the drop target
    -- (dropAtSlot exists for inv only — the bank asymmetry is behavior, not a bug), so
    -- its border goes accent + 2px while the cursor is loaded.
    local carrying = ctx.hasItemOnCursor()
    if carrying then
        ImGui.PushStyleColor(ImGuiCol.Border, ctx.theme.ToVec4(ctx.theme.Kit.OpenBlue))
        ImGui.PushStyleVar(ImGuiStyleVar.ChildBorderSize, 2)
    end
    -- ResizeX MUST pair with NoSavedSettings: without it ImGui persists the child size to
    -- its own ini and fights the layout INI on every load (spec §4.2 / WINDOWS_PASS plan).
    ImGui.BeginChild("MergedBagsPane", splitX, 0,
        bit32.bor(ImGuiChildFlags.Borders, ImGuiChildFlags.ResizeX),
        ImGuiWindowFlags.NoSavedSettings)
    -- pcall INSIDE the child: a content throw must never skip EndChild (overlay-pause rule).
    pcall(InventoryView.renderTable, ctx, bankOpen)
    local measuredW = ImGui.GetWindowSize()  -- tuple; width only
    ImGui.EndChild()
    if carrying then
        ImGui.PopStyleVar(1)
        ImGui.PopStyleColor(1)
    end

    -- Persist ONLY on an actual drag: measured differs from what we passed. Comparing to
    -- the stored value instead would write the auto width on first paint, and calling
    -- scheduleLayoutSave unconditionally per frame would starve the 600ms debounce.
    measuredW = tonumber(measuredW) or splitX
    if math.abs(measuredW - splitX) > 1 then
        ctx.layoutConfig.InventoryBankSplitX = math.floor(measuredW)
        ctx.scheduleLayoutSave()
    end

    ImGui.SameLine(0, MERGED_PANE_GAP)

    ImGui.BeginChild("MergedBankPane", 0, 0, ImGuiChildFlags.Borders, ImGuiWindowFlags.NoSavedSettings)
    -- 20a: live vs snapshot is the first thing you see, never a tooltip. The chip line
    -- stays at full alpha; only the table dims in snapshot state.
    ctx.theme.TextHeader("Bank")
    ImGui.SameLine(0, 8)
    if bankOpen then
        ctx.theme.TextSuccess("live")
        ImGui.SameLine(0, 8)
        ctx.theme.TextMuted(bankPaneStatText(list, true, ctx.perfCache.lastBankCacheTime))
    else
        ctx.theme.TextWarning("snapshot · " .. bankSnapshotAgeText(ctx.perfCache.lastBankCacheTime))
        ImGui.SameLine(0, 8)
        ctx.theme.TextMuted(bankPaneStatText(list, false, ctx.perfCache.lastBankCacheTime))
        ImGui.SameLine(0, 8)
        if ctx.theme.TextFurniture then
            ctx.theme.TextFurniture("read-only — open a bank to refresh")
        else
            ctx.theme.TextMuted("read-only — open a bank to refresh")
        end
    end
    ImGui.Separator()
    if not bankOpen then
        -- Snapshot: same table, dimmed (20a). Push/pop OUTSIDE the pcall'd body so the
        -- pair can never be skipped by a content throw.
        ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.55)
    end
    pcall(BankView.renderTable, ctx, list, bankOpen)
    if not bankOpen then
        ImGui.PopStyleVar(1)
    end
    ImGui.EndChild()
end

return InventoryView
