-- AA truth-overlay suite. Pins the fix for the three field defects (2026-08-04):
-- Train firing refused ids, Can Purchase lying, and the multi-second freeze on
-- window open. The load-bearing assertions:
--   * the spend fields come from the plugin truth maps, not the TLO: nextIndex
--     is the NEXT-rank table id for the OWNED rank (what /alt buy takes on this
--     server's custom table), cost is the next rank's cost, canTrain includes
--     prereqs and requires a buyable id;
--   * a group with no next-rank table entry (auto-granted) is canTrain=false;
--   * maxed lines are canTrain=false with nextIndex 0;
--   * with truth present the character-side Me.AltAbility resolve is SKIPPED
--     (it was both the lying read and the bulk of the scan cost);
--   * noteTrained bumps a record in place so repeat-click trains the NEXT rank
--     while the rescan is still pumping;
--   * the pump is time-boxed: a hot clock stops a chunk early instead of
--     freezing the frame.

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
local mqStub = package.loaded['mq']

-- Controllable clock: static by default; "hot" mode advances 5ms per read so
-- the pump's every-32-ids check trips its 8ms budget.
local clock = { now = 100000, step = 0 }
mqStub.gettime = function()
    clock.now = clock.now + clock.step
    return clock.now
end

-- ---------------------------------------------------------------- fixtures
-- Global AltAbility(id) entries. ID() is the group id (the scan's kept record).
local function field(v) return function() return v end end
local function entry(gid, name, maxRank, flatCost, reqGid, reqRank)
    return {
        ID = field(gid), Name = field(name), MaxRank = field(maxRank),
        Cost = field(flatCost), Type = field(1), Category = field(''),
        Description = field('desc ' .. name), Passive = field(true),
        RequiresAbility = field(reqGid and tostring(reqGid) or nil),
        RequiresAbilityPoints = field(reqRank or 0),
    }
end
local entries = {
    [100] = entry(100, 'Combat Agility', 5, 1),
    [200] = entry(200, 'Granted Thing', 3, 1),
    [300] = entry(300, 'Deep Line', 3, 1, 100, 3),   -- requires Combat Agility rank 3
    [400] = entry(400, 'Maxed Line', 2, 1),
    [500] = entry(500, 'Unlocked Line', 2, 1, 400, 2), -- requires Maxed Line rank 2 (met)
}

local meAltAbilityCalls = 0
mqStub.TLO = {
    Zone = { ID = field(1) },
    Me = {
        AAPointsSpent = field(10), Level = field(54),
        AAPoints = field(4), AAPointsAssigned = field(10), PctAAExp = field(50),
        AltAbility = function(name)
            meAltAbilityCalls = meAltAbilityCalls + 1
            return nil
        end,
    },
    AltAbility = function(i) return entries[i] end,
}

-- Plugin stub: truth maps. visibleOn toggles the visible-ids path so the
-- time-box test can run the full sparse scan instead.
local visibleOn = true
local pluginStub = {
    aa = {
        getVisibleAAIds = function()
            if not visibleOn then return nil end
            return { 100, 200, 300, 400, 500 }
        end,
        getOwnedRanks = function()
            return { [100] = 2, [200] = 1, [300] = 0, [400] = 2, [500] = 0 }
        end,
        getGroupRankIndexes = function()
            return {
                [100] = { 101, 102, 103, 104, 105 },
                [200] = { 201 },                      -- no rank-2 entry: auto-granted
                [300] = { 301, 302, 303 },
                [400] = { 401, 402 },
                [500] = { 501, 502 },
            }
        end,
        getGroupRankCosts = function()
            return {
                [100] = { 1, 2, 3, 4, 5 },
                [200] = { 1 },
                [300] = { 2, 2, 2 },
                [400] = { 1, 1 },
                [500] = { 7, 8 },
            }
        end,
    },
}
package.loaded['itemui.utils.coopui_plugin'] = {
    getPlugin = function() return pluginStub end,
}

local aa_data = require('itemui.services.aa_data')

-- ---------------------------------------------------------------- truth scan
aa_data.refresh()
local pumps = 0
while aa_data.isBuilding() and pumps < 50 do
    aa_data.pump()
    pumps = pumps + 1
end
check('scan completes on the visible-ids path', not aa_data.isBuilding(), 'pumps=' .. pumps)

local byId = {}
for _, rec in ipairs(aa_data.getList()) do byId[rec.id] = rec end
check('all five records built', byId[100] and byId[200] and byId[300] and byId[400] and byId[500])

local ca = byId[100] or {}
check('rank is the OWNED rank, not a TLO read', ca.rank == 2)
check('nextIndex is the next-rank table id (owned 2 -> id of rank 3)', ca.nextIndex == 103,
    'got ' .. tostring(ca.nextIndex))
check('cost is the NEXT rank cost, not rank-1 flat', ca.cost == 3, 'got ' .. tostring(ca.cost))
check('trainable line canTrain=true', ca.canTrain == true)

local granted = byId[200] or {}
check('no next-rank table entry -> nextIndex 0', granted.nextIndex == 0)
check('no buyable id -> canTrain=false (auto-granted line)', granted.canTrain == false)

local deep = byId[300] or {}
check('unmet prereq (CA rank 2 of 3 required) -> canTrain=false', deep.canTrain == false)

local maxed = byId[400] or {}
check('maxed -> canTrain=false', maxed.canTrain == false)
check('maxed -> nextIndex 0', maxed.nextIndex == 0)

local unlocked = byId[500] or {}
check('met prereq (Maxed Line at required 2) -> canTrain=true', unlocked.canTrain == true)
check('unlocked nextIndex is rank-1 table id', unlocked.nextIndex == 501)
check('unlocked cost is rank-1 cost from per-rank table', unlocked.cost == 7)

check('truth path SKIPS the character-side Me.AltAbility resolve', meAltAbilityCalls == 0,
    'calls=' .. meAltAbilityCalls)

-- ---------------------------------------------------------------- noteTrained
aa_data.noteTrained(100)
check('noteTrained bumps rank in place', ca.rank == 3)
check('noteTrained advances nextIndex to the new next rank', ca.nextIndex == 104,
    'got ' .. tostring(ca.nextIndex))
check('noteTrained advances cost', ca.cost == 4)
aa_data.noteTrained(400)
check('noteTrained clamps at maxRank', (byId[400] or {}).rank == 2)
check('noteTrained keeps maxed canTrain=false', (byId[400] or {}).canTrain == false)

-- ---------------------------------------------------------------- time box
-- Full sparse scan (visible ids off) with a hot clock: one pump must stop far
-- short of its 2500-id cap instead of eating the whole chunk in one frame.
visibleOn = false
clock.step = 5
aa_data.refresh()
aa_data.pump()
check('hot clock: still building after one pump', aa_data.isBuilding())
clock.step = 0
local fullPumps = 0
while aa_data.isBuilding() and fullPumps < 200 do
    aa_data.pump()
    fullPumps = fullPumps + 1
end
check('static clock: sparse scan completes under the id cap', not aa_data.isBuilding(),
    'pumps=' .. fullPumps)
check('sparse scan still built the known records', #aa_data.getList() == 5)

print(string.format('%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
