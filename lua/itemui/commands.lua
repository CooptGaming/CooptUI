--[[ commands.lua: /itemui command handler.
     Subcommands: toggle, show, hide, center, refresh, setup, config, onboarding,
     reroll, sell [legacy|lua], exit/quit/unload, help.
     Dispatched from app.lua via mq.bind('/itemui', ...).
]]
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
            deps.uiState.userClosedViaKeybind = false
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
            deps.uiState.userClosedViaKeybind = true
            if deps.closeAllCompanionWindows then deps.closeAllCompanionWindows() end
            if deps.closeGameInventoryIfOpen then deps.closeGameInventoryIfOpen() end
            if deps.closeGameBankIfOpen then deps.closeGameBankIfOpen() end
            if deps.closeGameMerchantIfOpen then deps.closeGameMerchantIfOpen() end
        end
    elseif cmd == "show" then
        deps.uiState.userClosedViaKeybind = false
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
        deps.uiState.userClosedViaKeybind = true
        setShouldDraw(false)
        setIsOpen(false)
        if deps.closeAllCompanionWindows then deps.closeAllCompanionWindows() end
        if deps.closeGameInventoryIfOpen then deps.closeGameInventoryIfOpen() end
        if deps.closeGameBankIfOpen then deps.closeGameBankIfOpen() end
        if deps.closeGameMerchantIfOpen then deps.closeGameMerchantIfOpen() end
    elseif cmd == "center" then
        -- In bars mode the command bar has replaced the Command Center window, so this makes
        -- sure that bar is on screen instead of opening a window the user has retired. In
        -- classic mode it keeps doing exactly what it always did.
        local lc = deps.layoutConfig
        if lc and tostring(lc.UIMode or "classic") == "bars" then
            if lc.DockBottom == false then
                lc.DockBottom = true
                if deps.scheduleLayoutSave then deps.scheduleLayoutSave() end
            end
            print("\ag[ItemUI]\ax Command bar is on screen (hover Items / Character / Actions / Game windows).")
        else
            -- Native Command Center (the repurposed Tip of the Day window; needs /loadskin coopt)
            pcall(function() mq.TLO.Window('TipWindow').DoOpen() end)
        end
    elseif cmd == "dock" or (cmd:sub(1, 5) == "dock " and #cmd > 5) then
        local args = { ... }
        local sub = (cmd == "dock" and args[2]) and (tostring(args[2])):lower()
            or (cmd:match("^dock%s+(%S+)") or ""):lower()
        local lc = deps.layoutConfig
        if not lc then
            print("\ar[ItemUI]\ax Layout not loaded yet.")
        elseif sub == "off" or sub == "classic" then
            lc.UIMode = "classic"
            print("\ag[ItemUI]\ax Bars off - back to the classic UI.")
        elseif sub == "on" or sub == "bars" then
            lc.UIMode = "bars"
            print("\ag[ItemUI]\ax Bars on.")
        elseif sub == "top" or sub == "bottom" then
            lc.UIMode = "bars"
            lc.DockPosition = sub
            print(string.format("\ag[ItemUI]\ax Status bar moved to the %s edge.", sub))
        elseif sub == "" then
            -- No argument toggles, which is what a bare /itemui dock should do.
            local on = tostring(lc.UIMode or "classic") == "bars"
            lc.UIMode = on and "classic" or "bars"
            print(string.format("\ag[ItemUI]\ax Bars %s.", on and "off" or "on"))
        else
            print("\ar[ItemUI]\ax /itemui dock [on|off|top|bottom]")
            return
        end
        if deps.scheduleLayoutSave then deps.scheduleLayoutSave() end
    elseif cmd == "refresh" then
        if deps.scanInventory then deps.scanInventory() end
        if deps.isBankWindowOpen and deps.isBankWindowOpen() and deps.scanBank then deps.scanBank() end
        if deps.isMerchantWindowOpen and deps.isMerchantWindowOpen() and deps.scanSellItems then deps.scanSellItems() end
        print("\ag[ItemUI]\ax Refreshed")
    elseif cmd == "setup" then
        deps.uiState.setupMode = not deps.uiState.setupMode
        if deps.uiState.setupMode then
            -- The wizard renders steps 1-13 only; step 0 with setupMode on
            -- draws nothing (the Welcome screen requires setupMode OFF).
            deps.uiState.setupStep = 1
            if deps.loadConfigCache then deps.loadConfigCache() end
            if deps.loadLayoutConfig then deps.loadLayoutConfig() end
        else
            deps.uiState.setupStep = 0
        end
        setShouldDraw(true)
        setIsOpen(true)
        print(deps.uiState.setupMode and "\ag[ItemUI]\ax Setup wizard started - follow the 13 steps in the main window." or "\ar[ItemUI]\ax Setup off.")
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
        -- Inventory store: prefer inventoryItems — its rows serialize real stat values, while
        -- sellItems rows are flat copies whose lazy stat fields serialize as defaults (zeroed
        -- snapshots). Sell cache keeps its old source: the sell list when present.
        if deps.inventoryItems and #deps.inventoryItems > 0 then
            if deps.computeAndAttachSellStatus then deps.computeAndAttachSellStatus(deps.inventoryItems) end
            deps.storage.saveInventory(deps.inventoryItems)
        elseif deps.sellItems and #deps.sellItems > 0 then
            deps.storage.saveInventory(deps.sellItems)
        end
        if deps.sellItems and #deps.sellItems > 0 then
            deps.storage.writeSellCache(deps.sellItems)
        elseif deps.inventoryItems and #deps.inventoryItems > 0 then
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
        print("\ag[ItemUI]\ax /itemui or /inv or /inventoryui [toggle|show|hide|center|dock|refresh|setup|config|onboarding|reroll|sell|exit|help]")
        print("  center = focus the command bar (bars mode) or open the native Command Center (classic)")
        print("  dock [on|off|top|bottom] = the two bars: status on one edge, launchers and chat on the other")
        print("  setup = run the 13-step setup wizard (layout, sell/loot rules, epic protection)")
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
