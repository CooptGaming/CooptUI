--[[ native_bridge.lua: drives CoOpt controls that the "coopt" UI skin adds to
     native EQ windows (uifiles\coopt). v1 surface: the MerchantWnd sell strip.

     Click detection: skin buttons are Style_Checkbox, so every real click
     toggles bChecked. We poll Checked each tick and treat ANY transition as
     one user click - no synthetic input is ever sent during interaction.
     (v1 unlatched by sending /notify leftmouseup immediately; at main-loop
     tick rate that synthetic click can land while the user's real mouse
     button is still held down, wedging EQ's mouse capture on the button so
     all later clicks re-route to it.) The only synthetic click we send is a
     cosmetic un-latch, deferred >=350ms after the click and gated on
     MouseOver()==false - a real click cannot be in progress on a control
     the cursor is not over, so the capture race cannot occur.

     Missing-control detection: on this MQ build, Window.Child() for an
     absent name can return an object whose ToString is non-nil but whose
     members are nil (proven by the POC crash after /loadskin). Existence is
     therefore judged by a pcall'd member read, never by Child()/ToString.

     The status readout is an EditBox because this MQ build's Window.SetText
     method only supports EditBoxes.

     Service contract: init(deps) with the main_loop deps table; tick(now)
     from the main loop only (never from ImGui render). No ImGui calls, no
     mq.delay. Everything degrades to a no-op when the skin isn't loaded or
     the toggle uiState.nativeMerchantStrip is off.
]]

local mq = require('mq')

local M = {}

local d -- main_loop deps table, set by init()

-- Control names: must match uifiles/coopt/EQUI_MerchantWnd.xml
local WND          = 'MerchantWnd'
local BTN_AUTOSELL = 'Coopt_AutoSellBtn'
local BTN_PREVIEW  = 'Coopt_PreviewBtn'
local BTN_KEEP     = 'Coopt_KeepBtn'
local BTN_JUNK     = 'Coopt_JunkBtn'
local STATUS       = 'Coopt_Status'

local PROBE_INTERVAL_MS   = 2000
local STATUS_INTERVAL_MS  = 500
local HINT_MS             = 3000
local STATUS_MAX_CHARS    = 60
local UNLATCH_SETTLE_MS   = 350   -- min age of a click before the cosmetic un-latch
local UNLATCH_ECHO_MS     = 1000  -- window to swallow our own un-latch transition

local state = {
    available = false,    -- skin controls present in the open merchant window
    lastProbeAt = 0,
    lastStatusAt = 0,
    lastStatusText = nil,
    hintText = nil,
    hintUntil = 0,
    textBroken = false,   -- SetText failed; retried on next merchant open
    wasOpen = false,
    btn = {},             -- name -> { last, unlatchAt, expectSyntheticUntil }
}

local function merchantOpen()
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window(WND)
    return (w and w() ~= nil and w.Open and w.Open()) or false
end

local function child(name)
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window(WND)
    if not w or w() == nil then return nil end
    return w.Child and w.Child(name) or nil
end

-- Checked state as a real boolean, or nil when the control is absent/invalid.
local function readChecked(name)
    local c = child(name)
    if not c then return nil end
    local ok, checked = pcall(function() return c.Checked() end)
    if not ok or type(checked) ~= 'boolean' then return nil end
    return checked
end

-- True exactly once per real user click (checkbox toggled in either direction).
-- Also runs the deferred cosmetic un-latch when it is provably safe.
local function consumeClick(name, now)
    local checked = readChecked(name)
    if checked == nil then return false end
    local b = state.btn[name]
    if not b then
        state.btn[name] = { last = checked }
        return false
    end
    if checked == b.last then
        -- Steady state: maybe un-latch a stale pressed look, cursor-off only.
        if checked and b.unlatchAt and now >= b.unlatchAt then
            local c = child(name)
            local okOver, over = pcall(function() return c.MouseOver() end)
            if okOver and over == false then
                mq.cmdf('/notify %s %s leftmouseup', WND, name)
                b.expectSyntheticUntil = now + UNLATCH_ECHO_MS
                b.unlatchAt = nil
            end
        end
        return false
    end
    -- Transition observed.
    b.last = checked
    if now < (b.expectSyntheticUntil or 0) then
        b.expectSyntheticUntil = 0 -- our own un-latch echoing back; not a click
        b.unlatchAt = nil
        return false
    end
    b.unlatchAt = checked and (now + UNLATCH_SETTLE_MS) or nil
    return true
end

local function setStatus(text)
    if state.textBroken then return end
    if #text > STATUS_MAX_CHARS then text = text:sub(1, STATUS_MAX_CHARS - 3) .. "..." end
    if text == state.lastStatusText then return end
    local c = child(STATUS)
    if not c then return end
    local ok = pcall(function() c.SetText(text)() end)
    if not ok then state.textBroken = true; return end
    state.lastStatusText = text
end

local function hint(text, now)
    state.hintText = text
    state.hintUntil = now + HINT_MS
    setStatus(text)
end

-- The player's selected sell-side item, resolved against the scanned sell list.
-- Returns nil for no selection or a merchant-side (buy list) selection.
local function selectedSellItem()
    local m = mq.TLO and mq.TLO.Merchant
    local sel = m and m.SelectedItem
    if not sel or sel() == nil then return nil end
    local okName, name = pcall(function() return sel.Name() end)
    if not okName or not name or name == "" then return nil end
    local items = d.sellItems
    if not items then return nil end
    for _, it in ipairs(items) do
        if it.name == name then return it end
    end
    return nil
end

local function sellBusy()
    local mb = d.macroBridge
    if mb and mb.isSellMacroRunning and mb.isSellMacroRunning() then return true end
    local sb = d.sellBatch
    if sb and sb.isRunning and sb.isRunning() then return true end
    return false
end

local function onAutoSell(now)
    if sellBusy() then hint("Already selling", now); return end
    d.uiState.autoSellRequested = true
    hint("Starting sell...", now)
end

local function onPreview(now)
    -- The preview modal renders inside the CoOpt sell view, so make sure the
    -- UI is shown and the sell list is fresh, then let the view open the popup.
    if d.getShouldDraw and not d.getShouldDraw() then
        if d.setShouldDraw then d.setShouldDraw(true) end
        d.uiState.userClosedViaKeybind = false
    end
    if d.maybeScanSellItems then d.maybeScanSellItems(true) end
    d.uiState.nativePreviewRequested = true
    hint("Opening preview...", now)
end

-- Mirrors the sell view's per-row Keep/Junk toggle semantics.
local function onKeep(now)
    local it = selectedSellItem()
    if not it then hint("Select one of your items first", now); return end
    if not d.applySellListChange then return end
    if it.inKeep then
        d.applySellListChange(it.name, false, it.inJunk and true or false)
        hint("Keep removed: " .. it.name, now)
    else
        d.applySellListChange(it.name, true, false)
        hint("Keep: " .. it.name, now)
    end
end

local function onJunk(now)
    local it = selectedSellItem()
    if not it then hint("Select one of your items first", now); return end
    if not d.applySellListChange then return end
    if it.inJunk then
        d.applySellListChange(it.name, it.inKeep and true or false, false)
        hint("Junk removed: " .. it.name, now)
    else
        d.applySellListChange(it.name, false, true)
        hint("Junk: " .. it.name, now)
    end
end

-- Idle summary: same counting rules as the sell view's summary line.
local function summaryText()
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

local function updateStatus(now)
    if (now - state.lastStatusAt) < STATUS_INTERVAL_MS then return end
    state.lastStatusAt = now
    if state.hintText and now < state.hintUntil then return end
    state.hintText = nil
    local mb = d.macroBridge
    if mb and mb.isSellMacroRunning and mb.isSellMacroRunning() then
        local prog = (mb.getSellProgress and mb.getSellProgress()) or {}
        if (prog.total or 0) > 0 then
            setStatus(string.format("Selling %d/%d", prog.current or 0, prog.total or 0))
        else
            setStatus("Selling...")
        end
        return
    end
    local sb = d.sellBatch
    if sb and sb.isRunning and sb.isRunning() then
        setStatus("Selling...")
        return
    end
    setStatus(summaryText())
end

function M.init(deps)
    d = deps
end

function M.tick(now)
    if not d or not d.uiState then return end
    if d.uiState.nativeMerchantStrip == false then return end
    if not merchantOpen() then
        state.wasOpen = false
        state.available = false
        state.lastStatusText = nil
        state.btn = {}
        return
    end
    -- Probe for the skin's controls on open and periodically (covers /loadskin
    -- while a merchant is up). Existence = pcall'd member read, never ToString.
    if not state.wasOpen or (now - state.lastProbeAt) >= PROBE_INTERVAL_MS then
        state.lastProbeAt = now
        local wasAvailable = state.available
        state.available = readChecked(BTN_AUTOSELL) ~= nil
        if not state.wasOpen or (state.available and not wasAvailable) then
            state.lastStatusText = nil
            state.textBroken = false
            state.btn = {}
        end
        state.wasOpen = true
    end
    if not state.available then return end

    if consumeClick(BTN_AUTOSELL, now) then onAutoSell(now) end
    if consumeClick(BTN_PREVIEW, now) then onPreview(now) end
    if consumeClick(BTN_KEEP, now) then onKeep(now) end
    if consumeClick(BTN_JUNK, now) then onJunk(now) end

    updateStatus(now)
end

return M
