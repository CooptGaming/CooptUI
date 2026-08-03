--[[ layout_setup.lua: Capture current layout as default, reset layout to default. Requires init(deps). ]]
local file_safe = require('itemui.utils.file_safe')
local constants = require('itemui.constants')

local layoutDefaults
local layoutConfig
local uiState
local columnVisibility
local sortState
local perfCache
local getLayoutFilePath
local parseLayoutFileFull
local initColumnVisibility
local applyDefaultsFromParsed
local saveLayoutToFile

local function layout_setup_init(deps)
    layoutDefaults = deps.layoutDefaults
    layoutConfig = deps.layoutConfig
    uiState = deps.uiState
    columnVisibility = deps.columnVisibility
    sortState = deps.sortState
    perfCache = deps.perfCache
    getLayoutFilePath = deps.getLayoutFilePath
    parseLayoutFileFull = deps.parseLayoutFileFull
    initColumnVisibility = deps.initColumnVisibility
    applyDefaultsFromParsed = deps.applyDefaultsFromParsed
    saveLayoutToFile = deps.saveLayoutToFile
end

--- Capture current layout state as snapshot (defaults) and write [Defaults] + [ColumnVisibilityDefaults] to INI.
local function layout_setup_captureCurrentLayoutAsDefault()
    layoutDefaults.WidthInventory = layoutConfig.WidthInventory or layoutDefaults.WidthInventory
    layoutDefaults.Height = layoutConfig.Height or layoutDefaults.Height
    -- WidthSell retired: one window, one rect (see saveLayoutForView).
    layoutDefaults.WidthLoot = layoutConfig.WidthLoot or layoutDefaults.WidthLoot
    layoutDefaults.WidthBankPanel = layoutConfig.WidthBankPanel or layoutDefaults.WidthBankPanel
    layoutDefaults.HeightBank = layoutConfig.HeightBank or layoutDefaults.HeightBank
    layoutDefaults.WidthLootPanel = layoutConfig.WidthLootPanel or layoutDefaults.WidthLootPanel
    layoutDefaults.HeightLoot = layoutConfig.HeightLoot or layoutDefaults.HeightLoot
    layoutDefaults.LootWindowX = layoutConfig.LootWindowX or layoutDefaults.LootWindowX
    layoutDefaults.LootWindowY = layoutConfig.LootWindowY or layoutDefaults.LootWindowY
    layoutDefaults.BankWindowX = layoutConfig.BankWindowX or layoutDefaults.BankWindowX
    layoutDefaults.BankWindowY = layoutConfig.BankWindowY or layoutDefaults.BankWindowY
    layoutDefaults.ScriptTrackerWindowX = layoutConfig.ScriptTrackerWindowX or layoutDefaults.ScriptTrackerWindowX or 0
    layoutDefaults.ScriptTrackerWindowY = layoutConfig.ScriptTrackerWindowY or layoutDefaults.ScriptTrackerWindowY or 0
    layoutDefaults.WidthScriptTrackerPanel = layoutConfig.WidthScriptTrackerPanel or layoutDefaults.WidthScriptTrackerPanel
    layoutDefaults.HeightScriptTracker = layoutConfig.HeightScriptTracker or layoutDefaults.HeightScriptTracker
    layoutDefaults.WidthAugmentsPanel = layoutConfig.WidthAugmentsPanel or layoutDefaults.WidthAugmentsPanel
    layoutDefaults.HeightAugments = layoutConfig.HeightAugments or layoutDefaults.HeightAugments
    layoutDefaults.AugmentsWindowX = layoutConfig.AugmentsWindowX or layoutDefaults.AugmentsWindowX
    layoutDefaults.AugmentsWindowY = layoutConfig.AugmentsWindowY or layoutDefaults.AugmentsWindowY
    layoutDefaults.WidthMythicalsPanel = layoutConfig.WidthMythicalsPanel or layoutDefaults.WidthMythicalsPanel
    layoutDefaults.HeightMythicals = layoutConfig.HeightMythicals or layoutDefaults.HeightMythicals
    layoutDefaults.MythicalsWindowX = layoutConfig.MythicalsWindowX or layoutDefaults.MythicalsWindowX
    layoutDefaults.MythicalsWindowY = layoutConfig.MythicalsWindowY or layoutDefaults.MythicalsWindowY
    layoutDefaults.CommandCenterWindowX = layoutConfig.CommandCenterWindowX or layoutDefaults.CommandCenterWindowX
    layoutDefaults.CommandCenterWindowY = layoutConfig.CommandCenterWindowY or layoutDefaults.CommandCenterWindowY
    layoutDefaults.WidthFavoritesPanel = layoutConfig.WidthFavoritesPanel or layoutDefaults.WidthFavoritesPanel
    layoutDefaults.HeightFavorites = layoutConfig.HeightFavorites or layoutDefaults.HeightFavorites
    layoutDefaults.FavoritesWindowX = layoutConfig.FavoritesWindowX or layoutDefaults.FavoritesWindowX
    layoutDefaults.FavoritesWindowY = layoutConfig.FavoritesWindowY or layoutDefaults.FavoritesWindowY
    layoutDefaults.WidthEffectsPanel = layoutConfig.WidthEffectsPanel or layoutDefaults.WidthEffectsPanel
    layoutDefaults.HeightEffects = layoutConfig.HeightEffects or layoutDefaults.HeightEffects
    layoutDefaults.EffectsWindowX = layoutConfig.EffectsWindowX or layoutDefaults.EffectsWindowX
    layoutDefaults.EffectsWindowY = layoutConfig.EffectsWindowY or layoutDefaults.EffectsWindowY
    layoutDefaults.EffectsCompact = layoutConfig.EffectsCompact or layoutDefaults.EffectsCompact or 0
    layoutDefaults.ChatWindowX = layoutConfig.ChatWindowX or layoutDefaults.ChatWindowX
    layoutDefaults.ChatWindowY = layoutConfig.ChatWindowY or layoutDefaults.ChatWindowY
    layoutDefaults.WidthChatPanel = layoutConfig.WidthChatPanel or layoutDefaults.WidthChatPanel
    layoutDefaults.HeightChat = layoutConfig.HeightChat or layoutDefaults.HeightChat
    layoutDefaults.ShowChatWindow = layoutConfig.ShowChatWindow or layoutDefaults.ShowChatWindow
    layoutDefaults.ItemDisplayWindowX = layoutConfig.ItemDisplayWindowX or layoutDefaults.ItemDisplayWindowX
    layoutDefaults.ItemDisplayWindowY = layoutConfig.ItemDisplayWindowY or layoutDefaults.ItemDisplayWindowY
    layoutDefaults.WidthItemDisplayPanel = layoutConfig.WidthItemDisplayPanel or layoutDefaults.WidthItemDisplayPanel
    layoutDefaults.HeightItemDisplay = layoutConfig.HeightItemDisplay or layoutDefaults.HeightItemDisplay
    layoutDefaults.AugmentUtilityWindowX = layoutConfig.AugmentUtilityWindowX or layoutDefaults.AugmentUtilityWindowX
    layoutDefaults.AugmentUtilityWindowY = layoutConfig.AugmentUtilityWindowY or layoutDefaults.AugmentUtilityWindowY
    layoutDefaults.WidthAugmentUtilityPanel = layoutConfig.WidthAugmentUtilityPanel or layoutDefaults.WidthAugmentUtilityPanel
    layoutDefaults.HeightAugmentUtility = layoutConfig.HeightAugmentUtility or layoutDefaults.HeightAugmentUtility
    layoutDefaults.WidthAAPanel = layoutConfig.WidthAAPanel or layoutDefaults.WidthAAPanel
    layoutDefaults.HeightAA = layoutConfig.HeightAA or layoutDefaults.HeightAA
    layoutDefaults.AAWindowX = layoutConfig.AAWindowX or layoutDefaults.AAWindowX
    layoutDefaults.AAWindowY = layoutConfig.AAWindowY or layoutDefaults.AAWindowY
    layoutDefaults.ShowAAWindow = layoutConfig.ShowAAWindow or layoutDefaults.ShowAAWindow
    layoutDefaults.ShowEquipmentWindow = layoutConfig.ShowEquipmentWindow or layoutDefaults.ShowEquipmentWindow
    layoutDefaults.EquipmentWindowX = layoutConfig.EquipmentWindowX or layoutDefaults.EquipmentWindowX
    layoutDefaults.EquipmentWindowY = layoutConfig.EquipmentWindowY or layoutDefaults.EquipmentWindowY
    layoutDefaults.WidthEquipmentPanel = layoutConfig.WidthEquipmentPanel or layoutDefaults.WidthEquipmentPanel
    layoutDefaults.HeightEquipment = layoutConfig.HeightEquipment or layoutDefaults.HeightEquipment
    layoutDefaults.ShowBankWindow = layoutConfig.ShowBankWindow or layoutDefaults.ShowBankWindow
    layoutDefaults.ShowAugmentsWindow = layoutConfig.ShowAugmentsWindow or layoutDefaults.ShowAugmentsWindow
    layoutDefaults.ShowAugmentUtilityWindow = layoutConfig.ShowAugmentUtilityWindow or layoutDefaults.ShowAugmentUtilityWindow
    layoutDefaults.ShowItemDisplayWindow = layoutConfig.ShowItemDisplayWindow or layoutDefaults.ShowItemDisplayWindow
    layoutDefaults.ShowConfigWindow = layoutConfig.ShowConfigWindow or layoutDefaults.ShowConfigWindow
    layoutDefaults.ShowRerollWindow = layoutConfig.ShowRerollWindow or layoutDefaults.ShowRerollWindow
    layoutDefaults.AABackupPath = layoutConfig.AABackupPath or ""
    layoutDefaults.WidthRerollPanel = layoutConfig.WidthRerollPanel or layoutDefaults.WidthRerollPanel
    layoutDefaults.HeightReroll = layoutConfig.HeightReroll or layoutDefaults.HeightReroll
    layoutDefaults.RerollWindowX = layoutConfig.RerollWindowX or layoutDefaults.RerollWindowX
    layoutDefaults.RerollWindowY = layoutConfig.RerollWindowY or layoutDefaults.RerollWindowY
    -- Dock / bars ARRANGEMENT keys (where things are) round-trip through [Defaults]. The
    -- paradigm keys (UIMode, DockTop, DockBottom, DockPosition, DockChat, DockBottomStyle,
    -- DockButtons) are deliberately absent: same intent as the bundled-revert keep-list in
    -- settings.lua — capture/reset must never switch the UI paradigm out from under the
    -- player, so those live only in [Layout] and survive both operations untouched.
    layoutDefaults.DockSegments = layoutConfig.DockSegments or layoutDefaults.DockSegments
    layoutDefaults.ZoneAssign = layoutConfig.ZoneAssign or layoutDefaults.ZoneAssign or ""
    layoutDefaults.WindowAttach = layoutConfig.WindowAttach or layoutDefaults.WindowAttach or ""
    layoutDefaults.LayoutPreset = layoutConfig.LayoutPreset or layoutDefaults.LayoutPreset or ""
    layoutDefaults.UserPlaced = layoutConfig.UserPlaced or layoutDefaults.UserPlaced or ""
    layoutDefaults.AlignToContext = uiState.alignToContext and 1 or 0
    layoutDefaults.UILocked = uiState.uiLocked and 1 or 0
    layoutDefaults.SuppressWhenLootMac = uiState.suppressWhenLootMac and 1 or 0
    layoutDefaults.EnableRealTimeLoot = (uiState.enableRealTimeLoot == true) and 1 or 0
    layoutDefaults.EnableLootHistory = (uiState.enableLootHistory == true) and 1 or 0
    layoutDefaults.EnableSkipHistory = (uiState.enableSkipHistory == true) and 1 or 0
    layoutDefaults.ConfirmBeforeDelete = (uiState.confirmBeforeDelete == true) and 1 or 0
    layoutDefaults.NativeMerchantStrip = (uiState.nativeMerchantStrip ~= false) and 1 or 0
    layoutDefaults.NativeHoverTooltip = (uiState.nativeHoverTooltip ~= false) and 1 or 0
    layoutDefaults.NativeItemDisplayReplace = (uiState.nativeItemDisplayReplace ~= false) and 1 or 0
    if ImGui and ImGui.SaveIniSettingsToDisk then ImGui.SaveIniSettingsToDisk(nil) end

    local path = getLayoutFilePath and getLayoutFilePath()
    if path then
        local content = file_safe.safeReadAll(path) or ""
        local lines = {}
        local inDefaults = false
        local inColDefaults = false
        for line in content:gmatch("[^\n]+") do
            if line:match("^%s*%[Defaults%]") then
                inDefaults = true
            elseif line:match("^%s*%[ColumnVisibilityDefaults%]") then
                inColDefaults = true
            elseif line:match("^%s*%[") then
                inDefaults = false
                inColDefaults = false
                if not line:match("^%s*%[Defaults%]") and not line:match("^%s*%[ColumnVisibilityDefaults%]") then
                    table.insert(lines, line)
                end
            elseif not inDefaults and not inColDefaults then
                table.insert(lines, line)
            end
        end

        local function writeDefaultsFile(targetPath)
            local f = io.open(targetPath, "w")
            if not f then error("io.open write failed") end
            for _, line in ipairs(lines) do
                f:write(line .. "\n")
            end
            f:write("\n[Defaults]\n")
            f:write("AlignToContext=" .. layoutDefaults.AlignToContext .. "\n")
            f:write("UILocked=" .. layoutDefaults.UILocked .. "\n")
            f:write("WidthInventory=" .. layoutDefaults.WidthInventory .. "\n")
            f:write("Height=" .. layoutDefaults.Height .. "\n")
            f:write("WidthLoot=" .. layoutDefaults.WidthLoot .. "\n")
            f:write("WidthBankPanel=" .. layoutDefaults.WidthBankPanel .. "\n")
            f:write("HeightBank=" .. layoutDefaults.HeightBank .. "\n")
            f:write("BankWindowX=" .. layoutDefaults.BankWindowX .. "\n")
            f:write("BankWindowY=" .. layoutDefaults.BankWindowY .. "\n")
            f:write("ScriptTrackerWindowX=" .. tostring(layoutDefaults.ScriptTrackerWindowX or 0) .. "\n")
            f:write("ScriptTrackerWindowY=" .. tostring(layoutDefaults.ScriptTrackerWindowY or 0) .. "\n")
            f:write("WidthScriptTrackerPanel=" .. tostring(layoutDefaults.WidthScriptTrackerPanel or 460) .. "\n")
            f:write("HeightScriptTracker=" .. tostring(layoutDefaults.HeightScriptTracker or 400) .. "\n")
            f:write("WidthLootPanel=" .. tostring(layoutDefaults.WidthLootPanel or 420) .. "\n")
            f:write("HeightLoot=" .. tostring(layoutDefaults.HeightLoot or 380) .. "\n")
            f:write("LootWindowX=" .. tostring(layoutDefaults.LootWindowX or 0) .. "\n")
            f:write("LootWindowY=" .. tostring(layoutDefaults.LootWindowY or 0) .. "\n")
            f:write("WidthAugmentsPanel=" .. layoutDefaults.WidthAugmentsPanel .. "\n")
            f:write("HeightAugments=" .. layoutDefaults.HeightAugments .. "\n")
            f:write("AugmentsWindowX=" .. layoutDefaults.AugmentsWindowX .. "\n")
            f:write("AugmentsWindowY=" .. layoutDefaults.AugmentsWindowY .. "\n")
            f:write("WidthMythicalsPanel=" .. layoutDefaults.WidthMythicalsPanel .. "\n")
            f:write("HeightMythicals=" .. layoutDefaults.HeightMythicals .. "\n")
            f:write("MythicalsWindowX=" .. layoutDefaults.MythicalsWindowX .. "\n")
            f:write("MythicalsWindowY=" .. layoutDefaults.MythicalsWindowY .. "\n")
            f:write("CommandCenterWindowX=" .. layoutDefaults.CommandCenterWindowX .. "\n")
            f:write("CommandCenterWindowY=" .. layoutDefaults.CommandCenterWindowY .. "\n")
            f:write("WidthFavoritesPanel=" .. layoutDefaults.WidthFavoritesPanel .. "\n")
            f:write("HeightFavorites=" .. layoutDefaults.HeightFavorites .. "\n")
            f:write("FavoritesWindowX=" .. layoutDefaults.FavoritesWindowX .. "\n")
            f:write("FavoritesWindowY=" .. layoutDefaults.FavoritesWindowY .. "\n")
            f:write("WidthEffectsPanel=" .. (layoutDefaults.WidthEffectsPanel or 340) .. "\n")
            f:write("HeightEffects=" .. (layoutDefaults.HeightEffects or 480) .. "\n")
            f:write("EffectsWindowX=" .. (layoutDefaults.EffectsWindowX or 0) .. "\n")
            f:write("EffectsWindowY=" .. (layoutDefaults.EffectsWindowY or 0) .. "\n")
            f:write("EffectsCompact=" .. (layoutDefaults.EffectsCompact or 0) .. "\n")
            f:write("ChatWindowX=" .. (layoutDefaults.ChatWindowX or 0) .. "\n")
            f:write("ChatWindowY=" .. (layoutDefaults.ChatWindowY or 0) .. "\n")
            f:write("WidthChatPanel=" .. (layoutDefaults.WidthChatPanel or 560) .. "\n")
            f:write("HeightChat=" .. (layoutDefaults.HeightChat or 380) .. "\n")
            f:write("ShowChatWindow=" .. (layoutDefaults.ShowChatWindow or 1) .. "\n")
            f:write("ItemDisplayWindowX=" .. tostring(layoutDefaults.ItemDisplayWindowX or 0) .. "\n")
            f:write("ItemDisplayWindowY=" .. tostring(layoutDefaults.ItemDisplayWindowY or 0) .. "\n")
            f:write("WidthItemDisplayPanel=" .. tostring(layoutDefaults.WidthItemDisplayPanel or 760) .. "\n")
            f:write("HeightItemDisplay=" .. tostring(layoutDefaults.HeightItemDisplay or constants.VIEWS.HeightItemDisplay) .. "\n")
            f:write("AugmentUtilityWindowX=" .. tostring(layoutDefaults.AugmentUtilityWindowX or 0) .. "\n")
            f:write("AugmentUtilityWindowY=" .. tostring(layoutDefaults.AugmentUtilityWindowY or 0) .. "\n")
            f:write("WidthAugmentUtilityPanel=" .. tostring(layoutDefaults.WidthAugmentUtilityPanel or constants.VIEWS.WidthAugmentUtilityPanel) .. "\n")
            f:write("HeightAugmentUtility=" .. tostring(layoutDefaults.HeightAugmentUtility or 480) .. "\n")
            f:write("WidthAAPanel=" .. layoutDefaults.WidthAAPanel .. "\n")
            f:write("HeightAA=" .. layoutDefaults.HeightAA .. "\n")
            f:write("AAWindowX=" .. layoutDefaults.AAWindowX .. "\n")
            f:write("AAWindowY=" .. layoutDefaults.AAWindowY .. "\n")
            f:write("ShowAAWindow=" .. layoutDefaults.ShowAAWindow .. "\n")
            f:write("ShowEquipmentWindow=" .. tostring(layoutDefaults.ShowEquipmentWindow or 1) .. "\n")
            f:write("EquipmentWindowX=" .. tostring(layoutDefaults.EquipmentWindowX or 191) .. "\n")
            f:write("EquipmentWindowY=" .. tostring(layoutDefaults.EquipmentWindowY or 31) .. "\n")
            f:write("WidthEquipmentPanel=" .. tostring(layoutDefaults.WidthEquipmentPanel or 261) .. "\n")
            f:write("HeightEquipment=" .. tostring(layoutDefaults.HeightEquipment or 497) .. "\n")
            f:write("ShowBankWindow=" .. tostring(layoutDefaults.ShowBankWindow or 1) .. "\n")
            f:write("ShowAugmentsWindow=" .. tostring(layoutDefaults.ShowAugmentsWindow or 1) .. "\n")
            f:write("ShowAugmentUtilityWindow=" .. tostring(layoutDefaults.ShowAugmentUtilityWindow or 1) .. "\n")
            f:write("ShowItemDisplayWindow=" .. tostring(layoutDefaults.ShowItemDisplayWindow or 1) .. "\n")
            f:write("ShowConfigWindow=" .. tostring(layoutDefaults.ShowConfigWindow or 1) .. "\n")
            f:write("ShowRerollWindow=" .. tostring(layoutDefaults.ShowRerollWindow or 1) .. "\n")
            f:write("AABackupPath=" .. tostring(layoutDefaults.AABackupPath or "") .. "\n")
            f:write("WidthRerollPanel=" .. tostring(layoutDefaults.WidthRerollPanel or constants.VIEWS.WidthRerollPanel or 520) .. "\n")
            f:write("HeightReroll=" .. tostring(layoutDefaults.HeightReroll or constants.VIEWS.HeightReroll or 480) .. "\n")
            f:write("RerollWindowX=" .. tostring(layoutDefaults.RerollWindowX or 0) .. "\n")
            f:write("RerollWindowY=" .. tostring(layoutDefaults.RerollWindowY or 0) .. "\n")
            f:write("SuppressWhenLootMac=" .. layoutDefaults.SuppressWhenLootMac .. "\n")
            f:write("EnableRealTimeLoot=" .. (layoutDefaults.EnableRealTimeLoot or 0) .. "\n")
            f:write("EnableLootHistory=" .. (layoutDefaults.EnableLootHistory or 0) .. "\n")
            f:write("EnableSkipHistory=" .. (layoutDefaults.EnableSkipHistory or 0) .. "\n")
            f:write("ConfirmBeforeDelete=" .. (layoutDefaults.ConfirmBeforeDelete or 1) .. "\n")
            -- Bars arrangement only — paradigm keys (UIMode, Dock toggles/style) never enter
            -- [Defaults]; see the capture block above.
            f:write("DockSegments=" .. tostring(layoutDefaults.DockSegments or "") .. "\n")
            f:write("ZoneAssign=" .. tostring(layoutDefaults.ZoneAssign or "") .. "\n")
            f:write("WindowAttach=" .. tostring(layoutDefaults.WindowAttach or "") .. "\n")
            f:write("LayoutPreset=" .. tostring(layoutDefaults.LayoutPreset or "") .. "\n")
            f:write("UserPlaced=" .. tostring(layoutDefaults.UserPlaced or "") .. "\n")
            f:write("\n[ColumnVisibilityDefaults]\n")
            for view, cols in pairs(columnVisibility) do
                local visibleCols = {}
                for colKey, visible in pairs(cols) do
                    if visible then table.insert(visibleCols, colKey) end
                end
                f:write(view .. "=" .. table.concat(visibleCols, "/") .. "\n")
            end
            f:close()
        end
        -- Crash-safe write: stream to .tmp then swap in (remove + rename; os.rename does not
        -- overwrite existing files on Windows). On tmp/swap failure fall back to the direct
        -- write so behavior never regresses.
        local ok, err = pcall(function()
            local tmpPath = path .. ".tmp"
            writeDefaultsFile(tmpPath)
            os.remove(path)  -- may not exist yet; result intentionally ignored
            local renamed, renameErr = os.rename(tmpPath, path)
            if not renamed then error("os.rename failed: " .. tostring(renameErr)) end
        end)
        if not ok then
            pcall(os.remove, path .. ".tmp")  -- best-effort cleanup of orphaned tmp
            ok, err = pcall(writeDefaultsFile, path)
        end
        if not ok and print then
            print(string.format("\ar[CoOpt UI]\ax captureCurrentLayoutAsDefault write failed: %s", tostring(err)))
        end
    end

    print("\ag[CoOpt UI]\ax Current layout configuration captured as default! (Window sizes, positions, column widths, column visibility, and all settings)")
end

--- Reset layout to defaults (from parsed [Defaults]) and save.
local function layout_setup_resetLayoutToDefault()
    local parsed = parseLayoutFileFull and parseLayoutFileFull()
    if initColumnVisibility then initColumnVisibility() end
    if applyDefaultsFromParsed and parsed then applyDefaultsFromParsed(parsed) end

    layoutConfig.WidthInventory = layoutDefaults.WidthInventory
    layoutConfig.Height = layoutDefaults.Height
    layoutConfig.WidthLoot = layoutDefaults.WidthLoot
    layoutConfig.WidthBankPanel = layoutDefaults.WidthBankPanel
    layoutConfig.HeightBank = layoutDefaults.HeightBank
    layoutConfig.BankWindowX = layoutDefaults.BankWindowX
    layoutConfig.BankWindowY = layoutDefaults.BankWindowY
    layoutConfig.ScriptTrackerWindowX = layoutDefaults.ScriptTrackerWindowX or 0
    layoutConfig.ScriptTrackerWindowY = layoutDefaults.ScriptTrackerWindowY or 0
    layoutConfig.WidthScriptTrackerPanel = layoutDefaults.WidthScriptTrackerPanel
    layoutConfig.HeightScriptTracker = layoutDefaults.HeightScriptTracker
    layoutConfig.WidthLootPanel = layoutDefaults.WidthLootPanel
    layoutConfig.HeightLoot = layoutDefaults.HeightLoot
    layoutConfig.LootWindowX = layoutDefaults.LootWindowX
    layoutConfig.LootWindowY = layoutDefaults.LootWindowY
    layoutConfig.WidthAugmentsPanel = layoutDefaults.WidthAugmentsPanel
    layoutConfig.HeightAugments = layoutDefaults.HeightAugments
    layoutConfig.AugmentsWindowX = layoutDefaults.AugmentsWindowX
    layoutConfig.AugmentsWindowY = layoutDefaults.AugmentsWindowY
    layoutConfig.WidthMythicalsPanel = layoutDefaults.WidthMythicalsPanel
    layoutConfig.HeightMythicals = layoutDefaults.HeightMythicals
    layoutConfig.MythicalsWindowX = layoutDefaults.MythicalsWindowX
    layoutConfig.MythicalsWindowY = layoutDefaults.MythicalsWindowY
    layoutConfig.CommandCenterWindowX = layoutDefaults.CommandCenterWindowX
    layoutConfig.CommandCenterWindowY = layoutDefaults.CommandCenterWindowY
    layoutConfig.WidthFavoritesPanel = layoutDefaults.WidthFavoritesPanel
    layoutConfig.HeightFavorites = layoutDefaults.HeightFavorites
    layoutConfig.FavoritesWindowX = layoutDefaults.FavoritesWindowX
    layoutConfig.FavoritesWindowY = layoutDefaults.FavoritesWindowY
    layoutConfig.WidthEffectsPanel = layoutDefaults.WidthEffectsPanel
    layoutConfig.HeightEffects = layoutDefaults.HeightEffects
    layoutConfig.EffectsWindowX = layoutDefaults.EffectsWindowX
    layoutConfig.EffectsWindowY = layoutDefaults.EffectsWindowY
    layoutConfig.ChatWindowX = layoutDefaults.ChatWindowX or 0
    layoutConfig.ChatWindowY = layoutDefaults.ChatWindowY or 0
    layoutConfig.WidthChatPanel = layoutDefaults.WidthChatPanel or 560
    layoutConfig.HeightChat = layoutDefaults.HeightChat or 380
    layoutConfig.ShowChatWindow = layoutDefaults.ShowChatWindow or 1
    layoutConfig.EffectsCompact = layoutDefaults.EffectsCompact or 0
    layoutConfig.ItemDisplayWindowX = layoutDefaults.ItemDisplayWindowX
    layoutConfig.ItemDisplayWindowY = layoutDefaults.ItemDisplayWindowY
    layoutConfig.WidthItemDisplayPanel = layoutDefaults.WidthItemDisplayPanel
    layoutConfig.HeightItemDisplay = layoutDefaults.HeightItemDisplay
    layoutConfig.AugmentUtilityWindowX = layoutDefaults.AugmentUtilityWindowX
    layoutConfig.AugmentUtilityWindowY = layoutDefaults.AugmentUtilityWindowY
    layoutConfig.WidthAugmentUtilityPanel = layoutDefaults.WidthAugmentUtilityPanel
    layoutConfig.HeightAugmentUtility = layoutDefaults.HeightAugmentUtility
    layoutConfig.WidthAAPanel = layoutDefaults.WidthAAPanel
    layoutConfig.HeightAA = layoutDefaults.HeightAA
    layoutConfig.AAWindowX = layoutDefaults.AAWindowX
    layoutConfig.AAWindowY = layoutDefaults.AAWindowY
    layoutConfig.ShowAAWindow = layoutDefaults.ShowAAWindow
    layoutConfig.ShowEquipmentWindow = layoutDefaults.ShowEquipmentWindow
    layoutConfig.EquipmentWindowX = layoutDefaults.EquipmentWindowX or 191
    layoutConfig.EquipmentWindowY = layoutDefaults.EquipmentWindowY or 31
    layoutConfig.WidthEquipmentPanel = layoutDefaults.WidthEquipmentPanel or 261
    layoutConfig.HeightEquipment = layoutDefaults.HeightEquipment or 497
    layoutConfig.ShowBankWindow = layoutDefaults.ShowBankWindow
    layoutConfig.ShowAugmentsWindow = layoutDefaults.ShowAugmentsWindow
    layoutConfig.ShowAugmentUtilityWindow = layoutDefaults.ShowAugmentUtilityWindow
    layoutConfig.ShowItemDisplayWindow = layoutDefaults.ShowItemDisplayWindow
    layoutConfig.ShowConfigWindow = layoutDefaults.ShowConfigWindow
    layoutConfig.ShowRerollWindow = layoutDefaults.ShowRerollWindow
    layoutConfig.AABackupPath = layoutDefaults.AABackupPath or ""
    layoutConfig.WidthRerollPanel = layoutDefaults.WidthRerollPanel
    layoutConfig.HeightReroll = layoutDefaults.HeightReroll
    layoutConfig.RerollWindowX = layoutDefaults.RerollWindowX or 0
    layoutConfig.RerollWindowY = layoutDefaults.RerollWindowY or 0
    -- Dock / bars arrangement restored from the captured snapshot (or state.lua shipped
    -- defaults when never captured). UIMode and the other paradigm keys are deliberately
    -- NOT touched — mirroring the bundled-revert keep-list in settings.lua: resetting the
    -- LAYOUT must not flip classic<->bars or the dock's configuration out from under the
    -- player. window_zones picks up UserPlaced/WindowAttach via its own change detection.
    layoutConfig.DockSegments = layoutDefaults.DockSegments
    layoutConfig.ZoneAssign = layoutDefaults.ZoneAssign or ""
    layoutConfig.WindowAttach = layoutDefaults.WindowAttach or ""
    layoutConfig.LayoutPreset = layoutDefaults.LayoutPreset or ""
    layoutConfig.UserPlaced = layoutDefaults.UserPlaced or ""
    if sortState then
        sortState.invColumn = "Name"
        sortState.invDirection = ImGuiSortDirection.Ascending
        sortState.sellColumn = "Name"
        sortState.sellDirection = ImGuiSortDirection.Ascending
        sortState.bankColumn = "Name"
        sortState.bankDirection = ImGuiSortDirection.Ascending
        sortState.aaColumn = "Title"
        sortState.aaDirection = ImGuiSortDirection.Ascending
        sortState.aaTab = 1
    end
    uiState.alignToContext = (layoutDefaults.AlignToContext == 1)
    uiState.uiLocked = (layoutDefaults.UILocked == 1)
    uiState.suppressWhenLootMac = (layoutDefaults.SuppressWhenLootMac == 1)
    uiState.enableRealTimeLoot = ((layoutDefaults.EnableRealTimeLoot or 0) == 1)
    uiState.enableLootHistory = ((layoutDefaults.EnableLootHistory or 0) == 1)
    uiState.enableSkipHistory = ((layoutDefaults.EnableSkipHistory or 0) == 1)
    uiState.confirmBeforeDelete = ((layoutDefaults.ConfirmBeforeDelete or 1) == 1)
    uiState.nativeMerchantStrip = ((layoutDefaults.NativeMerchantStrip or 1) == 1)
    uiState.nativeHoverTooltip = ((layoutDefaults.NativeHoverTooltip or 1) == 1)
    uiState.nativeItemDisplayReplace = ((layoutDefaults.NativeItemDisplayReplace or 1) == 1)
    require('itemui.core.registry').setPinnedFromCSV("")  -- reset clears window Locks
    -- Reset restores the audited defaults AND pushes them to MQ, so the keys the user
    -- sees in Settings after a reset are the keys that actually fire.
    do
        local keybinds = require('itemui.utils.keybinds')
        keybinds.resetAll()
        keybinds.applyAll()
    end
    if saveLayoutToFile then saveLayoutToFile() end
    if perfCache then perfCache.layoutNeedsReload = true end

    print("\ag[CoOpt UI]\ax Layout reset to default! (Window sizes, column visibility, and settings restored)")
    print("\ay[CoOpt UI]\ax Note: Window sizes will apply on next reload. Close and reopen CoOpt UI Inventory Companion.")
end

return {
    init = layout_setup_init,
    captureCurrentLayoutAsDefault = layout_setup_captureCurrentLayoutAsDefault,
    resetLayoutToDefault = layout_setup_resetLayoutToDefault,
}
