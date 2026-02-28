--[[
    Onboarding tutorial: 14-screen welcome and setup wizard.
    Screens 0 (Welcome), 1-13 (wizard steps). Description overlays for
    overview screens; config steps show the live view with header prompt only.
]]

require('ImGui')
local registry = require('itemui.core.registry')
local welcomeEnv = require('itemui.core.welcome_env_manifest')

local TOTAL_SCREENS = 14   -- 0 = Welcome (pre-wizard), 1-13 = wizard steps

local SCREEN_TITLES = {
    [0]  = "Welcome",
    [1]  = "Inventory overview",
    [2]  = "Inventory configuration",
    [3]  = "Sell overview",
    [4]  = "Sell configuration",
    [5]  = "Bank overview",
    [6]  = "Bank configuration",
    [7]  = "Remaining companions",
    [8]  = "Open all windows",
    [9]  = "Protection overview",
    [10] = "Sell protection",
    [11] = "Loot rules",
    [12] = "Epic protection",
    [13] = "Settings overview",
    [14] = "Save & finish",
}

-- Instructional header prompt for config/action steps (shown in setup bar)
-- Steps where user configures sizing/reshaping include "Click Next to save and proceed."
local HEADER_PROMPTS = {
    [2]  = "Resize the window, reorder columns, and adjust column widths to your liking. When done, click Next to save and proceed.",
    [4]  = "Resize the Sell window and adjust columns as you like. No merchant needed — this is a simulated view. When done, click Next to save and proceed.",
    [6]  = "Open and resize the Bank companion window to your preference. When done, click Next to save and proceed.",
    [8]  = "All companion windows are now open. Drag and resize each one to fit your screen. When done, click Next to save and proceed.",
    [9]  = "Review the three layers of protection (Sell, Loot, Epic). Additional settings are in the Settings window. Click Next to continue.",
    [10] = "Choose which item flags to protect from selling. When done, click Next to save and proceed.",
    [11] = "Configure loot rules and minimum values. When done, click Next to save and proceed.",
    [12] = "Optionally select classes whose epic items are protected. When done, click Next to save and proceed.",
    [13] = "Review the Settings window tabs, then click Save & Finish to complete setup.",
}

local function isDescriptionScreen(step)
    return step == 1 or step == 3 or step == 5 or step == 7 or step == 9 or step == 12 or step == 13
end

--- Screen 0: Welcome (env checklist, two buttons, bullet points). Shown when showWelcomePanel or when setupMode and setupStep==0.
function renderWelcomeScreen(refs)
    local theme = refs.theme
    local uiState = refs.uiState
    -- Environment validation (Task 8.2): run once, show checklist
    if not uiState.welcomeEnvResults then
        uiState.welcomeEnvResults = welcomeEnv.validate()
    end
    local envResults = uiState.welcomeEnvResults
    local hasFailure = false
    for _, r in ipairs(envResults) do
        if r.status == "failed" then hasFailure = true; break end
    end
    local envAllValid = not hasFailure and #envResults > 0

    ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "Welcome to CoOpt UI")
    ImGui.Separator()
    ImGui.TextWrapped("Your unified inventory, sell, loot, and augment companion.")
    ImGui.Spacing()
    -- Environment checklist (collapsible if all valid)
    if ImGui.CollapsingHeader("Environment check", envAllValid and ImGuiTreeNodeFlags.DefaultOpen or ImGuiTreeNodeFlags.None) then
        for _, r in ipairs(envResults) do
            if r.status == "valid" then
                ImGui.TextColored(theme.ToVec4(theme.Colors.Success), "  [OK] ")
                ImGui.SameLine(0, 8)
                ImGui.Text(r.label or r.path)
            elseif r.status == "generated" then
                ImGui.TextColored(theme.ToVec4(theme.Colors.Warning), "  [Created] ")
                ImGui.SameLine(0, 8)
                ImGui.Text(r.label or r.path)
            else
                ImGui.TextColored(theme.ToVec4(theme.Colors.Error or theme.Colors.Warning), "  [Failed] ")
                ImGui.SameLine(0, 8)
                ImGui.Text(r.label or r.path)
                if r.message and r.message ~= "" then
                    ImGui.Indent()
                    ImGui.TextWrapped(r.message)
                    ImGui.Unindent()
                end
            end
        end
        if hasFailure then
            ImGui.Spacing()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Fix the failed items (create folders or run from your MacroQuest root) or acknowledge below to continue.")
            if ImGui.Button("I Understand, Continue##WelcomeEnvAck", ImVec2(200, 0)) then
                uiState.welcomeEnvAcknowledged = true
            end
        end
    end
    ImGui.Spacing()
    local allowProceed = not hasFailure or uiState.welcomeEnvAcknowledged
    if refs.defaultLayoutAppliedThisRun and refs.defaultLayoutAppliedThisRun() then
        ImGui.Spacing()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "A default window layout has been applied — your windows are pre-arranged. Revert anytime from Settings.")
    end
    ImGui.Spacing()
    ImGui.Spacing()

    -- Two buttons side-by-side, centered (disabled until env acknowledged if there were failures)
    local runSetupW, skipW = 220, 260
    local totalW = runSetupW + 24 + skipW
    ImGui.SetCursorPosX((ImGui.GetWindowWidth() - totalW) * 0.5)
    if not allowProceed then ImGui.BeginDisabled() end
    if ImGui.Button("Run Setup", ImVec2(runSetupW, 0)) then
        uiState.setupMode = true
        uiState.setupStep = 1
        if refs.loadConfigCache then refs.loadConfigCache() end
        if refs.loadLayoutConfig then refs.loadLayoutConfig() end
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Walk through each window and set up layout and rules")
        ImGui.EndTooltip()
    end
    ImGui.SameLine()
    if ImGui.Button("I Know What I'm Doing (Skip)", ImVec2(skipW, 0)) then
        if refs.setOnboardingComplete then refs.setOnboardingComplete() end
    end
    if not allowProceed then ImGui.EndDisabled() end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Skip setup; you can re-open this from Settings anytime")
        ImGui.EndTooltip()
    end

    ImGui.Spacing()
    ImGui.Spacing()
    -- Bullet points under Run Setup (left column)
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Run Setup:")
    ImGui.BulletText("Walks you through each window so you understand what it does.")
    ImGui.BulletText("Resize and reorder columns to show the information you care about.")
    ImGui.BulletText("Position windows to fit your screen and workflow.")
    ImGui.BulletText("Set up sell protection, loot rules, and epic item handling.")
    ImGui.Spacing()
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Skip:")
    ImGui.BulletText("I'll figure it out as I go.")
    ImGui.BulletText("You can always re-open this from Settings at any time.")
end

--- Description overlay for step 1 (Inventory overview). Renders as a child region over the content.
function renderInventoryOverviewOverlay(refs)
    local theme = refs.theme
    local availX, availY = ImGui.GetContentRegionAvail()
    local overlayH = math.floor((availY or 400) * 0.45)
    if overlayH < 200 then overlayH = 200 end

    ImGui.BeginChild("TutorialOverlay_Inv", ImVec2(availX or 400, overlayH), true)
    local cw, _ = ImGui.GetContentRegionAvail()
    if type(cw) ~= "number" or cw <= 0 then cw = (availX or 400) end
    ImGui.PushTextWrapPos(ImGui.GetCursorPosX() + cw - 24)
    ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "Your Inventory at a Glance")
    ImGui.Separator()
    ImGui.TextWrapped("The Inventory window shows every item across all your bags in one unified list.")
    ImGui.BulletText("Columns: Name, Value, Weight, Type, Bag, Clicky, and more. Right-click any column header to show or hide columns.")
    ImGui.BulletText("Sorting: Click a column header to sort ascending; click again for descending.")
    ImGui.BulletText("Reorder columns: Drag column headers left or right to rearrange.")
    ImGui.BulletText("Resize columns: Drag the border between column headers to adjust width.")
    ImGui.BulletText("Pick up items: Left-click an item name to pick it up onto your cursor.")
    ImGui.BulletText("Move to bank: Shift+click an item to move it to your bank (when bank is open).")
    ImGui.BulletText("Right-click menu: Inspect, Move to Bank, add to Keep/Sell lists, CoOp Item Display, and more.")
    ImGui.BulletText("Search: Use the search bar at the top to filter by name.")
    ImGui.BulletText("Clicky column: Right-click a clicky effect to activate it.")
    ImGui.PopTextWrapPos()
    ImGui.Spacing()
    if ImGui.Button("Got it##TutorialInvOverlay", ImVec2(80, 0)) then
        refs.uiState.setupStep = 2
    end
    ImGui.EndChild()
end

--- Description overlay for step 3 (Sell overview). Renders as a child region over the content.
function renderSellOverviewOverlay(refs)
    local theme = refs.theme
    local availX, availY = ImGui.GetContentRegionAvail()
    local overlayH = math.floor((availY or 400) * 0.45)
    if overlayH < 200 then overlayH = 200 end

    ImGui.BeginChild("TutorialOverlay_Sell", ImVec2(availX or 400, overlayH), true)
    local cw, _ = ImGui.GetContentRegionAvail()
    if type(cw) ~= "number" or cw <= 0 then cw = (availX or 400) end
    ImGui.PushTextWrapPos(ImGui.GetCursorPosX() + cw - 24)
    ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "The Sell Window")
    ImGui.Separator()
    ImGui.TextWrapped("The Sell view appears when you open a merchant (or is simulated here during setup). It shows the same items as Inventory, with sell-specific actions and status.")
    ImGui.BulletText("Action column: Each row has Sell, Keep, and Junk buttons.")
    ImGui.BulletText("Sell: Sells the item or stack of items to the vendor.")
    ImGui.BulletText("Keep adds the item to your Keep list (never sell); Junk adds it to Always Sell.")
    ImGui.BulletText("Status column: Shows whether an item is Protected, Kept, or will be Sold based on your rules.")
    ImGui.BulletText("Auto Sell button: Sells all items that are flagged or have a status of \"Sell\" when you are at a merchant.")
    ImGui.BulletText("Summary bar: Shows counts of Kept, Selling, and Protected items, plus total sell value.")
    ImGui.BulletText("Column customization works like Inventory: right-click headers to show or hide columns; drag to reorder or resize.")
    ImGui.PopTextWrapPos()
    ImGui.Spacing()
    if ImGui.Button("Got it##TutorialSellOverlay", ImVec2(80, 0)) then
        refs.uiState.setupStep = 4
    end
    ImGui.EndChild()
end

--- Description overlay for step 5 (Bank overview). Renders as a child region over the content.
function renderBankOverviewOverlay(refs)
    local theme = refs.theme
    local availX, availY = ImGui.GetContentRegionAvail()
    local overlayH = math.floor((availY or 400) * 0.45)
    if overlayH < 200 then overlayH = 200 end

    ImGui.BeginChild("TutorialOverlay_Bank", ImVec2(availX or 400, overlayH), true)
    local cw, _ = ImGui.GetContentRegionAvail()
    if type(cw) ~= "number" or cw <= 0 then cw = (availX or 400) end
    ImGui.PushTextWrapPos(ImGui.GetCursorPosX() + cw - 24)
    ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "The Bank Companion")
    ImGui.Separator()
    ImGui.TextWrapped("The Bank companion shows your bank contents. When your in-game bank window is open, it is live (online); when closed, it shows a cached snapshot from your last visit.")
    ImGui.BulletText("Online (green): Shift+click an item to move it from bank to inventory. Right-click for context menu, including Move to Inventory.")
    ImGui.BulletText("Offline (red): The list is read-only; the timestamp shows when the snapshot was taken. Open your bank in-game to move items.")
    ImGui.BulletText("Search and column customization work like Inventory: right-click headers to show or hide columns; drag to reorder or resize.")
    ImGui.PopTextWrapPos()
    ImGui.Spacing()
    if ImGui.Button("Got it##TutorialBankOverlay", ImVec2(80, 0)) then
        refs.uiState.setupStep = 6
    end
    ImGui.EndChild()
end

--- Helper: bullet + wrapped text (BulletText may not wrap in this binding).
local function bulletWrapped(text)
    ImGui.Bullet()
    ImGui.SameLine()
    ImGui.TextWrapped(text)
end

--- Description overlay for step 7 (Remaining companions). Content-heavy; uses most of content area (inventory not needed here).
function renderRemainingCompanionsOverlay(refs)
    local theme = refs.theme
    local availX, availY = ImGui.GetContentRegionAvail()
    local overlayH = math.floor((availY or 500) * 0.88)
    if overlayH < 320 then overlayH = 320 end

    ImGui.BeginChild("TutorialOverlay_Companions", ImVec2(availX or 400, overlayH), true)
    local cw, _ = ImGui.GetContentRegionAvail()
    if type(cw) ~= "number" or cw <= 0 then cw = (availX or 400) end
    ImGui.PushTextWrapPos(ImGui.GetCursorPosX() + cw - 24)
    ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "Your Other Companions")
    ImGui.Separator()
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Equipment")
    bulletWrapped("Paper-doll grid of your worn gear in the same layout as the game. Hover any slot for full stats; click to inspect or swap.")
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Item Display")
    bulletWrapped("Full stat sheet for any item. Right-click an item anywhere and choose \"CoOp UI Item Display\" to open it here.")
    bulletWrapped("Supports multiple tabs so you can compare items. Toolbar includes Can I Use?, Source, and Locate.")
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Augments")
    bulletWrapped("Lists every augment in your inventory with effects at a glance. Search and sort; right-click to add to Augment or Mythical Reroll lists.")
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Augment Utility")
    bulletWrapped("Insert or remove augments from your gear. Select a target item from Item Display, pick an augment slot, then browse compatible augments and click Insert or Remove.")
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "AA")
    bulletWrapped("Browse, search, and train Alt Advancement. Tabs: General, Archetype, Class, Special. Export and import AA profiles.")
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Reroll")
    bulletWrapped("Manage server augment and mythical reroll lists. See how many matching items you have in inventory and bank; add from cursor, remove, or roll when ready.")
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Loot UI")
    bulletWrapped("Opens during looting to show progress, session stats, total value, and alerts. If a mythical NoDrop/NoTrade item drops, you can choose to take it or pass.")
    ImGui.PopTextWrapPos()
    ImGui.Spacing()
    if ImGui.Button("Got it##TutorialCompanionsOverlay", ImVec2(80, 0)) then
        refs.uiState.setupStep = 8
    end
    ImGui.EndChild()
end

--- Description overlay for step 9 (Protection & Loot Rules overview). What's coming and note about Settings.
function renderProtectionOverviewOverlay(refs)
    local theme = refs.theme
    local availX, availY = ImGui.GetContentRegionAvail()
    local overlayH = math.floor((availY or 400) * 0.5)
    if overlayH < 220 then overlayH = 220 end

    ImGui.BeginChild("TutorialOverlay_Protection", ImVec2(availX or 400, overlayH), true)
    local cw, _ = ImGui.GetContentRegionAvail()
    if type(cw) ~= "number" or cw <= 0 then cw = (availX or 400) end
    ImGui.PushTextWrapPos(ImGui.GetCursorPosX() + cw - 24)
    ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "Protecting Your Items")
    ImGui.Separator()
    ImGui.TextWrapped("Before you use automatic selling and looting, you'll set up three layers of protection:")
    bulletWrapped("Sell Protection (next step): Flags that prevent certain item types from ever being sold — NoDrop, NoTrade, Lore, and more.")
    bulletWrapped("Loot Rules (after that): Control what gets picked up automatically — quest items, collectibles, minimum value thresholds.")
    bulletWrapped("Epic Protection (final config): Class-specific epic quest items that should never be sold and always be looted.")
    ImGui.Spacing()
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "The lists for all three can be maintained anytime in the Settings window. Additional options are available there.")
    ImGui.PopTextWrapPos()
    ImGui.Spacing()
    if ImGui.Button("Got it##TutorialProtectionOverlay", ImVec2(80, 0)) then
        refs.uiState.setupStep = 10
    end
    ImGui.EndChild()
end

--- Helper: complete onboarding and exit setup (used by step 13 Save & Finish).
local function completeOnboardingAndExit(refs)
    if refs.setOnboardingComplete then refs.setOnboardingComplete() end
    if refs.uiState then
        refs.uiState.setupMode = false
        refs.uiState.setupStep = 0
    end
end

--- Step 13: Settings overview and Save & Finish. Describes Settings tabs; button completes onboarding.
function renderSettingsOverviewOverlay(refs)
    local theme = refs.theme
    local availX, availY = ImGui.GetContentRegionAvail()
    local overlayH = math.floor((availY or 400) * 0.88)
    if overlayH < 280 then overlayH = 280 end

    ImGui.BeginChild("TutorialOverlay_SettingsFinish", ImVec2(availX or 400, overlayH), true)
    local cw, _ = ImGui.GetContentRegionAvail()
    if type(cw) ~= "number" or cw <= 0 then cw = (availX or 400) end
    ImGui.PushTextWrapPos(ImGui.GetCursorPosX() + cw - 24)
    ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "Settings window")
    ImGui.Separator()
    ImGui.TextWrapped("All of your preferences live in the Settings window. Open it anytime from the toolbar or the Settings button.")
    bulletWrapped("General: Layout, default window positions, and options like Run Setup / Show welcome again.")
    bulletWrapped("Sell Rules: Sell protection flags, always-sell and never-sell lists, and epic class protection.")
    bulletWrapped("Loot Rules: Loot flags, minimum value thresholds, and always-loot lists.")
    bulletWrapped("Shared: Options shared across characters (e.g. epic classes). Toolbar buttons open Inventory, Bank, Sell, and other companions.")
    ImGui.Spacing()
    ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "You're all set")
    ImGui.Separator()
    ImGui.TextWrapped("Click Save & Finish below to complete setup. Your window positions and options are already saved.")
    ImGui.Spacing()
    if ImGui.Button("Save & Finish##TutorialFinish", ImVec2(140, 0)) then
        completeOnboardingAndExit(refs)
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Complete setup and close the wizard"); ImGui.EndTooltip() end
    ImGui.Spacing()
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "You can revert to the default layout or show this welcome again from Settings.")
    ImGui.PopTextWrapPos()
    ImGui.EndChild()
end

--- Render description overlay for a given step. Steps 1,3,5,7,9 have overlays; 13 = Settings + Save & Finish.
function renderDescriptionOverlay(step, refs)
    if step == 1 then
        renderInventoryOverviewOverlay(refs)
    elseif step == 3 then
        renderSellOverviewOverlay(refs)
    elseif step == 5 then
        renderBankOverviewOverlay(refs)
    elseif step == 7 then
        renderRemainingCompanionsOverlay(refs)
    elseif step == 9 then
        renderProtectionOverviewOverlay(refs)
    elseif step == 13 then
        renderSettingsOverviewOverlay(refs)
    end
end

--- Setup bar (header): step indicator and Back/Next. Called from main_window when setupMode.
function renderSetupBar(refs)
    local uiState = refs.uiState
    local theme = refs.theme
    local step = uiState.setupStep
    local saveLayoutForView = refs.saveLayoutForView or function() end

    if step < 1 or step > 13 then return end

    local prompt = HEADER_PROMPTS[step]
    local title = SCREEN_TITLES[step] or ("Step " .. step)
    local headerText = "Step " .. step .. " of 13: " .. (prompt and prompt ~= "" and prompt or title .. ".")
    local winW = ImGui.GetWindowWidth()
    local buttonReserve = (step == 13) and 180 or 130
    ImGui.PushTextWrapPos(winW - buttonReserve - 16)
    ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Warning))
    ImGui.TextWrapped(headerText)
    ImGui.PopStyleColor(1)
    ImGui.PopTextWrapPos()
    ImGui.SameLine(winW - buttonReserve)

    if step == 1 then
        if ImGui.Button("Next##TutorialBar", ImVec2(60, 0)) then
            uiState.setupStep = 2
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Continue to configure the Inventory window"); ImGui.EndTooltip() end
    elseif step == 2 then
        if ImGui.Button("Back##TutorialBar", ImVec2(50, 0)) then uiState.setupStep = 1 end
        ImGui.SameLine()
        if ImGui.Button("Next##TutorialBar", ImVec2(60, 0)) then
            local w, h = ImGui.GetWindowSize()
            if w and h and w > 0 and h > 0 then saveLayoutForView("Inventory", w, h, nil) end
            uiState.setupStep = 3
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Save layout and continue to Sell overview"); ImGui.EndTooltip() end
    elseif step == 3 then
        if ImGui.Button("Back##TutorialBar", ImVec2(50, 0)) then uiState.setupStep = 2 end
        ImGui.SameLine()
        if ImGui.Button("Next##TutorialBar", ImVec2(60, 0)) then uiState.setupStep = 4 end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Continue to configure the Sell window"); ImGui.EndTooltip() end
    elseif step == 4 then
        if ImGui.Button("Back##TutorialBar", ImVec2(50, 0)) then uiState.setupStep = 3 end
        ImGui.SameLine()
        if ImGui.Button("Next##TutorialBar", ImVec2(60, 0)) then
            local w, h = ImGui.GetWindowSize()
            if w and h and w > 0 and h > 0 then saveLayoutForView("Sell", w, h, nil) end
            uiState.setupStep = 5
            registry.setWindowState("bank", true, true)
            if refs.recordCompanionWindowOpened then refs.recordCompanionWindowOpened("bank") end
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Save Sell layout and open Bank companion"); ImGui.EndTooltip() end
    elseif step == 5 then
        if ImGui.Button("Back##TutorialBar", ImVec2(50, 0)) then uiState.setupStep = 4 end
        ImGui.SameLine()
        if ImGui.Button("Next##TutorialBar", ImVec2(60, 0)) then uiState.setupStep = 6 end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Continue to configure the Bank window"); ImGui.EndTooltip() end
    elseif step == 6 then
        if ImGui.Button("Back##TutorialBar", ImVec2(50, 0)) then uiState.setupStep = 5 end
        ImGui.SameLine()
        if ImGui.Button("Next##TutorialBar", ImVec2(60, 0)) then uiState.setupStep = 7 end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Continue to Remaining companions overview"); ImGui.EndTooltip() end
    elseif step == 7 then
        if ImGui.Button("Back##TutorialBar", ImVec2(50, 0)) then uiState.setupStep = 6 end
        ImGui.SameLine()
        if ImGui.Button("Next##TutorialBar", ImVec2(60, 0)) then uiState.setupStep = 8 end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open all companion windows and continue"); ImGui.EndTooltip() end
    elseif step == 8 then
        if ImGui.Button("Back##TutorialBar", ImVec2(50, 0)) then uiState.setupStep = 7 end
        ImGui.SameLine()
        if ImGui.Button("Next##TutorialBar", ImVec2(60, 0)) then uiState.setupStep = 9 end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Continue to Protection overview"); ImGui.EndTooltip() end
    elseif step == 9 then
        if ImGui.Button("Back##TutorialBar", ImVec2(50, 0)) then uiState.setupStep = 8 end
        ImGui.SameLine()
        if ImGui.Button("Next##TutorialBar", ImVec2(60, 0)) then uiState.setupStep = 10 end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Continue to Sell protection"); ImGui.EndTooltip() end
    elseif step == 10 then
        if ImGui.Button("Back##TutorialBar", ImVec2(50, 0)) then uiState.setupStep = 9 end
        ImGui.SameLine()
        if ImGui.Button("Next##TutorialBar", ImVec2(60, 0)) then uiState.setupStep = 11 end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Continue to Loot rules"); ImGui.EndTooltip() end
    elseif step == 11 then
        if ImGui.Button("Back##TutorialBar", ImVec2(50, 0)) then uiState.setupStep = 10 end
        ImGui.SameLine()
        if ImGui.Button("Next##TutorialBar", ImVec2(60, 0)) then uiState.setupStep = 12 end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Continue to Epic protection"); ImGui.EndTooltip() end
    elseif step == 12 then
        if ImGui.Button("Back##TutorialBar", ImVec2(50, 0)) then uiState.setupStep = 11 end
        ImGui.SameLine()
        if ImGui.Button("Next##TutorialBar", ImVec2(60, 0)) then
            local nSelected = 0
            for _, cls in ipairs(refs.EPIC_CLASSES or {}) do
                if (refs.configEpicClasses or {})[cls] == true then nSelected = nSelected + 1 end
            end
            if nSelected > 0 and refs.config and refs.config.writeINIValue and refs.config.writeLootINIValue then
                refs.config.writeINIValue("sell_flags.ini", "Settings", "protectEpic", "TRUE")
                refs.config.writeLootINIValue("loot_flags.ini", "Settings", "alwaysLootEpic", "TRUE")
                if refs.configSellFlags then refs.configSellFlags.protectEpic = true end
                if refs.configLootFlags then refs.configLootFlags.alwaysLootEpic = true end
                if refs.invalidateSellConfigCache then refs.invalidateSellConfigCache() end
                if refs.invalidateLootConfigCache then refs.invalidateLootConfigCache() end
            end
            uiState.setupStep = 13
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Continue to Settings overview"); ImGui.EndTooltip() end
    elseif step == 13 then
        if ImGui.Button("Back##TutorialBar", ImVec2(50, 0)) then uiState.setupStep = 12 end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Back to Epic protection"); ImGui.EndTooltip() end
        ImGui.SameLine()
        if ImGui.Button("Save & Finish##TutorialBar", ImVec2(110, 0)) then
            if refs.setOnboardingComplete then refs.setOnboardingComplete() end
            uiState.setupMode = false
            uiState.setupStep = 0
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Complete setup and close the wizard"); ImGui.EndTooltip() end
    end
    ImGui.Separator()
end

return {
    TOTAL_SCREENS = TOTAL_SCREENS,
    SCREEN_TITLES = SCREEN_TITLES,
    isDescriptionScreen = isDescriptionScreen,
    renderWelcomeScreen = renderWelcomeScreen,
    renderDescriptionOverlay = renderDescriptionOverlay,
    renderSetupBar = renderSetupBar,
}
