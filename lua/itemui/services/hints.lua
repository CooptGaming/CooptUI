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
local events = require('itemui.core.events')

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
      -- The pin clause rides here rather than becoming a sixth hint. Pinning was taught
      -- NOWHERE: middle-click is global across every bar cell (dock_top's universal pin) but
      -- it is only mentioned inside a popover's own header, which you cannot read until you
      -- have already discovered it. This card is the one that already has the user's
      -- attention on a popover, so the clause lands where the gesture is useful -- and five
      -- hints stays five.
      body = "Hover the sell slot any time to see the breakdown by reason - middle-click pins it open, Esc closes it. Nothing sells until you press Auto Sell at a merchant." },
    { id = "loot_run", anchor = "lane",
      title = "A loot run, live",
      -- Was: "...and a Stop button live here while loot.mac runs. The Review button opens the
      -- full recap." Both halves were STALE, not invented: the lane once carried its own Stop,
      -- and a Review button on the done mood really shipped -- it was removed at the user's
      -- request because it blocked the lane's return to idle (94cef00). The copy was written
      -- against that bar and nobody re-read it when the controls moved. That is the lesson
      -- worth keeping: inherited copy outlives its control, so a hint body is re-checked
      -- whenever the surface it teaches changes shape. Today: Stop is never in the lane --
      -- Loot All becomes its own Stop in place -- and the finished mood draws the result and
      -- holds it six seconds, with no button.
      body = "Corpse progress and items taken appear here while a run goes. Loot All becomes Stop while it runs, and the result holds here for a few seconds after." },
    { id = "mythical", anchor = "lane",
      title = "A mythical needs a decision",
      -- Named all THREE only after a field capture of the decision mood: the lane draws Take,
      -- Pass and Reroll, and this card taught two of them. Reroll is the one that needs
      -- saying, because Take and Pass are self-evident and Reroll is not (it takes the item
      -- AND queues it) -- and because it shares Take's exact button style, so nothing on
      -- screen distinguishes them either. The stats line points at the hover, which is on the
      -- bar where the card is, rather than at the Loot window.
      body = "Three choices on the bar: Take, Pass, or Take + reroll. Hover the item's name for its full stats first - you have five minutes, and the bar counts them down." },
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
local ruleEditSeen = false  -- set by the CONFIG_SELL_CHANGED subscription when fromUser rides the emit
local prev = {}             -- previous-tick snapshot values for edge detection
local visibleCells = nil    -- cells actually on the bar this frame (dock_top pushes; nil = never told)
local subscribed = false

function M.init(deps)
    d = deps
    if subscribed then return end
    subscribed = true
    -- The trigger is the COMMIT, not the filter UI. The old arming point was
    -- bumpFilterListGeneration, on the theory that every user rule edit lands in the
    -- filters view; it does not -- right-click Keep/Junk, the first edit a newcomer ever
    -- makes, goes applySellListChange -> config_cache and never enters that file, so the
    -- hint mostly never fired at all. Every rule-changing route already ends in one place,
    -- the CONFIG_SELL_CHANGED emit, so the hint listens there and provenance rides the
    -- payload: fromUser=true is a person editing, absent-or-false is the product seeding
    -- (profile application, the wizard, first-run defaults) -- a hint that says "rules
    -- explain themselves" must not fire because the product edited the rules. Absent
    -- defaults to NOT-user on purpose: a forgotten flag is a missed hint, never a wrong
    -- first-run card.
    events.on(events.EVENTS.CONFIG_SELL_CHANGED, function(payload)
        if payload and payload.fromUser then ruleEditSeen = true end
    end)
end

--- dock_top pushes the set of cells that made it onto the bar this frame (the enable set
--- minus narrow-width drops). A hint whose anchor is not in it is SUPPRESSED, not
--- relocated -- and not consumed: nothing here marks it seen, so it waits and fires when
--- the cell comes back. nil (never told: classic mode, or a test that never renders)
--- fails open, matching the old behaviour exactly.
function M.noteVisibleCells(set)
    if type(set) ~= "table" then return end
    visibleCells = set
end

local function cellOn(id)
    return visibleCells == nil or visibleCells[id] == true
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
    -- Structurally quiet during setup: the wizard and the welcome screen are teaching
    -- surfaces of their own, and a card over either stacks two vocabularies on one moment.
    -- This is a GATE, not a flag audit -- getting fromUser right at every wizard site is
    -- the fragile version of the same guarantee.
    if d.uiState and d.uiState.setupMode then return end
    loadSeen()

    -- The anchor-visibility gate rides IN the trigger chain, before anything is marked
    -- seen, so a suppressed hint is never consumed -- it waits, and fires when its cell
    -- comes back (the ruling: suppressed, not relocated, not used up).
    local s = dockState.get()
    local fire = nil
    if s.merchantOpen and not prev.merchantOpen and not seen.merchant and cellOn("sell") then fire = "merchant" end
    if not fire and s.lootRunning and not prev.lootRunning and not seen.loot_run then fire = "loot_run" end
    if not fire and s.lootState == "decision" and prev.lootState ~= "decision" and not seen.mythical then fire = "mythical" end
    if not fire and s.bagFree == 0 and prev.bagFree ~= 0 and (s.bagItems or 0) > 0 and not seen.full_bag and cellOn("bags") then fire = "full_bag" end
    if not fire and ruleEditSeen and not seen.rule_edit and cellOn("sell") then fire = "rule_edit" end

    -- prev freezes for a suppressed trigger's OWN field. Without this the edge a hint
    -- waits on can be eaten while its cell is off: bags fill with the bags cell disabled,
    -- prev.bagFree advances to 0, and re-enabling the cell with the bags still full finds
    -- no edge left -- the card would wait until the player empties AND refills. Freezing
    -- prev turns the suppressed occurrence into a still-pending edge, which is what "it
    -- waits" means. The lane cannot be disabled, so its two fields always advance.
    if cellOn("sell") then prev.merchantOpen = s.merchantOpen end
    if cellOn("bags") then prev.bagFree = s.bagFree end
    prev.lootRunning, prev.lootState = s.lootRunning, s.lootState

    if fire and not active then
        local h = hintById(fire)
        if h then active = { id = h.id, title = h.title, body = h.body, anchor = h.anchor } end
    end
end

--- Tests only.
-- ---------------------------------------------------------------------------
-- LESSONS: one-time teaching that has no bar cell to point at.
--
-- A hint is positioned by M.slots[anchor], so it can only ever teach the eight segments
-- (test_hints enforces the anchor is a live one). Two things a newcomer must know have their
-- first moment somewhere else entirely -- dragging a window, and never having opened the hub
-- list -- so no hint can carry them, and giving them fake anchors would be the 480fe52 bug
-- as a decision.
--
-- They ride the degraded strip instead, which already solves position, dismissal and
-- session scoping, and already has a non-alarming member (stale_bank is Success). All this
-- module owns is whether one has been shown, in the same INI as the hints because it is the
-- same kind of state.
-- ---------------------------------------------------------------------------

local lessonSeen = nil

local function loadLessons()
    if lessonSeen then return end
    lessonSeen = {}
end

--- Has this lesson already been shown and dismissed? Reads through to the INI once per id.
function M.lessonSeen(id)
    if not id then return true end
    loadLessons()
    if lessonSeen[id] == nil then
        lessonSeen[id] = config.readINIValue(HINTS_INI, HINTS_SECTION, "lesson_" .. id, "FALSE") == "TRUE"
    end
    return lessonSeen[id] == true
end

--- Mark it shown. Called from the strip's dismiss path, so a lesson costs exactly one
--- dismissal ever -- unlike the degraded strips, whose dismissal is session-scoped because
--- their condition can come back.
function M.markLessonSeen(id)
    if not id then return end
    loadLessons()
    lessonSeen[id] = true
    config.writeINIValue(HINTS_INI, HINTS_SECTION, "lesson_" .. id, "TRUE")
end

function M._reset()
    seen, active, replayQueue, ruleEditSeen, prev = nil, nil, nil, false, {}
    lessonSeen = nil
    visibleCells = nil
end

--- Tests only: observe what dock_top pushed without clobbering the setter.
function M._visibleCells()
    return visibleCells
end

return M
