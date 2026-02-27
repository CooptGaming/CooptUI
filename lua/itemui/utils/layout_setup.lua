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

function layout_setup_init(deps)
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
function layout_setup_captureCurrentLayoutAsDefault()
    layoutDefaults.WidthInventory = layoutConfig.WidthInventory or layoutDefaults.WidthInventory
    layoutDefaults.Height = layoutConfig.Height or layoutDefaults.Height
    layoutDefaults.WidthSell = layoutConfig.WidthSell or layoutDefaults.WidthSell
    layoutDefaults.WidthLoot = layoutConfig.WidthLoot or layoutDefaults.WidthLoot
    layoutDefaults.WidthBankPanel = layoutConfig.WidthBankPanel or layoutDefaults.WidthBankPanel
    layoutDefaults.HeightBank = layoutConfig.HeightBank or layoutDefaults.HeightBank
    layoutDefaults.WidthLootPanel = layoutConfig.WidthLootPanel or layoutDefaults.WidthLootPanel
    layoutDefaults.HeightLoot = layoutConfig.HeightLoot or layoutDefaults.HeightLoot
    layoutDefaults.LootWindowX = layoutConfig.LootWindowX or layoutDefaults.LootWindowX
    layoutDefaults.LootWindowY = layoutConfig.LootWindowY or layoutDefaults.LootWindowY
    if uiState.bankWindowOpen and uiState.bankWindowShouldDraw then
        layoutDefaults.BankWindowX = layoutConfig.BankWindowX or layoutDefaults.BankWindowX
        layoutDefaults.BankWindowY = layoutConfig.BankWindowY or layoutDefaults.BankWindowY
    else
        layoutDefaults.BankWindowX = layoutConfig.BankWindowX or layoutDefaults.BankWindowX
        layoutDefaults.BankWindowY = layoutConfig.BankWindowY or layoutDefaults.BankWindowY
    end
    layoutDefaults.WidthAugmentsPanel = layoutConfig.WidthAugmentsPanel or layoutDefaults.WidthAugmentsPanel
    layoutDefaults.HeightAugments = layoutConfig.HeightAugments or layoutDefaults.HeightAugments
    layoutDefaults.AugmentsWindowX = layoutConfig.AugmentsWindowX or layoutDefaults.AugmentsWindowX
    layoutDefaults.AugmentsWindowY = layoutConfig.AugmentsWindowY or layoutDefaults.AugmentsWindowY
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
    layoutDefaults.AlignToContext = uiState.alignToContext and 1 or 0
    layoutDefaults.AlignToMerchant = uiState.alignToMerchant and 1 or 0
    layoutDefaults.UILocked = uiState.uiLocked and 1 or 0
    layoutDefaults.SyncBankWindow = uiState.syncBankWindow and 1 or 0
    layoutDefaults.SuppressWhenLootMac = uiState.suppressWhenLootMac and 1 or 0
    layoutDefaults.ConfirmBeforeDelete = (uiState.confirmBeforeDelete == true) and 1 or 0
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

        local ok, err = pcall(function()
            local f = io.open(path, "w")
            if not f then error("io.open write failed") end
            for _, line in ipairs(lines) do
                f:write(line .. "\n")
            end
            f:write("\n[Defaults]\n")
            f:write("AlignToContext=" .. layoutDefaults.AlignToContext .. "\n")
            f:write("UILocked=" .. layoutDefaults.UILocked .. "\n")
            f:write("WidthInventory=" .. layoutDefaults.WidthInventory .. "\n")
            f:write("Height=" .. layoutDefaults.Height .. "\n")
            f:write("WidthSell=" .. layoutDefaults.WidthSell .. "\n")
            f:write("WidthLoot=" .. layoutDefaults.WidthLoot .. "\n")
            f:write("WidthBankPanel=" .. layoutDefaults.WidthBankPanel .. "\n")
            f:write("HeightBank=" .. layoutDefaults.HeightBank .. "\n")
            f:write("BankWindowX=" .. layoutDefaults.BankWindowX .. "\n")
            f:write("BankWindowY=" .. layoutDefaults.BankWindowY .. "\n")
            f:write("WidthLootPanel=" .. tostring(layoutDefaults.WidthLootPanel or 420) .. "\n")
            f:write("HeightLoot=" .. tostring(layoutDefaults.HeightLoot or 380) .. "\n")
            f:write("LootWindowX=" .. tostring(layoutDefaults.LootWindowX or 0) .. "\n")
            f:write("LootWindowY=" .. tostring(layoutDefaults.LootWindowY or 0) .. "\n")
            f:write("WidthAugmentsPanel=" .. layoutDefaults.WidthAugmentsPanel .. "\n")
            f:write("HeightAugments=" .. layoutDefaults.HeightAugments .. "\n")
            f:write("AugmentsWindowX=" .. layoutDefaults.AugmentsWindowX .. "\n")
            f:write("AugmentsWindowY=" .. layoutDefaults.AugmentsWindowY .. "\n")
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
            f:write("SyncBankWindow=" .. layoutDefaults.SyncBankWindow .. "\n")
            f:write("SuppressWhenLootMac=" .. layoutDefaults.SuppressWhenLootMac .. "\n")
            f:write("ConfirmBeforeDelete=" .. (layoutDefaults.ConfirmBeforeDelete or 1) .. "\n")
            f:write("SellViewLocked=" .. (uiState.sellViewLocked and "1" or "0") .. "\n")
            f:write("InvViewLocked=" .. (uiState.invViewLocked and "1" or "0") .. "\n")
            f:write("BankViewLocked=" .. (uiState.bankViewLocked and "1" or "0") .. "\n")
            f:write("\n[ColumnVisibilityDefaults]\n")
            for view, cols in pairs(columnVisibility) do
                local visibleCols = {}
                for colKey, visible in pairs(cols) do
                    if visible then table.insert(visibleCols, colKey) end
                end
                f:write(view .. "=" .. table.concat(visibleCols, "/") .. "\n")
            end
            f:close()
        end)
        if not ok and print then
            print(string.format("\ar[ItemUI]\ax captureCurrentLayoutAsDefault write failed: %s", tostring(err)))
        end
    end

    print("\ag[ItemUI]\ax Current layout configuration captured as default! (Window sizes, positions, column widths, column visibility, and all settings)")
end

--- Reset layout to defaults (from parsed [Defaults]) and save.
function layout_setup_resetLayoutToDefault()
    local parsed = parseLayoutFileFull and parseLayoutFileFull()
    if initColumnVisibility then initColumnVisibility() end
    if applyDefaultsFromParsed and parsed then applyDefaultsFromParsed(parsed) end

    layoutConfig.WidthInventory = layoutDefaults.WidthInventory
    layoutConfig.Height = layoutDefaults.Height
    layoutConfig.WidthSell = layoutDefaults.WidthSell
    layoutConfig.WidthLoot = layoutDefaults.WidthLoot
    layoutConfig.WidthBankPanel = layoutDefaults.WidthBankPanel
    layoutConfig.HeightBank = layoutDefaults.HeightBank
    layoutConfig.BankWindowX = layoutDefaults.BankWindowX
    layoutConfig.BankWindowY = layoutDefaults.BankWindowY
    layoutConfig.WidthLootPanel = layoutDefaults.WidthLootPanel
    layoutConfig.HeightLoot = layoutDefaults.HeightLoot
    layoutConfig.LootWindowX = layoutDefaults.LootWindowX
    layoutConfig.LootWindowY = layoutDefaults.LootWindowY
    layoutConfig.WidthAugmentsPanel = layoutDefaults.WidthAugmentsPanel
    layoutConfig.HeightAugments = layoutDefaults.HeightAugments
    layoutConfig.AugmentsWindowX = layoutDefaults.AugmentsWindowX
    layoutConfig.AugmentsWindowY = layoutDefaults.AugmentsWindowY
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
    if sortState then
        sortState.aaColumn = "Title"
        sortState.aaDirection = ImGuiSortDirection.Ascending
        sortState.aaTab = 1
    end
    uiState.alignToContext = (layoutDefaults.AlignToContext == 1)
    uiState.uiLocked = (layoutDefaults.UILocked == 1)
    uiState.syncBankWindow = (layoutDefaults.SyncBankWindow == 1)
    uiState.suppressWhenLootMac = (layoutDefaults.SuppressWhenLootMac == 1)
    uiState.confirmBeforeDelete = ((layoutDefaults.ConfirmBeforeDelete or 1) == 1)
    if saveLayoutToFile then saveLayoutToFile() end
    if perfCache then perfCache.layoutNeedsReload = true end

    print("\ag[ItemUI]\ax Layout reset to default! (Window sizes, column visibility, and settings restored)")
    print("\ay[ItemUI]\ax Note: Window sizes will apply on next reload. Close and reopen CoOpt UI Inventory Companion.")
end

return {
    init = layout_setup_init,
    captureCurrentLayoutAsDefault = layout_setup_captureCurrentLayoutAsDefault,
    resetLayoutToDefault = layout_setup_resetLayoutToDefault,
}
