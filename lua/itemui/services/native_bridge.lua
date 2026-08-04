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
local coopuiPlugin = require('itemui.utils.coopui_plugin')
local aaTransfer = require('itemui.services.aa_transfer')

local M = {}

local d -- main_loop deps table, set by init()

-- Plugin window API (direct SetCheck / SetWindowText - state writes, no
-- synthetic input, so no capture wedge and no echo to swallow). One-shot
-- capability detection per session, same pattern as the plugin loader.
local pwCache
local function plugWindow()
    if pwCache ~= nil then return pwCache or nil end
    local w = coopuiPlugin.getWindow()
    pwCache = (w and type(w.setChecked) == 'function' and type(w.setText) == 'function') and w or false
    return pwCache or nil
end

-- Control names: must match the uifiles/coopt window XMLs
local MERCHANT_WND   = 'MerchantWnd'
local BTN_AUTOSELL   = 'Coopt_AutoSellBtn'
local BTN_PREVIEW    = 'Coopt_PreviewBtn'
local MERCHANT_STATUS = 'Coopt_Status'

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
    { name = 'Coopt_ActEffectsBtn',  action = 'effects' },
    { name = 'Coopt_ActClickiesBtn', action = 'favorites' },
    { name = 'Coopt_ActSettingsBtn', action = 'config' },
}

-- Native Command Center (repurposed Tip of the Day window; open with /itemui center)
local CMD_WND   = 'TipWindow'
local CC_STATUS = 'Coopt_CCStatus'
local CC_BUTTONS = {
    { name = 'Coopt_CCLootAllBtn',  action = 'lootall' },
    { name = 'Coopt_CCStopLootBtn', action = 'stoploot' },
    { name = 'Coopt_CCSellBtn',     action = 'autosell' },
    -- The registry Scripts companion, NOT the standalone sidecar. The sidecar is kept for
    -- exactly one audience -- people running it with itemui down -- and that audience never
    -- sees this panel, because this panel is ticked by itemui. Offering the sidecar here
    -- promoted the lesser window (3 columns, read-only, no turn-in) from inside the thing
    -- it is a fallback for. As a registry id the button also inherits the open-state latch
    -- every other launcher on this panel has (ccOpenState's generic branch).
    { name = 'Coopt_CCTrackerBtn',  action = 'scripttracker' },
    { name = 'Coopt_CCUiBtn',       action = 'cmd:/itemui' },
    { name = 'Coopt_CCLootUiBtn',   action = 'lootui' },
    { name = 'Coopt_CCEquipBtn',    action = 'equipment' },
    { name = 'Coopt_CCBankBtn',     action = 'bank' },
    { name = 'Coopt_CCAugBtn',      action = 'augments' },
    { name = 'Coopt_CCMythBtn',     action = 'mythicals' },
    { name = 'Coopt_CCUtilBtn',     action = 'augmentUtility' },
    { name = 'Coopt_CCRerollBtn',   action = 'reroll' },
    { name = 'Coopt_CCAABtn',       action = 'aa' },
    { name = 'Coopt_CCEffectsBtn',  action = 'effects' },
    { name = 'Coopt_CCClickiesBtn', action = 'favorites' },
    { name = 'Coopt_CCSettingsBtn', action = 'config' },
}

local ITEMDISPLAY_WND = 'ItemDisplayWindow'

-- Native AA window: CoOpt Export/Import buttons + status line (coopt skin
-- repurposes the dead Monster Abilities corner). Logic lives in aa_transfer.
local AA_WND       = 'AAWindow'
local BTN_AAEXPORT = 'Coopt_AAExportBtn'
local BTN_AAIMPORT = 'Coopt_AAImportBtn'
local BTN_AAFILE   = 'Coopt_AAFileBtn'
local AA_STATUS    = 'Coopt_AAStatus'

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
        -- Deferred un-latch: the settle delay + MouseOver gate are LOAD-BEARING
        -- even with the plugin. Touching bChecked inside the click window makes
        -- the release re-toggle it — a phantom second transition that toggled
        -- the just-opened window closed (seen on the native Command Center).
        -- The plugin only upgrades the MECHANISM: a silent state write instead
        -- of a synthetic click, so no capture wedge and no echo to swallow.
        if checked and b.unlatchAt and now >= b.unlatchAt then
            local c = child(wnd, name)
            local okOver, over = pcall(function() return c.MouseOver() end)
            if okOver and over == false then
                local pw = plugWindow()
                if pw and pw.setChecked(wnd, name, false) then
                    b.last = false
                    b.unlatchAt = nil
                else
                    mq.cmdf('/notify %s %s leftmouseup', wnd, name)
                    b.expectSyntheticUntil = now + UNLATCH_ECHO_MS
                    b.unlatchAt = nil
                end
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
    local pw = plugWindow()
    if pw then
        -- Plugin SetWindowText works on labels too, not just EditBoxes.
        if pw.setText(wnd, name, text) then s.lastStatusText = text end
        return
    end
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

--- Stateful button captions (mockup 8a/8b: "labels carry state"). Plugin-only — the TLO
--- SetText path is EditBox-only, so without the plugin the skin's static XML labels stand,
--- which is the correct degraded behaviour. Deduped per control like setStatus.
local function setBtnLabel(s, wnd, name, text)
    local pw = plugWindow()
    if not pw then return end
    s.btnLabels = s.btnLabels or {}
    if s.btnLabels[name] == text then return end
    if pw.setText(wnd, name, text) then s.btnLabels[name] = text end
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
            s.btnLabels = nil    -- fresh window instance: re-write stateful captions
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

-- Shared launcher/process executor for all native button surfaces. The optional
-- s/wnd/statusName route feedback into that surface's status EditBox.
local function runAction(action, s, wnd, statusName, now)
    local cmd = action:match('^cmd:(.+)$')
    if cmd then mq.cmd(cmd) return end
    if action == 'lootui' then
        local uiState = d.uiState
        uiState.lootUIOpen = not uiState.lootUIOpen
        if uiState.lootUIOpen and d.recordCompanionWindowOpened then d.recordCompanionWindowOpened("loot") end
    elseif action == 'lootall' then
        -- While a loot run is live AND the caption has actually been rewritten to
        -- "Looting... stop" (plugin present, 500ms label clock has run), the click IS the
        -- stop. The caption gate matters twice over: pluginless the static XML still says
        -- "Loot All" — a click must not silently kill a run the label promises to start —
        -- and even with the plugin, an impatient double-click lands before the relabel and
        -- must be absorbed, not obeyed.
        if lootBusy() then
            if s and s.btnLabels and s.btnLabels['Coopt_CCLootAllBtn'] == "Looting... stop" then
                mq.cmd('/endmacro')
                hint(s, wnd, statusName, "Loot stopped.", now)
            elseif s then
                hint(s, wnd, statusName, "Busy - macro already running", now)
            end
            return
        end
        if sellBusy() then
            if s then hint(s, wnd, statusName, "Busy - macro already running", now) end
            return
        end
        local uiState = d.uiState
        if not uiState.suppressWhenLootMac then
            uiState.lootUIOpen = true
            uiState.lootRunFinished = false
            if d.recordCompanionWindowOpened then d.recordCompanionWindowOpened("loot") end
        end
        mq.cmd('/macro loot')
    elseif action == 'stoploot' then
        if lootBusy() then
            mq.cmd('/endmacro')
        elseif s then
            hint(s, wnd, statusName, "No loot macro running", now)
        end
    elseif action == 'autosell' then
        if not windowOpen(MERCHANT_WND) then
            if s then hint(s, wnd, statusName, "Open a merchant first", now) end
            return
        end
        if sellBusy() or lootBusy() then
            if s then hint(s, wnd, statusName, "Busy - macro already running", now) end
            return
        end
        d.uiState.autoSellRequested = true
        if s then hint(s, wnd, statusName, "Starting sell...", now) end
    else
        registry.toggleWindow(action)
    end
end

---------------------------------------------------------------------------
-- Merchant surface
---------------------------------------------------------------------------

local function merchantCounts()
    local items = d.sellItems
    local keepCount, sellCount, protectCount, sellCopper = 0, 0, 0, 0
    for _, it in ipairs(items or {}) do
        if it.inKeep then keepCount = keepCount + 1 end
        if it.willSell then
            sellCount = sellCount + 1
            sellCopper = sellCopper + (tonumber(it.totalValue) or 0)
        end
        if it.isProtected then protectCount = protectCount + 1 end
    end
    return sellCount, keepCount, protectCount, math.floor(sellCopper / 1000)
end

local function merchantSummary()
    if not d.sellItems or #d.sellItems == 0 then return "CoOpt ready" end
    -- 8b idle state: the strip states the offer before you click.
    local sellCount, _, protectCount, plat = merchantCounts()
    if sellCount == 0 then
        return string.format("Nothing to sell | %d protected", protectCount)
    end
    return string.format("%dp | %d protected by your rules", plat, protectCount)
end

--- 8b done state: the result sticks (for a while) after a macro sell finishes — the
--- failure count is the one thing the old strip never told you.
local function merchantDoneLine(now)
    local sm = d.sellMacState
    if not sm or not sm.finishedAt or sm.finishedAt == 0 then return nil end
    if (now - sm.finishedAt) > 30000 then return nil end
    local sold = d.uiState.sellRunSoldItems
    if type(sold) ~= "table" or #sold == 0 then return nil end
    local copper = 0
    for _, it in ipairs(sold) do copper = copper + (tonumber(it.value) or 0) end
    local line = string.format("Sold %d for %dp", #sold, math.floor(copper / 1000))
    if (sm.failedCount or 0) > 0 then
        line = line .. string.format(" | %d failed", sm.failedCount)
    end
    return line
end

local function merchantStatus(s, now)
    if (now - s.lastStatusAt) < STATUS_INTERVAL_MS then return end
    s.lastStatusAt = now

    -- 8b button captions ride the status clock (plugin setText; static XML otherwise).
    local mb = d.macroBridge
    local macroSelling = mb and mb.isSellMacroRunning and mb.isSellMacroRunning()
    local sb = d.sellBatch
    local batchSelling = sb and sb.isRunning and sb.isRunning()
    if macroSelling then
        setBtnLabel(s, MERCHANT_WND, BTN_AUTOSELL, "Stop")
    elseif batchSelling then
        setBtnLabel(s, MERCHANT_WND, BTN_AUTOSELL, "Selling...")
    else
        local sellCount = merchantCounts()
        setBtnLabel(s, MERCHANT_WND, BTN_AUTOSELL,
            sellCount > 0 and string.format("Sell %d", sellCount) or "Nothing to sell")
    end

    if s.hintText and now < s.hintUntil then return end
    s.hintText = nil
    if macroSelling then
        local prog = (mb.getSellProgress and mb.getSellProgress()) or {}
        if (prog.total or 0) > 0 then
            setStatus(s, MERCHANT_WND, MERCHANT_STATUS, string.format("Selling %d/%d", prog.current or 0, prog.total or 0))
        else
            setStatus(s, MERCHANT_WND, MERCHANT_STATUS, "Selling...")
        end
        return
    end
    if batchSelling then
        setStatus(s, MERCHANT_WND, MERCHANT_STATUS, "Selling...")
        return
    end
    local done = merchantDoneLine(now)
    if done then
        setStatus(s, MERCHANT_WND, MERCHANT_STATUS, done)
        return
    end
    setStatus(s, MERCHANT_WND, MERCHANT_STATUS, merchantSummary())
end

local function tickMerchant(now)
    local s = surf(MERCHANT_WND)
    if not refreshSurface(s, MERCHANT_WND, BTN_AUTOSELL, now) then return end

    if consumeClick(s, MERCHANT_WND, BTN_AUTOSELL, now) then
        local mb = d.macroBridge
        if mb and mb.isSellMacroRunning and mb.isSellMacroRunning() then
            -- The click stops ONLY once the caption actually says Stop (8b state 3):
            -- pluginless the XML label still promises a sell, and a double-click inside
            -- the 500ms relabel window must be absorbed, not obeyed.
            if s.btnLabels and s.btnLabels[BTN_AUTOSELL] == "Stop" then
                mq.cmd('/endmacro')
                hint(s, MERCHANT_WND, MERCHANT_STATUS, "Sell stopped.", now)
            else
                hint(s, MERCHANT_WND, MERCHANT_STATUS, "Already selling", now)
            end
        elseif sellBusy() then
            -- Lua batch: no cancel exists; say so rather than pretend.
            hint(s, MERCHANT_WND, MERCHANT_STATUS, "Lua sell has no stop", now)
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
-- Actions surface (companion launchers; no status line)
---------------------------------------------------------------------------

local function tickActions(now)
    local s = surf(ACTIONS_WND)
    if not refreshSurface(s, ACTIONS_WND, ACTION_BUTTONS[1].name, now) then return end
    for _, spec in ipairs(ACTION_BUTTONS) do
        if consumeClick(s, ACTIONS_WND, spec.name, now) then
            runAction(spec.action, nil, nil, nil, now)
        end
    end
end

---------------------------------------------------------------------------
-- Command Center surface (repurposed Tip of the Day window)
---------------------------------------------------------------------------

local function ccStatusText()
    local mb = d.macroBridge
    local plugin = (mb and mb.isIPCAvailable and mb.isIPCAvailable()) and "Plugin OK" or "No plugin"
    local uiState = d.uiState
    -- 8a: doing beats naming. While something runs, the line carries its progress; idle,
    -- it carries the offer. Everything here is a cached uiState/bridge read.
    if mb and mb.isSellMacroRunning and mb.isSellMacroRunning() then
        local prog = (mb.getSellProgress and mb.getSellProgress()) or {}
        if (prog.total or 0) > 0 then
            return string.format("Selling %d/%d | %s", prog.current or 0, prog.total or 0, plugin)
        end
        return "Selling | " .. plugin
    end
    if lootBusy() then
        local cur = tonumber(uiState.lootRunCorpsesLooted) or 0
        local tot = tonumber(uiState.lootRunTotalCorpses) or 0
        if tot > 0 then
            return string.format("Looting corpse %d of %d | %s", cur, tot, plugin)
        end
        return "Looting | " .. plugin
    end
    return plugin .. " | Idle"
end

--- Which CC buttons mirror a window's open state (8a: "Open — lit = already open", the
--- panel doubles as a window list). Run controls return nil and keep click-unlatch.
local function ccOpenState(action)
    if action == 'lootui' then return d.uiState.lootUIOpen == true end
    if action == 'cmd:/itemui' then return (d.getShouldDraw and d.getShouldDraw()) == true end
    if action == 'lootall' or action == 'stoploot' or action == 'autosell' then
        return nil
    end
    return registry.isRegistered and registry.isRegistered(action) and registry.isOpen(action) or false
end

--- Reflect open windows as latched checkboxes. Plugin-only (a synthetic /notify latch
--- would wedge mouse capture). The write updates b.last in the same breath so the click
--- poller never sees our own state write as a user transition, and the cosmetic un-latch
--- is cancelled — the latch owns these buttons while their window is open.
local function ccApplyLatch(s)
    local pw = plugWindow()
    if not pw then return end
    for _, spec in ipairs(CC_BUTTONS) do
        local open = ccOpenState(spec.action)
        if open ~= nil then
            local b = s.btn[spec.name]
            if b and b.last ~= open then
                if pw.setChecked(CMD_WND, spec.name, open) then
                    b.last = open
                    b.unlatchAt = nil
                end
            elseif b and open then
                b.unlatchAt = nil
            end
        end
    end
end

--- Stateful captions for the run controls (8a): the label says what the click DOES now.
local function ccLabels(s)
    local looting = lootBusy()
    setBtnLabel(s, CMD_WND, 'Coopt_CCLootAllBtn', looting and "Looting... stop" or "Loot All")
    local sellLabel
    if sellBusy() then
        sellLabel = "Selling..."
    elseif not windowOpen(MERCHANT_WND) then
        sellLabel = "Sell-no merchant"
    else
        sellLabel = "Auto Sell"
    end
    setBtnLabel(s, CMD_WND, 'Coopt_CCSellBtn', sellLabel)
end

local function tickCommandCenter(now)
    local s = surf(CMD_WND)
    if not refreshSurface(s, CMD_WND, CC_BUTTONS[1].name, now) then return end
    for _, spec in ipairs(CC_BUTTONS) do
        if consumeClick(s, CMD_WND, spec.name, now) then
            runAction(spec.action, s, CMD_WND, CC_STATUS, now)
        end
    end
    if (now - s.lastStatusAt) >= STATUS_INTERVAL_MS then
        s.lastStatusAt = now
        ccApplyLatch(s)
        ccLabels(s)
        if not (s.hintText and now < s.hintUntil) then
            s.hintText = nil
            setStatus(s, CMD_WND, CC_STATUS, ccStatusText())
        end
    end
end

---------------------------------------------------------------------------
-- AA window surface: Export / Import (arm-then-confirm) + status line
---------------------------------------------------------------------------

local function tickAAWindow(now)
    local s = surf(AA_WND)
    if not refreshSurface(s, AA_WND, BTN_AAEXPORT, now) then return end
    if consumeClick(s, AA_WND, BTN_AAEXPORT, now) then
        aaTransfer.requestExport()
    end
    if consumeClick(s, AA_WND, BTN_AAIMPORT, now) then
        aaTransfer.armOrStartImport()
    end
    if consumeClick(s, AA_WND, BTN_AAFILE, now) then
        aaTransfer.cycleFile()
    end
    if (now - s.lastStatusAt) >= STATUS_INTERVAL_MS then
        s.lastStatusAt = now
        setStatus(s, AA_WND, AA_STATUS, aaTransfer.getStatusLine() or "CoOpt")
    end
end

---------------------------------------------------------------------------
-- Item Display surface: squash-only (the redirect lives in native_hover)
---------------------------------------------------------------------------

local function tickItemDisplay(now)
    -- After a worn-slot inspect was redirected to the CoOpt Item Display
    -- (native_hover sets nativeInspectSquashUntil), close the native inspect
    -- that the same right-click opened. Works with or without the coopt skin.
    local squashUntil = d.uiState.nativeInspectSquashUntil
    if squashUntil then
        if now > squashUntil then
            d.uiState.nativeInspectSquashUntil = nil
        elseif windowOpen(ITEMDISPLAY_WND) then
            pcall(function() mq.TLO.Window(ITEMDISPLAY_WND).DoClose() end)
            d.uiState.nativeInspectSquashUntil = nil
        end
    end
end

---------------------------------------------------------------------------

function M.init(deps)
    d = deps
end

function M.tick(now)
    if not d or not d.uiState then return end
    if (now - lastPollAt) < POLL_INTERVAL_MS then return end
    lastPollAt = now
    -- The inspect-redirect squash belongs to nativeItemDisplayReplace (checked
    -- in native_hover, which sets the flag) - it must keep working when the
    -- native strips master toggle is off or the skin isn't loaded at all.
    tickItemDisplay(now)
    if d.uiState.nativeMerchantStrip == false then return end
    tickMerchant(now)
    tickActions(now)
    tickCommandCenter(now)
    tickAAWindow(now)
end

return M
