-- Session record suite (§12 / phase 14, mockups 26b/26c). The load-bearing test is
-- acceptance 12 as REVISED after field use: an augment already on the reroll list, or
-- carrying an explicit always-junk rule, lands in SORTED and does not increment the amber
-- count. A keep-rule match and a NoDrop item do NOT - they stay in the queue, because
-- every category this record tracks is keep-protected by default, so "protected" is the
-- resting state of the loot rather than a decision anyone made.
-- Plus: the decide/undo/clear lifecycle, stack-growth counting for scripts, departure
-- marking, and the file round-trip.
--
-- And the two rules that came out of field use after that:
--   * a script is a TALLY - counted, never queued, never sorted;
--   * only what came off a CORPSE is recorded, so an augment pulled out of a socket does
--     not queue up as tonight's loot.
-- The third block below covers re-linking, which is what makes "not in bags" true: an
-- entry finds its live row by item identity, not by an acquiredSeq that follows the slot.

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
-- charName() resolves through mq.TLO.Me.Name() — the TLO trap returns a trap table whose
-- __call gives nil, so the service treats the char as unresolved unless we override.
local mqStub = package.loaded['mq']
mqStub.TLO = { Me = { Name = function() return 'Testchar' end } }

local sessionRecord = require('itemui.services.session_record')
local lootWatch = require('itemui.services.loot_watch')

-- ---------------------------------------------------------------- deps factory
local files = {}   -- path -> content, the fake disk
local function makeDeps(over)
    -- `local d` BEFORE the constructor: the closures below reference d, and inside a
    -- `local d = {...}` statement the local is not yet in scope — they would bind the
    -- GLOBAL d (nil forever). The declare-then-assign split is what makes them capture.
    local d
    d = {
        inventoryItems = {},
        _floor = 100,
        getSessionStartAcquiredSeq = function() return (over or {})._floorOverride or 100 end,
        getSellStatusForItem = function(row)
            local keep = (over or {}).keepNames or {}
            local junk = (over or {}).junkNames or {}
            return '-', false, keep[row.name] == true, junk[row.name] == true
        end,
        applySellListChange = function(name, k, j)
            d._sellChanges[#d._sellChanges + 1] = { name = name, keep = k, junk = j }
        end,
        rerollService = {
            _pendingAdds = {},
            getListStatus = function(kind, id)
                local listed = (over or {}).rerollIds or {}
                return listed[id] and 'listed' or nil
            end,
            addToPendingList = function(kind, id, name)
                d.rerollService._pendingAdds[#d.rerollService._pendingAdds + 1] = { kind = kind, id = id, name = name }
                return true
            end,
            removeFromPending = function(kind, id)
                d.rerollService._removed = { kind = kind, id = id }
                return true
            end,
        },
        getCharStoragePath = function(char, file) return 'FAKE/' .. char .. '/' .. file end,
        safeWrite = function(path, content) files[path] = content return true end,
        safeReadAll = function(path) return files[path] end,
        _sellChanges = {},
    }
    for k, v in pairs(over or {}) do
        if k ~= 'keepNames' and k ~= 'junkNames' and k ~= 'rerollIds' and k ~= '_floorOverride' then d[k] = v end
    end
    return d
end

local function aug(seq, name, id, value, extra)
    local r = { name = name, id = id, type = 'Augmentation', bag = 1, slot = seq,
        value = value, totalValue = value, stackSize = 1, acquiredSeq = seq }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

-- ---------------------------------------------------------------- 1. acceptance 12
do
    sessionRecord._resetForTests()
    files = {}
    local deps = makeDeps({
        rerollIds = { [777] = true },
        keepNames = { ['Kept Gem'] = true },
        junkNames = { ['Junk Oil'] = true },
    })
    deps.inventoryItems = {
        aug(101, 'Fresh Emerald', 11, 142000),                       -- genuinely undecided
        aug(102, 'Pear Cut Taaffeite', 777, 88000),                  -- already on reroll list
        aug(103, 'Kept Gem', 12, 50000),                             -- keep rule
        aug(104, 'Junk Oil', 13, 31000),                             -- always-junk rule
        aug(105, 'Bound Sigil', 14, 20000, { nodrop = true }),       -- NoDrop
        aug(99,  'Old Aug From Last Week', 15, 999000),              -- below the floor
        { name = 'Mythical Whispering Compass II', id = 20, type = 'Misc', bag = 2, slot = 1,
          value = 2410000, totalValue = 2410000, stackSize = 1, acquiredSeq = 106 },
        { name = 'Script of Lost Memories', id = 30, type = 'Misc', bag = 2, slot = 2,
          value = 0, totalValue = 0, stackSize = 4, acquiredSeq = 107 },
        { name = 'Plain Sword', id = 40, type = '1H Slashing', bag = 2, slot = 3,
          value = 5000, totalValue = 5000, stackSize = 1, acquiredSeq = 108 },  -- not recorded
    }
    sessionRecord.init(deps)
    sessionRecord.tick(1000)

    -- The pre-emption is DELIBERATELY NARROW: only an explicit sell (always-junk) or a
    -- reroll counts as a decision already made. Augments, mythics and scripts are ALL
    -- keep-protected by default (Augmentation in sell_keep_types; Mythical and Script of
    -- in sell_keep_contains) - which is exactly the loot this record tracks. Treating
    -- "matches a keep rule" as a decision therefore pre-empted every single item the
    -- feature exists to ask about, and the queue sat permanently empty. Protected-from-
    -- sale is the DEFAULT STATE of this loot, not a call anyone made.
    local c = sessionRecord.getCounts()
    check('acc12: keep-protected and NoDrop augs still NEED a call',
        c.augsCall == 3, c.augsCall)   -- Fresh Emerald + Kept Gem + Bound Sigil
    check('acc12: only reroll and explicit-junk pre-empt', c.sorted == 2, c.sorted)
    check('acc12: aug total counts every aug looted', c.augsTotal == 5, c.augsTotal)
    check('acc12: the mythic needs its call', c.mythicsCall == 1 and c.mythicsTotal == 1,
        c.mythicsCall .. '/' .. c.mythicsTotal)
    check('acc12: scripts counted by stack', c.scripts == 4, c.scripts)
    -- You always keep a script and the Scripts window turns it in, so there is no call to
    -- make on one. It is counted and nothing else: not in the queue, not in SORTED.
    check('acc12: a script is a tally - it is in NEITHER list', (function()
        for _, e in ipairs(sessionRecord.getCallList()) do
            if e.cat == 'script' then return false end
        end
        for _, e in ipairs(sessionRecord.getSortedList()) do
            if e.cat == 'script' then return false end
        end
        return true
    end)())
    -- looted is the DECISION record - 5 augs + 1 mythic. The script is counted apart, so
    -- the panel's truth line adds up and every row it counts is one you can go and see.
    check('acc12: below-floor loot is not the session', c.looted == 6, c.looted)
    check('acc12: the truth line is an identity', c.looted == c.needCall + c.sorted,
        c.looted .. ' vs ' .. c.needCall .. '+' .. c.sorted)
    check('acc12: ordinary loot is not recorded', (function()
        for _, e in ipairs(sessionRecord.getSortedList()) do
            if e.name == 'Plain Sword' then return false end
        end
        for _, e in ipairs(sessionRecord.getCallList()) do
            if e.name == 'Plain Sword' then return false end
        end
        return true
    end)())

    local sorted = sessionRecord.getSortedList()
    local reasons = {}
    for _, e in ipairs(sorted) do reasons[e.name] = e.reason end
    check('acc12: reroll pre-emption carries its reason',
        reasons['Pear Cut Taaffeite'] == 'already on the reroll list', reasons['Pear Cut Taaffeite'])
    check('acc12: explicit junk pre-emption carries its reason',
        reasons['Junk Oil'] == 'matches an always-junk rule', reasons['Junk Oil'])
    check('acc12: a keep-rule match is NOT sorted', reasons['Kept Gem'] == nil)
    check('acc12: a NoDrop item is NOT sorted', reasons['Bound Sigil'] == nil)
    -- NoDrop still has to block the Junk chip - it just does it from a field on the entry
    -- now rather than by removing the row from the queue.
    check('acc12: NoDrop still blocks the Junk chip', (function()
        for _, e in ipairs(sessionRecord.getCallList()) do
            if e.name == 'Bound Sigil' then
                local ok, why = sessionRecord.canDecide(e.uid, 'junk')
                return ok == false and why == 'NoDrop'
            end
        end
        return false
    end)())
    check('acc12: no call of any kind is offered on a script', (function()
        for _, e in ipairs(sessionRecord._entriesForTests()) do
            if e.cat == 'script' then
                for _, choice in ipairs({ 'keep', 'reroll', 'junk' }) do
                    local ok, why = sessionRecord.canDecide(e.uid, choice)
                    if ok ~= false or why ~= 'kept for turn-in' then return false end
                end
                return e.state == 'tally'
            end
        end
        return false
    end)())

    local calls = sessionRecord.getCallList()
    check('calls: best first (mythic 2410p over aug 142p)',
        calls[1] and calls[1].name == 'Mythical Whispering Compass II'
        and calls[2] and calls[2].name == 'Fresh Emerald', calls[1] and calls[1].name)
end

-- ---------------------------------------------------------------- 2. decide / undo
do
    -- Continues from block 1's state. Decide the fresh aug onto the reroll list.
    local deps = nil
    -- (re-init with the same fake deps to observe mutations)
    sessionRecord._resetForTests()
    files = {}
    deps = makeDeps({})
    deps.inventoryItems = { aug(201, 'Sapphirine Emerald', 55, 142000) }
    sessionRecord.init(deps)
    sessionRecord.tick(1000)
    local e = sessionRecord.getCallList()[1]
    check('decide: entry recorded as a call', e ~= nil and e.name == 'Sapphirine Emerald')

    check('decide: reroll possible', sessionRecord.canDecide(e.uid, 'reroll') == true)
    check('decide: applies', sessionRecord.decide(e.uid, 'reroll') == true)
    check('decide: pending reroll add went through the service',
        deps.rerollService._pendingAdds[1] and deps.rerollService._pendingAdds[1].id == 55
        and deps.rerollService._pendingAdds[1].kind == 'aug')
    local c = sessionRecord.getCounts()
    check('decide: amber cleared, sorted grew', c.augsCall == 0 and c.sorted == 1,
        c.augsCall .. '/' .. c.sorted)
    check('decide: cannot re-decide a sorted entry', sessionRecord.decide(e.uid, 'junk') == false)

    check('undo: reverts', sessionRecord.undo() == true)
    check('undo: pending reroll removed', deps.rerollService._removed
        and deps.rerollService._removed.id == 55)
    local c2 = sessionRecord.getCounts()
    check('undo: back to needing a call', c2.augsCall == 1 and c2.sorted == 0,
        c2.augsCall .. '/' .. c2.sorted)

    -- keep decision routes through applySellListChange
    check('decide keep: applies', sessionRecord.decide(e.uid, 'keep') == true)
    check('decide keep: sell list mutation', deps._sellChanges[1]
        and deps._sellChanges[1].keep == true and deps._sellChanges[1].junk == false)
end

-- ---------------------------------------------------------------- 3. stacks + departure
do
    sessionRecord._resetForTests()
    files = {}
    local deps = makeDeps({})
    local scriptRow = { name = 'Script of Planar Power', id = 31, type = 'Misc', bag = 3, slot = 1,
        value = 0, totalValue = 0, stackSize = 2, acquiredSeq = 301 }
    deps.inventoryItems = { scriptRow }
    sessionRecord.init(deps)
    sessionRecord.tick(1000)
    check('stack: initial scripts = 2', sessionRecord.getCounts().scripts == 2,
        sessionRecord.getCounts().scripts)

    scriptRow.stackSize = 5   -- three more merged into the stack
    sessionRecord.tick(2000)
    check('stack: growth counts as more loot (5 total)', sessionRecord.getCounts().scripts == 5,
        sessionRecord.getCounts().scripts)

    deps.inventoryItems = {}  -- consumed / sold: the row is gone
    sessionRecord.tick(3000)
    check('departure: nothing ever leaves the session', sessionRecord.getCounts().scripts == 5,
        sessionRecord.getCounts().scripts)
end

-- ---------------------------------------------------------------- 4. persistence + clear
do
    sessionRecord._resetForTests()
    files = {}
    local deps = makeDeps({})
    deps.inventoryItems = { aug(401, 'Persisted Aug', 61, 77000) }
    sessionRecord.init(deps)
    sessionRecord.tick(1000)
    sessionRecord.tick(10000)   -- past the save debounce
    local path = 'FAKE/Testchar/session_record.ini'
    check('persist: file written', files[path] ~= nil and files[path]:find('Persisted Aug', 1, true) ~= nil,
        tostring(files[path]))

    -- A fresh process (reset) loads the record back.
    sessionRecord._resetForTests()
    sessionRecord.init(deps)
    deps.inventoryItems = {}
    sessionRecord.tick(1000)
    local c = sessionRecord.getCounts()
    check('persist: reloads across a restart (session survives logout)',
        c.looted == 1 and c.augsCall == 1, c.looted .. '/' .. c.augsCall)
    local e = sessionRecord.getCallList()[1]
    check('persist: reloaded entry is departed until re-linked', e and e.departed == true)

    sessionRecord.clear()
    local c2 = sessionRecord.getCounts()
    check('clear: the one thing that ends a session', c2.looted == 0 and c2.sorted == 0,
        c2.looted)
    check('clear: file cleared too', files[path] ~= nil and not files[path]:find('Persisted Aug', 1, true))
end

-- ---------------------------------------------------------------- 5. the corpse gate
-- Only what came off a corpse belongs in the queue. The old source was the inventory
-- delta, which is a different question entirely: a row appears for every way an item can
-- enter the bags, so the reported case - an ornamentation removed from a weapon the player
-- had owned for weeks - queued up as tonight's loot and asked to be rerolled.
do
    sessionRecord._resetForTests()
    lootWatch._resetForTests(false)
    files = {}
    local deps = makeDeps({})
    deps.inventoryItems = { aug(501, 'Socketed Ornamentation', 71, 0) }
    sessionRecord.init(deps)
    sessionRecord.tick(1000)
    check('gate: unarmed, the record behaves exactly as it did before',
        sessionRecord.getCounts().looted == 1, sessionRecord.getCounts().looted)

    -- One real loot line arms the gate for the rest of the session. Until then a silent
    -- record would be indistinguishable from a quiet night, which is why it fails open.
    sessionRecord._resetForTests()
    lootWatch._resetForTests(false)
    files = {}
    deps = makeDeps({})
    deps.inventoryItems = {}
    sessionRecord.init(deps)
    lootWatch._feedLine('--You have looted a Fresh Emerald.--')
    check('gate: a loot line arms the watcher', lootWatch.isArmed() == true)

    deps.inventoryItems = {
        aug(511, 'Fresh Emerald', 11, 142000),               -- off a corpse: has a credit
        aug(512, 'Socketed Ornamentation', 71, 0),           -- out of a socket: has none
    }
    sessionRecord.tick(2000)
    local names = {}
    for _, e in ipairs(sessionRecord._entriesForTests()) do names[e.name] = true end
    check('gate: corpse loot is recorded', names['Fresh Emerald'] == true)
    check('gate: an aug out of a socket is NOT loot', names['Socketed Ornamentation'] == nil)

    -- Credits are consumed, so one line can never pay for two items. The ornament stays
    -- out on every subsequent tick, not just the one where it appeared.
    sessionRecord.tick(3000)
    check('gate: the exclusion holds across ticks', sessionRecord.getCounts().looted == 1,
        sessionRecord.getCounts().looted)

    -- Two off two corpses need two lines.
    lootWatch._feedLine('--You have looted a Socketed Ornamentation.--')
    sessionRecord.tick(4000)
    check('gate: a later line lets the same name in', sessionRecord.getCounts().looted == 2,
        sessionRecord.getCounts().looted)
end

-- ---------------------------------------------------------------- 6. re-linking
-- What makes "not in bags" mean it. An entry used to find its live row by acquiredSeq
-- alone, and that stamp follows the SLOT before it follows the item (scan.lua matches
-- bag:slot first, id second) - so a bag shuffle handed the entry's seq to whatever moved
-- into its old slot, and the panel told the player an augment sitting in their bags was
-- gone. It also greyed out the Reroll chip, which is the whole point of the queue.
do
    sessionRecord._resetForTests()
    lootWatch._resetForTests(false)
    files = {}
    local deps = makeDeps({})
    local row = aug(601, 'Sapphirine Emerald', 55, 142000)
    deps.inventoryItems = { row }
    sessionRecord.init(deps)
    sessionRecord.tick(1000)
    local e = sessionRecord.getCallList()[1]
    check('relink: recorded live', e and e.departed == nil and e.rowSeq == 601)

    -- The bag shuffle: same item, new slot, and the stamp it used to answer to now belongs
    -- to whatever moved into its old slot. (An ordinary item, so the only thing under test
    -- here is the re-link - a stolen seq on a second AUGMENT would legitimately record a
    -- second entry and muddy the count assertions below.)
    deps.inventoryItems = {
        { name = 'Plain Sword', id = 99, type = '1H Slashing', bag = 1, slot = 1,
          value = 1000, totalValue = 1000, stackSize = 1, acquiredSeq = 601 },
        { name = 'Sapphirine Emerald', id = 55, type = 'Augmentation', bag = 2, slot = 7,
          value = 142000, totalValue = 142000, stackSize = 1, acquiredSeq = 990 },
    }
    sessionRecord.tick(2000)
    check('relink: a stolen seq is rejected, identity wins', e.departed == nil and e.rowSeq == 990,
        tostring(e.departed) .. '/' .. tostring(e.rowSeq))
    check('relink: Reroll stays offered on an item that is still in the bags',
        sessionRecord.canDecide(e.uid, 'reroll') == true)
    check('relink: the impostor did not take the entry with it', e.bag == 2 and e.slot == 7,
        tostring(e.bag) .. ':' .. tostring(e.slot))

    -- ...and departed still means departed.
    deps.inventoryItems = {}
    sessionRecord.tick(3000)
    check('relink: a real departure still departs', e.departed == true)
    local ok, why = sessionRecord.canDecide(e.uid, 'reroll')
    check('relink: and Reroll says why', ok == false and why == 'not in bags', tostring(why))

    -- The restart case, which used to leave EVERY reloaded entry departed with the item
    -- sitting right there: rowSeq is not persisted and the floor is re-stamped on load, so
    -- identity is the only thing left to match on.
    sessionRecord.tick(10000)   -- flush to the fake disk
    sessionRecord._resetForTests()
    sessionRecord.init(deps)
    deps.inventoryItems = {
        { name = 'Sapphirine Emerald', id = 55, type = 'Augmentation', bag = 3, slot = 2,
          value = 142000, totalValue = 142000, stackSize = 1, acquiredSeq = 4 },  -- below any floor
    }
    sessionRecord.tick(1000)
    local reloaded = sessionRecord.getCallList()[1]
    check('relink: a reloaded entry finds its item again after a restart',
        reloaded and reloaded.departed == nil and reloaded.bag == 3,
        reloaded and tostring(reloaded.departed))
    check('relink: re-linking does not re-record it', sessionRecord.getCounts().looted == 1,
        sessionRecord.getCounts().looted)
end

-- ---------------------------------------------------------------- 6b. moved vs. a second
-- The one genuinely ambiguous case: a departed entry, and a row with the same id sitting
-- above the session floor. Your augment moved, or you looted another exactly like it -
-- identical on paper. The outstanding loot credit is the tiebreak, and getting it wrong in
-- the greedy direction would silently under-count the night's take.
do
    sessionRecord._resetForTests()
    lootWatch._resetForTests(false)
    files = {}
    local deps = makeDeps({})
    deps.inventoryItems = {}
    sessionRecord.init(deps)
    lootWatch._feedLine('--You have looted a Fresh Emerald.--')
    deps.inventoryItems = { aug(801, 'Fresh Emerald', 11, 142000) }
    sessionRecord.tick(1000)
    check('ambiguity: the first one is recorded', sessionRecord.getCounts().looted == 1,
        sessionRecord.getCounts().looted)

    -- Sold. The entry departs, and its credit is long spent.
    deps.inventoryItems = {}
    sessionRecord.tick(2000)
    check('ambiguity: it departs', sessionRecord.getCallList()[1].departed == true)

    -- A SECOND one off a corpse: its own line, its own credit, so it is its own record
    -- rather than being quietly absorbed by the entry that is already sitting there.
    lootWatch._feedLine('--You have looted a Fresh Emerald.--')
    deps.inventoryItems = { aug(802, 'Fresh Emerald', 11, 142000) }
    sessionRecord.tick(3000)
    check('ambiguity: a second corpse gets a second record',
        sessionRecord.getCounts().looted == 2, sessionRecord.getCounts().looted)

    -- Whereas the SAME one changing slots has nothing left to pay with, so it re-links and
    -- no phantom row appears.
    local before = sessionRecord.getCounts().looted
    deps.inventoryItems = { aug(803, 'Fresh Emerald', 11, 142000) }
    sessionRecord.tick(4000)
    check('ambiguity: a move is not a second loot',
        sessionRecord.getCounts().looted == before, sessionRecord.getCounts().looted)
end

-- ---------------------------------------------------------------- 7. script migration
-- A session already in progress has scripts sitting in the queue under the old rule. They
-- fix themselves on the next tick rather than needing a Clear, and a keep the player
-- pressed just to get the row off the list does not leave an undo that resurrects it.
do
    sessionRecord._resetForTests()
    lootWatch._resetForTests(false)
    files = {}
    local deps = makeDeps({})
    local scriptRow = { name = 'Script of Lost Memories', id = 30, type = 'Misc', bag = 1, slot = 1,
        value = 0, totalValue = 0, stackSize = 3, acquiredSeq = 701 }
    deps.inventoryItems = { scriptRow }
    sessionRecord.init(deps)
    sessionRecord.tick(1000)
    -- Force the pre-migration shape onto the entry, then tick.
    local se = sessionRecord._entriesForTests()[1]
    se.state, se.choice, se.reason = 'call', nil, nil
    sessionRecord.tick(2000)
    check('migrate: an old script row becomes a tally', se.state == 'tally', se.state)
    check('migrate: and leaves the queue', #sessionRecord.getCallList() == 0)
    check('migrate: counted all the same', sessionRecord.getCounts().scripts == 3,
        sessionRecord.getCounts().scripts)

    -- Turning scripts in shrinks the stack. The high-water mark has to follow it down or
    -- the tally silently swallows the next several loots.
    scriptRow.stackSize = 0
    sessionRecord.tick(3000)
    scriptRow.stackSize = 2
    sessionRecord.tick(4000)
    check('migrate: the tally sees loot after a turn-in', sessionRecord.getCounts().scripts == 5,
        sessionRecord.getCounts().scripts)
end

-- ---------------------------------------------------------------- report
print(string.format('\n%d passed, %d failed', pass, fail))
if fail > 0 then os.exit(1) end
