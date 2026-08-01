-- Inventory + Bank suite. The phase-10 two-pane merge these views were split for was
-- ROLLED BACK (bags and bank are separate windows again, aligned by window_zones), but
-- the split and its invariants survived and are what this guards:
--
--   1. Classic/bars composition: render = toolbar + table, drawing balanced.
--   2. BankView.resolveList picks live vs snapshot per source.
--   3. The 20a source chip - live vs snapshot-with-age, what the source holds, and the
--      rule that applies - now in the standalone Bank window's own header.
--   4. The pcall sits INSIDE BeginTable/EndTable in BOTH views: a throw that skips
--      EndTable is a C++ ImGuiException MQ2Lua answers by killing the script.
--   5. Bank carries no classicOnly flag, which is what re-arms zone placement for it.

local repo = os.getenv('COOPT_REPO') or 'C:/Claude/CooptUI'
package.path = repo .. '/lua/?.lua;' .. repo .. '/lua/?/init.lua;'
    .. repo .. '/scripts/tests/?.lua;' .. package.path

local pass, fail = 0, 0
local function check(name, cond, extra)
    if cond then
        pass = pass + 1
        print('PASS: ' .. name)
    else
        fail = fail + 1
        print('FAIL: ' .. name .. (extra and ('  -> ' .. tostring(extra)) or ''))
    end
end

local stub = require('imgui_stub')
stub.install()
package.loaded['mq'] = stub.newMq()
package.loaded['mq.ItemUtils'] = {
    formatValue = function(v) return tostring(v or 0) .. 'p' end,
}
package.loaded['itemui.utils.coopui_plugin'] = {
    getPlugin = function() return nil end, getIPC = function() return nil end,
    getINI = function() return nil end, getWindow = function() return nil end,
    getCursor = function() return nil end, getItems = function() return nil end,
}
package.loaded['itemui.core.diagnostics'] = {
    getErrorCount = function() return 0 end, recordError = function() end,
}

local theme = require('itemui.utils.theme')
local registry = require('itemui.core.registry')
local InventoryView = require('itemui.views.inventory')
local BankView = require('itemui.views.bank')

-- ---------------------------------------------------------------- ctx factory
local function makeItems(prefix, n)
    local t = {}
    for i = 1, n do
        t[i] = {
            name = prefix .. ' Item ' .. i,
            bag = 1 + (i % 3), slot = i,
            totalValue = i * 100,
            stackSize = (i % 4 == 0) and 5 or 1,
            icon = 500 + i,
            type = 'Misc',
        }
    end
    return t
end

local function makeCtx(over)
    local calls = { scheduleLayoutSave = 0, flushLayoutSave = 0, ensureBank = 0 }
    local ctx = {
        _calls = calls,
        theme = theme,
        uiState = {
            searchFilterInv = '', searchFilterBank = '',
            tableFlags = 0,
            lastPickup = {},
            uiLocked = false,
        },
        sortState = { invColumn = 'Name', invDirection = 1, bankColumn = 'Name', bankDirection = 1 },
        perfCache = {
            lastScanTimeInv = 0, lastBankCacheTime = os.time() - (2 * 86400 + 120),
            inv = {}, bank = {},
            invTotalSlots = 80, invTotalValue = 1234,
        },
        layoutConfig = { UIMode = 'bars', ShowBankWindow = 1 },
        inventoryItems = makeItems('Inv', 4),
        bankItems = makeItems('BankLive', 3),
        bankCache = makeItems('BankSnap', 5),
        columnAutofitWidths = { Inventory = {}, Bank = {} },
        availableColumns = { Inventory = {}, Bank = {} },
        sortColumns = {
            simpleHash = function(s) return #tostring(s) end,
            getCellDisplayText = function(item, colKey) return tostring(item[string.lower(colKey)] or item.name or '') end,
        },
        getFixedColumns = function(view)
            if view == 'Bank' then
                return { {key='Name',label='Name'}, {key='Value',label='Value'} }
            end
            return { {key='Name',label='Name'}, {key='Status',label='Status'} }
        end,
        getSortedList = function(_, list) return list end,
        getColumnKeyByIndex = function() return 'Name' end,
        isColumnInFixedSet = function() return true end,
        toggleFixedColumn = function() end,
        autofitColumns = function() end,
        setStatusMessage = function() end,
        hasItemOnCursor = function() return false end,
        shouldHideRowForCursor = function() return false end,
        getSessionStartAcquiredSeq = function() return nil end,
        resolveSellStatusDisplay = function() return '-', ImVec4(1, 1, 1, 1) end,
        getSellStatusNameColor = function() return ImVec4(1, 1, 1, 1) end,
        renderItemContextMenu = function() end,
        renderRefreshButton = function() end,
        refreshAllScans = function() end,
        scheduleLayoutSave = function() calls.scheduleLayoutSave = calls.scheduleLayoutSave + 1 end,
        flushLayoutSave = function() calls.flushLayoutSave = calls.flushLayoutSave + 1 end,
        ensureBankCacheFromStorage = function() calls.ensureBank = calls.ensureBank + 1 end,
        computeAndAttachSellStatus = function() end,
        getItemSpellId = function() return 0 end,
        getSpellName = function() return nil end,
        getSpellDescription = function() return nil end,
        getTimerReady = function() return 0 end,
        moveInvToBank = function() end,
        moveBankToInv = function() end,
        dropAtSlot = function() end,
        pickupFromSlot = function() end,
        putCursorInBags = function() end,
        isBankWindowOpen = function() return false end,
    }
    for k, v in pairs(over or {}) do ctx[k] = v end
    return ctx
end

-- ---------------------------------------------------------------- 1. classic shape
do
    local ctx = makeCtx({ layoutConfig = { UIMode = 'classic', ShowBankWindow = 1 } })
    local r = stub.frame(function() InventoryView.render(ctx, false) end)
    check('classic: render draws without error', r.ok, r.err)
    check('classic: stacks balanced', stub.balanced(r))
    check('classic: table body ran (rows drawn)', stub.drew(r, 'Inv Item 1'))
    check('classic: items/value status line drawn', stub.drew(r, 'Items: 4 / 80'))
end

-- ---------------------------------------------------------------- 2. bank table extraction
do
    local ctx = makeCtx()
    local list = BankView.resolveList(ctx, false)
    check('bank: resolveList snapshot source', list == ctx.bankCache)
    check('bank: resolveList live source', BankView.resolveList(ctx, true) == ctx.bankItems)
    check('bank: ensureBankCacheFromStorage called', ctx._calls.ensureBank == 2)
    local r = stub.frame(function() BankView.renderTable(ctx, list, false) end)
    check('bank: renderTable draws snapshot rows', r.ok and stub.drew(r, 'BankSnap Item 1'), r.err)
    check('bank: renderTable balanced', stub.balanced(r))
end

-- ---------------------------------------------------------------- 3. the 20a source chip
-- Salvaged from the merge suite: the chip is the one part of phase 10 that survived the
-- rollback, and it now lives in the standalone Bank window's own header.
do
    local ctx = makeCtx()
    local list = BankView.resolveList(ctx, false)
    local r = stub.frame(function() BankView.renderSourceChip(ctx, list, false) end)
    check('chip snapshot: says snapshot with a humanized age', r.ok and stub.drew(r, 'snapshot . 2d old'),
        table.concat(r.text, '|'))
    check('chip snapshot: states what the source holds', stub.drew(r, '5 items . 1500p'),
        table.concat(r.text, '|'))
    check('chip snapshot: says why it is read-only', stub.drew(r, 'read-only - open a bank to refresh'),
        table.concat(r.text, '|'))
    check('chip snapshot: balanced', stub.balanced(r))

    local ctxLive = makeCtx({ isBankWindowOpen = function() return true end })
    local liveList = BankView.resolveList(ctxLive, true)
    local rLive = stub.frame(function() BankView.renderSourceChip(ctxLive, liveList, true) end)
    check('chip live: says live', rLive.ok and stub.drew(rLive, 'live'), table.concat(rLive.text, '|'))
    check('chip live: states the input rule', stub.drew(rLive, 'shift + left-click moves an item to your bags'),
        table.concat(rLive.text, '|'))
    check('chip live: counts the LIVE list, not the snapshot', stub.drew(rLive, '3 items . 600p'),
        table.concat(rLive.text, '|'))
    check('chip live: balanced', stub.balanced(rLive))

    -- The stat is cached on (length, source, snapshot time). Flipping source alone must
    -- re-key it, or a live bank would report the snapshot's holdings forever.
    local rBack = stub.frame(function() BankView.renderSourceChip(ctx, list, false) end)
    check('chip: cache re-keys on source flip', stub.drew(rBack, '5 items . 1500p'),
        table.concat(rBack.text, '|'))
end

-- ---------------------------------------------------------------- 4. throw containment
do
    -- The pcall lives INSIDE BeginTable/EndTable in both views: a throw that skips
    -- EndTable is a C++ ImGuiException MQ2Lua answers by killing the script. This is the
    -- invariant the merge left behind, and it is why the table bodies are split out.
    stub.throwOn = { TableSetupScrollFreeze = true }
    local ctx = makeCtx()
    local r = stub.frame(function() InventoryView.render(ctx, false) end)
    local ctxB = makeCtx()
    local rB = stub.frame(function() BankView.renderTable(ctxB, BankView.resolveList(ctxB, false), false) end)
    stub.throwOn = {}
    check('throw: inventory content throw contained', r.ok, r.err)
    check('throw: inventory stacks balanced', stub.balanced(r),
        string.format('win=%d child=%d sv=%d sc=%d tbl=%d', r.depth.win, r.depth.child, r.depth.sv, r.depth.sc, r.depth.tbl))
    check('throw: bank content throw contained', rB.ok, rB.err)
    check('throw: bank stacks balanced', stub.balanced(rB),
        string.format('win=%d child=%d sv=%d sc=%d tbl=%d', rB.depth.win, rB.depth.child, rB.depth.sv, rB.depth.sc, rB.depth.tbl))
end

-- ---------------------------------------------------------------- 5. registry
do
    -- The merge made bank classicOnly. The rollback removes that: bank is a real window
    -- in BOTH modes, which is what re-arms window_zones placement (it can only place a
    -- module it can see open).
    registry.init({ layoutConfig = { UIMode = 'bars' } })
    check('registry: bank is offered in bars again (no classicOnly)', registry.isEnabled('bank') == true)
    registry.init({ layoutConfig = { UIMode = 'classic' } })
    check('registry: bank offered in classic', registry.isEnabled('bank') == true)
end

-- ---------------------------------------------------------------- report
print(string.format('\n%d passed, %d failed', pass, fail))
if fail > 0 then os.exit(1) end
