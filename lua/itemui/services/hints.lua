--[[
    hints.lua — the five contextual first-run hints (mockup 14c).

    "The bar itself does the teaching, one hint at a time, only when the thing is
    relevant": each hint fires on its own FIRST occurrence, is dismissed once, and never
    returns — `/itemui hints` (or the popover's "Show me all hints") replays the full set.

    Contract (dock_state rules): main-loop service. tick(now) reads only the dock_state
    snapshot and cached uiState — no TLO, no ImGui. Rendering belongs to dock_top, which
    reads M.getActive(); dismissal comes back through the dock action queue so the INI
    write happens here, never inside a frame.

    Persistence: coopui_onboarding.ini [Hints] hint_<id>=TRUE — the same char-scoped file
    the welcome flow already owns.
]]

local config = require('itemui.config')
local dockState = require('itemui.services.dock_state')

local M = {}

local d                     -- main-loop deps (init)

local HINTS_INI = "coopui_onboarding.ini"
local HINTS_SECTION = "Hints"

-- Order here is the replay order. anchor = the dock_top slot the popover points at, and it
-- MUST be a live id in dock_top's CELL_ORDER: renderHint does `M.slots[anchor] or {}` and
-- then `slot.x or barX`, so an unknown anchor silently anchors to the bar's left edge instead
-- of failing. Both loot hints said "loot" -- the segment the phase-13 lane replaced -- so the
-- two moments that matter most pointed at the CoOpt cell while describing the lane.
-- test_hints.lua now fails on any anchor that is not a real segment.
M.HINTS = {
    { id = "merchant", anchor = "sell",
      title = "This is what your rules would sell",
      body = "Hover the sell slot any time to see the breakdown by reason. Nothing sells until you press Auto Sell at a merchant." },
    { id = "loot_run", anchor = "lane",
      title = "A loot run, live",
      body = "Corpse progress, items taken and a Stop button live here while loot.mac runs. The Review button opens the full recap." },
    { id = "mythical", anchor = "lane",
      title = "A mythical needs a decision",
      body = "Take or Pass right from the bar. The Loot window shows the item's stats if you want a closer look first." },
    { id = "full_bag", anchor = "bags",
      title = "Bags are full",
      body = "The bags slot goes amber past 90%. Auto Sell at a merchant clears the junk your rules already agreed to." },
    { id = "rule_edit", anchor = "sell",
      title = "Rules explain themselves",
      body = "Every change updates the sell offer on the bar immediately - the count and value are your rules' live dry run." },
}

-- Session state. seen[] mirrors the INI once loaded; nil until then.
local seen = nil
local active = nil          -- { id, title, body, anchor, replay = bool }
local replayQueue = nil     -- list of hint ids when "show all" is running
local ruleEditSeen = false  -- set by noteRuleEdit (called from the filters UI)
local prev = {}             -- previous-tick snapshot values for edge detection

function M.init(deps)
    d = deps
end

local function loadSeen()
    if seen then return end
    seen = {}
    for _, h in ipairs(M.HINTS) do
        seen[h.id] = config.readINIValue(HINTS_INI, HINTS_SECTION, "hint_" .. h.id, "FALSE") == "TRUE"
    end
end

local function hintById(id)
    for _, h in ipairs(M.HINTS) do
        if h.id == id then return h end
    end
    return nil
end

--- The hint the bar should draw right now, or nil. Read-only for the render path.
function M.getActive()
    return active
end

--- Called from the filters UI whenever a rule is added or removed.
function M.noteRuleEdit()
    ruleEditSeen = true
end

--- [Got it]: mark the active hint seen (INI) and advance the replay queue, if one runs.
function M.dismissActive()
    if not active then return end
    loadSeen()
    seen[active.id] = true
    config.writeINIValue(HINTS_INI, HINTS_SECTION, "hint_" .. active.id, "TRUE")
    active = nil
    if replayQueue and #replayQueue > 0 then
        local nextId = table.remove(replayQueue, 1)
        local h = hintById(nextId)
        if h then active = { id = h.id, title = h.title, body = h.body, anchor = h.anchor, replay = true } end
    else
        replayQueue = nil
    end
end

--- /itemui hints and "Show me all hints": clear the seen flags and walk the whole set
--- immediately, in declaration order, one [Got it] at a time.
function M.replayAll()
    loadSeen()
    replayQueue = {}
    for _, h in ipairs(M.HINTS) do
        seen[h.id] = false
        config.writeINIValue(HINTS_INI, HINTS_SECTION, "hint_" .. h.id, "FALSE")
        replayQueue[#replayQueue + 1] = h.id
    end
    local first = table.remove(replayQueue, 1)
    local h = hintById(first)
    active = h and { id = h.id, title = h.title, body = h.body, anchor = h.anchor, replay = true } or nil
end

--- Edge detection against the dock snapshot. One hint at a time; a new trigger while one
--- is up simply waits for its own next occurrence (they are all recurring conditions).
function M.tick(now)
    local lc = d and d.layoutConfig
    if not lc or tostring(lc.UIMode or "classic") ~= "bars" then return end
    loadSeen()

    local s = dockState.get()
    local fire = nil
    if s.merchantOpen and not prev.merchantOpen and not seen.merchant then fire = "merchant" end
    if not fire and s.lootRunning and not prev.lootRunning and not seen.loot_run then fire = "loot_run" end
    if not fire and s.lootState == "decision" and prev.lootState ~= "decision" and not seen.mythical then fire = "mythical" end
    if not fire and s.bagFree == 0 and prev.bagFree ~= 0 and (s.bagItems or 0) > 0 and not seen.full_bag then fire = "full_bag" end
    if not fire and ruleEditSeen and not seen.rule_edit then fire = "rule_edit" end

    prev.merchantOpen, prev.lootRunning = s.merchantOpen, s.lootRunning
    prev.lootState, prev.bagFree = s.lootState, s.bagFree

    if fire and not active then
        local h = hintById(fire)
        if h then active = { id = h.id, title = h.title, body = h.body, anchor = h.anchor } end
    end
end

--- Tests only.
function M._reset()
    seen, active, replayQueue, ruleEditSeen, prev = nil, nil, nil, false, {}
end

return M
