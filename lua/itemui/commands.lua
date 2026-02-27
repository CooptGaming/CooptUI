local mq = require('mq')

local M = {}

local deps = {}

local function getShouldDraw()
    return deps.shouldDraw and deps.shouldDraw.get and deps.shouldDraw.get() or false
end

local function setShouldDraw(v)
    if deps.shouldDraw and deps.shouldDraw.set then deps.shouldDraw.set(v) end
end

local function getIsOpen()
    return deps.isOpen and deps.isOpen.get and deps.isOpen.get() or false
end

local function setIsOpen(v)
    if deps.isOpen and deps.isOpen.set then deps.isOpen.set(v) end
end

local function setTerminate(v)
    if deps.terminate and deps.terminate.set then deps.terminate.set(v) end
end

function M.init(initDeps)
    deps = initDeps or {}
end

function M.handleCommand(...)
    local cmd = (({ ... })[1] or ""):lower()
    if cmd == "" or cmd == "toggle" then
        local nextShouldDraw = not getShouldDraw()
        setShouldDraw(nextShouldDraw)
        if nextShouldDraw then
            local _w = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
            local invO = (_w and _w.Open and _w.Open()) or false
            local bankO = deps.isBankWindowOpen and deps.isBankWindowOpen() or false
            local merchO = deps.isMerchantWindowOpen and deps.isMerchantWindowOpen() or false
            if not invO then mq.cmd('/keypress inventory'); invO = true end
            setIsOpen(true)
            if deps.loadLayoutConfig then deps.loadLayoutConfig() end
            if deps.maybeScanInventory then deps.maybeScanInventory(invO) end
            if deps.maybeScanBank then deps.maybeScanBank(bankO) end
            if deps.maybeScanSellItems then deps.maybeScanSellItems(merchO) end
            deps.uiState.equipmentWindowOpen = true
            deps.uiState.equipmentWindowShouldDraw = true
            if deps.recordCompanionWindowOpened then deps.recordCompanionWindowOpened("equipment") end
        else
            if deps.closeGameInventoryIfOpen then deps.closeGameInventoryIfOpen() end
        end
    elseif cmd == "show" then
        setShouldDraw(true)
        setIsOpen(true)
        local _w = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
        local invO = (_w and _w.Open and _w.Open()) or false
        local bankO = deps.isBankWindowOpen and deps.isBankWindowOpen() or false
        local merchO = deps.isMerchantWindowOpen and deps.isMerchantWindowOpen() or false
        if deps.loadLayoutConfig then deps.loadLayoutConfig() end
        if deps.maybeScanInventory then deps.maybeScanInventory(invO) end
        if deps.maybeScanBank then deps.maybeScanBank(bankO) end
        if deps.maybeScanSellItems then deps.maybeScanSellItems(merchO) end
        deps.uiState.equipmentWindowOpen = true
        deps.uiState.equipmentWindowShouldDraw = true
        if deps.recordCompanionWindowOpened then deps.recordCompanionWindowOpened("equipment") end
    elseif cmd == "hide" then
        setShouldDraw(false)
        setIsOpen(false)
        if deps.closeGameInventoryIfOpen then deps.closeGameInventoryIfOpen() end
    elseif cmd == "refresh" then
        if deps.scanInventory then deps.scanInventory() end
        if deps.isBankWindowOpen and deps.isBankWindowOpen() and deps.scanBank then deps.scanBank() end
        if deps.isMerchantWindowOpen and deps.isMerchantWindowOpen() and deps.scanSellItems then deps.scanSellItems() end
        print("\ag[ItemUI]\ax Refreshed")
    elseif cmd == "setup" then
        deps.uiState.setupMode = not deps.uiState.setupMode
        if deps.uiState.setupMode then
            deps.uiState.setupStep = 0
            if deps.loadConfigCache then deps.loadConfigCache() end
            if deps.loadLayoutConfig then deps.loadLayoutConfig() end
        else
            deps.uiState.setupStep = 0
        end
        setShouldDraw(true)
        setIsOpen(true)
        print(deps.uiState.setupMode and "\ag[ItemUI]\ax Setup: Step 0 of 8 — Epic protection (optional), then layout and rules." or "\ar[ItemUI]\ax Setup off.")
    elseif cmd == "config" then
        deps.uiState.configWindowOpen = true
        deps.uiState.configNeedsLoad = true
        if deps.recordCompanionWindowOpened then deps.recordCompanionWindowOpened("config") end
        setShouldDraw(true)
        setIsOpen(true)
        print("\ag[ItemUI]\ax Config window opened.")
    elseif cmd == "onboarding" then
        if deps.resetOnboarding then deps.resetOnboarding() end
        setShouldDraw(true)
        setIsOpen(true)
        mq.cmd("/keypress inventory")
        print("\ag[ItemUI]\ax Welcome panel will show in the main window.")
    elseif cmd == "reroll" then
        if deps.registry and not deps.registry.isOpen("reroll") then deps.registry.toggleWindow("reroll") end
        if deps.registry and deps.registry.isOpen("reroll") and deps.recordCompanionWindowOpened then deps.recordCompanionWindowOpened("reroll") end
        setShouldDraw(true)
        setIsOpen(true)
        print("\ag[ItemUI]\ax Reroll Companion opened.")
    elseif cmd == "exit" or cmd == "quit" or cmd == "unload" then
        if deps.storage then deps.storage.ensureCharFolderExists() end
        if deps.sellItems and #deps.sellItems > 0 then
            deps.storage.saveInventory(deps.sellItems)
            deps.storage.writeSellCache(deps.sellItems)
        elseif deps.inventoryItems and #deps.inventoryItems > 0 then
            if deps.computeAndAttachSellStatus then deps.computeAndAttachSellStatus(deps.inventoryItems) end
            deps.storage.saveInventory(deps.inventoryItems)
            deps.storage.writeSellCache(deps.inventoryItems)
        end
        if (deps.bankItems and #deps.bankItems > 0) or (deps.bankCache and #deps.bankCache > 0) then
            deps.storage.saveBank((deps.bankItems and #deps.bankItems > 0) and deps.bankItems or deps.bankCache)
        end
        if deps.flushLayoutSave then deps.flushLayoutSave() end
        setTerminate(true)
        setShouldDraw(false)
        setIsOpen(false)
        deps.uiState.configWindowOpen = false
        print("\ag[ItemUI]\ax Unloading...")
    elseif cmd == "sell" or (cmd:sub(1, 5) == "sell " and #cmd > 5) then
        local args = { ... }
        local sub = (cmd == "sell" and args[2]) and (tostring(args[2])):lower() or (cmd:match("^sell%s+(%S+)") or ""):lower()
        if sub == "legacy" then
            if deps.runSellMacro then deps.runSellMacro("macro") end
        elseif sub == "lua" then
            if deps.runSellMacro then deps.runSellMacro("lua") end
        else
            print("\ag[ItemUI]\ax /itemui sell legacy = run sell.mac  |  /itemui sell lua = run Lua sell")
        end
    elseif cmd == "help" then
        print("\ag[ItemUI]\ax /itemui or /inv or /inventoryui [toggle|show|hide|refresh|setup|config|onboarding|reroll|exit|help]")
        print("  setup = resize and save window/column layout for Inventory, Sell, and Inventory+Bank")
        print("  config = open ItemUI & Loot settings (or click Settings in the header)")
        print("  onboarding = show the first-run welcome panel again")
        print("  reroll = open Reroll Companion (augment and mythical reroll lists)")
        print("  exit  = unload ItemUI completely")
        print("  sell legacy = run sell.mac  |  sell lua = run Lua sell (see sell_flags.ini sellMode)")
        print("\ag[ItemUI]\ax /dosell = run sell (macro or Lua per sellMode)  |  /doloot = run loot.mac")
    else
        print("\ar[ItemUI]\ax Unknown: " .. cmd .. " — use /itemui help")
    end
end

return M
