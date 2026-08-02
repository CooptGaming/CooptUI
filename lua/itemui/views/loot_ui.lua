--[[
    Loot UI View - Dedicated window for loot macro progress and session summary.
    Shown when user starts Loot current / Loot all (if not suppressed). Stays open until Esc or Close.
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')
local item_name = require('itemui.utils.item_name')

local constants = require('itemui.constants')
local diagnostics = require('itemui.core.diagnostics')
local LootUIView = {}

-- Per-frame render memos (invalidated by source-list identity/length changes)
local namesFallbackMemo = { src = nil, len = 0, rows = nil }
local normalizedNamesMemo = { src = nil, len = 0, best = nil, names = nil }

-- Quick loot rules: Name cell as a selectable with a right-click menu feeding the
-- always/never loot lists. MUST be called inside a per-row ImGui.PushID scope —
-- item names repeat across rows, and the row id is what keeps the Selectable and
-- popup ids unique (v1 of this feature triggered ImGui id conflicts without it).
local function renderNameCellWithLootMenu(ctx, theme, name, nameColor)
    name = name or ""
    if nameColor then ImGui.PushStyleColor(ImGuiCol.Text, nameColor) end
    ImGui.Selectable(name, false, ImGuiSelectableFlags.None, ImVec2(0, 0))
    if nameColor then ImGui.PopStyleColor() end
    if name ~= "" and ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
        ImGui.OpenPopup("LootRuleCtx")
    end
    -- The shared builder (windows pass item 7). This menu used to be hand-rolled, which
    -- is why it drifted: it carried "Remove from Never-loot list" as a THIRD row
    -- expressing the second row's state, where the builder renders one row with a check.
    -- A corpse row is a name and nothing else, so the lootRow context is RULES plus the
    -- id-needing rows rendered blocked - rule 3, they stay in place and say why.
    if ctx.renderItemContextMenu then
        ctx.renderItemContextMenu(ctx, { name = name }, {
            source = "inv", context = "lootRow", popupId = "LootRuleCtx",
        })
    end
end


-- Per 4.2 state ownership: all Loot UI companion state
local state = {
    lootUIOpen = false,
    lootRunCorpsesLooted = 0,
    lootRunTotalCorpses = 0,
    lootRunCurrentCorpse = "",
    lootRunLootedList = {},
    lootRunLootedItems = {},
    lootHistory = nil,
    skipHistory = nil,
    lootRunFinished = false,
    lootMythicalAlert = nil,
    lootMythicalDecisionStartAt = nil,
    lootMythicalFeedback = nil,
    lootRunTotalValue = 0,
    lootRunTributeValue = 0,
    lootRunBestItemName = "",
    lootRunBestItemValue = 0,
    lootRunSkipped = 0,   -- THIS run's skip count; skipHistory accumulates across runs
    corpseLootedHidden = true,
    lootUITab = 0,
}
function LootUIView.getState()
    return state
end

--- Clear Loot UI in-memory state and optionally clear session/alert INI (call on Esc or Close).
--- ctx.clearLootUIState() is provided by init.lua
function LootUIView.closeAndClearState(ctx)
    if ctx and ctx.clearLootUIState then ctx.clearLootUIState() end
end


--- Render the Loot UI window. Context must have: uiState, theme, layoutConfig, runLootCurrent, runLootAll, clearLootUIMythicalAlert, clearLootUIState.
function LootUIView.render(ctx)
    if not ctx or not state.lootUIOpen then return end

    local uiState = ctx.uiState  -- for layoutRevertedApplyFrames etc.
    local theme = ctx.theme
    local layoutConfig = ctx.layoutConfig or {}

    local forceApply = uiState.layoutRevertedApplyFrames and uiState.layoutRevertedApplyFrames > 0
    local condPos = forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver
    local w = layoutConfig.WidthLootPanel or constants.VIEWS.WidthLootPanel
    local h = layoutConfig.HeightLoot or constants.VIEWS.HeightLoot
    if w and h and w > 0 and h > 0 then
        -- Size floor (handoff item 6): band + table header + three rows - below this the
        -- 26px band stat is the first casualty.
        ImGui.SetNextWindowSizeConstraints(ImVec2(400, 240), ImVec2(16384, 16384))
        ImGui.SetNextWindowSize(ImVec2(w, h), condPos)
    end
    local lx = layoutConfig.LootWindowX
    local ly = layoutConfig.LootWindowY
    if lx and ly and (lx ~= 0 or ly ~= 0) then
        ImGui.SetNextWindowPos(ImVec2(lx, ly), condPos)
    end
    -- Loot window is always resizable (independent of main UI lock)
    local windowFlags = 0

    local winOpen, winVis = ImGui.Begin("CoOpt UI Loot Companion##LootUI", state.lootUIOpen, windowFlags)
    state.lootUIOpen = winOpen

    if not winOpen then
        LootUIView.closeAndClearState(ctx)
        ImGui.End()
        return
    end
    -- Escape closes this window via main Inventory Companion's LIFO handler only
    if not winVis then ImGui.End(); return end
    if ctx.renderWindowLock then ctx.renderWindowLock(ctx, "loot") end

    local function drawContent()
        -- Persist window size when resized (debounced via scheduleLayoutSave)
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            local prevW, prevH = layoutConfig.WidthLootPanel or 0, layoutConfig.HeightLoot or 0
            layoutConfig.WidthLootPanel = cw
            layoutConfig.HeightLoot = ch
            if (prevW ~= cw or prevH ~= ch) then ctx.scheduleLayoutSave() end
        end
        -- Mirror position back too (the bank.lua pattern). This window was the one
        -- positioned view that did not: window_zones reads these keys for drag detection,
        -- occupancy and magnet targets, and every force-apply re-applies them with
        -- ImGuiCond.Always — without the mirror, a user-dragged loot window teleported
        -- back to its stale stored position on the next zone action.
        local cx, cy = ImGui.GetWindowPos()
        if cx and cy then
            if not layoutConfig.LootWindowX or math.abs(layoutConfig.LootWindowX - cx) > 1 or
               not layoutConfig.LootWindowY or math.abs(layoutConfig.LootWindowY - cy) > 1 then
                layoutConfig.LootWindowX = cx
                layoutConfig.LootWindowY = cy
                ctx.scheduleLayoutSave()
            end
        end

        theme.TextHeader("Loot")
        ImGui.Separator()

        -- Tabs: Current (always) | Loot History (if enabled) | Skip History (if enabled)
        if not state.lootUITab then state.lootUITab = 0 end
        local enableLootHist = (ctx.uiState and ctx.uiState.enableLootHistory == true)
        local enableSkipHist = (ctx.uiState and ctx.uiState.enableSkipHistory == true)
        if state.lootUITab == 1 and not enableLootHist then state.lootUITab = 0 end
        if state.lootUITab == 2 and not enableSkipHist then state.lootUITab = 0 end
        local hasTabBarAPI = ImGui.BeginTabBar and ImGuiTabBarFlags and (ImGuiTabBarFlags.None ~= nil)
        if hasTabBarAPI and ImGui.BeginTabBar("LootUITabs", ImGuiTabBarFlags.None) then
            if ImGui.BeginTabItem("Current") then
                state.lootUITab = 0
                ImGui.EndTabItem()
            end
            if enableLootHist then
                if ImGui.BeginTabItem("Loot History") then
                    state.lootUITab = 1
                    if ctx.loadLootHistory then ctx.loadLootHistory() end
                    ImGui.EndTabItem()
                end
            end
            if enableSkipHist then
                if ImGui.BeginTabItem("Skip History") then
                    state.lootUITab = 2
                    if ctx.loadSkipHistory then ctx.loadSkipHistory() end
                    ImGui.EndTabItem()
                end
            end
            ImGui.EndTabBar()
        end
        ImGui.Separator()

        -- First-time tip (Current tab only)
        local tipSeen = (ctx.layoutConfig and (ctx.layoutConfig.LootUIFirstTipSeen or 0) ~= 0)
        if state.lootUITab == 0 and not tipSeen then
            ImGui.TextColored(theme.ToVec4(theme.Colors.Info), "Loot current = this corpse only. Loot all = all corpses in range.")
            if ImGui.Button("Got it##LootUITip") then
                if ctx.layoutConfig then ctx.layoutConfig.LootUIFirstTipSeen = 1 end
                if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
            end
            ImGui.Separator()
        end

        -- Current tab: buttons, progress, current loot table
        if state.lootUITab == 0 then
        -- Buttons: Loot current, Loot all
        if ctx.runLootCurrent and ImGui.Button("Loot current", ImVec2(110, 0)) then
            ctx.runLootCurrent()
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Target a corpse first. Loots only that corpse then stops.")
            ImGui.EndTooltip()
        end
        ImGui.SameLine()
        if ctx.runLootAll and ImGui.Button("Loot all", ImVec2(90, 0)) then
            ctx.runLootAll()
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Loot all corpses in range (same radius as loot.mac).")
            ImGui.EndTooltip()
        end
        -- Show/Hide looted corpses (troubleshooting; same as /hidecorpse looted vs /hidecorpse none)
        if state.corpseLootedHidden then
            if ImGui.Button("Show looted corpses", ImVec2(140, 0)) then
                mq.cmd('/hidecorpse none')
                state.corpseLootedHidden = false
            end
        else
            if ImGui.Button("Hide looted corpses", ImVec2(140, 0)) then
                mq.cmd('/hidecorpse looted')
                state.corpseLootedHidden = true
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Toggle visibility of looted corpses (troubleshooting). Same as /hidecorpse looted and /hidecorpse none.")
            ImGui.EndTooltip()
        end
        ImGui.SameLine()
        if (enableLootHist or enableSkipHist) and ctx.clearLootHistory and ctx.clearSkipHistory and ImGui.Button("Clear history", ImVec2(100, 0)) then
            if enableLootHist then ctx.clearLootHistory() end
            if enableSkipHist then ctx.clearSkipHistory() end
        end
        if (enableLootHist or enableSkipHist) and ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            if enableLootHist and enableSkipHist then
                ImGui.Text("Clear both Loot History and Skip History (this tab and the other tabs).")
            elseif enableLootHist then
                ImGui.Text("Clear Loot History.")
            else
                ImGui.Text("Clear Skip History.")
            end
            ImGui.EndTooltip()
        end
        ImGui.Separator()

        -- Suppress control -- inverted sense to match Settings > General > Features'
        -- "Enable Loot UI during looting" (same uiState.suppressWhenLootMac key).
        local openDuringLoots = not uiState.suppressWhenLootMac
        local prevOpenDuringLoots = openDuringLoots
        openDuringLoots = ImGui.Checkbox("Open during loots##LootSuppress", openDuringLoots)
        if prevOpenDuringLoots ~= openDuringLoots then
            uiState.suppressWhenLootMac = not openDuringLoots
            if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Same setting as Settings > General > Features: 'Enable Loot UI during looting'.")
            ImGui.Text("Uncheck to keep this window closed while loot runs.")
            ImGui.EndTooltip()
        end
        ImGui.Separator()

        -- Mythical feedback: brief "You chose: Take" / "Passed — left on corpse" after Take/Pass
        local feedback = state.lootMythicalFeedback
        if feedback and feedback.message and feedback.showUntil then
            local now = mq.gettime()
            if now >= feedback.showUntil then
                state.lootMythicalFeedback = nil
            else
                ImGui.PushStyleColor(ImGuiCol.Border, theme.ToVec4(theme.Colors.Success))
                ImGui.PushStyleVar(ImGuiStyleVar.ChildBorderSize, 2)
                if ImGui.BeginChild("MythicalFeedbackCard", ImVec2(-1, constants.UI.LOOT_FEEDBACK_CARD_HEIGHT), true) then
                    ImGui.TextColored(theme.ToVec4(theme.Colors.Success), feedback.message)
                end
                ImGui.EndChild()
                ImGui.PopStyleVar()
                ImGui.PopStyleColor()
                ImGui.Separator()
            end
        end

        -- Mythical alert: pending Take/Pass decision (distinct styling, countdown, link)
        if state.lootMythicalAlert and state.lootMythicalAlert.itemName and state.lootMythicalAlert.itemName ~= "" then
            local decision = (state.lootMythicalAlert.decision or ""):lower()
            local pending = (decision == "" or decision == "pending")
            local alert = state.lootMythicalAlert
            local amberBg = { 0.18, 0.14, 0.06, 0.85 }
            ImGui.PushStyleColor(ImGuiCol.Border, theme.ToVec4(theme.Colors.Warning))
            ImGui.PushStyleColor(ImGuiCol.ChildBg, ImVec4(amberBg[1], amberBg[2], amberBg[3], amberBg[4]))
            ImGui.PushStyleVar(ImGuiStyleVar.ChildBorderSize, 2)
            ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 4)
            local cardH = constants.UI.LOOT_MYTHICAL_CARD_HEIGHT
            if pending then cardH = constants.UI.LOOT_MYTHICAL_CARD_HEIGHT_PENDING end
            if ImGui.BeginChild("MythicalAlertCard", ImVec2(-1, cardH), true) then
                ImGui.TextColored(theme.ToVec4(theme.Colors.Warning), "MYTHICAL")
                ImGui.SameLine()
                ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), " NoDrop/NoTrade")
                local iconHover = false
                if ctx.drawItemIcon and alert.iconId and alert.iconId > 0 then
                    ctx.drawItemIcon(alert.iconId)
                    iconHover = ImGui.IsItemHovered()
                    ImGui.SameLine()
                end
                ImGui.TextColored(theme.ToVec4(theme.Colors.Header), alert.itemName or "")
                local nameHover = ImGui.IsItemHovered()
                -- Hover tooltip: resolve item from corpse when corpse is open so user can see full description before Take/Pass
                if iconHover or nameHover then
                    local corpse = mq.TLO and mq.TLO.Corpse
                    local itemsCount = corpse and corpse.Items and (corpse.Items() or 0)
                    local corpseSlot = nil
                    if corpse and itemsCount and itemsCount > 0 and alert.itemName and alert.itemName ~= "" then
                        for i = 1, itemsCount do
                            local it = corpse.Item and corpse.Item(i)
                            local n = it and it.Name and it.Name()
                            if n and tostring(n) == alert.itemName then
                                corpseSlot = i
                                break
                            end
                        end
                    end
                    if corpseSlot and ctx.getItemStatsForTooltip then
                        local showItem = ctx.getItemStatsForTooltip({ bag = 0, slot = corpseSlot }, "corpse")
                        if showItem and showItem.name then
                            local opts = { source = "corpse", bag = 0, slot = corpseSlot }
                            local effects, w, h = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
                            opts.effects = effects
                            ItemTooltip.beginItemTooltip(w, h)
                            ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
                            ImGui.EndTooltip()
                        else
                            ImGui.BeginTooltip()
                            ImGui.Text(alert.itemName or "-")
                            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Open the corpse to see full description.")
                            ImGui.EndTooltip()
                        end
                    else
                        ImGui.BeginTooltip()
                        ImGui.Text(alert.itemName or "-")
                        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Open the corpse loot window to see full description.")
                        ImGui.EndTooltip()
                    end
                end
                if alert.corpseName and alert.corpseName ~= "" then
                    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Corpse: " .. alert.corpseName)
                end
                if alert.timestamp and alert.timestamp ~= "" then
                    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Found: " .. alert.timestamp)
                end
                if pending then
                    local remainSec = constants.TIMING.LOOT_MYTHICAL_DECISION_SEC
                    local startAt = state.lootMythicalDecisionStartAt
                    if startAt and type(startAt) == "number" then
                        remainSec = math.max(0, constants.TIMING.LOOT_MYTHICAL_DECISION_SEC - ((os.time and os.time() or 0) - startAt))
                    end
                    local mins = math.floor(remainSec / 60)
                    local secs = math.floor(remainSec % 60)
                    ImGui.TextColored(theme.ToVec4(theme.Colors.Info), string.format("Time to decide: %d:%02d", mins, secs))
                    if remainSec < 60 then
                        ImGui.SameLine()
                        ImGui.TextColored(theme.ToVec4(theme.Colors.Error), " (less than 1 min)")
                    end
                    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Take = loot it. Pass = leave on corpse for group.")
                end
                if pending then
                    if ImGui.Button("Take##MythicalAlert") then
                        if ctx.mythicalTake then ctx.mythicalTake() end
                    end
                    ImGui.SameLine()
                    if ImGui.Button("Pass##MythicalAlert") then
                        if ctx.mythicalPass then ctx.mythicalPass() end
                    end
                    ImGui.SameLine()
                    -- Take + Reroll: enqueue the SAME dock action the bar's Reroll button
                    -- uses, so both surfaces share one corrected handler (main_loop
                    -- phase0b): it resolves the item's real id from the still-open corpse
                    -- before taking, and only falls back to the name latch when it can't.
                    -- An inline take here would lose the id and re-open the
                    -- same-name-different-id hazard. Replaces the old decision=="taken"
                    -- Reroll button, which was dead code: nothing ever wrote "taken" and
                    -- the alert was nil'd on Take anyway.
                    if ImGui.Button("Take + Reroll##MythicalAlert") then
                        local q = uiState.dockActionQueue
                        if not q then q = {}; uiState.dockActionQueue = q end
                        q[#q + 1] = { kind = "loot_take_reroll" }
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.BeginTooltip()
                        ImGui.Text("Take it AND queue it for the mythical reroll list.")
                        ImGui.EndTooltip()
                    end
                    ImGui.SameLine()
                end
                if ImGui.Button("Dismiss##MythicalAlert") then
                    if ctx.clearLootUIMythicalAlert then ctx.clearLootUIMythicalAlert() end
                end
            end
            ImGui.EndChild()
            ImGui.PopStyleVar()
            ImGui.PopStyleVar()
            ImGui.PopStyleColor()
            ImGui.PopStyleColor()
            ImGui.Separator()
        end

        -- Status (while running or just finished)
        local running = (mq.TLO and mq.TLO.Macro and mq.TLO.Macro.Name and (mq.TLO.Macro.Name() or "")) or ""
        running = running:lower()
        running = (running == "loot" or running == "loot.mac")
        if running or state.lootRunCorpsesLooted > 0 or state.lootRunTotalCorpses > 0 then
            ImGui.Text(string.format("Corpses looted: %d", state.lootRunCorpsesLooted))
            if state.lootRunTotalCorpses > 0 then
                ImGui.SameLine()
                ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), string.format(" / %d", state.lootRunTotalCorpses))
            end
            if state.lootRunCurrentCorpse and state.lootRunCurrentCorpse ~= "" then
                ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Current: " .. state.lootRunCurrentCorpse)
            end
            local total = state.lootRunTotalCorpses or 0
            local current = state.lootRunCorpsesLooted or 0
            local fraction = (total > 0) and (current / total) or 0
            local overlay = string.format("%d / %d", current, total > 0 and total or 0)
            theme.RenderProgressBar(fraction, ImVec2(-1, 24), overlay)
            ImGui.Separator()
        end

        -- Looted list (current run; persists until next run with items).
        -- The names-only fallback conversion is memoized: rebuilt when the source list
        -- or its length changes, not every frame.
        local itemsForTable = state.lootRunLootedItems and #state.lootRunLootedItems > 0 and state.lootRunLootedItems
        if not itemsForTable and state.lootRunLootedList and #state.lootRunLootedList > 0 then
            local src, len = state.lootRunLootedList, #state.lootRunLootedList
            if namesFallbackMemo.src ~= src or namesFallbackMemo.len ~= len then
                local t = {}
                for _, name in ipairs(src) do
                    t[#t+1] = { name = name, value = 0, statusText = "\xe2\x80\x94", willSell = false }
                end
                namesFallbackMemo.src, namesFallbackMemo.len, namesFallbackMemo.rows = src, len, t
            end
            itemsForTable = namesFallbackMemo.rows
        end
        if itemsForTable and #itemsForTable > 0 then
            local n = #itemsForTable
            local totalVal = state.lootRunTotalValue or 0
            local summaryStr = string.format("%d items", n)
            if totalVal > 0 then
                summaryStr = summaryStr .. "  .  " .. (ItemUtils.formatValue and ItemUtils.formatValue(totalVal) or tostring(totalVal) .. "c")
            end
            ImGui.TextColored(theme.ToVec4(theme.Colors.Success), summaryStr)
            if state.lootRunBestItemName and state.lootRunBestItemName ~= "" then
                local bestVal = state.lootRunBestItemValue or 0
                ImGui.Text("Best: ")
                ImGui.SameLine()
                ImGui.TextColored(theme.ToVec4(theme.Colors.Header), state.lootRunBestItemName)
                if bestVal > 0 then
                    ImGui.SameLine()
                    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), " (" .. (ItemUtils.formatValue and ItemUtils.formatValue(bestVal) or tostring(bestVal) .. "c") .. ")")
                end
            end
            ImGui.Text(string.format("Looted (%d items):", n))
            local tableFlags = ImGuiTableFlags.BordersOuter + ImGuiTableFlags.BordersInnerH + ImGuiTableFlags.ScrollY + ImGuiTableFlags.RowBg
            if ImGui.BeginChild("LootedList", ImVec2(-1, -constants.UI.LOOT_CURRENT_TABLE_FOOTER), true) then
                if ImGui.BeginTable("LootedItemsTable", 4, tableFlags) then
                    ImGui.TableSetupColumn("#", ImGuiTableColumnFlags.WidthFixed, constants.UI.LOOT_TABLE_COL_NUM_WIDTH, 0)
                    ImGui.TableSetupColumn("Name", ImGuiTableColumnFlags.WidthStretch, 0, 1)
                    ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthFixed, constants.UI.LOOT_TABLE_COL_VALUE_WIDTH, 2)
                    ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, constants.UI.LOOT_TABLE_COL_STATUS_WIDTH, 3)
                    ImGui.TableSetupScrollFreeze(0, 1)
                    ImGui.TableHeadersRow()
                    local normalizedBestName = state.lootRunBestItemName and item_name.normalizeItemName(state.lootRunBestItemName) or nil
                    -- Normalized names memo: full-list normalization only when the list or best-name changes
                    local normalizedRowNames = {}
                    if normalizedBestName then
                        local m = normalizedNamesMemo
                        if m.src ~= itemsForTable or m.len ~= #itemsForTable or m.best ~= normalizedBestName then
                            local names = {}
                            for i, row in ipairs(itemsForTable) do
                                names[i] = item_name.normalizeItemName(row.name)
                            end
                            m.src, m.len, m.best, m.names = itemsForTable, #itemsForTable, normalizedBestName, names
                        end
                        normalizedRowNames = m.names
                    end
                    local clipper = ImGuiListClipper.new()
                    clipper:Begin(#itemsForTable)
                    while clipper:Step() do
                        for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                            local row = itemsForTable[i]
                            if not row then goto continue end
                            ImGui.TableNextRow()
                            ImGui.TableNextColumn()
                            ImGui.Text(tostring(i))
                            ImGui.TableNextColumn()
                            local bestColor = (normalizedBestName and normalizedRowNames[i] == normalizedBestName)
                                and theme.ToVec4(theme.Colors.Header) or nil
                            ImGui.PushID(i)
                            renderNameCellWithLootMenu(ctx, theme, row.name, bestColor)
                            ImGui.PopID()
                            ImGui.TableNextColumn()
                            local valStr = (ItemUtils.formatValue and ItemUtils.formatValue(row.value or 0)) or tostring(row.value or 0)
                            ImGui.Text(valStr)
                            ImGui.TableNextColumn()
                            local statusText, statusColor = ctx.formatSellStatus(row.statusText, row.willSell, theme)
                            ImGui.TextColored(statusColor, statusText)
                            ::continue::
                        end
                    end
                    clipper:End()
                    ImGui.EndTable()
                end
            end
            ImGui.EndChild()
            ImGui.Separator()
        end
        end -- Current tab

        -- Loot History tab: cumulative recently looted items
        if state.lootUITab == 1 then
            local hist = state.lootHistory or {}
            if ctx.clearLootHistory and ImGui.Button("Clear history", ImVec2(100, 0)) then
                ctx.clearLootHistory()
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Clear Loot History (this list only).")
                ImGui.EndTooltip()
            end
            ImGui.SameLine()
            ImGui.Text(string.format("Recently looted (%d entries, newest last):", #hist))
            if #hist > 0 then
                local tableFlags = ImGuiTableFlags.BordersOuter + ImGuiTableFlags.BordersInnerH + ImGuiTableFlags.ScrollY + ImGuiTableFlags.RowBg
                if ImGui.BeginChild("LootHistoryList", ImVec2(-1, -constants.UI.LOOT_HISTORY_FOOTER_HEIGHT), true) then
                    if ImGui.BeginTable("LootHistoryTable", 4, tableFlags) then
                        ImGui.TableSetupColumn("#", ImGuiTableColumnFlags.WidthFixed, 28, 0)
                        ImGui.TableSetupColumn("Name", ImGuiTableColumnFlags.WidthStretch, 0, 1)
                        ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthFixed, 72, 2)
                        ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, 90, 3)
                        ImGui.TableSetupScrollFreeze(0, 1)
                        ImGui.TableHeadersRow()
                        local clipper = ImGuiListClipper.new()
                        clipper:Begin(#hist)
                        while clipper:Step() do
                            for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                                local row = hist[i]
                                if row then
                                    ImGui.TableNextRow()
                                    ImGui.TableNextColumn()
                                    ImGui.Text(tostring(i))
                                    ImGui.TableNextColumn()
                                    ImGui.PushID(i)
                                    renderNameCellWithLootMenu(ctx, theme, row.name, nil)
                                    ImGui.PopID()
                                    ImGui.TableNextColumn()
                                    ImGui.Text((ItemUtils.formatValue and ItemUtils.formatValue(row.value or 0)) or tostring(row.value or 0))
                                    ImGui.TableNextColumn()
                                    local st, sc = ctx.formatSellStatus(row.statusText, row.willSell, theme)
                                    ImGui.TextColored(sc, st)
                                end
                            end
                        end
                        ImGui.EndTable()
                    end
                end
                ImGui.EndChild()
            else
                ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "No history yet. Loot runs with items will appear here.")
            end
        end

        -- Skip History tab: list of skipped items (one row per occurrence, no combining)
        if state.lootUITab == 2 then
            local sk = state.skipHistory or {}
            if ctx.clearSkipHistory and ImGui.Button("Clear history", ImVec2(100, 0)) then
                ctx.clearSkipHistory()
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Clear Skip History (this list only).")
                ImGui.EndTooltip()
            end
            ImGui.SameLine()
            ImGui.Text(string.format("Skipped (%d):", #sk))
            if #sk > 0 then
                local tableFlags = ImGuiTableFlags.BordersOuter + ImGuiTableFlags.BordersInnerH + ImGuiTableFlags.ScrollY + ImGuiTableFlags.RowBg
                if ImGui.BeginChild("SkipHistoryList", ImVec2(-1, -constants.UI.LOOT_HISTORY_FOOTER_HEIGHT), true) then
                    if ImGui.BeginTable("SkipHistoryTable", 3, tableFlags) then
                        ImGui.TableSetupColumn("#", ImGuiTableColumnFlags.WidthFixed, 28, 0)
                        ImGui.TableSetupColumn("Name", ImGuiTableColumnFlags.WidthStretch, 0, 1)
                        ImGui.TableSetupColumn("Reason", ImGuiTableColumnFlags.WidthFixed, constants.UI.LOOT_TABLE_COL_REASON_WIDTH, 2)
                        ImGui.TableSetupScrollFreeze(0, 1)
                        ImGui.TableHeadersRow()
                        local clipper = ImGuiListClipper.new()
                        clipper:Begin(#sk)
                        while clipper:Step() do
                            for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                                local row = sk[i]
                                if row then
                                    ImGui.TableNextRow()
                                    ImGui.TableNextColumn()
                                    ImGui.Text(tostring(i))
                                    ImGui.TableNextColumn()
                                    ImGui.PushID(i)
                                    renderNameCellWithLootMenu(ctx, theme, row.name, nil)
                                    ImGui.PopID()
                                    ImGui.TableNextColumn()
                                    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), row.reason or "")
                                end
                            end
                        end
                        ImGui.EndTable()
                    end
                end
                ImGui.EndChild()
            else
                ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "No skip history yet. Items skipped by loot.mac will appear here.")
            end
        end


        -- Close button
        if ImGui.Button("Close", ImVec2(80, 0)) then
            state.lootUIOpen = false
            LootUIView.closeAndClearState(ctx)
        end
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Press Esc to close and clear summary.")
    end
    local ok, err = pcall(drawContent)
    if not ok then
        if mq and mq.log then mq.log("Loot UI: %s", tostring(err)) else print("Loot UI:", err) end
        diagnostics.recordError("Loot UI", "Draw content failed", err)
    end
    ImGui.End()
end

return LootUIView
