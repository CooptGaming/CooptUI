--[[
    stagecraft.lua — dream wave 1 (experiment: ExperimentStagecraft, default OFF).

    Micro-theater for the top bar, per MOCKUP_dream_stagecraft A + B (the kept pair;
    C sparklines and D poster were dropped in triage):

      A  the DING: one 80px light runs the bar's top edge once, 700ms, then gone.
         Blue when AA lands, green when a loot run finishes. Never routine ticks.
      B  the BREATH: a cell that WAITS ON A HUMAN oscillates its background.
         Decisions breathe on the open-blue pair; problems breathe slower toward
         red. Nothing else ever moves — scarcity is the vocabulary.

    Shape: a pure observed-values module. dock_top (flag-gated) feeds it the values
    it already renders every frame — AA total, loot-running — and asks for draw
    math back. No subscriptions, no ticks, no TLO, no ImGui: every function takes
    `nowMs` so the headless suite can drive the whole lifecycle on a fake clock.
    The observer rule for dream surfaces: this module writes nothing anywhere.
]]

local M = {}

M.DING_MS = 700          -- one pass, then gone (the mockup's number)
M.DING_W = 80            -- strip width in px
local MAX_QUEUE = 4      -- coincident dings play in order; beyond this they drop

-- Ding colors (r,g,b): blue = "something good landed" (AA), green = a run finished.
M.DING_BLUE = { 0.26, 0.59, 0.98 }
M.DING_GREEN = { 0.37, 0.75, 0.42 }

local dings = {}         -- { startMs, color } — active plays first, then queued
local lastAATotal = nil
local lastLootRunning = nil

--- Queue a ding. color is one of the M.DING_* tables.
function M.noteDing(nowMs, color)
    if #dings >= MAX_QUEUE then return end
    -- Chain: a new ding starts when the previous one ends, so coincident wins each
    -- get their own pass instead of stacking into one unreadable flash.
    local startMs = nowMs
    local tail = dings[#dings]
    if tail then
        local tailEnd = tail.startMs + M.DING_MS
        if tailEnd > startMs then startMs = tailEnd end
    end
    dings[#dings + 1] = { startMs = startMs, color = color or M.DING_BLUE }
end

--- Feed the AA total the bar already renders. First observation is a BASELINE
--- (the loot-phantom lesson: an initial read is never an event); later increases
--- ding blue. Decreases (respec, char swap) just move the baseline.
function M.observeAA(nowMs, total)
    total = tonumber(total)
    if not total then return end
    if lastAATotal ~= nil and total > lastAATotal then
        M.noteDing(nowMs, M.DING_BLUE)
    end
    lastAATotal = total
end

--- Feed the loot-running flag. The falling edge — a run FINISHING — dings green.
--- First observation is a baseline here too: a UI started mid-run must not ding
--- the moment the run ends... it must, actually — the run finished. Baseline
--- only suppresses the flag's very first value from reading as an edge.
function M.observeLootRunning(nowMs, running)
    running = running == true
    if lastLootRunning ~= nil and lastLootRunning and not running then
        M.noteDing(nowMs, M.DING_GREEN)
    end
    lastLootRunning = running
end

--- The strip to draw this frame, or nil. Returns xFrac (0..1 position of the strip's
--- LEFT edge across barW + strip, so it enters from off-left and exits off-right),
--- alpha (eased in/out), and the color table. Caller maps to pixels:
---   x = barX - DING_W + xFrac * (barW + DING_W)
function M.dingStrip(nowMs)
    local d = dings[1]
    if not d then return nil end
    if nowMs < d.startMs then return nil end
    local t = (nowMs - d.startMs) / M.DING_MS
    if t >= 1 then
        table.remove(dings, 1)
        return M.dingStrip(nowMs)
    end
    -- Ease in/out on alpha (the mockup's 10%/90% ramp); linear travel reads best.
    local alpha = 1.0
    if t < 0.1 then alpha = t / 0.1 elseif t > 0.9 then alpha = (1 - t) / 0.1 end
    return t, alpha, d.color
end

--- Breathing background for a waits-on-a-human cell. base = {r,g,b,a}; kind
--- "decision" (2.4s cycle toward the open-blue) or "problem" (3.6s, toward red —
--- slower and darker per the sheet). Returns {r,g,b,a}. Pure: same inputs, same
--- color, so the suite can pin exact phase values.
local BREATH = {
    decision = { period = 2400, to = { 0.15, 0.26, 0.43 } },
    problem  = { period = 3600, to = { 0.38, 0.16, 0.16 } },
}
function M.breathColor(nowMs, base, kind)
    local spec = BREATH[kind or "decision"] or BREATH.decision
    local phase = (nowMs % spec.period) / spec.period
    -- Sine-shaped 0->1->0 over the period (the CSS keyframes' 0/50/100 shape).
    local k = math.sin(phase * math.pi)
    local b = base or { 0.11, 0.20, 0.32, 1.0 }
    return {
        b[1] + (spec.to[1] - b[1]) * k,
        b[2] + (spec.to[2] - b[2]) * k,
        b[3] + (spec.to[3] - b[3]) * k,
        b[4] or 1.0,
    }
end

--- True while any ding is active or queued (dock_top uses it to skip the draw call
--- entirely on quiet frames).
function M.hasDing()
    return dings[1] ~= nil
end

-- Demo (/itemui experiments demo): the field cannot schedule an AA ding or a
-- mythical decision on request, so the demo queues both dings and breathes the
-- lane for a few seconds — same math, same draw paths, honestly temporary.
local DEMO_BREATH_MS = 8000
local demoBreathUntil = nil

function M.demoStart(nowMs)
    -- Eyes are on the chat line the instant the command runs (field round 2: the
    -- breath was seen, the dings were not - they had already played). The first
    -- pass waits a beat so the eye can travel to the bar, and the pair repeats
    -- once. noteDing already supports future starts: dingStrip stays nil until
    -- a ding's startMs arrives.
    local t = nowMs or 0
    M.noteDing(t + 900, M.DING_BLUE)
    M.noteDing(t + 900, M.DING_GREEN)   -- chains after the blue pass
    M.noteDing(t + 4200, M.DING_BLUE)
    M.noteDing(t + 4200, M.DING_GREEN)
    demoBreathUntil = t + DEMO_BREATH_MS
end

--- True while the demo wants the lane breathing (dock_top checks this only when
--- the lane has no real state of its own — a real decision always wins).
function M.demoBreathing(nowMs)
    if not demoBreathUntil then return false end
    if not nowMs or nowMs >= demoBreathUntil then demoBreathUntil = nil return false end
    return true
end

function M._resetForTests()
    dings = {}
    lastAATotal = nil
    lastLootRunning = nil
    demoBreathUntil = nil
end

return M
