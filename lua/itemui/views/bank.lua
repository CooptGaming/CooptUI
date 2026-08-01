--[[
    Bank View - Separate window showing live bank data or cached snapshot

    Part of ItemUI Phase 5: View Extraction
    Renders the bank window with online/offline modes

    Bank is its own window in BOTH modes. The phase-10 two-pane merge into the hub was
    built, tried in the field, and rolled back: bags and bank are used together often but
    you do not always want the bank on screen, and a merged window cannot express that.
    What replaced it is ALIGNMENT — services/window_zones places this window flush against
    the hub's right edge at the same Y (its registered zone is "R1"), and the first-open
    seed in main_window matches its height to the hub's, so the two read as a pair without
    being welded into one.

    The merge did leave two things worth keeping: resolveList/renderTable are extracted
    (so the table body can be pcall'd INSIDE BeginTable/EndTable — a throw that skips
    EndTable is a C++ ImGuiException MQ2Lua answers by killing the script), and the 20a
    live/snapshot chip, which now lives in this window's own header.
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')

local constants = require('itemui.constants')
local context = require('itemui.context')
local registry = require('itemui.core.registry')
local windowHeader = require('itemui.components.window_header')
local ItemDisplayView = require('itemui.views.item_display')

local BankView = {}

-- ---------------------------------------------------------------------------
-- 20a: live vs snapshot stops being a tooltip on a checkbox and becomes the first thing
-- you see. The window says which source it is showing, how old a snapshot is, and what
-- the source holds — and the table itself dims when it is read-only.
-- ---------------------------------------------------------------------------

-- Header stat ("242 items · 918,402p"), cached: summing 240 rows every frame is exactly
-- the per-frame recompute the perf pass removed elsewhere. Keyed on list length + source
-- + snapshot time; a same-length rescan with an equal timestamp is indistinguishable and
-- acceptably stale for a header line.
local statCache = { key = nil, text = "" }

local function bankStatText(list, bankOpen, lastBankCacheTime)
    local n = #(list or {})
    local key = string.format("%d|%s|%s", n, bankOpen and "L" or "S", tostring(lastBankCacheTime or 0))
    if statCache.key ~= key then
        local total = 0
        for _, it in ipairs(list or {}) do total = total + (it.totalValue or 0) end
        statCache.key = key
        statCache.text = string.format("%d items . %s", n, ItemUtils.formatValue(total))
    end
    return statCache.text
end

--- "snapshot · 2d old" — the AGE of the cached list, humanized. A raw timestamp is
--- furniture; the age is the fact you act on.
local function bankSnapshotAgeText(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return "no data yet" end
    local age = os.time() - ts
    if age < 0 then age = 0 end
    if age < 3600 then return string.format("%dm old", math.max(1, math.floor(age / 60))) end
    if age < 86400 then return string.format("%dh old", math.floor(age / 3600)) end
    return string.format("%dd old", math.floor(age / 86400))
end

--- The chip line: source, age when stale, what it holds, and the input rule that applies.
--- `withHoldings` is false when the kit band above already states them — the band's stat IS
--- bankStatText, and printing it twice on two adjacent lines is exactly the duplication the
--- §9 redundancy pass exists to remove.
function BankView.renderSourceChip(ctx, list, bankOpen, withHoldings)
    if withHoldings == nil then withHoldings = true end
    if bankOpen then
        ctx.theme.TextSuccess("live")
        if withHoldings then
            ImGui.SameLine(0, 8)
            ctx.theme.TextMuted(bankStatText(list, true, ctx.perfCache.lastBankCacheTime))
        end
        ImGui.SameLine(0, 8)
        ctx.theme.TextInfo("shift + left-click moves an item to your bags")
    else
        ctx.theme.TextWarning("snapshot . " .. bankSnapshotAgeText(ctx.perfCache.lastBankCacheTime))
        if withHoldings then
            ImGui.SameLine(0, 8)
            ctx.theme.TextMuted(bankStatText(list, false, ctx.perfCache.lastBankCacheTime))
        end
        ImGui.SameLine(0, 8)
        if ctx.theme.TextFurniture then
            ctx.theme.TextFurniture("read-only - open a bank to refresh")
        else
            ctx.theme.TextMuted("read-only - open a bank to refresh")
        end
    end
end

--- The band's stat, exported so the header can state the holdings once (see above).
function BankView.statText(ctx, list, bankOpen)
    return bankStatText(list, bankOpen, ctx.perfCache.lastBankCacheTime)
end

--- Resolve which list the bank surface shows (live items vs cached snapshot) and make
--- sure the snapshot rows carry sell status before first paint. Shared by the classic
--- window and the merged pane — the live/snapshot decision is per-source (23a) and must
--- not fork between hosts.
function BankView.resolveList(ctx, bankOpen)
    ctx.ensureBankCacheFromStorage()
    local list = bankOpen and ctx.bankItems or ctx.bankCache
    -- Ensure cached bank list has current sell status (e.g. RerollList) so initial display matches reroll list before live scan runs.
    if list and list == ctx.bankCache and #list > 0 and ctx.computeAndAttachSellStatus then
        local needStatus = false
        for _, it in ipairs(list) do
            if it.sellReason == nil or it.willSell == nil then needStatus = true; break end
        end
        if needStatus then ctx.computeAndAttachSellStatus(list) end
    end
    return list
end

-- Everything between BeginTable and EndTable, split out so renderTable can pcall it
-- INSIDE the pair: a body throw that skips EndTable is an unbalanced-table
-- ImGuiException from C++ — uncatchable from Lua, kills the script (aec75c0's class).
local function renderBankTableInner(ctx, list, bankOpen, visibleCols, filteredBank, hasCursor, lp)
        local simpleHash = ctx.sortColumns.simpleHash
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
                local loc = ItemDisplayView.getState().itemDisplayLocateRequest
                if loc and loc.source == "bank" and loc.bag == item.bag and loc.slot == item.slot then
                    ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, ImGui.GetColorU32(ImVec4(0.25, 0.45, 0.75, 0.45)))
                end
                local rid = "bank_" .. item.bag .. "_" .. item.slot
                ImGui.PushID(rid)
                if rawget(item, "_statsPending") then
                    -- BANK bag numbers must not go into pendingStatRescanBags -
                    -- that feeds rescanInventoryBags (packs only), which can't
                    -- heal a bank row. Request a bank rescan instead.
                    if ctx.deferredScanNeeded then ctx.deferredScanNeeded.bank = true end
                    for _ in ipairs(visibleCols) do ImGui.TableNextColumn(); ctx.theme.TextMuted("...") end
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
                    elseif colKey == "Status" then
                        local statusText, statusColor = ctx.resolveSellStatusDisplay(ctx, item)
                        ImGui.TextColored(statusColor, statusText)
                    else
                        -- All other columns use dynamic display text
                        ImGui.Text(ctx.sortColumns.getCellDisplayText(item, colKey, "Bank"))
                    end
                end
                -- Once per row (not per column): the Name column opens this popup too,
                -- and the Icon column is hidden by default.
                ctx.renderItemContextMenu(ctx, item, { source = "bank", popupId = "ItemContextBankIcon_" .. rid, bankOpen = bankOpen, hasCursor = hasCursor })
                ImGui.PopID()
                ::bank_continue::
            end
        end
end

--- The bank table, host-agnostic: no Begin/End, no window chrome, no position writes.
--- Everything row-level lives in renderBankTableInner verbatim from the pre-split window —
--- including the deliberate asymmetry that bank rows have NO drop-on-click branch
--- (dropping into the bank is not a thing item_ops supports; do not "fix" it in a host).
function BankView.renderTable(ctx, list, bankOpen)
    local hasCursor = ctx.hasItemOnCursor()
    local lp = ctx.uiState.lastPickup
    -- Pre-filter bank list
    local filteredBank = {}
    local searchBankLower = (ctx.uiState.searchFilterBank or ""):lower()
    for _, item in ipairs(list or {}) do
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
        -- pcall INSIDE the pair: EndTable is unconditional (see renderBankTableInner).
        pcall(renderBankTableInner, ctx, list, bankOpen, visibleCols, filteredBank, hasCursor, lp)
        ImGui.EndTable()
    end
end

-- Module interface: render bank window (the classic standalone surface)
-- Params: context table containing all necessary state and functions from init.lua
function BankView.render(ctx)
    if not registry.shouldDraw("bank") then return end

    local bankOpen = ctx.isBankWindowOpen and ctx.isBankWindowOpen() or false
    local list = BankView.resolveList(ctx, bankOpen)

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
    local barsOn = tostring(ctx.layoutConfig.UIMode or "classic") == "bars"
    -- The kit band carries the pin in bars; the legacy checkbox row stays for classic.
    if not barsOn and ctx.renderWindowLock then ctx.renderWindowLock(ctx, "bank") end

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

    -- Header. In bars this is the shared 26px band (19d): title, the one number the bar
    -- never shows (what the bank HOLDS), the refresh action as an icon, and the pin. The
    -- refresh icon is disabled while the bank is closed because a rescan has nothing to
    -- read then — and the reason is printed in the chip line right below it, never in a
    -- tooltip (kit rule: a disabled control states its reason beside itself).
    if barsOn then
        windowHeader.render({
            id = "bank", title = "Bank",
            stat = BankView.statText(ctx, list, bankOpen),
            actions = {
                { label = windowHeader.GLYPHS.REFRESH,
                  tooltip = bankOpen and "Rescan the bank" or nil,
                  disabled = not bankOpen,
                  onClick = function() if ctx.scanBank then ctx.scanBank() end end },
            },
            lock = windowHeader.registryLock("bank", ctx),
        })
    else
        ctx.theme.TextHeader("Bank")
        ImGui.SameLine()
        ctx.renderRefreshButton(ctx, "Refresh##BankHeader", "Rescan bank", function() ctx.scanBank() end, { width = 80, messageBefore = "Scanning bank...", messageAfter = "Bank refreshed" })
        ImGui.Separator()
    end

    -- 20a: the source chip replaces the old Online/Offline pair. It supersedes both — it
    -- says the same thing plus the age, the holdings, and the input rule, in one line and
    -- without a tooltip carrying the load. In bars the holdings move up into the band.
    BankView.renderSourceChip(ctx, list, bankOpen, not barsOn)
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
    -- The second Refresh that used to sit here while the bank was open is gone: the header
    -- already carries one, and two buttons doing the identical thing on one window is the
    -- redundancy the §9 pass exists to delete.
    ImGui.Separator()

    -- 20a: same table, dimmed, when it is a read-only snapshot. Push/pop OUTSIDE the
    -- render call so a content throw can never strand the style var.
    if not bankOpen then
        ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.55)
    end
    BankView.renderTable(ctx, list, bankOpen)
    if not bankOpen then
        ImGui.PopStyleVar(1)
    end

    ImGui.End()
end

-- Registry: Bank module (4.2 state ownership — window in registry only)
registry.register({
    id          = "bank",
    zone        = "R1",  -- window_zones placement column/slot (mockup 10a)
    label       = "Bank",
    buttonWidth = 60,
    tooltip     = "View bank items; shift+click to move to inventory",
    layoutKeys  = { x = "BankWindowX", y = "BankWindowY" },
    enableKey   = "ShowBankWindow",
    render      = function(refs)
        local ctx = context.build()
        BankView.render(ctx)
    end,
})

return BankView
