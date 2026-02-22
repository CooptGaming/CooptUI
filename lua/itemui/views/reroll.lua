--[[
    Reroll Companion — UI for server Augment and Mythical reroll lists.
    Architecture: New companion window (like Augments/Bank) with two internal tabs:
    Augments and Mythicals. Each tab shows the server list, inventory match counter,
    and actions (Add from Cursor, Remove, Roll, Refresh). Fits CoOpt UI's existing
    companion pattern and design language.
]]

local mq = require('mq')
require('ImGui')
local constants = require('itemui.constants')
local ItemTooltip = require('itemui.utils.item_tooltip')

local REROLL = constants.REROLL or {}
local ITEMS_REQUIRED = REROLL.ITEMS_REQUIRED or 10

local RerollView = {}

local AUGMENT_TYPE = "Augmentation"

-- Build set of list IDs for "on list" checks.
local function listIdSet(list)
    local set = {}
    if list then for _, e in ipairs(list) do if e.id then set[e.id] = true end end end
    return set
end

-- Tab index: 1 = Augments, 2 = Mythicals
local function renderTabContent(ctx, track, rerollService)
    local isAug = (track == "aug")
    local list = isAug and rerollService.getAugList() or rerollService.getMythicalList()
    local inventoryItems = ctx.inventoryItems or {}
    local countInInv = rerollService.countInInventory(list, inventoryItems)
    local theme = ctx.theme
    local setStatusMessage = ctx.setStatusMessage or function() end

    -- Selection state (defined first so Remove button can use it)
    local selectedKey = isAug and "rerollSelectedAugId" or "rerollSelectedMythicalId"
    local pendingRemoveKey = isAug and "rerollPendingRemoveAugId" or "rerollPendingRemoveMythicalId"
    local pendingRollKey = isAug and "rerollPendingAugRoll" or "rerollPendingMythicalRoll"
    local selectedId = ctx.uiState[selectedKey]
    local pendingRemoveId = ctx.uiState[pendingRemoveKey]
    local pendingRoll = ctx.uiState[pendingRollKey]

    -- Inventory match counter: X / 10, color grey -> yellow -> green
    local counterText = string.format("%d / %d items in inventory", countInInv, ITEMS_REQUIRED)
    if countInInv >= ITEMS_REQUIRED then
        ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Success))
    elseif countInInv >= (ITEMS_REQUIRED - 2) then
        ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Warning))
    else
        ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Muted))
    end
    ImGui.Text(counterText)
    ImGui.PopStyleColor(1)
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Number of listed items currently in your inventory (need 10 to roll)")
        ImGui.EndTooltip()
    end

    -- Action buttons row
    local hasCursor = ctx.hasItemOnCursor and ctx.hasItemOnCursor()
    local cursorOnList = rerollService.isCursorIdInList(list)
    local cursorValid = hasCursor and (isAug or rerollService.isCursorMythical())
    local addDisabled = not hasCursor or cursorOnList or not cursorValid
    local rollDisabled = countInInv < ITEMS_REQUIRED

    ImGui.SameLine()
    if addDisabled then
        theme.PushKeepButton(true)
    else
        theme.PushKeepButton(false)
    end
    local addLabel = "Add (from Cursor)##" .. track
    if ImGui.Button(addLabel, ImVec2(120, 0)) then
        if isAug then rerollService.addAugFromCursor() else rerollService.addMythicalFromCursor() end
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        if not hasCursor then ImGui.Text("Place an item on your cursor first.") end
        if hasCursor and cursorOnList then ImGui.Text("This item is already on the list.") end
        if hasCursor and not cursorValid and not isAug then ImGui.Text("Cursor item must be a Mythical (name starts with Mythical).") end
        if cursorValid and not cursorOnList then ImGui.Text("Add cursor item to the list.") end
        ImGui.EndTooltip()
    end
    theme.PopButtonColors()

    ImGui.SameLine()
    theme.PushDeleteButton()
    local removeLabel = "Remove##" .. track
    if ImGui.Button(removeLabel, ImVec2(70, 0)) then
        if selectedId then
            ctx.uiState[pendingRemoveKey] = selectedId
        else
            setStatusMessage("Select an item in the list first.")
        end
    end
    ImGui.PopStyleColor(3)
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Select a row (or use context menu), then click Remove to confirm."); ImGui.EndTooltip() end

    ImGui.SameLine()
    if rollDisabled then
        theme.PushKeepButton(true)
    else
        theme.PushKeepButton(false)
    end
    local rollLabel = "Roll##" .. track
    if ImGui.Button(rollLabel, ImVec2(60, 0)) then
        if not rollDisabled then ctx.uiState[pendingRollKey] = true end
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        if rollDisabled then ImGui.Text("You need 10 listed items in inventory to roll.") else ImGui.Text("Consumes 10 listed items from inventory. Confirm before rolling.") end
        ImGui.EndTooltip()
    end
    theme.PopButtonColors()

    ImGui.SameLine()
    if ImGui.Button("Refresh List##" .. track, ImVec2(90, 0)) then
        if isAug then rerollService.requestAugList() else rerollService.requestMythicalList() end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Re-query server list (!auglist / !mythicallist)"); ImGui.EndTooltip() end

    ImGui.Separator()

    -- Pending remove confirmation
    if pendingRemoveId then
        theme.TextWarning("Remove item ID " .. tostring(pendingRemoveId) .. " from list?")
        ImGui.SameLine()
        if ImGui.Button("Confirm Remove##" .. track, ImVec2(120, 0)) then
            if isAug then rerollService.removeAug(pendingRemoveId) else rerollService.removeMythical(pendingRemoveId) end
            ctx.uiState[pendingRemoveKey] = nil
            ctx.uiState[selectedKey] = nil
        end
        ImGui.SameLine()
        if ImGui.Button("Cancel##Remove" .. track, ImVec2(60, 0)) then
            ctx.uiState[pendingRemoveKey] = nil
        end
        ImGui.Separator()
    end

    -- Pending roll confirmation
    if pendingRoll then
        theme.TextWarning("Roll will consume 10 listed items from your inventory. Continue?")
        ImGui.SameLine()
        theme.PushKeepButton(false)
        if ImGui.Button("Confirm Roll##" .. track, ImVec2(100, 0)) then
            if isAug then rerollService.augRoll() else rerollService.mythicalRoll() end
            ctx.uiState[pendingRollKey] = nil
        end
        theme.PopButtonColors()
        ImGui.SameLine()
        if ImGui.Button("Cancel##Roll" .. track, ImVec2(60, 0)) then
            ctx.uiState[pendingRollKey] = nil
        end
        ImGui.Separator()
    end

    -- Server list table: Name, Item ID, Status (On list + In inv / On list only), In Inventory (sortable)
    theme.TextHeader(isAug and "Server reroll list (augments)" or "Server reroll list (mythicals)")
    if #list == 0 then
        theme.TextMuted(isAug and "No augments on list. Add from cursor or refresh." or "No mythicals on list. Add from cursor or refresh.")
    else
    local tableFlags = bit32.bor(ctx.uiState.tableFlags or 0, ImGuiTableFlags.Sortable)
    local nCols = 4
    if ImGui.BeginTable("RerollList_" .. track, nCols, tableFlags) then
        ImGui.TableSetupColumn("Item Name", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable, ImGuiTableColumnFlags.DefaultSort), 0, 0)
        ImGui.TableSetupColumn("Item ID", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), 60, 1)
        ImGui.TableSetupColumn("Status", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), 120, 2)
        ImGui.TableSetupColumn("In Inventory", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), 80, 3)
        ImGui.TableSetupScrollFreeze(0, 1)
        ImGui.TableHeadersRow()

        -- Sort
        local sortSpecs = ImGui.TableGetSortSpecs()
        local sortCol = 0
        local sortAsc = true
        if sortSpecs and sortSpecs.SpecsCount > 0 then
            local spec = sortSpecs:Specs(1)
            if spec then
                sortCol = spec.ColumnIndex
                sortAsc = (spec.SortDirection == ImGuiSortDirection.Ascending)
            end
        end
        local sorted = {}
        for i = 1, #list do sorted[i] = list[i] end
        local inInvSet = {}
        for _, entry in ipairs(list) do
            for _, inv in ipairs(inventoryItems) do
                if (inv.id or inv.ID) == entry.id then inInvSet[entry.id] = true; break end
            end
        end
        -- Strict comparator for table.sort: never return true when a and b are equal; use id as tie-breaker.
        table.sort(sorted, function(a, b)
            local aid, bid = a.id or 0, b.id or 0
            local an, bn = (a.name or ""):lower(), (b.name or ""):lower()
            local av = (inInvSet[a.id] and 1) or 0
            local bv = (inInvSet[b.id] and 1) or 0
            local primary_lt, primary_gt
            if sortCol == 0 then
                primary_lt = an < bn
                primary_gt = an > bn
            elseif sortCol == 1 then
                primary_lt = aid < bid
                primary_gt = aid > bid
            else
                primary_lt = av < bv
                primary_gt = av > bv
            end
            if primary_lt then return sortAsc end
            if primary_gt then return not sortAsc end
            -- Tie-breaker: same primary value -> order by id so comparator is strict
            return (aid < bid) and sortAsc or (aid > bid) and not sortAsc
        end)

        for _, entry in ipairs(sorted) do
            ImGui.TableNextRow()
            local inInv = inInvSet[entry.id] == true
            local rowId = "reroll_" .. track .. "_" .. tostring(entry.id)

            ImGui.TableNextColumn()
            ImGui.PushID(rowId)
            if inInv then
                ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Success))
            else
                ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Muted))
            end
            ImGui.Selectable(entry.name or ("ID " .. tostring(entry.id)), selectedId == entry.id, ImGuiSelectableFlags.None, ImVec2(0, 0))
            ImGui.PopStyleColor(1)
            if ImGui.IsItemHovered() then
                -- Tooltip: try to show item details from inventory if we have it
                local invItem = nil
                for _, inv in ipairs(inventoryItems) do
                    if (inv.id or inv.ID) == entry.id then invItem = inv; break end
                end
                if invItem and ctx.getItemStatsForTooltip then
                    local showItem = ctx.getItemStatsForTooltip(invItem, "inv")
                    if showItem then
                        local opts = { source = "inv", bag = invItem.bag, slot = invItem.slot }
                        local effects, w, h = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
                        opts.effects = effects
                        ItemTooltip.beginItemTooltip(w, h)
                        ImGui.Text("Stats")
                        ImGui.Separator()
                        ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
                        ImGui.EndTooltip()
                    end
                else
                    ImGui.BeginTooltip()
                    ImGui.Text(entry.name or "—")
                    ImGui.Text("ID: " .. tostring(entry.id))
                    ImGui.Text(inInv and "In inventory" or "Not in inventory")
                    ImGui.EndTooltip()
                end
            end
            if ImGui.IsItemClicked(ImGuiMouseButton.Left) then
                ctx.uiState[selectedKey] = entry.id
            end
            if ImGui.BeginPopupContextItem() then
                if ImGui.MenuItem("Remove from list") then
                    ctx.uiState[pendingRemoveKey] = entry.id
                end
                ImGui.EndPopup()
            end
            ImGui.PopID()

            ImGui.TableNextColumn()
            ImGui.Text(tostring(entry.id or "—"))

            ImGui.TableNextColumn()
            if inInv then
                ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Success))
                ImGui.Text("On list, in inv")
                ImGui.PopStyleColor(1)
            else
                theme.TextMuted("On list only")
            end

            ImGui.TableNextColumn()
            if inInv then
                ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Success))
                ImGui.Text("Yes")
                ImGui.PopStyleColor(1)
            else
                theme.TextMuted("No")
            end
        end
        ImGui.EndTable()
    end
    end

    -- In your inventory: augments (or mythicals) currently in bags
    local prefix = REROLL.MYTHICAL_NAME_PREFIX or "Mythical"
    local invFiltered = {}
    for _, it in ipairs(inventoryItems) do
        if isAug then
            local t = (it.type or ""):match("^%s*(.-)%s*$")
            if t == AUGMENT_TYPE then table.insert(invFiltered, it) end
        else
            local name = it.name or ""
            if name:sub(1, #prefix) == prefix then table.insert(invFiltered, it) end
        end
    end
    local listIds = listIdSet(list)

    ImGui.Spacing()
    theme.TextHeader(isAug and "In your inventory (augmentations)" or "In your inventory (mythicals)")
    if #invFiltered == 0 then
        theme.TextMuted(isAug and "No augmentations in your bags." or "No mythical items in your bags.")
    else
        local invTableFlags = bit32.bor(ctx.uiState.tableFlags or 0, ImGuiTableFlags.Sortable)
        if ImGui.BeginTable("RerollInv_" .. track, 3, invTableFlags) then
            ImGui.TableSetupColumn("Item Name", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable), 0, 0)
            ImGui.TableSetupColumn("Item ID", ImGuiTableColumnFlags.WidthFixed, 60, 1)
            ImGui.TableSetupColumn("On list", ImGuiTableColumnFlags.WidthFixed, 70, 2)
            ImGui.TableSetupScrollFreeze(0, 1)
            ImGui.TableHeadersRow()
            for _, it in ipairs(invFiltered) do
                local id = it.id or it.ID
                local onList = id and listIds[id]
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                local dispName = it.name or ("ID " .. tostring(id))
                if (it.stackSize or 1) > 1 then dispName = dispName .. string.format(" (x%d)", it.stackSize or 1) end
                if onList then
                    ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Success))
                end
                ImGui.Text(dispName)
                if onList then ImGui.PopStyleColor(1) end
                if ImGui.IsItemHovered() and ctx.getItemStatsForTooltip then
                    local showItem = ctx.getItemStatsForTooltip(it, "inv")
                    if showItem then
                        local opts = { source = "inv", bag = it.bag, slot = it.slot }
                        local effects, w, h = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
                        opts.effects = effects
                        ItemTooltip.beginItemTooltip(w, h)
                        ImGui.Text("Stats")
                        ImGui.Separator()
                        ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
                        ImGui.EndTooltip()
                    end
                end
                ImGui.TableNextColumn()
                ImGui.Text(tostring(id or "—"))
                ImGui.TableNextColumn()
                if onList then
                    ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Success))
                    ImGui.Text("Yes")
                    ImGui.PopStyleColor(1)
                else
                    theme.TextMuted("No")
                end
            end
            ImGui.EndTable()
        end
    end
end

-- Render the full Reroll Companion window (tabs + content).
function RerollView.render(ctx)
    if not ctx.uiState.rerollWindowShouldDraw then return end

    local layoutConfig = ctx.layoutConfig or {}
    local layoutDefaults = ctx.layoutDefaults or {}
    local constants_views = constants.VIEWS or {}
    local w = layoutConfig.WidthRerollPanel or layoutDefaults.WidthRerollPanel or constants_views.WidthRerollPanel or 520
    local h = layoutConfig.HeightReroll or layoutDefaults.HeightReroll or constants_views.HeightReroll or 480

    local rx = layoutConfig.RerollWindowX or 0
    local ry = layoutConfig.RerollWindowY or 0
    if rx and ry and (rx ~= 0 or ry ~= 0) then
        ImGui.SetNextWindowPos(ImVec2(rx, ry), ImGuiCond.FirstUseEver)
    end
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.FirstUseEver)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Reroll Companion##ItemUIReroll", ctx.uiState.rerollWindowOpen, windowFlags)
    ctx.uiState.rerollWindowOpen = winOpen
    ctx.uiState.rerollWindowShouldDraw = winOpen

    if not winOpen then ImGui.End(); return end
    if not winVis then ImGui.End(); return end

    if not ctx.uiState.uiLocked then
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            layoutConfig.WidthRerollPanel = cw
            layoutConfig.HeightReroll = ch
        end
    end
    local cx, cy = ImGui.GetWindowPos()
    if cx and cy and ctx.scheduleLayoutSave then
        if not layoutConfig.RerollWindowX or math.abs(layoutConfig.RerollWindowX - cx) > 1 or
           not layoutConfig.RerollWindowY or math.abs(layoutConfig.RerollWindowY - cy) > 1 then
            layoutConfig.RerollWindowX = cx
            layoutConfig.RerollWindowY = cy
            ctx.scheduleLayoutSave()
        end
    end

    local rerollService = ctx.rerollService
    if not rerollService then
        ctx.theme.TextMuted("Reroll service not available.")
        ImGui.End()
        return
    end

    -- Tab bar: Augments | Mythicals
    ctx.uiState.rerollTab = ctx.uiState.rerollTab or 1
    if ImGui.BeginTabBar("RerollTabs##ItemUI", ImGuiTabBarFlags.None) then
        if ImGui.BeginTabItem("Augments", nil, ImGuiTabItemFlags.None) then
            ctx.uiState.rerollTab = 1
            renderTabContent(ctx, "aug", rerollService)
            ImGui.EndTabItem()
        end
        if ImGui.BeginTabItem("Mythicals", nil, ImGuiTabItemFlags.None) then
            ctx.uiState.rerollTab = 2
            renderTabContent(ctx, "mythical", rerollService)
            ImGui.EndTabItem()
        end
        ImGui.EndTabBar()
    end

    ImGui.End()
end

return RerollView
