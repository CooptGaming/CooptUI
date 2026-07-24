--[[ native_bridge.lua: drives CoOpt controls that the "coopt" UI skin adds to
     native EQ windows (uifiles\coopt). Surfaces:
       MerchantWnd    - Auto Sell / Preview buttons + sell status line
       LootWnd        - CoOpt Cur / CoOpt All buttons + loot status line,
                        plus optional auto-loot when a corpse window opens
       ActionsWindow  - "CoOpt" tab with companion launcher buttons

     Click detection: skin buttons are Style_Checkbox, so every real click
     toggles bChecked. We poll Checked (throttled) and treat ANY transition
     as one user click - no synthetic input during interaction. The only
     synthetic event is a cosmetic un-latch deferred >=350ms and gated on
     MouseOver()==false, when no real click can be in progress (sending it
     immediately can land mid-click and wedge EQ's mouse capture).

     Missing-control detection: on this MQ build, Window.Child() for an
     absent name can return an object whose ToString is non-nil but whose
     members are nil. Existence is judged by a pcall'd member read only.

     Status readouts are EditBoxes because this MQ build's Window.SetText
     method only supports EditBoxes.

     Service contract: init(deps) with the main_loop deps table; tick(now)
     from the main loop only (never from ImGui render). No ImGui calls, no
     mq.delay. Everything degrades to a no-op when the skin isn't loaded or
     the toggle uiState.nativeMerchantStrip is off.
]]

local mq = require('mq')
local registry = require('itemui.core.registry')

local M = {}

local d -- main_loop deps table, set by init()

-- Control names: must match the uifiles/coopt window XMLs
local MERCHANT_WND   = 'MerchantWnd'
local BTN_AUTOSELL   = 'Coopt_AutoSellBtn'
local BTN_PREVIEW    = 'Coopt_PreviewBtn'
local MERCHANT_STATUS = 'Coopt_Status'

local LOOT_WND       = 'LootWnd'
local BTN_LOOT_ALL   = 'Coopt_LootAllBtn'
local LOOT_STATUS    = 'Coopt_LootStatus'

local ACTIONS_WND    = 'ActionsWindow'
-- launcher button -> action ("cmd:" issues a slash command, "lootui" toggles the
-- Loot UI window flag, otherwise a registry module id)
local ACTION_BUTTONS = {
    { name = 'Coopt_ActUiBtn',       action = 'cmd:/itemui' },
    { name = 'Coopt_ActBankBtn',     action = 'bank' },
    { name = 'Coopt_ActAugBtn',      action = 'augments' },
    { name = 'Coopt_ActUtilBtn',     action = 'augmentUtility' },
    { name = 'Coopt_ActRerollBtn',   action = 'reroll' },
    { name = 'Coopt_ActAABtn',       action = 'aa' },
    { name = 'Coopt_ActLootBtn',     action = 'lootui' },
    { name = 'Coopt_ActSettingsBtn', action = 'config' },
}

local POLL_INTERVAL_MS   = 100
local PROBE_INTERVAL_MS  = 2000
local STATUS_INTERVAL_MS = 500
local HINT_MS            = 3000
local STATUS_MAX_CHARS   = 60
local UNLATCH_SETTLE_MS  = 350   -- min age of a click before the cosmetic un-latch
local UNLATCH_ECHO_MS    = 1000  -- window to swallow our own un-latch transition

local lastPollAt = 0

-- Per-window surface state, created lazily.
local surfaces = {}

local function surf(wnd)
    local s = surfaces[wnd]
    if not s then
        s = {
            wasOpen = false, available = false, justOpened = false,
            lastProbeAt = 0, btn = {},
            lastStatusText = nil, statusBroken = false, lastStatusAt = 0,
            hintText = nil, hintUntil = 0,
        }
        surfaces[wnd] = s
    end
    return s
end

local function windowOpen(wnd)
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window(wnd)
    return (w and w() ~= nil and w.Open and w.Open()) or false
end

local function child(wnd, name)
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window(wnd)
    if not w or w() == nil then return nil end
    return w.Child and w.Child(name) or nil
end

-- Checked state as a real boolean, or nil when the control is absent/invalid.
local function readChecked(wnd, name)
    local c = child(wnd, name)
    if not c then return nil end
    local ok, checked = pcall(function() return c.Checked() end)
    if not ok or type(checked) ~= 'boolean' then return nil end
    return checked
end

-- True exactly once per real user click (checkbox toggled in either direction).
-- Also runs the deferred cosmetic un-latch when it is provably safe.
local function consumeClick(s, wnd, name, now)
    local checked = readChecked(wnd, name)
    if checked == nil then return false end
    local b = s.btn[name]
    if not b then
        b = { last = checked }
        s.btn[name] = b
        -- Already latched at first sight (window reopened mid-run, or our state was
        -- reset while the button was pressed): stale latch, not a click — schedule
        -- the cosmetic un-latch so it doesn't stay visually pushed in.
        if checked then b.unlatchAt = now + UNLATCH_SETTLE_MS end
        return false
    end
    if checked == b.last then
        if checked and b.unlatchAt and now >= b.unlatchAt then
            local c = child(wnd, name)
            local okOver, over = pcall(function() return c.MouseOver() end)
            if okOver and over == false then
                mq.cmdf('/notify %s %s leftmouseup', wnd, name)
                b.expectSyntheticUntil = now + UNLATCH_ECHO_MS
                b.unlatchAt = nil
            end
        end
        return false
    end
    b.last = checked
    if now < (b.expectSyntheticUntil or 0) then
        b.expectSyntheticUntil = 0 -- our own un-latch echoing back; not a click
        b.unlatchAt = nil
        return false
    end
    b.unlatchAt = checked and (now + UNLATCH_SETTLE_MS) or nil
    return true
end

local function setStatus(s, wnd, name, text)
    if s.statusBroken then return end
    if #text > STATUS_MAX_CHARS then text = text:sub(1, STATUS_MAX_CHARS - 3) .. "..." end
    if text == s.lastStatusText then return end
    local c = child(wnd, name)
    if not c then return end
    local ok = pcall(function() c.SetText(text)() end)
    if not ok then s.statusBroken = true; return end
    s.lastStatusText = text
end

local function hint(s, wnd, name, text, now)
    s.hintText = text
    s.hintUntil = now + HINT_MS
    setStatus(s, wnd, name, text)
end

-- Open/close + skin-presence bookkeeping shared by all surfaces.
-- Returns false when the surface is closed or its controls are absent.
local function refreshSurface(s, wnd, probeButton, now)
    if not windowOpen(wnd) then
        s.wasOpen = false
        s.available = false
        s.justOpened = false
        s.lastStatusText = nil
        s.btn = {}
        return false
    end
    s.justOpened = not s.wasOpen
    if s.justOpened or (now - s.lastProbeAt) >= PROBE_INTERVAL_MS then
        s.lastProbeAt = now
        local wasAvailable = s.available
        s.available = readChecked(wnd, probeButton) ~= nil
        if s.justOpened or (s.available and not wasAvailable) then
            s.lastStatusText = nil
            s.statusBroken = false
            s.btn = {}
        end
    end
    s.wasOpen = true
    return s.available
end

local function sellBusy()
    local mb = d.macroBridge
    if mb and mb.isSellMacroRunning and mb.isSellMacroRunning() then return true end
    local sb = d.sellBatch
    if sb and sb.isRunning and sb.isRunning() then return true end
    return false
end

local function lootBusy()
    local mb = d.macroBridge
    return (mb and mb.isLootMacroRunning and mb.isLootMacroRunning()) or false
end

---------------------------------------------------------------------------
-- Merchant surface
---------------------------------------------------------------------------

local function merchantSummary()
    local items = d.sellItems
    if not items or #items == 0 then return "CoOpt ready" end
    local keepCount, sellCount, protectCount = 0, 0, 0
    for _, it in ipairs(items) do
        if it.inKeep then keepCount = keepCount + 1 end
        if it.willSell then sellCount = sellCount + 1 end
        if it.isProtected then protectCount = protectCount + 1 end
    end
    return string.format("Sell %d | Keep %d | Prot %d", sellCount, keepCount, protectCount)
end

local function merchantStatus(s, now)
    if (now - s.lastStatusAt) < STATUS_INTERVAL_MS then return end
    s.lastStatusAt = now
    if s.hintText and now < s.hintUntil then return end
    s.hintText = nil
    local mb = d.macroBridge
    if mb and mb.isSellMacroRunning and mb.isSellMacroRunning() then
        local prog = (mb.getSellProgress and mb.getSellProgress()) or {}
        if (prog.total or 0) > 0 then
            setStatus(s, MERCHANT_WND, MERCHANT_STATUS, string.format("Selling %d/%d", prog.current or 0, prog.total or 0))
        else
            setStatus(s, MERCHANT_WND, MERCHANT_STATUS, "Selling...")
        end
        return
    end
    local sb = d.sellBatch
    if sb and sb.isRunning and sb.isRunning() then
        setStatus(s, MERCHANT_WND, MERCHANT_STATUS, "Selling...")
        return
    end
    setStatus(s, MERCHANT_WND, MERCHANT_STATUS, merchantSummary())
end

local function tickMerchant(now)
    local s = surf(MERCHANT_WND)
    if not refreshSurface(s, MERCHANT_WND, BTN_AUTOSELL, now) then return end

    if consumeClick(s, MERCHANT_WND, BTN_AUTOSELL, now) then
        if sellBusy() then
            hint(s, MERCHANT_WND, MERCHANT_STATUS, "Already selling", now)
        else
            d.uiState.autoSellRequested = true
            hint(s, MERCHANT_WND, MERCHANT_STATUS, "Starting sell...", now)
        end
    end
    if consumeClick(s, MERCHANT_WND, BTN_PREVIEW, now) then
        -- The preview modal renders inside the CoOpt sell view, so show the
        -- UI and freshen the sell list, then let the view open the popup.
        if d.getShouldDraw and not d.getShouldDraw() then
            if d.setShouldDraw then d.setShouldDraw(true) end
            d.uiState.userClosedViaKeybind = false
        end
        if d.maybeScanSellItems then d.maybeScanSellItems(true) end
        d.uiState.nativePreviewRequested = true
        hint(s, MERCHANT_WND, MERCHANT_STATUS, "Opening preview...", now)
    end

    merchantStatus(s, now)
end

---------------------------------------------------------------------------
-- Loot surface
---------------------------------------------------------------------------

-- Mirrors main_window's loot callbacks (Loot UI open flags + macro run), with one
-- addition: the open corpse window is CLOSED first so the loot macro starts from
-- its own clean state machine (target/open/loot per corpse). Launching it over an
-- already-open corpse window confused the run and fragmented the loot session.
local function tryStartLoot(s, now, quiet)
    if lootBusy() then
        if not quiet then hint(s, LOOT_WND, LOOT_STATUS, "Already looting", now) end
        return
    end
    if sellBusy() then
        if not quiet then hint(s, LOOT_WND, LOOT_STATUS, "Sell in progress", now) end
        return
    end
    hint(s, LOOT_WND, LOOT_STATUS, "Looting all...", now)
    mq.cmdf('/notify %s DoneButton leftmouseup', LOOT_WND)
    local uiState = d.uiState
    if not uiState.suppressWhenLootMac then
        uiState.lootUIOpen = true
        uiState.lootRunFinished = false
        if d.recordCompanionWindowOpened then d.recordCompanionWindowOpened("loot") end
    end
    mq.cmd('/macro loot')
end

local function lootStatus(s, now)
    if (now - s.lastStatusAt) < STATUS_INTERVAL_MS then return end
    s.lastStatusAt = now
    if s.hintText and now < s.hintUntil then return end
    s.hintText = nil
    setStatus(s, LOOT_WND, LOOT_STATUS, lootBusy() and "Looting..." or "CoOpt")
end

local function tickLoot(now)
    local s = surf(LOOT_WND)
    if not refreshSurface(s, LOOT_WND, BTN_LOOT_ALL, now) then return end

    -- Optional: a corpse window opened by the USER starts a full rules-based
    -- loot run. The loot macro's own window churn is excluded by lootBusy().
    if s.justOpened and d.uiState.nativeAutoLootOnCorpse == true and not lootBusy() and not sellBusy() then
        tryStartLoot(s, now, true)
    end

    if consumeClick(s, LOOT_WND, BTN_LOOT_ALL, now) then tryStartLoot(s, now, false) end

    lootStatus(s, now)
end

---------------------------------------------------------------------------
-- Actions surface (companion launchers; no status line)
---------------------------------------------------------------------------

local function tickActions(now)
    local s = surf(ACTIONS_WND)
    if not refreshSurface(s, ACTIONS_WND, ACTION_BUTTONS[1].name, now) then return end
    for _, spec in ipairs(ACTION_BUTTONS) do
        if consumeClick(s, ACTIONS_WND, spec.name, now) then
            local cmd = spec.action:match('^cmd:(.+)$')
            if cmd then
                mq.cmd(cmd)
            elseif spec.action == 'lootui' then
                local uiState = d.uiState
                uiState.lootUIOpen = not uiState.lootUIOpen
                if uiState.lootUIOpen and d.recordCompanionWindowOpened then
                    d.recordCompanionWindowOpened("loot")
                end
            else
                registry.toggleWindow(spec.action)
            end
        end
    end
end

---------------------------------------------------------------------------

function M.init(deps)
    d = deps
end

function M.tick(now)
    if not d or not d.uiState then return end
    if d.uiState.nativeMerchantStrip == false then return end
    if (now - lastPollAt) < POLL_INTERVAL_MS then return end
    lastPollAt = now
    tickMerchant(now)
    tickLoot(now)
    tickActions(now)
end

return M
