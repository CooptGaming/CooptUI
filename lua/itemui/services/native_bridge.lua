--[[ native_bridge.lua: drives CoOpt controls that the "coopt" UI skin adds to
     native EQ windows (uifiles\coopt). v1 surface: the MerchantWnd sell strip.

     Mechanism (proven by poc/native_window): skin buttons are Style_Checkbox,
     so a user click latches bChecked; we poll Window("MerchantWnd").Child(...)
     .Checked each tick while the merchant is open, act, then unlatch with
     /notify leftmouseup. The status readout is an EditBox because this MQ
     build's Window.SetText method only supports EditBoxes.

     Service contract: init(deps) with the main_loop deps table; tick(now) from
     the main loop only (never from ImGui render). No ImGui calls, no mq.delay.
     Everything degrades to a no-op when the skin isn't loaded (controls absent)
     or the toggle uiState.nativeMerchantStrip is off.
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

local PROBE_INTERVAL_MS  = 2000
local STATUS_INTERVAL_MS = 500
local HINT_MS            = 3000
local STATUS_MAX_CHARS   = 60

local state = {
    available = false,    -- skin controls present in the open merchant window
    lastProbeAt = 0,
    lastStatusAt = 0,
    lastStatusText = nil,
    hintText = nil,
    hintUntil = 0,
    textBroken = false,   -- SetText failed once; stop trying this session
    wasOpen = false,
}

local function merchantOpen()
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window(WND)
    return (w and w() ~= nil and w.Open and w.Open()) or false
end

-- Child TLO or nil (window closed / control absent).
local function child(name)
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window(WND)
    if not w or w() == nil then return nil end
    local c = w.Child and w.Child(name)
    if not c or c() == nil then return nil end
    return c
end

-- True exactly once per user click (latch consume + unlatch).
local function consumeClick(name)
    local c = child(name)
    if not c then return false end
    local ok, checked = pcall(function() return c.Checked() end)
    if not ok or not checked then return false end
    mq.cmdf('/notify %s %s leftmouseup', WND, name)
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
    local name = sel.Name and sel.Name()
    if not name or name == "" then return nil end
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
        return
    end
    -- Probe for the skin's controls on open and periodically (covers /loadskin
    -- while a merchant is up). Absent controls = skin not loaded = no-op.
    if not state.wasOpen or (now - state.lastProbeAt) >= PROBE_INTERVAL_MS then
        state.lastProbeAt = now
        state.available = child(STATUS) ~= nil or child(BTN_AUTOSELL) ~= nil
        if not state.wasOpen then state.lastStatusText = nil end
        state.wasOpen = true
    end
    if not state.available then return end

    if consumeClick(BTN_AUTOSELL) then onAutoSell(now) end
    if consumeClick(BTN_PREVIEW) then onPreview(now) end
    if consumeClick(BTN_KEEP) then onKeep(now) end
    if consumeClick(BTN_JUNK) then onJunk(now) end

    updateStatus(now)
end

return M
