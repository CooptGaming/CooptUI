--[[
    test_hints.lua — headless suite for services/hints.lua (the five 14c first-run hints).

    dock_state is stubbed with a controllable snapshot; config with an in-memory INI, so
    the suite proves edge detection, one-at-a-time discipline, INI persistence and replay
    without files or a game.

    Run:  COOPT_REPO=C:/Claude/CooptUI <luajit> scripts/tests/test_hints.lua
]]

local repo = os.getenv('COOPT_REPO') or 'C:/Claude/CooptUI'
package.path = repo .. '/lua/?.lua;' .. repo .. '/lua/?/init.lua;' .. package.path

local pass, fail = 0, 0
local function check(name, cond, extra)
    if cond then pass = pass + 1; print('PASS: ' .. name)
    else fail = fail + 1; print('FAIL: ' .. name .. '  -> ' .. tostring(extra)) end
end

-- In-memory INI store.
local ini = {}
local function iniKey(file, section, key) return file .. '|' .. section .. '|' .. key end
package.loaded['mq'] = { gettime = function() return 0 end, cmd = function() end, TLO = {} }
package.loaded['itemui.config'] = {
    readINIValue = function(f, s, k, def) return ini[iniKey(f, s, k)] or def end,
    writeINIValue = function(f, s, k, v) ini[iniKey(f, s, k)] = v end,
    getConfigFile = function(n) return n end,
}
package.loaded['itemui.core.diagnostics'] = { getErrorCount = function() return 0 end, recordError = function() end }

-- Controllable dock snapshot.
local snap = { merchantOpen = false, lootRunning = false, lootState = 'idle', bagFree = 10, bagItems = 50 }
package.loaded['itemui.services.dock_state'] = { get = function() return snap end }

local hints = require('itemui.services.hints')

local lc = { UIMode = 'bars' }
hints.init({ layoutConfig = lc })

local now = 0
local function tick() now = now + 260; hints.tick(now) end

-- 1. Classic mode is inert.
lc.UIMode = 'classic'
snap.merchantOpen = true
tick()
check('classic mode never fires', hints.getActive() == nil)
snap.merchantOpen = false
lc.UIMode = 'bars'
tick()   -- baseline in bars mode

-- 2. Merchant edge fires exactly once, and only on the EDGE.
snap.merchantOpen = true
tick()
local a = hints.getActive()
check('merchant edge fires the merchant hint', a and a.id == 'merchant', a and a.id)
tick()
check('a held condition does not re-fire or replace', hints.getActive().id == 'merchant')

-- 3. One at a time: a second trigger while one is up does not preempt.
snap.lootRunning = true
tick()
check('active hint is not preempted by a new trigger', hints.getActive().id == 'merchant')

-- 4. Dismiss persists and the hint never returns.
hints.dismissActive()
check('dismiss clears the active hint', hints.getActive() == nil)
check('dismiss wrote the INI flag', ini[iniKey('coopui_onboarding.ini', 'Hints', 'hint_merchant')] == 'TRUE')
snap.merchantOpen = false
tick()
snap.merchantOpen = true
tick()
check('a dismissed hint never fires again', hints.getActive() == nil)

-- 5. The missed loot trigger fires on its own NEXT occurrence.
snap.lootRunning = false
tick()
snap.lootRunning = true
tick()
check('loot hint fires on its next edge', hints.getActive() and hints.getActive().id == 'loot_run')
hints.dismissActive()

-- 6. Full-bag needs a plausible inventory (bagItems > 0), mirroring dock_state's own guard.
snap.bagFree = 0; snap.bagItems = 0
tick()
check('bagFree==0 with empty inventory does not fire', hints.getActive() == nil)
snap.bagFree = 10
tick()
snap.bagFree = 0; snap.bagItems = 120
tick()
check('full bag fires with a real inventory', hints.getActive() and hints.getActive().id == 'full_bag')
hints.dismissActive()

-- 7. Mythical decision edge.
snap.lootState = 'decision'
tick()
check('decision edge fires the mythical hint', hints.getActive() and hints.getActive().id == 'mythical')
hints.dismissActive()
snap.lootState = 'idle'

-- 8. Rule edit via the filters-UI hook.
hints.noteRuleEdit()
tick()
check('rule edit fires the last hint', hints.getActive() and hints.getActive().id == 'rule_edit')
hints.dismissActive()
check('all five INI flags are now TRUE', (function()
    for _, id in ipairs({ 'merchant', 'loot_run', 'mythical', 'full_bag', 'rule_edit' }) do
        if ini[iniKey('coopui_onboarding.ini', 'Hints', 'hint_' .. id)] ~= 'TRUE' then return false end
    end
    return true
end)())

-- 9. Replay walks all five in declaration order, one Got-it at a time.
hints.replayAll()
local order = {}
for _ = 1, 6 do
    local h = hints.getActive()
    if not h then break end
    order[#order + 1] = h.id
    hints.dismissActive()
end
check('replay shows all five in order', table.concat(order, ',') == 'merchant,loot_run,mythical,full_bag,rule_edit',
    table.concat(order, ','))
check('replay ends clean', hints.getActive() == nil)
check('replayed hints are re-marked seen as dismissed',
    ini[iniKey('coopui_onboarding.ini', 'Hints', 'hint_rule_edit')] == 'TRUE')

-- 10. Every anchor must be a LIVE dock_top segment.
--
-- renderHint does `M.slots[hint.anchor or ""] or {}` and then `slot.x or barX`, so an anchor
-- that no longer exists does not fail -- it silently pins the popover to the bar's left edge.
-- Both loot hints anchored to "loot", the segment the phase-13 lane replaced, so the two
-- teaching moments that matter most pointed at the CoOpt cell while describing the lane. A
-- retirement that misses a consumer is the recurring shape here (the retired `loot` id, the
-- mandatory status bar's stale DockTop tests), and a silent positional fallback is the worst
-- place for it because nothing looks broken.
local SEGMENTS = { status = true, session = true, bags = true, sell = true,
                   buttons = true, lane = true, buffs = true, xp = true }
local orphaned = {}
for _, h in ipairs(hints.HINTS or {}) do
    if not SEGMENTS[tostring(h.anchor or '')] then
        orphaned[#orphaned + 1] = tostring(h.id) .. '->' .. tostring(h.anchor)
    end
end
check('every hint anchors to a segment that still exists', #orphaned == 0,
    table.concat(orphaned, ', '))
-- 11. No hint may name a control that was REMOVED and left its copy behind.
--
-- A Review button did exist in the lane's finished state, and was removed because it stayed on
-- screen after a run and had to be clicked before the bar would return to idle. The copy that
-- taught it survived in two places -- docs/DOCK_UI.md and this hint, the card a new player
-- meets at their first loot run -- and both shipped for months after the control was gone.
-- The finished mood now draws the result and decays after six seconds on its own.
--
-- The general shape, which is the part worth carrying: WHEN A CONTROL IS REMOVED, THE COPY
-- THAT TAUGHT IT USUALLY SURVIVES, and nothing sweeps for that. Copy is also the one surface
-- no render test reaches -- that card was correctly anchored, perfectly stack-balanced and
-- passing every assertion while naming a button that had been deleted.
--
-- Scope honestly: this is a denylist of names known to have outlived their control, not a
-- general proof that every hint names something real. Add to it when a control is retired.
local PHANTOM = { 'Review' }
local promises = {}
for _, h in ipairs(hints.HINTS or {}) do
    for _, word in ipairs(PHANTOM) do
        if tostring(h.body or ''):find(word, 1, true) then
            promises[#promises + 1] = tostring(h.id) .. ' promises ' .. word
        end
    end
end
check('no hint names a control that was removed', #promises == 0,
    table.concat(promises, ', '))

-- Stop is never in the lane -- it is Loot All transforming in place. A hint that says
-- otherwise sends someone hunting the wrong end of the bar mid-run.
check('no hint puts Stop in the lane',
    not tostring((function()
        for _, h in ipairs(hints.HINTS or {}) do
            if h.id == 'loot_run' then return h.body end
        end
        return ''
    end)()):find('Stop button', 1, true))

-- 12. A hint that lists controls must list ALL of them.
--
-- The mythical card said "Take or Pass" while the lane draws Take, Pass AND Reroll -- the same
-- copy-does-not-match-controls class as the Review button, except by omission rather than by
-- residue, and invisible from source because the copy reads perfectly well. It took a field
-- capture of the decision mood to see it. Reroll is also the one that most needs naming: it
-- shares Take's exact button style (both PushKeepButton), so nothing on screen tells them
-- apart either. test_dock_render's decision block is what proves these are the three the lane
-- actually draws.
local mythBody = ''
for _, h in ipairs(hints.HINTS or {}) do
    if h.id == 'mythical' then mythBody = tostring(h.body or '') end
end
-- Matched case-insensitively against the LABELS the lane draws, so a relabel has to be
-- reflected in the copy: this guard caught "Take + reroll" the moment the button changed and
-- the card still said "Reroll", which is the same mismatch one rename later.
local unnamed = {}
for _, verb in ipairs({ 'take', 'pass', 'reroll' }) do
    if not mythBody:lower():find(verb, 1, true) then unnamed[#unnamed + 1] = verb end
end
check('the mythical hint names every button the lane offers', #unnamed == 0,
    'missing: ' .. table.concat(unnamed, ','))

check('the two lane hints point at the lane, not the retired loot slot',
    (function()
        for _, h in ipairs(hints.HINTS or {}) do
            if (h.id == 'loot_run' or h.id == 'mythical') and h.anchor ~= 'lane' then return false end
        end
        return true
    end)())

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
