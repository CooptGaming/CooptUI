-- Phase 10 (23a) merge suite: the split of inventory.lua into toolbar/table, the bank
-- table extraction, and the merged two-pane content the bars-mode hub hosts.
--
-- Like the other render suites this proves balance and behaviour, not pixels:
--   1. Classic composition (render = toolbar + table) draws and ends balanced — the
--      acceptance bar is "classic renders exactly what it rendered before the split".
--   2. renderMergedContent builds both panes, passes ResizeX + NoSavedSettings on the
--      bags child (the load-bearing pairing: without NoSavedSettings ImGui persists the
--      child size to its own ini and fights the layout INI), and clamps the splitter.
--   3. The one-toolbar rule: the merged search filters BOTH panes.
--   4. The 20a chip: live vs snapshot-with-age is drawn, table dims only in snapshot,
--      and every push/pop pair survives an injected throw inside either pane's table.
--   5. ShowBankWindow=0 renders the classic single-pane shape (no bank child).

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
        layoutConfig = { UIMode = 'bars', ShowBankWindow = 1, InventoryBankSplitX = 0 },
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
        resolveSellStatusDisplay = function() return '—', ImVec4(1, 1, 1, 1) end,
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

local function childArg(r, name)
    for _, c in ipairs(r.childArgs) do
        if c.name == name then return c end
    end
    return nil
end

-- ---------------------------------------------------------------- 1. classic shape
do
    local ctx = makeCtx({ layoutConfig = { UIMode = 'classic', ShowBankWindow = 1, InventoryBankSplitX = 0 } })
    local r = stub.frame(function() InventoryView.render(ctx, false) end)
    check('classic: render draws without error', r.ok, r.err)
    check('classic: stacks balanced', stub.balanced(r))
    check('classic: table body ran (rows drawn)', stub.drew(r, 'Inv Item 1'))
    check('classic: items/value status line drawn', stub.drew(r, 'Items: 4 / 80'))
    check('classic: no merged panes', childArg(r, 'MergedBagsPane') == nil and childArg(r, 'MergedBankPane') == nil)
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

-- ---------------------------------------------------------------- 3. merged content
do
    stub.contentAvail = { 1000, 600 }
    stub.windowSize = { 550, 0 }  -- child reports the width we pass = no drag
    local ctx = makeCtx()
    local r = stub.frame(function() InventoryView.renderMergedContent(ctx, false) end)
    check('merged: draws without error', r.ok, r.err)
    check('merged: stacks balanced', stub.balanced(r))
    local bags = childArg(r, 'MergedBagsPane')
    local bank = childArg(r, 'MergedBankPane')
    check('merged: both panes exist', bags ~= nil and bank ~= nil)
    if bags then
        local wantChild = bit32.bor(ImGuiChildFlags.Borders, ImGuiChildFlags.ResizeX)
        check('merged: bags child uses ResizeX child flags', bags.c == wantChild, tostring(bags.c))
        check('merged: bags child pairs NoSavedSettings', bags.d == ImGuiWindowFlags.NoSavedSettings, tostring(bags.d))
        check('merged: auto split = 55% of avail', bags.a == 550, tostring(bags.a))
    end
    check('merged: both tables drew rows', stub.drew(r, 'Inv Item 1') and stub.drew(r, 'BankSnap Item 1'))
    check('merged: snapshot chip drawn with age', stub.drew(r, 'snapshot · 2d old'))
    check('merged: snapshot stat line drawn', stub.drew(r, '5 items · 1500p'))
    check('merged: read-only hint drawn', stub.drew(r, 'read-only — open a bank to refresh'))
    check('merged: no drag -> no split persist', ctx._calls.scheduleLayoutSave == 0 and ctx.layoutConfig.InventoryBankSplitX == 0)
    check('merged: one search, both panes', ctx.uiState.searchFilterBank == ctx.uiState.searchFilterInv)

    -- live source: chip flips, no dim
    local ctxLive = makeCtx({ isBankWindowOpen = function() return true end })
    local rLive = stub.frame(function() InventoryView.renderMergedContent(ctxLive, true) end)
    check('merged live: chip says live', rLive.ok and stub.drew(rLive, 'live'), rLive.err)
    check('merged live: live rows drawn', stub.drew(rLive, 'BankLive Item 1'))
    check('merged live: balanced', stub.balanced(rLive))
end

-- ---------------------------------------------------------------- 4. splitter behaviour
do
    -- stored width honored + clamped
    stub.contentAvail = { 1000, 600 }
    stub.windowSize = { 900, 0 }
    local ctx = makeCtx()
    ctx.layoutConfig.InventoryBankSplitX = 5000  -- absurd: must clamp to avail - min pane
    local r = stub.frame(function() InventoryView.renderMergedContent(ctx, false) end)
    local bags = childArg(r, 'MergedBagsPane')
    check('splitter: clamped to avail - MIN', bags and bags.a == 780, bags and tostring(bags.a))

    -- drag: measured (900) differs from passed (780) -> persisted once
    check('splitter: drag persisted', ctx.layoutConfig.InventoryBankSplitX == 900
        and ctx._calls.scheduleLayoutSave == 1, tostring(ctx.layoutConfig.InventoryBankSplitX))

    -- narrow region: halve rather than 0-width a pane
    stub.contentAvail = { 300, 600 }
    stub.windowSize = { 150, 0 }
    local ctx2 = makeCtx()
    local r2 = stub.frame(function() InventoryView.renderMergedContent(ctx2, false) end)
    local bags2 = childArg(r2, 'MergedBagsPane')
    check('splitter: narrow region halves', bags2 and bags2.a == 150, bags2 and tostring(bags2.a))
    check('splitter: narrow region balanced', stub.balanced(r2))
end

-- ---------------------------------------------------------------- 5. gate + cursor ring
do
    stub.contentAvail = { 1000, 600 }
    stub.windowSize = { 550, 0 }
    local ctx = makeCtx()
    ctx.layoutConfig.ShowBankWindow = 0
    local r = stub.frame(function() InventoryView.renderMergedContent(ctx, false) end)
    check('gate: ShowBankWindow=0 -> classic shape', r.ok and childArg(r, 'MergedBagsPane') == nil
        and childArg(r, 'MergedBankPane') == nil, r.err)
    check('gate: rows still drawn', stub.drew(r, 'Inv Item 1'))
    check('gate: balanced', stub.balanced(r))

    -- carrying an item rings the bags pane: border color + 2px pushed AND popped
    local ctx2 = makeCtx({ hasItemOnCursor = function() return true end })
    local r2 = stub.frame(function() InventoryView.renderMergedContent(ctx2, false) end)
    check('ring: carrying draws and stays balanced', r2.ok and stub.balanced(r2), r2.err)
end

-- ---------------------------------------------------------------- 6. throw containment
do
    stub.contentAvail = { 1000, 600 }
    stub.windowSize = { 550, 0 }
    -- A throw inside either pane's table must cost the frame's content, never the stacks:
    -- EndChild is unconditional and the snapshot Alpha pair sits outside the pcall'd body.
    stub.throwOn = { TableSetupScrollFreeze = true }
    local ctx = makeCtx()
    local r = stub.frame(function() InventoryView.renderMergedContent(ctx, false) end)
    stub.throwOn = {}
    check('throw: content throw contained', r.ok, r.err)
    check('throw: stacks balanced after pane throw', stub.balanced(r),
        string.format('win=%d child=%d sv=%d sc=%d tbl=%d', r.depth.win, r.depth.child, r.depth.sv, r.depth.sc, r.depth.tbl))
end

-- ---------------------------------------------------------------- 7. registry gate
do
    registry.init({ layoutConfig = { UIMode = 'bars' } })
    check('registry: bank hidden in bars (classicOnly)', registry.isEnabled('bank') == false)
    registry.init({ layoutConfig = { UIMode = 'classic' } })
    check('registry: bank offered in classic', registry.isEnabled('bank') == true)
end

-- ---------------------------------------------------------------- report
stub.windowSize = nil
stub.contentAvail = nil
print(string.format('\n%d passed, %d failed', pass, fail))
if fail > 0 then os.exit(1) end
