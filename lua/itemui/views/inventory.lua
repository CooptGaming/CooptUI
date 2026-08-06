--[[
    Inventory View - Gameplay view for inventory management

    Part of ItemUI Phase 5: View Extraction
    Renders the main inventory view with bag, slot, weight, flags

    render() is split into renderToolbar / renderTable. That split outlived the phase-10
    two-pane merge it was cut for (rolled back — Bags and Bank are separate windows again,
    aligned by services/window_zones): renderTable's body lives in a local so the pcall can
    sit INSIDE BeginTable/EndTable, which is the invariant that actually matters — a throw
    that skips EndTable is a C++ ImGuiException MQ2Lua answers by killing the script.
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')
local constants = require('itemui.constants')
local ItemDisplayView = require('itemui.views.item_display')
local windowHeader = require('itemui.components.window_header')
local cursorSubject = require('itemui.services.cursor_subject')

local InventoryView = {}

-- The band's search row exists only while search is ON (windows pass item 8) — the same
-- rule chat's filter follows. A filter you cannot see is a window that has quietly
-- stopped showing you your items. Module-local: one Bags pane per session.
local searchOpen = false

--- Total bag/container slots, cached on perfCache (invalidated on scan/move). Bags' band
--- does NOT print this — the bar's bags cell owns free slots and weight — but the classic
--- toolbar still does, so the computation stays shared.
local function invTotalSlots(ctx)
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
    return ctx.perfCache.invTotalSlots
end

local function invTotalValue(ctx)
    if ctx.perfCache.invTotalValue == nil then
        local v = 0
        for _, it in ipairs(ctx.inventoryItems) do v = v + (it.totalValue or 0) end
        ctx.perfCache.invTotalValue = v
    end
    return ctx.perfCache.invTotalValue
end

--- The band's stat: the one number the bar does NOT already show. Total inventory VALUE
--- (strictly greater than the bar's sell-waiting figure, which counts only what the rules
--- will actually sell) plus scan age. "last scan" is spelled out because "Last:" beside a
--- Refresh button reads as "last refresh".
--- Degrades: no scan yet -> "no scan yet"; no value -> drop the clause and its separator;
--- neither -> nil, and the band renders its title alone (legal - Settings ships that way).
local function bandStat(ctx)
    local parts = {}
    local value = invTotalValue(ctx)
    if value ~= nil then
        -- formatValue VERBATIM: the same formatter feeds Sell and Bank, so hand-trimming
        -- the gold clause here would make two windows disagree about one number.
        parts[#parts + 1] = ItemUtils.formatValue(value) .. " total"
    end
    local scanAt = tonumber(ctx.perfCache.lastScanTimeInv) or 0
    if scanAt > 0 then
        parts[#parts + 1] = "last scan " .. os.date("%H:%M:%S", scanAt / 1000)
    elseif #parts > 0 then
        parts[#parts + 1] = "no scan yet"
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " . ")
end

--- The 26px kit band (item 8). Replaces three stacked rows of chrome: the toolbar, the
--- status row and two separators.
---
--- NO lock action, deliberately. The handoff specified windowHeader.registryLock, but Bags
--- is not a registry module — its lock is the GLOBAL uiState.uiLocked checkbox that
--- main_window's header row already draws, and which Sell shares. A second lock here
--- would be two homes for one control, which is exactly what mockup 13d forbids.
local function renderBand(ctx)
    -- A locate request (equipment's "Find upgrade in Bags" menu row) arrives with
    -- searchFilterInv already set; consume-once and open the search section so the
    -- filtered list is the first thing the user sees.
    if ctx.uiState.invSearchOpenRequest then
        ctx.uiState.invSearchOpenRequest = nil
        searchOpen = true
    end
    windowHeader.render({
        id = "bags", title = "Bags", stat = bandStat(ctx),
        actions = {
            { label = windowHeader.GLYPHS.SEARCH,
              tooltip = searchOpen and "Close search" or "Search your bags",
              onClick = function()
                  searchOpen = not searchOpen
                  if not searchOpen then ctx.uiState.searchFilterInv = "" end
              end },
            { label = windowHeader.GLYPHS.REFRESH,
              tooltip = "Rescan inventory, bank (if open), sell list, and loot",
              onClick = function()
                  if ctx.setStatusMessage then ctx.setStatusMessage("Scanning...") end
                  ctx.refreshAllScans()
              end },
        },
    })
    if searchOpen then
        ImGui.SetNextItemWidth(200)
        -- Explicit if, never the `A and A(...) or B(...)` idiom: it truncates a
        -- multi-value call to one value (SPEC_CORRECTIONS' standing trap).
        local ft
        if ImGui.InputTextWithHint then
            ft = ImGui.InputTextWithHint("##InvSearch", "show only items containing...", ctx.uiState.searchFilterInv)
        else
            ft = ImGui.InputText("##InvSearch", ctx.uiState.searchFilterInv)
        end
        ctx.uiState.searchFilterInv = ft or ""
        ImGui.SameLine(0, 6)
        if ImGui.SmallButton("clear##InvSearchClear") then ctx.uiState.searchFilterInv = "" end
    end
end

--- Footer strip: the bank hint (item 8). It lives BELOW the table on purpose — conditional
--- chrome above a table shifts every row down the moment you walk up to a banker.
local function renderFooter(ctx, bankOpen)
    if not bankOpen then return end
    ctx.theme.TextFurniture("Bank open - shift+click an item to move it")
end

-- Toolbar: search, newest-sort, refresh, and the status line (bank hint or items/value).
-- CLASSIC ONLY since item 8 — in bars mode renderBand replaces this whole block. Kept
-- unchanged rather than adapted: with the bars off, nothing else on screen shows totals
-- or scan age, so the band's deliberate omissions would strand a windows-only user.
function InventoryView.renderToolbar(ctx, bankOpen)
    -- Classic shows the search unconditionally, so a locate request only needs its
    -- filter (already set) - consume the flag so it cannot leak into a later bars
    -- frame.
    if ctx.uiState.invSearchOpenRequest then ctx.uiState.invSearchOpenRequest = nil end
    -- Gameplay view: bag, slot, weight, flags; Shift+click to move when bank open
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(180)
    ctx.uiState.searchFilterInv, _ = ImGui.InputText("##InvSearch", ctx.uiState.searchFilterInv)
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Filter items by name"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("X##InvSearchClear2", ImVec2(22, 0)) then ctx.uiState.searchFilterInv = "" end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Clear search"); ImGui.EndTooltip() end
    -- "Newest" is gone (item 8). It was a BUTTON that set a SORT, and sorts belong to
    -- column headers — its second click silently restored Name sort, which no label said.
    -- `Acquired` is already a real hideable column (column_config.lua:26, default off), so
    -- turning it on and clicking its header does the same job and says what it is doing.
    ImGui.SameLine()
    ctx.renderRefreshButton(ctx, "Refresh##Inv", "Rescan inventory, bank (if open), sell list, and loot", function() ctx.refreshAllScans() end, { messageBefore = "Scanning..." })
    ImGui.SameLine()
    ctx.theme.TextMuted(string.format("Last: %s", os.date("%H:%M:%S", ctx.perfCache.lastScanTimeInv/1000)))
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Last inventory scan time"); ImGui.EndTooltip() end
    ImGui.Separator()

    if bankOpen then
        ctx.theme.TextSuccess("Bank open - Shift+click item to move to bank")
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Hold Shift and left-click an item to move it to bank (or to inventory from the Bank Companion)"); ImGui.EndTooltip() end
    else
        -- Current items / total bag (container) spaces (cached; invalidated on scan/move)
        local used = #ctx.inventoryItems
        local totalSlots = invTotalSlots(ctx)
        local totalValue = invTotalValue(ctx)
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
                -- The source row is DIMMED, not hidden (item 10). Removing it made the
                -- list jump and left no evidence of where the thing you are carrying came
                -- from; the dim says "not in that slot right now" while the row holds its
                -- place. See the Alpha push in the row loop below.
                table.insert(filtered, it)
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
        -- Recorded so renderTable can tell "your filter hid everything" from "you have
        -- nothing", which are different sentences and were previously neither.
        ctx.uiState.invVisibleCount = nInv
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
                -- The dim (item 10). Alpha MULTIPLIES each colour's own alpha, so a mythic
                -- row dims to faint mythic rather than toward grey — which is the whole
                -- point, or the dim would double as a category change. It also leaves the
                -- table's row background and stripe untouched, since those are drawn by
                -- TableNextRow outside this push.
                local dimmed = cursorSubject.isSourceRow(item.bag, item.slot, "inv")
                if dimmed then ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.45) end
                if rawget(item, "_statsPending") then
                    if ctx.uiState then ctx.uiState.pendingStatRescanBags = ctx.uiState.pendingStatRescanBags or {}; ctx.uiState.pendingStatRescanBags[item.bag] = true end
                    for _ in ipairs(visibleCols) do ImGui.TableNextColumn(); ImGui.TextColored(ImVec4(0.7, 0.7, 0.5, 1), "...") end
                    if dimmed then ImGui.PopStyleVar(1) end
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
                    elseif dimmed and (colKey == "Bag" or colKey == "Slot") then
                        -- A dimmed row never names a slot the item is not in. The dim
                        -- already says "this is on your cursor"; printing its old address
                        -- beside that says the opposite in the same row. The home address
                        -- comes back the moment it is put down.
                        ctx.theme.TextFurniture("-")
                    else
                        ImGui.Text(ctx.sortColumns.getCellDisplayText(item, colKey, "Inventory"))
                    end
                end
                -- Once per row (not per column): the Name column opens this popup too,
                -- and the Icon column is hidden by default.
                ctx.renderItemContextMenu(ctx, item, { source = "inv", popupId = "ItemContextInv_" .. rid, bankOpen = bankOpen or (ctx.uiState and ctx.uiState.bankOpen) or false, hasCursor = hasCursor })
                if dimmed then ImGui.PopStyleVar(1) end
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

    -- Bags had NO empty state at all. On a fresh install, before the first scan lands, this
    -- window was column headers over nothing and a "Total value: 0p" -- and it is the window a
    -- newcomer is most likely to open first, because the bars put it in front of them.
    --
    -- Two different nothings, kept apart (the rule augment_utility and mythicals already
    -- follow): an empty list is not the same as a filter that hid everything, and a user who
    -- cannot tell them apart concludes the scan is broken.
    -- Each string names the control BY THE LABEL THE CURRENT MODE DRAWS. The refresh is a
    -- band glyph in bars and a button labelled "Refresh" in classic; the search-clear is
    -- "clear" in bars and an "X" in classic -- and a fresh install lands in classic, so
    -- the mode-blind copy was wrong precisely for the reader it was written for.
    local barsMode = tostring((ctx.layoutConfig or {}).UIMode or "classic") == "bars"
    if #(ctx.inventoryItems or {}) == 0 then
        ImGui.Spacing()
        ctx.theme.TextMuted(barsMode
            and "Nothing here yet. Bags are scanned when CoOpt starts and when you loot; the refresh glyph in the title band rescans now."
            or "Nothing here yet. Bags are scanned when CoOpt starts and when you loot; the Refresh button above rescans now.")
    elseif tostring(ctx.uiState.searchFilterInv or "") ~= "" then
        -- Only reachable when the filter matched nothing, since the branch above owns the
        -- genuinely-empty case. The count is recorded by renderInvTableInner.
        if ctx.uiState.invVisibleCount == 0 then
            ImGui.Spacing()
            ctx.theme.TextMuted(barsMode
                and "No items match your search. Clear it with the clear button beside the box."
                or "No items match your search. Clear it with the X beside the box.")
        end
    end
end

-- Module interface: render inventory view content.
-- Two branches only (item 8): bars on -> the 26px band, no toolbar; bars off -> today's
-- toolbar, unchanged. The bank hint moves below the table in bars mode so arriving at a
-- banker does not shove every row down.
function InventoryView.render(ctx, bankOpen)
    local barsOn = tostring((ctx.layoutConfig or {}).UIMode or "classic") == "bars"
    if barsOn then
        renderBand(ctx)
        InventoryView.renderTable(ctx, bankOpen)
        renderFooter(ctx, bankOpen)
    else
        InventoryView.renderToolbar(ctx, bankOpen)
        InventoryView.renderTable(ctx, bankOpen)
    end
end

return InventoryView
