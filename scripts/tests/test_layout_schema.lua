-- utils/layout_schema.lua -- the migration that lets a shipped default reach an install that
-- already has a saved layout.
--
-- The bug this exists to kill: DockButtons, DockSegments and ColumnVisibility persist as
-- "these are on" whitelists rewritten in full on every change, with no version. So adding a
-- member to a shipped default never reached anyone past their first session -- four times,
-- most recently Clickies, which did not appear for the person who reported it missing.
--
-- The property that makes it safe is the one worth testing hardest: it must add what the user
-- has never seen WITHOUT resurrecting what they deliberately turned off. A plain union does
-- the first and fails the second.

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

local schema = require('itemui.utils.layout_schema')

-- =================================================================
-- 1. saved(): anything that is not a usable number is schema 0, because a file with no
--    marker is exactly the case this migrates.
-- =================================================================
check('saved: nil is 0', schema.saved(nil) == 0)
check('saved: empty string is 0', schema.saved('') == 0)
check('saved: garbage is 0', schema.saved('banana') == 0)
check('saved: a negative is 0 (not a schema)', schema.saved(-3) == 0)
check('saved: "1" parses', schema.saved('1') == 1)
check('saved: a float floors rather than comparing fractionally', schema.saved(2.9) == 2)

-- =================================================================
-- 2. additions(): newer than saved AND ships on. Both halves matter.
-- =================================================================
local ENTRIES = {
    { id = 'alpha',   default = true,  since = 0 },
    { id = 'bravo',   default = true,  since = 0 },
    { id = 'charlie', default = true,  since = 1 },   -- new, ships on -> migrates
    { id = 'delta',   default = false, since = 1 },   -- new, ships OFF -> never migrates
    { id = 'echo',    default = true,  since = 2 },   -- newer still
}

local function has(list, id)
    for _, v in ipairs(list) do if v == id then return true end end
    return false
end

local a0 = schema.additions(ENTRIES, 0)
check('additions: a schema-0 file gets everything newer that ships on',
    has(a0, 'charlie') and has(a0, 'echo'), table.concat(a0, ','))
check('additions: an entry that ships OFF is never added, however new',
    not has(a0, 'delta'), table.concat(a0, ','))
check('additions: entries the file already predates are not re-offered',
    not has(a0, 'alpha') and not has(a0, 'bravo'), table.concat(a0, ','))
local a1 = schema.additions(ENTRIES, 1)
check('additions: at schema 1, only what came after it',
    #a1 == 1 and a1[1] == 'echo', table.concat(a1, ','))
check('additions: at the current schema, nothing', #schema.additions(ENTRIES, 2) == 0)

-- =================================================================
-- 3. migrateCsv() -- THE load-bearing one. A plain union would pass every test here except
--    the resurrection case, which is the whole reason `since` exists.
-- =================================================================
local out, changed = schema.migrateCsv('alpha,bravo', ENTRIES, 0)
check('migrate: a new default-on id is added', out:find('charlie', 1, true) ~= nil, out)
check('migrate: reports that it changed something', changed == true)
check('migrate: a ships-off id stays out', out:find('delta', 1, true) == nil, out)

-- Canonical position, not append: DockButtons IS the bar's left-to-right order, so a
-- migrated install has to end up with the same row as a fresh one.
check('migrate: inserts at its canonical position, not the end',
    out == 'alpha,bravo,charlie,echo', out)

-- THE RESURRECTION CASE. The user removed `bravo`, which existed at their schema level.
-- A union against the shipped default would put it back; `since` is what stops that.
local kept, keptChanged = schema.migrateCsv('alpha', ENTRIES, 0)
check('migrate: does NOT resurrect an id the user deliberately removed',
    kept:find('bravo', 1, true) == nil, kept)
check('migrate: still adds the genuinely new ones alongside',
    kept == 'alpha,charlie,echo', kept)
check('migrate: reports change when it added', keptChanged == true)

-- Idempotence. The stamp is written by the next ordinary save, not by the loader, so a
-- migration may run more than once against the same file. It must land the same way.
local once = schema.migrateCsv('alpha,bravo', ENTRIES, 0)
local twice = schema.migrateCsv(once, ENTRIES, 0)
check('migrate: running twice against a schema-0 file is idempotent', once == twice, once .. ' vs ' .. twice)

local same, noChange = schema.migrateCsv('alpha,bravo,charlie,echo', ENTRIES, 2)
check('migrate: nothing to do at the current schema', same == 'alpha,bravo,charlie,echo' and noChange == false, same)

-- "none" is the explicit-empty marker both editors write. Carrying it through would produce
-- the literal id "none" sitting in the row.
local fromNone = schema.migrateCsv('none', ENTRIES, 0)
check('migrate: the "none" empty-marker is not treated as an id',
    fromNone == 'charlie,echo', fromNone)
local fromEmpty = schema.migrateCsv('', ENTRIES, 0)
check('migrate: an empty saved list still receives the new entries',
    fromEmpty == 'charlie,echo', fromEmpty)
check('migrate: whitespace around ids does not create duplicates',
    schema.migrateCsv(' alpha , charlie ', ENTRIES, 0) == 'alpha,charlie,echo',
    schema.migrateCsv(' alpha , charlie ', ENTRIES, 0))

-- =================================================================
-- 4. migrateVisibility(): same rule, per-view map shape. Only ever turns things ON --
--    a migration that could turn a column off would be deleting the user's choice.
-- =================================================================
local AVAILABLE = {
    Inventory = {
        { key = 'Name',  default = true,  since = 0 },
        { key = 'Fresh', default = true,  since = 1 },
        { key = 'OptIn', default = false, since = 1 },
    },
}
local vis = { Inventory = { Name = false, Fresh = false, OptIn = false } }
local visChanged = schema.migrateVisibility(vis, AVAILABLE, 0)
check('visibility: a new default-on column is turned on', vis.Inventory.Fresh == true)
check('visibility: a ships-off column is left alone', vis.Inventory.OptIn == false)
check('visibility: a column the user turned off is NOT turned back on', vis.Inventory.Name == false)
check('visibility: reports that it changed something', visChanged == true)
check('visibility: nothing to do at the current schema',
    schema.migrateVisibility(vis, AVAILABLE, 1) == false)
check('visibility: a view with no saved map is skipped rather than created',
    schema.migrateVisibility({}, AVAILABLE, 0) == false)

-- =================================================================
-- 5. Against the REAL shipped table, which is what actually has to work.
-- =================================================================
local dockButtons = require('itemui.utils.dock_buttons')

-- The exact string in the user's install that reported Clickies missing.
local FIELD = 'bags,bank,itemDisplay,augmentUtility,equipment,effects,mythicals,reroll,scripttracker,aa'
local real = schema.migrateCsv(FIELD, dockButtons.BUTTONS, 0)
check('real: the reported install gains Clickies', real:find('favorites', 1, true) ~= nil, real)
check('real: and does NOT gain Loot, which ships off', real:find('loot', 1, true) == nil, real)
check('real: the migrated row equals the shipped default', real == dockButtons.defaultCsv(),
    real .. ' vs ' .. dockButtons.defaultCsv())

-- A user who had turned two launchers off keeps them off and still gets Clickies.
local trimmed = schema.migrateCsv('bags,bank,equipment,aa', dockButtons.BUTTONS, 0)
check('real: a trimmed row keeps its trim', trimmed:find('mythicals', 1, true) == nil, trimmed)
check('real: a trimmed row still gains Clickies', trimmed == 'bags,bank,equipment,aa,favorites', trimmed)

-- Every entry must carry a `since`, or it silently reads as 0 and never migrates.
local missing = {}
for _, b in ipairs(dockButtons.BUTTONS) do
    if b.since == nil then missing[#missing + 1] = b.id end
end
check('real: every canonical button declares a `since`', #missing == 0, table.concat(missing, ','))
check('real: CURRENT is at least as high as the newest entry',
    (function()
        for _, b in ipairs(dockButtons.BUTTONS) do
            if (b.since or 0) > schema.CURRENT then return false end
        end
        return true
    end)(), 'an entry is newer than schema.CURRENT -- bump it')

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
