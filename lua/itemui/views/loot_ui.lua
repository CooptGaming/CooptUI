--[[
    Loot UI View - Dedicated window for loot macro progress and session summary.
    Shown when user starts Loot current / Loot all (if not suppressed). Stays open until Esc or Close.
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')

local constants = require('itemui.constants')
local LootUIView = {}

--- Clear Loot UI in-memory state and optionally clear session/alert INI (call on Esc or Close).
--- ctx.clearLootUIState() is provided by init.lua
function LootUIView.closeAndClearState(ctx)
    if ctx and ctx.clearLootUIState then ctx.clearLootUIState() end
end

--- Render the Loot UI window. Context must have: uiState, theme, layoutConfig, runLootCurrent, runLootAll, clearLootUIMythicalAlert, clearLootUIState.
function LootUIView.render(ctx)
    if not ctx or not ctx.uiState.lootUIOpen then return end

    local uiState = ctx.uiState
    local theme = ctx.theme
    local layoutConfig = ctx.layoutConfig or {}

    local w = layoutConfig.WidthLootPanel or constants.VIEWS.WidthLootPanel
    local h = layoutConfig.HeightLoot or constants.VIEWS.HeightLoot
    if w and h and w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.FirstUseEver)
    end
    -- Loot window is always resizable (independent of main UI lock)
    local windowFlags = 0

    local winOpen, winVis = ImGui.Begin("CoOpt UI Loot Companion##LootUI", uiState.lootUIOpen, windowFlags)
    uiState.lootUIOpen = winOpen

    if not winOpen then
        LootUIView.closeAndClearState(ctx)
        ImGui.End()
        return
    end
    -- Escape closes this window via main Inventory Companion's LIFO handler only
    if not winVis then ImGui.End(); return end

    -- Persist window size when resized (debounced via scheduleLayoutSave)
    local cw, ch = ImGui.GetWindowSize()
    if cw and ch and cw > 0 and ch > 0 then
        local prevW, prevH = layoutConfig.WidthLootPanel or 0, layoutConfig.HeightLoot or 0
        layoutConfig.WidthLootPanel = cw
        layoutConfig.HeightLoot = ch
        if (prevW ~= cw or prevH ~= ch) then ctx.scheduleLayoutSave() end
    end

    theme.TextHeader("Loot")
    ImGui.Separator()

    -- Tabs: Current | Loot History | Skip History
    if not uiState.lootUITab then uiState.lootUITab = 0 end
    if ImGui.BeginTabBar("LootUITabs", ImGuiTabBarFlags.None) then
        if ImGui.BeginTabItem("Current") then
            uiState.lootUITab = 0
            ImGui.EndTabItem()
        end
        if ImGui.BeginTabItem("Loot History") then
            uiState.lootUITab = 1
            if ctx.loadLootHistory then ctx.loadLootHistory() end
            ImGui.EndTabItem()
        end
        if ImGui.BeginTabItem("Skip History") then
            uiState.lootUITab = 2
            if ctx.loadSkipHistory then ctx.loadSkipHistory() end
            ImGui.EndTabItem()
        end
        ImGui.EndTabBar()
    end
    ImGui.Separator()

    -- First-time tip (Current tab only)
    local tipSeen = (ctx.layoutConfig and (ctx.layoutConfig.LootUIFirstTipSeen or 0) ~= 0)
    if uiState.lootUITab == 0 and not tipSeen then
        ImGui.TextColored(theme.ToVec4(theme.Colors.Info), "Loot current = this corpse only. Loot all = all corpses in range.")
        if ImGui.Button("Got it##LootUITip") then
            if ctx.layoutConfig then ctx.layoutConfig.LootUIFirstTipSeen = 1 end
            if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
        end
        ImGui.Separator()
    end

    -- Current tab: buttons, progress, current loot table
    if uiState.lootUITab == 0 then
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
    if uiState.corpseLootedHidden then
        if ImGui.Button("Show looted corpses", ImVec2(140, 0)) then
            mq.cmd('/hidecorpse none')
            uiState.corpseLootedHidden = false
        end
    else
        if ImGui.Button("Hide looted corpses", ImVec2(140, 0)) then
            mq.cmd('/hidecorpse looted')
            uiState.corpseLootedHidden = true
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Toggle visibility of looted corpses (troubleshooting). Same as /hidecorpse looted and /hidecorpse none.")
        ImGui.EndTooltip()
    end
    ImGui.SameLine()
    if ctx.clearLootHistory and ctx.clearSkipHistory and ImGui.Button("Clear history", ImVec2(100, 0)) then
        ctx.clearLootHistory()
        ctx.clearSkipHistory()
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Clear both Loot History and Skip History (this tab and the other tabs).")
        ImGui.EndTooltip()
    end
    ImGui.Separator()

    -- Suppress note (read-only)
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Suppress Loot UI during looting")
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("When enabled (Config), the Loot UI won't open during looting.")
        ImGui.EndTooltip()
    end
    ImGui.Separator()

    -- Mythical feedback: brief "You chose: Take" / "Passed — left on corpse" after Take/Pass
    local feedback = uiState.lootMythicalFeedback
    if feedback and feedback.message and feedback.showUntil then
        local now = mq.gettime()
        if now >= feedback.showUntil then
            uiState.lootMythicalFeedback = nil
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
    if uiState.lootMythicalAlert and uiState.lootMythicalAlert.itemName and uiState.lootMythicalAlert.itemName ~= "" then
        local decision = (uiState.lootMythicalAlert.decision or ""):lower()
        local pending = (decision == "" or decision == "pending")
        local alert = uiState.lootMythicalAlert
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
                        ImGui.Text(alert.itemName or "—")
                        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Open the corpse to see full description.")
                        ImGui.EndTooltip()
                    end
                else
                    ImGui.BeginTooltip()
                    ImGui.Text(alert.itemName or "—")
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
                local startAt = uiState.lootMythicalDecisionStartAt
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
    local running = mq.TLO.Macro and mq.TLO.Macro.Name and (mq.TLO.Macro.Name() or ""):lower()
    running = (running == "loot" or running == "loot.mac")
    if running or uiState.lootRunCorpsesLooted > 0 or uiState.lootRunTotalCorpses > 0 then
        ImGui.Text(string.format("Corpses looted: %d", uiState.lootRunCorpsesLooted))
        if uiState.lootRunTotalCorpses > 0 then
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), string.format(" / %d", uiState.lootRunTotalCorpses))
        end
        if uiState.lootRunCurrentCorpse and uiState.lootRunCurrentCorpse ~= "" then
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Current: " .. uiState.lootRunCurrentCorpse)
        end
        local total = uiState.lootRunTotalCorpses or 0
        local current = uiState.lootRunCorpsesLooted or 0
        local fraction = (total > 0) and (current / total) or 0
        local overlay = string.format("%d / %d", current, total > 0 and total or 0)
        theme.RenderProgressBar(fraction, ImVec2(-1, 24), overlay)
        ImGui.Separator()
    end

    -- Looted list (current run; persists until next run with items)
    local itemsForTable = uiState.lootRunLootedItems and #uiState.lootRunLootedItems > 0 and uiState.lootRunLootedItems
        or (uiState.lootRunLootedList and #uiState.lootRunLootedList > 0 and (function()
            local t = {}
            for _, name in ipairs(uiState.lootRunLootedList) do
                t[#t+1] = { name = name, value = 0, statusText = "—", willSell = false }
            end
            return t
        end)())
    if itemsForTable and #itemsForTable > 0 then
        local n = #itemsForTable
        local totalVal = uiState.lootRunTotalValue or 0
        local summaryStr = string.format("%d items", n)
        if totalVal > 0 then
            summaryStr = summaryStr .. "  ·  " .. (ItemUtils.formatValue and ItemUtils.formatValue(totalVal) or tostring(totalVal) .. "c")
        end
        ImGui.TextColored(theme.ToVec4(theme.Colors.Success), summaryStr)
        if uiState.lootRunBestItemName and uiState.lootRunBestItemName ~= "" then
            local bestVal = uiState.lootRunBestItemValue or 0
            ImGui.Text("Best: ")
            ImGui.SameLine()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Header), uiState.lootRunBestItemName)
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
                for i, row in ipairs(itemsForTable) do
                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    ImGui.Text(tostring(i))
                    ImGui.TableNextColumn()
                    if uiState.lootRunBestItemName and row.name == uiState.lootRunBestItemName then
                        ImGui.TextColored(theme.ToVec4(theme.Colors.Header), row.name or "")
                    else
                        ImGui.Text(row.name or "")
                    end
                    ImGui.TableNextColumn()
                    local valStr = (ItemUtils.formatValue and ItemUtils.formatValue(row.value or 0)) or tostring(row.value or 0)
                    ImGui.Text(valStr)
                    ImGui.TableNextColumn()
                    local statusText = row.statusText or "—"
                    if statusText == "Epic" then statusText = "EpicQuest" end
                    local statusColor = (row.willSell and theme.ToVec4(theme.Colors.Warning)) or theme.ToVec4(theme.Colors.Success)
                    if statusText == "EpicQuest" then statusColor = theme.ToVec4(theme.Colors.EpicQuest or theme.Colors.Muted)
                    elseif statusText == "NoDrop" or statusText == "NoTrade" then statusColor = theme.ToVec4(theme.Colors.Error)
                    end
                    ImGui.TextColored(statusColor, statusText)
                end
                ImGui.EndTable()
            end
        end
        ImGui.EndChild()
        ImGui.Separator()
    end
    end -- Current tab

    -- Loot History tab: cumulative recently looted items
    if uiState.lootUITab == 1 then
        local hist = uiState.lootHistory or {}
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
                    for i, row in ipairs(hist) do
                        ImGui.TableNextRow()
                        ImGui.TableNextColumn()
                        ImGui.Text(tostring(i))
                        ImGui.TableNextColumn()
                        ImGui.Text(row.name or "")
                        ImGui.TableNextColumn()
                        ImGui.Text((ItemUtils.formatValue and ItemUtils.formatValue(row.value or 0)) or tostring(row.value or 0))
                        ImGui.TableNextColumn()
                        local st = row.statusText or "—"
                        if st == "Epic" then st = "EpicQuest" end
                        local sc = (row.willSell and theme.ToVec4(theme.Colors.Warning)) or theme.ToVec4(theme.Colors.Success)
                        if st == "EpicQuest" then sc = theme.ToVec4(theme.Colors.EpicQuest or theme.Colors.Muted)
                        elseif st == "NoDrop" or st == "NoTrade" then sc = theme.ToVec4(theme.Colors.Error) end
                        ImGui.TextColored(sc, st)
                    end
                    ImGui.EndTable()
                end
            end
            ImGui.EndChild()
        else
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "No history yet. Loot runs with items will appear here.")
        end
    end

    -- Skip History tab: unique skipped items (one row per name, with count)
    if uiState.lootUITab == 2 then
        local sk = uiState.skipHistory or {}
        -- Build unique-by-name list with count (first reason seen, count of occurrences)
        local uniqueList = {}
        local seen = {}
        for _, row in ipairs(sk) do
            local name = row.name and row.name:match("^%s*(.-)%s*$") or ""
            if name ~= "" then
                if not seen[name] then
                    seen[name] = { name = name, reason = row.reason or "", count = 1 }
                    uniqueList[#uniqueList + 1] = seen[name]
                else
                    seen[name].count = seen[name].count + 1
                end
            end
        end
        if ctx.clearSkipHistory and ImGui.Button("Clear history", ImVec2(100, 0)) then
            ctx.clearSkipHistory()
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Clear Skip History (this list only).")
            ImGui.EndTooltip()
        end
        ImGui.SameLine()
        ImGui.Text(string.format("Skipped (unique: %d, total: %d):", #uniqueList, #sk))
        if #uniqueList > 0 then
            local tableFlags = ImGuiTableFlags.BordersOuter + ImGuiTableFlags.BordersInnerH + ImGuiTableFlags.ScrollY + ImGuiTableFlags.RowBg
            if ImGui.BeginChild("SkipHistoryList", ImVec2(-1, -constants.UI.LOOT_HISTORY_FOOTER_HEIGHT), true) then
                if ImGui.BeginTable("SkipHistoryTable", 4, tableFlags) then
                    ImGui.TableSetupColumn("#", ImGuiTableColumnFlags.WidthFixed, 28, 0)
                    ImGui.TableSetupColumn("Name", ImGuiTableColumnFlags.WidthStretch, 0, 1)
                    ImGui.TableSetupColumn("Reason", ImGuiTableColumnFlags.WidthFixed, constants.UI.LOOT_TABLE_COL_REASON_WIDTH, 2)
                    ImGui.TableSetupColumn("Count", ImGuiTableColumnFlags.WidthFixed, 44, 3)
                    ImGui.TableSetupScrollFreeze(0, 1)
                    ImGui.TableHeadersRow()
                    for i, row in ipairs(uniqueList) do
                        ImGui.TableNextRow()
                        ImGui.TableNextColumn()
                        ImGui.Text(tostring(i))
                        ImGui.TableNextColumn()
                        ImGui.Text(row.name or "")
                        ImGui.TableNextColumn()
                        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), row.reason or "")
                        ImGui.TableNextColumn()
                        if row.count and row.count > 1 then
                            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "×" .. tostring(row.count))
                        else
                            ImGui.Text("")
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
        uiState.lootUIOpen = false
        LootUIView.closeAndClearState(ctx)
    end
    ImGui.SameLine()
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Press Esc to close and clear summary.")

    ImGui.End()
end

return LootUIView
